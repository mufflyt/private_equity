#!/usr/bin/env Rscript
# Re-draw the fielded 200-pair calling set so that no two fielded clinicians share a
# physical office, then backfill from the full 511-pair matched pool to get back to 200.
#
# Why this exists: build_matched_control_group_psm.R clusters *only the PE arm* by
# address (controls get a synthetic control_office_<i>, and PE clinicians whose address
# failed to parse get office_singleton_<id>). The unique-office_id invariant therefore
# holds by construction and hides real duplication: in the fielded 200, 110 of 400 rows
# share a dialed phone number with another row, including one Miami front desk that
# appears 15 times and one matched pair whose PE and control clinician share a number.
#
# This script re-selects the fielded set from the full pool under an explicit
# no-shared-office constraint, keeping the existing geographic balancing method
# (round-robin across states, which caps Florida) and preferring already-fielded pairs
# so churn against the current sheet is minimised.
#
# Selection unit is the matched pair: if either member collides, the pair is unusable,
# because dropping one member alone would break 1-to-1 matching.
#
# Usage:
#   Rscript dedup_offices_and_backfill_200.R                  # dry run, writes audit only
#   Rscript dedup_offices_and_backfill_200.R --out=FILE.csv   # write redraw to a new file
#   Rscript dedup_offices_and_backfill_200.R --apply          # backs up + overwrites the sheet
#   Rscript dedup_offices_and_backfill_200.R --apply --phone-only
#
# --out writes the full redrawn sheet to a path of your choosing and never touches
# pe_obgyn_final_calling_sheet_200.csv; it refuses to clobber an existing file.
#
# After --apply, redcap_import_ready_200.csv and redcap_physician_name_choices.txt are
# stale. Re-run build_200_redcap_import.R with REDRAW <- FALSE (see note at the bottom).

suppressMessages({library(readr); library(dplyr); library(stringr)})

POOL       <- "pe_obgyn_matched_calling_list.csv"          # 511 pairs, 11 cols
SHEET200   <- "pe_obgyn_final_calling_sheet_200.csv"       # current fielded set, 28 cols
STUDY_DB   <- "pe_obgyn_study_database.csv"                # address + NPPES/DAC/Scraped phones
CHURN_DB   <- "pe_obgyn_study_database_with_churn.csv"     # 15 enrichment columns
AUDIT_OUT  <- "dedup_backfill_audit.csv"
BACKUP_DIR <- "backups"
N_TARGET   <- 200L
SEED       <- 1978L                                        # same seed as build_200_redcap_import.R

args       <- commandArgs(trailingOnly = TRUE)
APPLY      <- "--apply" %in% args
PHONE_ONLY <- "--phone-only" %in% args
OUT        <- sub("^--out=", "", grep("^--out=", args, value = TRUE))
OUT        <- if (length(OUT) > 0) OUT[1] else ""
WRITE      <- APPLY || nzchar(OUT)

# 15 columns carried from the churn database; the 2 phone-verification columns are
# recomputed below because they are derived from the sheet's own Phone value.
ENRICH_DB <- c("CDC_SVI", "Medicaid_Fee_Index", "PE_Concentration_15mi", "HQ_Distance_Miles",
               "Tract_Pct_Female_Private", "Tract_Pct_Female_Medicaid", "Tract_Pct_Female_Medicare",
               "Tract_Pct_Female_Uninsured", "County_OBGYN_Count", "County_Medicare_Enrollment",
               "County_Medicaid_Enrollment", "Mean_Annual_Churn", "Total_Exits", "Total_Entries",
               "Max_Staff_Count")
ENRICH_PHONE <- c("Phone_Database_Matches", "Phone_Verification_Status")

# ---------------------------------------------------------------- helpers

# Pure helpers live in R/pe_helpers.R so they can be unit-tested without running this
# pipeline. Sourcing that file has no side effects.
source(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])),
                 "R", "pe_helpers.R"))

# ---------------------------------------------------------------- load

for (f in c(POOL, SHEET200, STUDY_DB, CHURN_DB)) {
  if (!file.exists(f)) stop(sprintf("Required input not found: %s", f))
}

pool     <- read_csv(POOL,     show_col_types = FALSE) %>% mutate(npi_key = npi_key(NPI))
current  <- read_csv(SHEET200, show_col_types = FALSE) %>% mutate(npi_key = npi_key(NPI))
study_db <- read_csv(STUDY_DB, show_col_types = FALSE, name_repair = "minimal") %>%
  mutate(npi_key = npi_key(NPI)) %>% distinct(npi_key, .keep_all = TRUE)
churn_db <- read_csv(CHURN_DB, show_col_types = FALSE, name_repair = "minimal") %>%
  mutate(npi_key = npi_key(NPI)) %>% distinct(npi_key, .keep_all = TRUE)

sheet_cols   <- names(current)[names(current) != "npi_key"]
current_pair <- unique(current$`Matched Pair ID`)

cat(sprintf("Pool: %d pairs (%d clinicians) | current fielded: %d pairs\n",
            n_distinct(pool$`Matched Pair ID`), nrow(pool), length(current_pair)))

missing_db <- setdiff(pool$npi_key, study_db$npi_key)
if (length(missing_db) > 0)
  cat(sprintf("  NOTE: %d pool NPIs absent from %s; address blocking unavailable for them.\n",
              length(missing_db), STUDY_DB))

# ---------------------------------------------------------------- block keys

addr_lookup <- tibble(npi_key = study_db$npi_key, addr = address_key(study_db))

pool <- pool %>%
  left_join(addr_lookup, by = "npi_key") %>%
  mutate(
    k_phone = phone_key(Phone),
    k_addr  = if (PHONE_ONLY) NA_character_ else addr
  )

if (any(is.na(pool$k_phone)))
  cat(sprintf("  NOTE: %d pool rows have no usable phone; blocked on address only.\n",
              sum(is.na(pool$k_phone))))
cat(sprintf("Blocking on: phone%s | address key resolved for %d/%d pool rows\n",
            if (PHONE_ONLY) " only" else " + address",
            sum(!is.na(pool$k_addr)), nrow(pool)))

keys_of <- function(idx) {
  k <- c(paste0("P:", pool$k_phone[idx]), paste0("A:", pool$k_addr[idx]))
  unique(k[!grepl("NA$", k)])
}

pair_rows <- split(seq_len(nrow(pool)), pool$`Matched Pair ID`)
pair_keys <- lapply(pair_rows, keys_of)

# A pair whose two members share a key is unusable at any sample size: the PE clinician
# and their matched control sit at the same front desk, so the contrast is confounded.
self_collide <- names(pair_rows)[vapply(pair_rows, function(idx) {
  length(intersect(keys_of(idx[1]), keys_of(idx[2]))) > 0
}, logical(1))]
cat(sprintf("Pairs dropped as internally collided (PE and its control co-located): %d\n",
            length(self_collide)))

# ---------------------------------------------------------------- ordering

# Round-robin across states, as in build_200_redcap_import.R: rank pairs within each
# state, then take rank 1 of every state, rank 2 of every state, and so on. Small states
# fill first and large ones are capped, which is what holds Florida down. The only change
# is the tie-break -- already-fielded pairs sort to the front of their state, so the
# redraw keeps as much of the current sheet as the constraint allows.
set.seed(SEED)

ordering <- pool %>%
  distinct(pair = `Matched Pair ID`, State) %>%
  filter(!pair %in% self_collide) %>%
  mutate(fielded = pair %in% current_pair) %>%
  group_by(State) %>%
  slice_sample(prop = 1) %>%
  arrange(desc(fielded), .by_group = TRUE) %>%
  mutate(rank = row_number()) %>%
  ungroup() %>%
  arrange(rank, State)

# ---------------------------------------------------------------- greedy selection

accepted <- character(0)
used     <- new.env(parent = emptyenv())
audit    <- list()

for (i in seq_len(nrow(ordering))) {
  p <- ordering$pair[i]
  k <- pair_keys[[p]]
  hit <- k[vapply(k, exists, logical(1), envir = used, inherits = FALSE)]

  if (length(accepted) >= N_TARGET) {
    status <- "not_needed"; conflict <- NA_character_; against <- NA_character_
  } else if (length(hit) > 0) {
    status   <- "dropped_shares_office"
    conflict <- hit[1]
    against  <- get(hit[1], envir = used)
  } else {
    for (key in k) assign(key, p, envir = used)
    accepted <- c(accepted, p)
    status <- "selected"; conflict <- NA_character_; against <- NA_character_
  }

  audit[[length(audit) + 1]] <- tibble(
    pair = p, State = ordering$State[i], was_fielded = ordering$fielded[i],
    status = status, conflict_key = conflict, conflicts_with = against
  )
}

audit <- bind_rows(
  audit,
  tibble(pair = self_collide,
         State = vapply(self_collide, function(p) pool$State[pair_rows[[p]][1]], character(1)),
         was_fielded = self_collide %in% current_pair,
         status = "dropped_pair_self_collision",
         conflict_key = NA_character_, conflicts_with = NA_character_)
) %>%
  mutate(now_fielded = pair %in% accepted) %>%
  arrange(match(status, c("selected", "dropped_shares_office",
                          "dropped_pair_self_collision", "not_needed")), State, pair)

write_csv(audit, AUDIT_OUT)

if (length(accepted) < N_TARGET) {
  cat(sprintf("\nSHORTFALL: only %d of %d pairs are office-disjoint under this blocking.\n",
              length(accepted), N_TARGET))
  cat("  Options: rerun with --phone-only, lower N_TARGET, or widen the control pool.\n")
  if (WRITE) stop("Refusing to write a short calling sheet.")
}

# ---------------------------------------------------------------- build the sheet

kept   <- intersect(accepted, current_pair)
added  <- setdiff(accepted, current_pair)
lost   <- setdiff(current_pair, accepted)

# Retained pairs keep their existing enriched rows verbatim; backfilled pairs are
# rebuilt from the pool's 11 columns plus the enrichment join.
retained_rows <- current %>% filter(`Matched Pair ID` %in% kept)

new_rows <- pool %>%
  filter(`Matched Pair ID` %in% added) %>%
  select(all_of(intersect(sheet_cols, names(pool))), npi_key) %>%
  left_join(churn_db %>% select(npi_key, all_of(ENRICH_DB)), by = "npi_key")

# Recompute the phone-verification columns exactly as cross_reference_phones.py does:
# count how many of NPPES / CMS-DAC / WebScrape agree with the dialed number.
verify_phone <- function(df) {
  src <- df %>% select(npi_key) %>%
    left_join(study_db %>% select(npi_key, `NPPES Phone`, `DAC Phone`, `Scraped Phone`),
              by = "npi_key")
  dialed <- phone_key(df$Phone)
  hits <- cbind(NPPES     = !is.na(dialed) & dialed == phone_key(src$`NPPES Phone`),
                `CMS-DAC` = !is.na(dialed) & dialed == phone_key(src$`DAC Phone`),
                WebScrape = !is.na(dialed) & dialed == phone_key(src$`Scraped Phone`))
  hits[is.na(hits)] <- FALSE
  n <- rowSums(hits)
  first_src <- apply(hits, 1, function(r) if (any(r)) colnames(hits)[which(r)[1]] else NA_character_)
  tibble(Phone_Database_Matches = as.integer(n),
         Phone_Verification_Status = ifelse(n >= 2, "Verified (2+ DBs)",
                                     ifelse(n == 1, sprintf("Verified (1 DB: %s)", first_src),
                                            "Unverified")))
}

if (nrow(new_rows) > 0) new_rows <- bind_cols(new_rows %>% select(-any_of(ENRICH_PHONE)),
                                              verify_phone(new_rows))

final <- bind_rows(retained_rows, new_rows) %>%
  select(all_of(sheet_cols)) %>%
  mutate(.sort = as.numeric(str_remove(`Matched Pair ID`, "pair_"))) %>%
  arrange(.sort, PE_or_Not) %>%
  select(-.sort)

# ---------------------------------------------------------------- verify

fk <- final %>% mutate(npi_key = npi_key(NPI)) %>%
  left_join(addr_lookup, by = "npi_key") %>%
  mutate(k_phone = phone_key(Phone), k_addr = if (PHONE_ONLY) NA_character_ else addr)

stopifnot(
  "pair count != target"          = n_distinct(final$`Matched Pair ID`) == N_TARGET,
  "row count != 2 x target"       = nrow(final) == 2L * N_TARGET,
  "arms not balanced"             = all(table(final$PE_or_Not) == N_TARGET),
  "every pair must have 2 rows"   = all(table(final$`Matched Pair ID`) == 2L),
  "duplicate NPI in fielded set"  = !any(duplicated(final$NPI)),
  "column schema changed"         = identical(names(final), sheet_cols),
  "duplicate phone survived"      = !any(duplicated(na.omit(fk$k_phone))),
  "duplicate address survived"    = PHONE_ONLY || !any(duplicated(na.omit(fk$k_addr)))
)

before <- current %>% mutate(k = phone_key(Phone))
cat(sprintf("\n--- shared-phone rows: %d/%d before -> %d/%d after ---\n",
            sum(before$k %in% before$k[duplicated(before$k)], na.rm = TRUE), nrow(before),
            sum(fk$k_phone %in% fk$k_phone[duplicated(fk$k_phone)], na.rm = TRUE), nrow(fk)))
cat(sprintf("Pairs: %d retained, %d backfilled, %d dropped (churn %.0f%%)\n",
            length(kept), length(added), length(lost), 100 * length(added) / N_TARGET))

st <- full_join(count(current, State, name = "before") %>% mutate(before = before / 2L),
                count(final,   State, name = "after")  %>% mutate(after  = after  / 2L),
                by = "State") %>%
  mutate(across(c(before, after), ~ ifelse(is.na(.x), 0, .x))) %>%
  arrange(desc(after))
cat(sprintf("States: %d before -> %d after | FL share: %.0f%% -> %.0f%%\n",
            n_distinct(current$State), n_distinct(final$State),
            100 * sum(st$before[st$State == "FL"]) / N_TARGET,
            100 * sum(st$after[st$State == "FL"]) / N_TARGET))
print(as.data.frame(st), row.names = FALSE)

vs <- count(final, Phone_Verification_Status, sort = TRUE)
cat("\nPhone verification in the redrawn set:\n"); print(as.data.frame(vs), row.names = FALSE)
if (any(is.na(final$HQ_Distance_Miles)))
  cat(sprintf("  NOTE: %d rows have no HQ_Distance_Miles after enrichment.\n",
              sum(is.na(final$HQ_Distance_Miles))))

# ---------------------------------------------------------------- write

if (nzchar(OUT)) {
  if (file.exists(OUT)) stop(sprintf("Refusing to overwrite an existing file: %s", OUT))
  write_csv(final, OUT)
  cat(sprintf("\nWrote %s (%d pairs / %d clinicians)\nAudit: %s\n%s left untouched.\n",
              OUT, N_TARGET, nrow(final), AUDIT_OUT, SHEET200))
} else if (!APPLY) {
  cat(sprintf("\nDRY RUN. Wrote %s only. Re-run with --apply to replace %s.\n", AUDIT_OUT, SHEET200))
} else {
  dir.create(BACKUP_DIR, showWarnings = FALSE)
  bk <- file.path(BACKUP_DIR, sprintf("pe_obgyn_final_calling_sheet_200_%s.csv",
                                      format(Sys.time(), "%Y%m%d_%H%M%S")))
  file.copy(SHEET200, bk, overwrite = FALSE)
  write_csv(final, SHEET200)
  cat(sprintf("\nBacked up to %s\nWrote %s (%d pairs / %d clinicians)\nAudit: %s\n",
              bk, SHEET200, N_TARGET, nrow(final), AUDIT_OUT))
  cat("\nNEXT: the REDCap load files are now stale. Regenerate them with\n")
  cat("  Rscript build_200_redcap_import.R\n")
  cat("  which reads this sheet as-is. Do NOT pass --redraw: that re-derives the fielded\n")
  cat("  200 from the 300-pair sheet and would discard this de-duplication.\n")
}
