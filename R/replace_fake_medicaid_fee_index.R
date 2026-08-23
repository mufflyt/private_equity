#!/usr/bin/env Rscript
# =============================================================================
# Replace the fabricated Medicaid_Fee_Index column in
# pe_obgyn_final_calling_sheet_300.csv with the real KFF state-level index.
#
# The existing column does not match the real 2024 KFF/Urban Institute data
# (e.g. AL shows 0.69 here vs. the real 0.92; MI has two different values,
# 0.66 and 0.61, for the same state, which a real state-level join could not
# produce). See R/fetch_medicaid_fee_index.R for how the real source was
# fetched and verified.
#
# Real input: data/covariates/medicaid_fee_index.csv (state -> medicaid_fee_index)
#
# Reuses the pe_obgyn_final_calling_sheet_300.ORIGINAL_FAKE.csv backup
# convention from R/replace_fake_covariates.R -- only created if it doesn't
# already exist, so the true pre-correction original is preserved once.
# =============================================================================

options(stringsAsFactors = FALSE)
sheet_path <- "pe_obgyn_final_calling_sheet_300.csv"
backup     <- "pe_obgyn_final_calling_sheet_300.ORIGINAL_FAKE.csv"

sh <- read.csv(sheet_path, colClasses = "character", check.names = FALSE)
if (!file.exists(backup)) invisible(file.copy(sheet_path, backup))

kff <- read.csv("data/covariates/medicaid_fee_index.csv", colClasses = "character", na.strings = NULL)
fee_by_state <- setNames(kff$medicaid_fee_index, kff$state)

old <- sh$Medicaid_Fee_Index
unknown <- setdiff(unique(sh$State), kff$state)
if (length(unknown) > 0)
  stop("State(s) not in the KFF fee index table at all: ", paste(unknown, collapse = ", "))

new <- unname(fee_by_state[sh$State])
if (any(new == "NA")) {
  na_states <- sort(unique(sh$State[new == "NA"]))
  cat("Note: KFF has no comparable Medicaid fee schedule for:", paste(na_states, collapse = ", "),
      "-- writing as honest missing (blank), not a placeholder.\n")
  new[new == "NA"] <- NA_character_
}
sh$Medicaid_Fee_Index <- new

utils::write.csv(sh, sheet_path, row.names = FALSE, na = "")

changed <- sum(old != new, na.rm = TRUE)
cat(sprintf("Replaced Medicaid_Fee_Index for %d/%d rows (values that changed: %d).\n",
            nrow(sh), nrow(sh), changed))
cat("Sample before -> after (first row per state, first 8 states):\n")
states8 <- head(sort(unique(sh$State)), 8)
for (st in states8) {
  i <- which(sh$State == st)[1]
  cat(sprintf("  %-3s %s -> %s\n", st, old[i], new[i]))
}
cat("Backup:", backup, "\n")
