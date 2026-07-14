#!/usr/bin/env Rscript
# =============================================================================
# Real county-level OB/GYN physician supply, replacing the seed-1978 rnorm
# County_OBGYN_Count column.
#
# Source: CMS "Doctors and Clinicians" National Downloadable File (all Medicare-
# enrolled clinicians with primary specialty + practice ZIP). Keep providers
# whose primary specialty is OBSTETRICS/GYNECOLOGY or GYNECOLOGICAL ONCOLOGY,
# de-duplicate NPIs within a county, and count per county. ZIP -> county comes
# from the Census 2020 ZCTA5->county relationship file (dominant county by land
# area), so this script is self-contained.
#
# Output: data/covariates/county_obgyn_count.csv  (county_fips, county_obgyn_count)
# =============================================================================

suppressPackageStartupMessages({library(data.table)})
options(timeout = 1200)
dir.create("data/covariates", showWarnings = FALSE, recursive = TRUE)
cache <- file.path(tempdir(), "obgyn_src"); dir.create(cache, showWarnings = FALSE)

# 1) ZIP -> dominant county from the Census ZCTA relationship file
f_zcta <- file.path(cache, "zcta_county.txt")
if (!file.exists(f_zcta)) utils::download.file(
  "https://www2.census.gov/geo/docs/maps-data/data/rel2020/zcta520/tab20_zcta520_county20_natl.txt",
  f_zcta, quiet = TRUE)
z <- data.table::fread(f_zcta, sep = "|", colClasses = "character")
z <- z[GEOID_ZCTA5_20 != "", .(zip = GEOID_ZCTA5_20, county_fips = GEOID_COUNTY_20,
                               area = as.numeric(AREALAND_PART))]
data.table::setorder(z, zip, -area)
zip2cty <- z[, .SD[1], by = zip][, .(zip, county_fips)]

# 2) National Downloadable File -> OB/GYN NPIs + practice ZIP
f_ndf <- file.path(cache, "ndf.csv")
if (!file.exists(f_ndf)) utils::download.file(
  paste0("https://data.cms.gov/provider-data/sites/default/files/resources/",
         "52c3f098d7e56028a298fd297cb0b38d_1782750575/DAC_NationalDownloadableFile.csv"),
  f_ndf, quiet = TRUE)
ndf <- data.table::fread(f_ndf, select = c("NPI", "pri_spec", "ZIP Code"),
                         colClasses = "character")
data.table::setnames(ndf, c("NPI", "pri_spec", "ZIP Code"), c("npi", "spec", "zip9"))
ob <- ndf[grepl("OBSTETR|GYNECOLOG", toupper(spec))]
ob[, zip := sprintf("%05s", substr(gsub("[^0-9]", "", zip9), 1, 5))]
ob <- unique(ob[, .(npi, zip)])

# 3) map to county and count distinct NPIs per county
ob <- merge(ob, zip2cty, by = "zip")
cnt <- ob[, .(county_obgyn_count = uniqueN(npi)), by = county_fips]
data.table::setorder(cnt, county_fips)
data.table::fwrite(cnt, "data/covariates/county_obgyn_count.csv")
cat(sprintf("Wrote county_obgyn_count.csv: %d counties, %d distinct OB/GYNs\n",
            nrow(cnt), uniqueN(ob$npi)))
