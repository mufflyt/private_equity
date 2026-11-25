#!/usr/bin/env Rscript
# Cross-reference the calling sheet's dialed Phone against the three phone databases
# (NPPES, CMS DAC, scraped) and stamp the sheet with Phone_Database_Matches and
# Phone_Verification_Status. Port of cross_reference_phones.py, which is deleted -- the
# pipeline is R-only for live data.
#
# Two defects in the Python original are fixed here, not preserved:
#   1. The lookup was dtype-fragile: `npi not in db_lookup.index` compares int64 against
#      whatever dtype pandas inferred, so a float-parsed NPI column silently matched
#      NOTHING and every row fell through to "Unverified" without a word. Keys here are
#      normalised through npi_key() on both sides.
#   2. Duplicated NPIs in the study database were collapsed with iloc[0] -- first row by
#      accident of iteration order. Duplicates are now counted and reported, and the
#      first-row choice is explicit rather than silent.
#
# The counting rule itself is phone_verification() in R/pe_helpers.R, shared with
# dedup_offices_and_backfill_200.R so the two cannot drift.
#
# Usage: Rscript cross_reference_phones.R [--sheet=FILE] [--db=FILE]

suppressMessages(library(readr))
source(file.path("R", "pe_helpers.R"))

argval <- function(flag, default) {
  a <- commandArgs(trailingOnly = TRUE)
  v <- sub(paste0("^", flag, "="), "", grep(paste0("^", flag, "="), a, value = TRUE))
  if (length(v)) v[1] else default
}
SHEET <- argval("--sheet", "pe_obgyn_final_calling_sheet_300.csv")
DB    <- argval("--db",    "pe_obgyn_study_database.csv")

sheet <- read_csv(SHEET, col_types = cols(.default = col_character()))
db    <- read_csv(DB,    col_types = cols(.default = col_character()))

db$k     <- npi_key(db$NPI)
sheet$k  <- npi_key(sheet$NPI)

ndup <- sum(duplicated(db$k))
if (ndup > 0)
  cat(sprintf("  NOTE: %d duplicated NPI rows in %s; first occurrence used, explicitly.\n",
              ndup, basename(DB)))
dbu <- db[!duplicated(db$k), ]

idx <- match(sheet$k, dbu$k)
missing_sheet <- sum(is.na(idx))
if (missing_sheet > 0)
  cat(sprintf("  NOTE: %d sheet rows have no study-database NPI and stay Unverified.\n",
              missing_sheet))

ph <- dbu[idx, , drop = FALSE]
ver <- phone_verification(sheet$Phone, ph$`NPPES Phone`, ph$`DAC Phone`, ph$`Scraped Phone`)
ver$Phone_Database_Matches[is.na(idx)]   <- 0L
ver$Phone_Verification_Status[is.na(idx)] <- "Unverified"

sheet$Phone_Database_Matches   <- ver$Phone_Database_Matches
sheet$Phone_Verification_Status <- ver$Phone_Verification_Status
sheet$k <- NULL

n <- nrow(sheet)
tb <- table(factor(ver$Phone_Database_Matches, levels = 0:3))
cat("Phone validation cross-reference results:\n")
cat(sprintf("- Checked: %d rows\n", n))
cat(sprintf("- Matches in 2+ databases: %d (%.1f%%)\n", sum(ver$Phone_Database_Matches >= 2),
            100 * mean(ver$Phone_Database_Matches >= 2)))
cat(sprintf("- Matches in 1 database:  %d (%.1f%%)\n", sum(ver$Phone_Database_Matches == 1),
            100 * mean(ver$Phone_Database_Matches == 1)))
cat(sprintf("- Matches in 0 databases: %d (%.1f%%)\n", sum(ver$Phone_Database_Matches == 0),
            100 * mean(ver$Phone_Database_Matches == 0)))

write_csv(sheet, SHEET)
cat(sprintf("%s updated with phone verification columns.\n", basename(SHEET)))
