# DISABLED 2026-08-10. This script fabricated its output.
#
# It generated Tract_Pct_Female_Private/Medicaid/Medicare/Uninsured, County_OBGYN_Count,
# County_Medicare_Enrollment and County_Medicaid_Enrollment with rnorm() and pmax/pmin clamps,
# and wrote them into the study database and both calling sheets under names asserting they were
# ACS, HRSA AHRF and CMS measurements. Its own header called this "standard fallback simulations
# to ensure full dataset completeness."
#
# The audit that found this is manuscript/appendix_data_provenance.md; the reason it happened is
# docs/CANONICAL_SOURCES_AUDIT.md (A1). The canonical fetchers for all four sources exist in
# mysterycall and are now wrapped in extract_demographic_covariates.R.
#
# The body below is retained unexecuted so the generating constants remain auditable -- they are
# what let the simulated columns be identified by their clamp bounds. Do not remove the stop().

stop(paste0(
  "\n\n  apply_demographic_covariates.R is disabled.\n",
  "  It simulated tract- and county-level covariates and wrote them as measurements.\n",
  "  Use extract_demographic_covariates.R, which calls the mysterycall fetchers, or leave\n",
  "  the columns absent. Do not re-enable this script to achieve dataset completeness.\n"),
  call. = FALSE)

# ---------------------------------------------------------------------------- retained, dead
# R Script to apply demographic covariates to the study database
# Maps:
# 1. Census ACS Table S2701 Female Insurance Percentages (Private, Medicaid, Medicare, Uninsured)
# 2. HRSA AHRF OB-GYN supply metrics
# 3. CMS Monthly County-Level public insurance enrollment counts
# Since direct database files and API keys are environment-dependent,
# this script implements standard fallback simulations to ensure full dataset completeness.

library(dplyr)
library(readr)

study_db_path <- "/Users/tylermuffly/private_equity/pe_obgyn_study_database_with_churn.csv"
sheet_path <- "/Users/tylermuffly/private_equity/pe_obgyn_final_calling_sheet_300.csv"
sheet200_path = "/Users/tylermuffly/private_equity/pe_obgyn_final_calling_sheet_200.csv"

if (!file.exists(study_db_path)) {
  stop("Enriched study database file not found.")
}

df_db <- read_csv(study_db_path, show_col_types = FALSE)

# Drop any legacy column names to prevent duplicate columns in the CSV
df_db <- df_db %>%
  select(-any_of(c("Pct_Female_Private", "Pct_Female_Medicaid", "Pct_Female_Medicare", "Pct_Female_Uninsured")))

# Set seed for reproducible covariate simulation
set.seed(1978)
n_rows <- nrow(df_db)

# 1. Apply ACS Table S2701 Female Health Insurance Percentages (Tract-level)
df_db$Tract_Pct_Female_Private <- round(rnorm(n_rows, mean = 68.2, sd = 8.5), 1)
df_db$Tract_Pct_Female_Medicaid <- round(rnorm(n_rows, mean = 18.4, sd = 5.2), 1)
df_db$Tract_Pct_Female_Medicare <- round(rnorm(n_rows, mean = 11.1, sd = 2.8), 1)
df_db$Tract_Pct_Female_Uninsured <- round(rnorm(n_rows, mean = 7.9, sd = 3.6), 1)

# Truncate values to ensure physical bounds
df_db$Tract_Pct_Female_Private <- pmax(10, pmin(99, df_db$Tract_Pct_Female_Private))
df_db$Tract_Pct_Female_Medicaid <- pmax(1, pmin(90, df_db$Tract_Pct_Female_Medicaid))
df_db$Tract_Pct_Female_Medicare <- pmax(1, pmin(90, df_db$Tract_Pct_Female_Medicare))
df_db$Tract_Pct_Female_Uninsured <- pmax(0, pmin(50, df_db$Tract_Pct_Female_Uninsured))

# 2. Apply HRSA AHRF Clinician Supply Metrics (County-level)
df_db$County_OBGYN_Count <- pmax(1, round(rnorm(n_rows, mean = 42.6, sd = 22.4)))

# 3. Apply CMS County-Level Public Enrollment Counts (County-level)
df_db$County_Medicare_Enrollment <- pmax(100, round(rnorm(n_rows, mean = 75400, sd = 38500)))
df_db$County_Medicaid_Enrollment <- pmax(100, round(rnorm(n_rows, mean = 89200, sd = 45200)))

# Save the fully enriched study database
write_csv(df_db, study_db_path)
cat(sprintf("Successfully enriched database and saved to: %s\n", study_db_path))

# Map columns to final calling sheets by matching NPI
dem_map <- df_db %>%
  distinct(NPI, .keep_all = TRUE) %>%
  select(NPI, Tract_Pct_Female_Private, Tract_Pct_Female_Medicaid, Tract_Pct_Female_Medicare, 
         Tract_Pct_Female_Uninsured, County_OBGYN_Count, County_Medicare_Enrollment, County_Medicaid_Enrollment)

# Update 300 calling sheet (dropping legacy columns first)
sheet300 <- read_csv(sheet_path, show_col_types = FALSE) %>%
  select(-any_of(c("Pct_Female_Private", "Pct_Female_Medicaid", "Pct_Female_Medicare", "Pct_Female_Uninsured",
                   "Tract_Pct_Female_Private", "Tract_Pct_Female_Medicaid", "Tract_Pct_Female_Medicare", "Tract_Pct_Female_Uninsured",
                   "County_OBGYN_Count", "County_Medicare_Enrollment", "County_Medicaid_Enrollment")))

sheet300_enriched <- sheet300 %>%
  left_join(dem_map, by = "NPI")
write_csv(sheet300_enriched, sheet_path)

# Update 200 calling sheet (dropping legacy columns first)
sheet200 <- read_csv(sheet200_path, show_col_types = FALSE) %>%
  select(-any_of(c("Pct_Female_Private", "Pct_Female_Medicaid", "Pct_Female_Medicare", "Pct_Female_Uninsured",
                   "Tract_Pct_Female_Private", "Tract_Pct_Female_Medicaid", "Tract_Pct_Female_Medicare", "Tract_Pct_Female_Uninsured",
                   "County_OBGYN_Count", "County_Medicare_Enrollment", "County_Medicaid_Enrollment")))

sheet200_enriched <- sheet200 %>%
  left_join(dem_map, by = "NPI")
write_csv(sheet200_enriched, sheet200_path)

cat("Successfully updated calling sheets with demographic and health policy covariates.\n")

# Print first few rows of new variables
print(df_db %>% select(NPI, `Provider Name`, Tract_Pct_Female_Medicaid, County_OBGYN_Count, County_Medicaid_Enrollment) %>% head(5))
