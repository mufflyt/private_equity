#!/usr/bin/env Rscript
# =============================================================================
# Backfill the ~49 addresses that the primary Census geocoder
# (R/fetch_npi_geography.R) could not match. Two fallback stages, both landing
# on the SAME Census tract geography as the primary pass so results are mixable:
#
#   Stage A  Retry the Census one-line geocoder with the unit/suite token
#            stripped from the street ("... STE 412", "... # LIFTER1"). Most
#            primary failures are suite formatting, not bad addresses.
#   Stage B  For whatever still fails, Nominatim (OpenStreetMap) address ->
#            lat/long, then the Census "coordinates" endpoint lat/long -> tract.
#
# Rows fixed get status "ok_fallback_census" or "ok_fallback_nominatim".
# Addresses with no NPPES street at all (status "no_nppes") are left NA -- there
# is nothing to geocode. Honest missingness is preserved for any true failure.
#
# In/out: data/covariates/npi_geography.csv  (updated in place)
# =============================================================================

suppressPackageStartupMessages({library(httr); library(jsonlite)})
options(stringsAsFactors = FALSE, timeout = 120)

path <- "data/covariates/npi_geography.csv"
g <- read.csv(path, colClasses = "character")

strip_unit <- function(s) {
  s <- gsub("(?i)\\b(ste|suite|apt|unit|rm|room|fl|floor|#)\\b.*$", "", s, perl = TRUE)
  s <- gsub("#.*$", "", s)                      # bare "# LIFTER1"
  trimws(gsub("\\s+", " ", s))
}

# --- Stage A: Census one-line geocoder on the cleaned street -----------------
census_oneline <- function(street, city, state, zip) {
  addr <- paste0(street, ", ", city, ", ", state, " ", zip)
  r <- tryCatch(GET("https://geocoding.geo.census.gov/geocoder/geographies/onelineaddress",
    query = list(address = addr, benchmark = "Public_AR_Current",
                 vintage = "Current_Current", format = "json", layers = "Census Tracts")),
    error = function(e) NULL)
  if (is.null(r) || http_error(r)) return(NULL)
  m <- tryCatch(content(r, "parsed")$result$addressMatches, error = function(e) NULL)
  if (length(m) == 0) return(NULL)
  geo <- m[[1]]$geographies$`Census Tracts`[[1]]
  if (is.null(geo$GEOID)) return(NULL)
  list(tract = geo$GEOID, county = paste0(geo$STATE, geo$COUNTY), state_fips = geo$STATE)
}

# --- Stage B: Nominatim -> lat/long, then Census coordinates -> tract --------
nominatim_latlon <- function(street, city, state, zip) {
  q <- paste0(strip_unit(street), ", ", city, ", ", state, " ", zip, ", USA")
  r <- tryCatch(GET("https://nominatim.openstreetmap.org/search",
    query = list(q = q, format = "json", limit = 1, countrycodes = "us"),
    add_headers(`User-Agent` = "grace-ent-research/1.0 (tyler.muffly@dhha.org)")),
    error = function(e) NULL)
  Sys.sleep(1.1)                                # Nominatim: <=1 req/sec
  if (is.null(r) || http_error(r)) return(NULL)
  j <- tryCatch(content(r, "parsed"), error = function(e) NULL)
  if (length(j) == 0) return(NULL)
  list(lat = j[[1]]$lat, lon = j[[1]]$lon)
}
census_coords <- function(lat, lon) {
  r <- tryCatch(GET("https://geocoding.geo.census.gov/geocoder/geographies/coordinates",
    query = list(x = lon, y = lat, benchmark = "Public_AR_Current",
                 vintage = "Current_Current", format = "json", layers = "Census Tracts")),
    error = function(e) NULL)
  if (is.null(r) || http_error(r)) return(NULL)
  geo <- tryCatch(content(r, "parsed")$result$geographies$`Census Tracts`[[1]],
                  error = function(e) NULL)
  if (is.null(geo$GEOID)) return(NULL)
  list(tract = geo$GEOID, county = paste0(geo$STATE, geo$COUNTY), state_fips = geo$STATE)
}

idx <- which(g$status == "no_geocode" & nzchar(g$street))
cat(sprintf("Backfilling %d addresses...\n", length(idx)))
na <- nb <- 0
for (i in idx) {
  hit <- census_oneline(strip_unit(g$street[i]), g$city[i], g$state[i], g$zip5[i])
  src <- "ok_fallback_census"
  if (is.null(hit)) {
    ll <- nominatim_latlon(g$street[i], g$city[i], g$state[i], g$zip5[i])
    if (!is.null(ll)) hit <- census_coords(ll$lat, ll$lon)
    src <- "ok_fallback_nominatim"
  }
  if (!is.null(hit) && nchar(hit$tract) == 11) {
    g$tract_geoid[i] <- hit$tract; g$county_fips[i] <- hit$county
    g$state_fips[i]  <- hit$state_fips; g$status[i] <- src
    if (src == "ok_fallback_census") na <- na + 1 else nb <- nb + 1
  }
}
write.csv(g, path, row.names = FALSE, na = "")
still <- sum(g$status == "no_geocode")
cat(sprintf("Recovered %d via Census-retry, %d via Nominatim. Still missing: %d\n",
            na, nb, still))
print(table(g$status))
