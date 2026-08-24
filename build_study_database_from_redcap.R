#!/usr/bin/env Rscript
# Build pe_obgyn_study_database.csv from the raw REDCap export.
#
# This is the merge script primary_analysis.Rmd already names as a dependency it does not
# improvise. It does not exist until calling finishes -- there is no raw REDCap export in this
# repo yet, so this script fails closed the same way primary_analysis.Rmd does.
#
# Derivation is delegated to mysterycall::mysterycall_prepare_calls() wherever possible rather
# than reimplemented: it resolves calldate1/contacted1/contacted2/appdate/exclusions into
# `appt_offered` (obtainment) and `business_days_until_appointment` (via
# mysterycall_count_business_days()) using the exact REDCap field names and exclusion codes
# this study's own data dictionary defines (logistic_include_codes = c(0,7,9,10) is
# mysterycall's own default and matches this study's codes exactly -- not re-decided here).
#
# What this script still has to do itself, because mysterycall_prepare_calls() has no reason to
# know about it: resolve the blinded record_id back to an NPI via the slot crosswalk, merge in
# the fielded sheet's covariates, and decode two REDCap fields prepare_calls() does not touch
# (transfers, holdtime).

suppressMessages({library(readr); library(dplyr); library(tidyr)})

root <- normalizePath(".", mustWork = TRUE)
source(file.path(root, "R", "pe_helpers.R"))
source(file.path(root, "R", "analysis_gates.R"))

RAW_EXPORT_PATH <- file.path(root, "redcap", "redcap_raw_export_800.csv")
CROSSWALK_PATH  <- file.path(root, "redcap", "redcap_slot_crosswalk_400.csv")
SHEET_PATH      <- file.path(root, "pe_obgyn_final_calling_sheet_200_dedup.csv")
OUT_PATH        <- file.path(root, "pe_obgyn_study_database.csv")

if (!file.exists(RAW_EXPORT_PATH)) {
  stop(
    "\n\n  Cannot build ", basename(OUT_PATH), ": ", RAW_EXPORT_PATH, " does not exist yet.\n",
    "  This is the full REDCap 'Export Data' download of the calling instrument once calling\n",
    "  finishes -- one row per record_id, 1-800. It needs at least: record_id, contacted1,\n",
    "  calldate1, contacted2, calldate2, appdate, exclusions, transfers, holdtime, initials.\n",
    "  Place it at this path (or edit RAW_EXPORT_PATH above) and re-run.\n",
    call. = FALSE
  )
}
for (p in c(CROSSWALK_PATH, SHEET_PATH)) {
  if (!file.exists(p)) stop("Required input not found: ", p, call. = FALSE)
}

raw       <- read_csv(RAW_EXPORT_PATH, show_col_types = FALSE, col_types = cols(.default = "c"))
crosswalk <- read_csv(CROSSWALK_PATH,  show_col_types = FALSE, col_types = cols(.default = "c"))
sheet     <- read_csv(SHEET_PATH,      show_col_types = FALSE)

cat(sprintf("Raw REDCap export: %d rows. Crosswalk: %d NPIs. Fielded sheet: %d clinicians.\n",
            nrow(raw), nrow(crosswalk), nrow(sheet)))

# ---------------------------------------------------------------------------- record_id -> NPI
#
# redcap_slot_crosswalk_400.csv is wide: one row per NPI, with medicaid_record_id and
# bcbs_record_id as separate columns (the blinded-slot design in R/pe_helpers.R's
# assign_blinded_slots() assigns two non-adjacent slots per clinician, not two adjacent rows).
# Reshape to long so it joins onto one-row-per-record_id raw export data.
stopifnot("crosswalk must have medicaid_record_id, bcbs_record_id, NPI, pair_id, ownership" =
         all(c("medicaid_record_id", "bcbs_record_id", "NPI", "pair_id", "ownership") %in%
             names(crosswalk)))

crosswalk_long <- bind_rows(
  crosswalk %>% transmute(record_id = medicaid_record_id, NPI, pair_id, ownership, payer = "Medicaid"),
  crosswalk %>% transmute(record_id = bcbs_record_id,     NPI, pair_id, ownership, payer = "BCBS")
)
stopifnot("crosswalk_long must have exactly 2 rows (Medicaid, BCBS) per NPI" =
         all(table(crosswalk_long$NPI) == 2L))

raw_ids <- as.character(raw$record_id)
xwalk_ids <- as.character(crosswalk_long$record_id)
unmatched <- setdiff(raw_ids, xwalk_ids)
if (length(unmatched)) {
  gate_fail("redcap merge",
           sprintf("%d raw record_id(s) not found in the crosswalk: %s",
                   length(unmatched), paste(head(unmatched, 10), collapse = ", ")),
           "\n\n  Every record_id in a real REDCap export for this instrument must be one of\n",
           "  the 800 slots assign_blinded_slots() assigned. An unmatched id means either the\n",
           "  wrong crosswalk file or a REDCap project mismatch -- do not proceed past this.")
}

# The raw REDCap export carries its own ownership/pair_id fields (real REDCap fields, per the
# data dictionary -- hidden from the caller's view, not absent from the database). These collide
# by name with the crosswalk's own ownership/pair_id columns, which are authoritative (the
# crosswalk is "the only record of which id is which clinician" -- see
# docs/APPENDIX_RECORD_BLINDING.md). Rename the raw export's copies rather than let a join
# silently suffix or shadow one of them, and use both as an extra three-way cross-check below.
raw <- raw %>% rename(redcap_ownership_field = ownership, redcap_pair_id_field = pair_id)

merged <- raw %>%
  mutate(record_id = as.character(record_id)) %>%
  left_join(crosswalk_long %>% mutate(record_id = as.character(record_id)),
            by = "record_id")

# Three-way cross-check: crosswalk vs the raw export's own (caller-hidden) fields vs the
# fielded sheet's PE_or_Not/Matched Pair ID, all for the same NPI. All three are supposed to
# describe the same clinician; a disagreement means something upstream is stale and must be
# found, not adjudicated by silently preferring one file over another.
check <- merged %>%
  distinct(NPI, ownership, pair_id, redcap_ownership_field, redcap_pair_id_field) %>%
  inner_join(sheet %>% distinct(NPI = as.character(NPI), PE_or_Not, `Matched Pair ID`),
            by = "NPI")
xwalk_pe_label  <- ifelse(check$ownership == "PE", "PE", "Non-PE")
raw_pe_label    <- ifelse(is.na(check$redcap_ownership_field), NA_character_,
                          c("1" = "PE", "2" = "Non-PE")[as.character(check$redcap_ownership_field)])
disagree <- check[
  xwalk_pe_label != check$PE_or_Not |
  check$pair_id  != check$`Matched Pair ID` |
  (!is.na(raw_pe_label) & raw_pe_label != check$PE_or_Not) |
  (!is.na(check$redcap_pair_id_field) & check$redcap_pair_id_field != check$`Matched Pair ID`),
  , drop = FALSE]
if (nrow(disagree)) {
  gate_fail("redcap merge",
           sprintf("%d NPI(s) disagree on ownership or pair id across the crosswalk, the raw",
                   nrow(disagree)),
           " REDCap export's own fields, and ", basename(SHEET_PATH), ".",
           "\n\n  These three sources are supposed to describe the same 400 clinicians. A",
           " disagreement means one of them is stale -- find out which before trusting any.")
}

# ---------------------------------------------------------------------------- derive outcomes
#
# mysterycall_prepare_calls() does the real work: resolves the second-call-attempt contact
# logic, applies this study's own exclusion-code inclusion rule (its default,
# logistic_include_codes = c(0,7,9,10), already matches this study's data dictionary), and
# computes business_days_until_appointment via mysterycall_count_business_days(). Not
# reimplemented here.
prepared <- mysterycall::mysterycall_prepare_calls(merged)

cat("\n--- Waterfall ---\n"); print(prepared$waterfall)
cat("\n--- Exclusion summary ---\n"); print(prepared$exclusion_summary)

obtained_by_id <- prepared$logistic_data %>%
  transmute(record_id = as.character(record_id), obtained = appt_offered)
waittime_by_id <- prepared$waittime_data %>%
  transmute(record_id = as.character(record_id), business_days_until_appointment,
           calendar_days)

# ---------------------------------------------------------------------------- transfers, hold time
#
# transfers is decoded by decode_redcap_transfers() (R/pe_helpers.R, tested in
# tests/testthat/test-decode-redcap-transfers.R) -- not reimplemented here.
#
# holdtime/calltime are validated as integer *seconds* in the data dictionary (min 0, max
# 1000). SAP.lock's >5-minute-hold exclusion (code 2) is stated in minutes, so hold_time is
# converted to minutes here for a consistent unit across the study database.
tr <- decode_redcap_transfers(merged$transfers)

# ---------------------------------------------------------------------------- assemble
#
# Every raw row is kept (the source population), with obtained / business_days_until_appointment
# NA where mysterycall_prepare_calls() excluded the record from that dataset -- not dropped, so
# the source/eligible/analytic distinction stays auditable rather than collapsing to only the
# analytic rows.
study_db <- merged %>%
  transmute(record_id, NPI, pair_id, ownership, payer,
           call_date       = calldate1,
           appointment_date = appdate,
           hold_time        = suppressWarnings(as.numeric(holdtime)) / 60,
           calltime_seconds = suppressWarnings(as.numeric(calltime)),
           exclusions       = suppressWarnings(as.integer(exclusions))) %>%
  mutate(transfers = tr$transfers, transfers_censored = tr$transfers_censored) %>%
  left_join(obtained_by_id, by = "record_id") %>%
  left_join(waittime_by_id, by = "record_id") %>%
  left_join(sheet %>% mutate(NPI = as.character(NPI)) %>%
            select(NPI, `Matched Pair ID`, PE_or_Not, State, phone_id, same_phone_within_pair,
                   SVI_geocode_via, Eligible, Taxonomy_Is_OBGYN, Platform_Excluded,
                   CDC_SVI_real, SVI_tract_fips),
            by = "NPI")

# ---------------------------------------------------------------------------- QC gates
#
# Real, already-tested guards -- not written for the first time here. exclusion_col must hold
# a label whose success value equals contact_value, not the raw integer code (0-10), so build
# the binary label the guard expects rather than pass the integer column directly.
study_db <- study_db %>%
  mutate(reason_for_exclusions = ifelse(exclusions == 0L, "Able to contact", "Not able to contact"))

guard <- mysterycall::mysterycall_guard_contaminated_wait(
  study_db, wait_col = "business_days_until_appointment",
  appointment_col = "appointment_date", exclusion_col = "reason_for_exclusions",
  contact_value = "Able to contact", action = "error"
)

gate_business_days_correct(study_db %>% filter(!is.na(business_days_until_appointment)))

n_source   <- nrow(study_db)
n_eligible <- sum(!is.na(study_db$obtained))
n_analytic <- sum(!is.na(study_db$business_days_until_appointment))
stopifnot("source >= eligible >= analytic must hold" = n_source >= n_eligible &&
         n_eligible >= n_analytic)
cat(sprintf("\nPopulations: %d source rows | %d eligible (logistic) | %d analytic (wait-time)\n",
           n_source, n_eligible, n_analytic))

write_csv(study_db, OUT_PATH)
record_output_provenance(
  basename(OUT_PATH),
  c(basename(RAW_EXPORT_PATH), basename(CROSSWALK_PATH), basename(SHEET_PATH)),
  "build_study_database_from_redcap.R", "derived",
  path = file.path(root, "manuscript", "PROVENANCE.csv")
)
cat(sprintf("\nWrote %s (%d rows, %d columns).\n", OUT_PATH, nrow(study_db), ncol(study_db)))
