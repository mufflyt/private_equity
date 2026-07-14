#!/usr/bin/env Rscript
# =============================================================================
# Geocode each study NPI to its census tract + county.
#
# Two free, no-key APIs:
#   1. NPPES registry   NPI -> primary practice LOCATION address
#   2. Census geocoder  address -> 2020 census tract GEOID + county FIPS
#
# Resumable: results are cached to data/covariates/npi_geography.csv and NPIs
# already present are skipped on re-run.
#
# Output columns: NPI, street, city, state, zip5, state_fips, county_fips,
#                 tract_geoid, status
# =============================================================================

suppressPackageStartupMessages({library(httr); library(jsonlite)})
options(stringsAsFactors = FALSE)
dir.create("data/covariates", showWarnings = FALSE, recursive = TRUE)
out_csv <- "data/covariates/npi_geography.csv"

sheet <- read.csv("pe_obgyn_final_calling_sheet_300.csv", colClasses = "character",
                  check.names = FALSE)
npis <- unique(sheet$NPI)

done <- if (file.exists(out_csv)) read.csv(out_csv, colClasses = "character") else
        data.frame()
todo <- setdiff(npis, done$NPI)
cat(sprintf("NPIs total %d | already done %d | to fetch %d\n",
            length(npis), nrow(done), length(todo)))

nppes_address <- function(npi) {
  r <- tryCatch(httr::GET("https://npiregistry.cms.hhs.gov/api/",
                query = list(version = "2.1", number = npi), httr::timeout(20)),
                error = function(e) NULL)
  if (is.null(r) || httr::status_code(r) != 200) return(NULL)
  d <- tryCatch(jsonlite::fromJSON(httr::content(r, "text", encoding = "UTF-8"),
                                   simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(d) || length(d$results) == 0) return(NULL)
  addrs <- d$results[[1]]$addresses
  loc <- Filter(function(a) identical(a$address_purpose, "LOCATION"), addrs)
  a <- if (length(loc)) loc[[1]] else if (length(addrs)) addrs[[1]] else return(NULL)
  list(street = a$address_1 %||% "", city = a$city %||% "",
       state = a$state %||% "", zip5 = substr(gsub("[^0-9]", "", a$postal_code %||% ""), 1, 5))
}
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || is.na(x)) y else x

geocode_tract <- function(street, city, state, zip5) {
  oneline <- paste(street, city, state, zip5, sep = ", ")
  r <- tryCatch(httr::GET("https://geocoding.geo.census.gov/geocoder/geographies/onelineaddress",
                query = list(address = oneline, benchmark = "Public_AR_Current",
                             vintage = "Census2020_Current", format = "json"),
                httr::timeout(30)), error = function(e) NULL)
  if (is.null(r) || httr::status_code(r) != 200) return(NULL)
  d <- tryCatch(jsonlite::fromJSON(httr::content(r, "text", encoding = "UTF-8"),
                                   simplifyVector = FALSE), error = function(e) NULL)
  m <- d$result$addressMatches
  if (is.null(m) || length(m) == 0) return(NULL)
  g <- m[[1]]$geographies[["Census Tracts"]][[1]]
  list(state_fips = g$STATE, county_fips = paste0(g$STATE, g$COUNTY), tract_geoid = g$GEOID)
}

rows <- vector("list", length(todo))
for (i in seq_along(todo)) {
  npi <- todo[i]
  ad <- nppes_address(npi)
  rec <- list(NPI = npi, street = "", city = "", state = "", zip5 = "",
              state_fips = "", county_fips = "", tract_geoid = "", status = "no_nppes")
  if (!is.null(ad)) {
    rec[c("street","city","state","zip5")] <- ad[c("street","city","state","zip5")]
    rec$status <- "no_geocode"
    gc <- geocode_tract(ad$street, ad$city, ad$state, ad$zip5)
    if (!is.null(gc) && nzchar(gc$tract_geoid)) {
      rec[c("state_fips","county_fips","tract_geoid")] <-
        gc[c("state_fips","county_fips","tract_geoid")]
      rec$status <- "ok"
    }
  }
  rows[[i]] <- as.data.frame(rec)
  if (i %% 25 == 0) cat(sprintf("  %d/%d\n", i, length(todo)))
  Sys.sleep(0.05)
}
res <- if (length(rows)) do.call(rbind, rows) else data.frame()
all <- rbind(done, res)
utils::write.csv(all, out_csv, row.names = FALSE, na = "")
tb <- table(all$status)
cat("Done. status:", paste(sprintf("%s=%d", names(tb), tb), collapse = " "), "\n")
