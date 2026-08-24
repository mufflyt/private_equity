#!/usr/bin/env Rscript
# Build the REDCap load files for the fielded 200-pair / 800-call set.
#
# GUARD (changed 2026-08-09): this script used to *re-derive* the fielded 200 from
# pe_obgyn_final_calling_sheet_300.csv and overwrite pe_obgyn_final_calling_sheet_200_dedup.csv
# as a side effect of building the REDCap files. That silently destroys any downstream
# correction to the fielded sheet -- in particular the office de-duplication produced by
# dedup_offices_and_backfill_200.R, which cannot be reproduced from the 300-pair sheet at
# all (only ~184 office-disjoint pairs exist there, short of the 200 needed).
#
# The fielded sheet is now an INPUT. This script never writes it unless you explicitly
# pass --redraw, which restores the old round-robin selection.
#
# Usage:
#   Rscript build_200_redcap_import.R                                  # from the default sheet
#   Rscript build_200_redcap_import.R --sheet=FILE.csv --suffix=_dedup # from a specific sheet
#   Rscript build_200_redcap_import.R --redraw                         # legacy: re-draw + overwrite
#
# Record structure: one REDCap record per physician per insurance arm, i.e. 400
# physicians x 2 arms = 800 records. A record cannot hold both arms, because appdate,
# calltime, holdtime and medicaid_status are single-valued per record and
# medicaid_status option 3 is literally "NA as this was a Blue Cross/Blue Shield call".
# contacted2/calldate2 are a *retry* of the same insurance call ("second attempt with
# this insurance type"), not the other arm.

suppressMessages({library(readr); library(dplyr); library(stringr)})
source(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE),
                                                  value = TRUE)[1])), "R", "pe_helpers.R"))

SHEET300 <- "pe_obgyn_final_calling_sheet_300.csv"
SHEET    <- "pe_obgyn_final_calling_sheet_200_dedup.csv"
FORM     <- "acost_three_dx_urogyn_2"
N_TARGET <- 200L                       # pairs
ARMS     <- c("Medicaid", "Blue Cross/Blue Shield")
SEED     <- 1978L

args   <- commandArgs(trailingOnly = TRUE)
REDRAW <- "--redraw" %in% args
argval <- function(flag, default) {
  v <- sub(paste0("^", flag, "="), "", grep(paste0("^", flag, "="), args, value = TRUE))
  if (length(v) > 0) v[1] else default
}
SHEET  <- argval("--sheet", SHEET)
SUFFIX <- argval("--suffix", "")

OUT_IMPORT   <- sprintf("redcap_import_ready_200%s.csv", SUFFIX)
OUT_CHOICES  <- sprintf("redcap_physician_name_choices%s.txt", SUFFIX)
OUT_SCHEDULE <- sprintf("redcap_call_schedule_800%s.csv", SUFFIX)
OUT_CROSSWALK <- sprintf("redcap_slot_crosswalk_400%s.csv", SUFFIX)

# The slot permutation is seeded so a build is reproducible, but unlike the old sorted
# contract it cannot be re-derived from the sheet. OUT_CROSSWALK is therefore the only
# record of which code is which clinician, and must be kept.
SLOT_SEED <- 20260824L

set.seed(SEED)

# ---------------------------------------------------------------- fielded sheet

if (REDRAW) {
  # Legacy path. Round-robin pair selection across states (fills small states first,
  # caps big ones) drawn from the 300-pair sheet, then OVERWRITES the fielded sheet.
  cat("--redraw: re-deriving the fielded 200 from", SHEET300, "and OVERWRITING", SHEET, "\n")
  cat("  WARNING: this discards any office de-duplication already applied to", SHEET, "\n")
  cs <- read_csv(SHEET300, show_col_types = FALSE)
  pair_state <- cs %>% distinct(pair = `Matched Pair ID`, State)
  selected <- pair_state %>%
    group_by(State) %>% slice_sample(prop = 1) %>% mutate(rank = row_number()) %>% ungroup() %>%
    arrange(rank, State) %>% slice_head(n = N_TARGET)
  sheet <- cs %>% filter(`Matched Pair ID` %in% selected$pair)
  write_csv(sheet, SHEET)
  cat(sprintf("Wrote %s\n", SHEET))
} else {
  if (!file.exists(SHEET)) stop(sprintf("Fielded sheet not found: %s", SHEET))
  sheet <- read_csv(SHEET, show_col_types = FALSE)
  cat(sprintf("Reading fielded sheet as-is (not re-derived): %s\n", SHEET))
}

# The sheet is authoritative; fail loudly rather than silently emitting a short load.
stopifnot(
  "fielded sheet must have 2 rows per pair" = all(table(sheet$`Matched Pair ID`) == 2L),
  "unexpected pair count"                   = n_distinct(sheet$`Matched Pair ID`) == N_TARGET,
  "arms not balanced"                       = all(table(sheet$PE_or_Not) == N_TARGET),
  "duplicate NPI in fielded sheet"          = !any(duplicated(sheet$NPI))
)

# A physician appearing twice under one phone number would be called 4 times, not 2.
dial <- gsub("\\D", "", sheet$Phone)
dial <- ifelse(nchar(dial) >= 10, substr(dial, nchar(dial) - 9, nchar(dial)), NA_character_)
shared <- sum(dial %in% dial[duplicated(dial)], na.rm = TRUE)
if (shared > 0) {
  cat(sprintf("  WARNING: %d of %d clinicians share a dialed number with another clinician.\n",
              shared, nrow(sheet)))
  cat("  Those offices will be called more than twice. Run dedup_offices_and_backfill_200.R.\n")
} else {
  cat("  Office check: all dialed numbers distinct -> exactly 2 calls per office.\n")
}

has_backup <- all(c("Backup Provider Name", "Backup Phone") %in% names(sheet))
if (!has_backup)
  cat("  NOTE: no Backup Provider columns on this sheet; labels omit backups and\n",
      "        doctor_called should be recorded as 1 (Primary) for every call.\n")

# ---------------------------------------------------------------- 800 records

# Dropdown codes are DEFINED here, not looked up from the old data dictionary (whose
# physician_name choices belong to the earlier urogyn study). Codes 1..400 are the
# Medicaid calls and 401..800 the BCBS calls, same physicians in the same order, so
# code i and code i+400 are the two calls to one physician.
# Slots are assigned by assign_blinded_slots(), NOT by sorting. Sorting on
# (pair, PE_or_Not) put "Non-PE" before "PE" in every pair, which made record parity a
# perfect predictor of ownership and sat pair members next to each other in the caller's
# dropdown. See R/pe_helpers.R and tests/testthat/test-blinded-slot-assignment.R.
phys <- sheet %>%
  mutate(
    slot  = assign_blinded_slots(`Matched Pair ID`, PE_or_Not, seed = SLOT_SEED),
    label = if (has_backup)
      sprintf("%s (Backup: %s), %s, %s, Phone: %s, NPI: %s",
              `Provider Name`, `Backup Provider Name`, City, State, Phone, NPI)
    else
      sprintf("%s, %s, %s, Phone: %s, NPI: %s", `Provider Name`, City, State, Phone, NPI)
  )

n <- nrow(phys)
combo <- bind_rows(lapply(seq_along(ARMS), function(a) {
  phys %>% transmute(
    code = slot + (a - 1L) * n,
    NPI, `Provider Name`, City, State, Phone, PE_or_Not,
    pair = `Matched Pair ID`, insurance = ARMS[a], label
  )
})) %>% arrange(code)

# physician_name is a dropdown: REDCap imports the CODE, not the label text. Writing the
# human-readable string here (as the previous version did) leaves the field blank on import.
imp <- combo %>%
  transmute(record_id = code, physician_name = code)
imp[[paste0(FORM, "_complete")]] <- 0L

stopifnot(
  "record count != physicians x arms" = nrow(imp) == n * length(ARMS),
  "record_id not contiguous 1..N"     = identical(imp$record_id, seq_len(nrow(imp))),
  "physician_name must be a code"     = is.numeric(imp$physician_name)
)

write_csv(imp, OUT_IMPORT)

# REDCap dropdown CHOICES for physician_name: one "code, label" line per physician x
# insurance. REDCap splits each line on the first comma only, so the label's internal
# commas (city, state, phone, NPI) are preserved.
choice_lines <- sprintf("%d, id: %d, %s, Insurance: %s, id: %d",
                        combo$code, combo$code, combo$label, combo$insurance, combo$code)
writeLines(choice_lines, OUT_CHOICES)

# ---------------------------------------------------------------- call schedule

# The Methods claim randomised arm order with >=48h spacing, but nothing in the
# instrument assigns or enforces it -- calldate1 only lets you recover the order after
# the fact. This emits the assignment the caller should follow.
sched <- phys %>%
  mutate(first_arm = ifelse(runif(n()) < 0.5, ARMS[1], ARMS[2])) %>%
  mutate(second_arm = ifelse(first_arm == ARMS[1], ARMS[2], ARMS[1])) %>%
  transmute(
    `Provider Name`, City, State, Phone, PE_or_Not, pair = `Matched Pair ID`,
    first_arm, second_arm,
    first_record_id  = ifelse(first_arm == ARMS[1], slot, slot + n),
    second_record_id = ifelse(first_arm == ARMS[1], slot + n, slot),
    min_hours_between_calls = 48L
  )
write_csv(sched, OUT_SCHEDULE)

# ---------------------------------------------------------------- slot crosswalk

# The permutation is seeded but not derivable from the sheet, so this file is the mapping.
# It is also the only artifact here that pairs a record id with an ownership label, which is
# exactly why it must not travel with the caller's materials.
crosswalk <- phys %>%
  transmute(
    medicaid_record_id = slot,
    bcbs_record_id     = slot + n,
    NPI, `Provider Name`, City, State, Phone,
    pair_id   = `Matched Pair ID`,
    ownership = PE_or_Not
  ) %>% arrange(medicaid_record_id)
write_csv(crosswalk, OUT_CROSSWALK)

# The leak this replaced: assert it is gone rather than trusting the allocator.
odd_pe <- sum(crosswalk$ownership == "PE" & crosswalk$medicaid_record_id %% 2L == 1L)
stopifnot(
  "record parity still predicts ownership" = odd_pe == sum(crosswalk$ownership == "PE") / 2L,
  "a matched pair still sits on consecutive record ids" =
    !any(crosswalk$pair_id[-1L] == crosswalk$pair_id[-nrow(crosswalk)])
)

# ---------------------------------------------------------------- report

cat(sprintf("\nFielded: %d pairs / %d clinicians across %d states\n",
            n_distinct(sheet$`Matched Pair ID`), n, n_distinct(sheet$State)))
cat(sprintf("Records: %d clinicians x %d arms = %d  (ceiling 800: %s)\n",
            n, length(ARMS), nrow(imp), ifelse(nrow(imp) <= 800, "YES", "NO")))
cat(sprintf("  codes %d-%d = %s | codes %d-%d = %s\n",
            1, n, ARMS[1], n + 1, 2 * n, ARMS[2]))
cat(sprintf("Arm order randomised: %d %s-first, %d %s-first\n",
            sum(sched$first_arm == ARMS[1]), ARMS[1],
            sum(sched$first_arm == ARMS[2]), ARMS[2]))
cat(sprintf("Blinding: parity carries no ownership signal (%d of %d PE on odd record ids)\n",
            odd_pe, sum(crosswalk$ownership == "PE")))
cat(sprintf("\nWrote %s (%d records)\n      %s (%d choice lines)\n      %s (%d clinicians)\n      %s (%d clinicians)\n",
            OUT_IMPORT, nrow(imp), OUT_CHOICES, length(choice_lines), OUT_SCHEDULE, nrow(sched),
            OUT_CROSSWALK, nrow(crosswalk)))
cat("\nPaste the choices file into the physician_name field in the REDCap Online Designer\n")
cat("before importing the records, or every physician_name code will be rejected.\n")
