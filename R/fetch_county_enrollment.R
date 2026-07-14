#!/usr/bin/env Rscript
# =============================================================================
# Real county Medicare + Medicaid enrollment, replacing the seed-1978 rnorm
# columns County_Medicare_Enrollment and County_Medicaid_Enrollment.
#
#   Medicare = CMS Medicare Monthly Enrollment, latest annual TOT_BENES (county)
#   Medicaid = ACS 2022 5-yr, total persons "With Medicaid/means-tested public
#              coverage" (table C27007, both sexes, all ages) by county
#
# Output: data/covariates/county_enrollment.csv
#   county_fips, county_medicare_enrollment, county_medicaid_enrollment
# =============================================================================

suppressPackageStartupMessages({library(tidycensus); library(dplyr)})
options(stringsAsFactors = FALSE, timeout = 900)
if (!nzchar(Sys.getenv("CENSUS_API_KEY"))) stop("CENSUS_API_KEY not set.")
dir.create("data/covariates", showWarnings = FALSE, recursive = TRUE)
cache <- file.path(tempdir(), "geo_src"); dir.create(cache, showWarnings = FALSE)

geo <- read.csv("data/covariates/npi_geography.csv", colClasses = "character")
states <- sort(unique(geo$state[nzchar(geo$state) & geo$state %in% c(state.abb, "DC")]))

# ---- Medicare: CMS Medicare Monthly Enrollment (county, latest annual) ------
f_csv <- file.path(cache, "cms_mme.csv")
if (!file.exists(f_csv)) {
  url <- paste0("https://data.cms.gov/sites/default/files/2026-06/",
    "38b2bd15-bfb9-421d-9bf7-06b9449a94ef/",
    "Medicare%20Monthly%20Enrollment%20Data_March%202026.csv")
  utils::download.file(url, f_csv, quiet = TRUE)
}
hdr <- strsplit(readLines(f_csv, n = 1), ",")[[1]]
keep <- c("YEAR","MONTH","BENE_GEO_LVL","BENE_FIPS_CD","TOT_BENES")
cms <- utils::read.csv(f_csv, colClasses = ifelse(hdr %in% keep, "character", "NULL"),
                       check.names = FALSE)
cms <- cms[cms$BENE_GEO_LVL == "County" & cms$MONTH == "Year", ]
cms <- cms[cms$YEAR == max(cms$YEAR), ]
medicare <- data.frame(county_fips = sprintf("%05s", cms$BENE_FIPS_CD),
                       county_medicare_enrollment = suppressWarnings(as.numeric(cms$TOT_BENES)))

# ---- Medicaid: ACS C27007 total "With Medicaid" by county -------------------
vars <- load_variables(2022, "acs5")
mcaid_ids <- vars$name[grepl("^C27007_", vars$name) &
                       grepl("With Medicaid/means-tested", vars$label)]
acc <- list()
for (st in states) {
  d <- tryCatch(suppressMessages(get_acs(geography = "county", variables = mcaid_ids,
        state = st, year = 2022, survey = "acs5")), error = function(e) NULL)
  if (!is.null(d))
    acc[[st]] <- aggregate(estimate ~ GEOID, d, sum, na.rm = TRUE)
  cat("  ", st, "\n")
}
md <- do.call(rbind, acc)
medicaid <- data.frame(county_fips = md$GEOID,
                       county_medicaid_enrollment = round(md$estimate))

out <- merge(medicare, medicaid, by = "county_fips", all = TRUE)
out <- out[order(out$county_fips), ]
utils::write.csv(out, "data/covariates/county_enrollment.csv", row.names = FALSE, na = "")
cat(sprintf("Wrote county_enrollment.csv: %d counties (Medicare snapshot %s)\n",
            nrow(out), max(cms$YEAR)))
