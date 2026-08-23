#!/usr/bin/env Rscript
# Contextual covariates: ACS female insurance, HRSA AHRF supply, CMS enrollment, NPPES churn.
#
# WHAT THIS FILE USED TO BE, AND WHY THAT MATTERED.
#
# Until 2026-08-10 this script contained verbatim local copies of four functions that the
# mysterycall package already exports, under the same names:
#
#     mysterycall_track_clinician_churn        mysterycall/R/demographic_covariates.R:12
#     mysterycall_get_acs_female_insurance     mysterycall/R/demographic_covariates.R:97
#     mysterycall_get_hrsa_ahrf                mysterycall/R/demographic_covariates.R:142
#     mysterycall_get_cms_enrollment           mysterycall/R/demographic_covariates.R:170
#
# Shadowing an exported name is worse than an ordinary duplicate: whichever definition is
# sourced last wins, silently, and which one that is depends on script order.
#
# The consequence is on the record. apply_demographic_covariates.R called none of these. It
# generated Tract_Pct_Female_*, County_OBGYN_Count and both County_*_Enrollment with rnorm()
# and clamps, describing that in its own header as "standard fallback simulations to ensure
# full dataset completeness." The real-data path existed in the author's own package the entire
# time and was bypassed by a local copy. See docs/CANONICAL_SOURCES_AUDIT.md (A1) and
# manuscript/appendix_data_provenance.md.
#
# The local definitions are gone. This script now calls the canonical functions and fails
# loudly when the inputs they need are absent, rather than substituting numbers.

suppressMessages({
  library(mysterycall)
  library(dplyr)
})

# Every one of these functions needs an input this repository does not and should not carry:
# a Census API key, an 80 GB NPPES history database, a licensed HRSA extract, a CMS download.
# They are read from the environment so that a missing input is a clear stop rather than a
# silent fallback.
CENSUS_API_KEY <- Sys.getenv("CENSUS_API_KEY", "")
NPPES_DUCKDB   <- Sys.getenv("NPPES_HISTORY_DUCKDB", "")
AHRF_DB        <- Sys.getenv("HRSA_AHRF_PATH", "")
CMS_CSV        <- Sys.getenv("CMS_ENROLLMENT_CSV", "")

require_input <- function(value, name, what) {
  if (!nzchar(value)) {
    stop(sprintf(paste0(
      "\n\n  %s is not set.\n  %s\n\n",
      "  This script will not substitute simulated values for a missing input. That is what\n",
      "  produced the covariate defect documented in Appendix S2. Set the variable, or do not\n",
      "  run this step and leave the columns absent.\n"), name, what), call. = FALSE)
  }
  if (grepl("PATH|DUCKDB|CSV", name) && !file.exists(value)) {
    stop(sprintf("%s points at a path that does not exist: %s", name, value), call. = FALSE)
  }
  value
}

# ---------------------------------------------------------------- 1. clinician churn
#' Annual staffing, entries, exits and churn at a practice location.
#' Canonical implementation: mysterycall::mysterycall_track_clinician_churn().
track_churn <- function(street_address, zip_code,
                        table_name = "temporal_obgyn_only_all_years") {
  db <- require_input(NPPES_DUCKDB, "NPPES_HISTORY_DUCKDB",
                      "Path to the NPPES historical DuckDB used to track office staffing.")
  mysterycall::mysterycall_track_clinician_churn(
    db_path = db, street_address = street_address, zip_code = zip_code,
    table_name = table_name)
}

# ---------------------------------------------------------------- 2. ACS female insurance
#' Tract-level female health-insurance coverage shares, ACS table S2701.
#' Canonical implementation: mysterycall::mysterycall_get_acs_female_insurance().
acs_female_insurance <- function(state_fips, county_fips) {
  key <- require_input(CENSUS_API_KEY, "CENSUS_API_KEY",
                       "US Census Bureau API key. Request one at api.census.gov/data/key_signup.html")
  mysterycall::mysterycall_get_acs_female_insurance(
    api_key = key, state_fips = state_fips, county_fips = county_fips)
}

# ---------------------------------------------------------------- 3. HRSA AHRF supply
#' County-level clinician supply from the HRSA Area Health Resources File.
#' Canonical implementation: mysterycall::mysterycall_get_hrsa_ahrf().
ahrf_supply <- function(county_fips) {
  db <- require_input(AHRF_DB, "HRSA_AHRF_PATH", "Path to the HRSA AHRF extract.")
  mysterycall::mysterycall_get_hrsa_ahrf(ahrf_db_path = db, county_fips = county_fips)
}

# ---------------------------------------------------------------- 4. CMS enrollment
#' County-level monthly Medicare and Medicaid/CHIP enrollment.
#' Canonical implementation: mysterycall::mysterycall_get_cms_enrollment().
cms_enrollment <- function(county_fips) {
  csv <- require_input(CMS_CSV, "CMS_ENROLLMENT_CSV",
                       "Path to the CMS monthly county-level enrollment CSV.")
  mysterycall::mysterycall_get_cms_enrollment(cms_csv_path = csv, county_fips = county_fips)
}

if (identical(environment(), globalenv()) && !interactive()) {
  message("Canonical covariate fetchers are available as track_churn(), acs_female_insurance(),")
  message("ahrf_supply() and cms_enrollment(). Each wraps the mysterycall function of the same")
  message("purpose and stops if its input is unset. Nothing is fetched by sourcing this file.")
  present <- c(CENSUS_API_KEY = nzchar(CENSUS_API_KEY), NPPES_HISTORY_DUCKDB = nzchar(NPPES_DUCKDB),
               HRSA_AHRF_PATH = nzchar(AHRF_DB), CMS_ENROLLMENT_CSV = nzchar(CMS_CSV))
  message("\nInputs configured: ",
          if (any(present)) paste(names(present)[present], collapse = ", ") else "none")
  if (!all(present)) message("Missing: ", paste(names(present)[!present], collapse = ", "))
}
