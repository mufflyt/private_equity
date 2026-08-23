#!/usr/bin/env Rscript
# =============================================================================
# State-level Medicaid-to-Medicare fee index (physician fees), replacing the
# Medicaid_Fee_Index column referenced by dedup_offices_and_backfill_200.R
# with a real measurement instead of a placeholder/simulated value. See
# docs/CANONICAL_SOURCES_AUDIT.md (A1) for why this repo now insists on
# fetching real source data rather than approximating it.
#
# Source: KFF State Health Facts, "Medicaid-to-Medicare Fee Index"
#   https://www.kff.org/medicaid/state-indicator/medicaid-to-medicare-fee-index/
#   Underlying data: Laura Skopec, Avani Pugazhendhi, and Stephen Zuckerman,
#   "Updated Medicaid-To-Medicare Fee Index: Medicaid Physician Fees Still Lag
#   Behind Medicare Physician Fees," Urban Institute, May 2025 (2024 fee data).
#   KFF renders this page from a public Google Sheet, fetched directly below.
#
# Output: data/covariates/medicaid_fee_index.csv
#   state, medicaid_fee_index (= All Services), medicaid_fee_index_primary_care,
#   medicaid_fee_index_obstetric_care, medicaid_fee_index_other_services
# =============================================================================

options(timeout = 300)
dir.create("data/covariates", showWarnings = FALSE, recursive = TRUE)

KFF_SHEET_URL <- paste0(
  "https://docs.google.com/spreadsheets/d/",
  "13HN-M0ip23XkIiLYZrZ3MMuBjp08Yte9WQEvTCLMit4/export?format=csv"
)

cache <- file.path(tempdir(), "kff_fee_index.csv")
utils::download.file(KFF_SHEET_URL, cache, quiet = TRUE)

raw <- utils::read.csv(cache, skip = 2, header = FALSE, colClasses = "character",
                        col.names = c("state_name", "all_services", "primary_care",
                                      "obstetric_care", "other_services"))
raw <- raw[nzchar(raw$state_name) & raw$state_name != "United States", ]

state_lookup <- c(setNames(state.abb, state.name), "District of Columbia" = "DC")
state_abb <- unname(state_lookup[raw$state_name])
if (anyNA(state_abb)) {
  stop("Unmapped state name(s) in KFF fee index sheet: ",
       paste(raw$state_name[is.na(state_abb)], collapse = ", "))
}

out <- data.frame(
  state = state_abb,
  medicaid_fee_index = as.numeric(raw$all_services),
  medicaid_fee_index_primary_care = as.numeric(raw$primary_care),
  medicaid_fee_index_obstetric_care = as.numeric(raw$obstetric_care),
  medicaid_fee_index_other_services = as.numeric(raw$other_services)
)
out <- out[order(out$state), ]

utils::write.csv(out, "data/covariates/medicaid_fee_index.csv", row.names = FALSE)
cat(sprintf("Wrote medicaid_fee_index.csv: %d states/DC (KFF, 2024 fee data)\n", nrow(out)))
