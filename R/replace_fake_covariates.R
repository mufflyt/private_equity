#!/usr/bin/env Rscript
# =============================================================================
# Replace the 7 seed-1978 rnorm() placeholder columns in
# pe_obgyn_final_calling_sheet_300.csv with real geocoded covariates.
#
# Real inputs (built by the sibling R/ scripts):
#   data/covariates/npi_geography.csv          NPI -> tract_geoid, county_fips
#   data/covariates/tract_female_insurance.csv tract -> 4 female coverage %
#   data/covariates/county_obgyn_count.csv     county -> OB/GYN supply
#   data/covariates/county_enrollment.csv      county -> Medicare, Medicaid
#
# The original file is backed up once to
# pe_obgyn_final_calling_sheet_300.ORIGINAL_FAKE.csv. Rows whose address did
# not geocode keep NA in the affected columns (honest missingness -- unlike the
# rnorm fill). County columns are recovered from ZIP where the tract geocode
# failed but a ZIP is known.
# =============================================================================

options(stringsAsFactors = FALSE)
sheet_path <- "pe_obgyn_final_calling_sheet_300.csv"
backup     <- "pe_obgyn_final_calling_sheet_300.ORIGINAL_FAKE.csv"

sh <- read.csv(sheet_path, colClasses = "character", check.names = FALSE)
sh$.row <- seq_len(nrow(sh))
if (!file.exists(backup)) file.copy(sheet_path, backup)

geo <- read.csv("data/covariates/npi_geography.csv", colClasses = "character")
geo <- geo[!duplicated(geo$NPI), c("NPI","zip5","county_fips","tract_geoid")]

# Recover county from ZIP (grace-ent crosswalk) where the geocode failed.
xw_path <- Sys.getenv("PE_ZIP_COUNTY_CROSSWALK",
                       file.path(path.expand("~"), "grace-ent/data/raw/zip_to_county_cbsa.csv"))
if (file.exists(xw_path)) {
  xw <- read.csv(xw_path, colClasses = "character")
  z2c <- setNames(xw$county_fips, xw$zip)
  need <- !nzchar(geo$county_fips) & nzchar(geo$zip5)
  geo$county_fips[need] <- unname(z2c[sprintf("%05s", geo$zip5[need])])
  geo$county_fips[is.na(geo$county_fips)] <- ""
}

fi  <- read.csv("data/covariates/tract_female_insurance.csv", colClasses = c(tract_geoid = "character"))
cnt <- read.csv("data/covariates/county_obgyn_count.csv",     colClasses = c(county_fips = "character"))
enr <- read.csv("data/covariates/county_enrollment.csv",      colClasses = c(county_fips = "character"))

m <- merge(sh, geo, by = "NPI", all.x = TRUE, sort = FALSE)
m <- merge(m, fi,  by = "tract_geoid", all.x = TRUE, sort = FALSE)
m <- merge(m, cnt, by = "county_fips", all.x = TRUE, sort = FALSE)
m <- merge(m, enr, by = "county_fips", all.x = TRUE, sort = FALSE)
m <- m[order(m$.row), ]
stopifnot(nrow(m) == nrow(sh))

fmt1 <- function(x) ifelse(is.na(x), "", formatC(as.numeric(x), format = "f", digits = 1))
fmti <- function(x) ifelse(is.na(x), "", as.character(as.integer(round(as.numeric(x)))))

sh$Tract_Pct_Female_Private    <- fmt1(m$pct_female_private)
sh$Tract_Pct_Female_Medicaid   <- fmt1(m$pct_female_medicaid)
sh$Tract_Pct_Female_Medicare   <- fmt1(m$pct_female_medicare)
sh$Tract_Pct_Female_Uninsured  <- fmt1(m$pct_female_uninsured)
sh$County_OBGYN_Count          <- fmti(m$county_obgyn_count)
sh$County_Medicare_Enrollment  <- fmti(m$county_medicare_enrollment)
sh$County_Medicaid_Enrollment  <- fmti(m$county_medicaid_enrollment)

sh$.row <- NULL
utils::write.csv(sh, sheet_path, row.names = FALSE, na = "")

filled <- function(col) sprintf("%.1f%%", 100 * mean(nzchar(sh[[col]])))
cat("Replaced 7 columns. Non-missing coverage:\n")
for (c in c("Tract_Pct_Female_Private","Tract_Pct_Female_Medicaid",
            "Tract_Pct_Female_Medicare","Tract_Pct_Female_Uninsured",
            "County_OBGYN_Count","County_Medicare_Enrollment",
            "County_Medicaid_Enrollment"))
  cat(sprintf("  %-28s %s\n", c, filled(c)))
cat("Backup:", backup, "\n")
