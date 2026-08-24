# Reconstruct the CDC Social Vulnerability Index for every fielded clinician from real data.
#
# WHY THIS EXISTS. The CDC_SVI column currently in pe_obgyn_final_calling_sheet_200_dedup.csv is not
# a measurement. It is Normal(0.434, 0.193) truncated to [0.01, 0.99]: a Kolmogorov-Smirnov test
# against that Normal returns p = 0.985 while a test against the Uniform returns p < 0.001, and
# six rows sit at exactly 0.010 with one at exactly 0.990 -- the floor and ceiling of a
# pmax/pmin. A real SVI overall percentile rank is approximately UNIFORM on [0,1] by
# construction, because it IS a percentile rank. The sibling Tract_* and County_* columns were
# generated the same way by apply_demographic_covariates.R, which says so in its own header.
#
# So the 94 controls missing SVI were never the whole problem. The 306 rows that HAVE a value
# have a simulated one. This script replaces the column for all 400 fielded clinicians with the
# published value, using only public sources:
#
#   1. NPPES practice address  ->  2020 census tract, via the Census Bureau batch geocoder
#   2. 2020 census tract       ->  RPL_THEMES, via CDC/ATSDR SVI 2022 state files
#
# RPL_THEMES is the overall summary percentile ranking across all four SVI themes, which is the
# quantity the analysis plan names. CDC codes unavailable tracts as -999; those become NA here
# rather than being carried as a numeric -999 into a model.
#
# Output columns are written under NEW names (CDC_SVI_real, SVI_tract_fips, SVI_source). The
# simulated CDC_SVI column is left in place and untouched, so that nothing downstream silently
# changes meaning; swapping the analysis over to the real column is a separate, visible edit.

suppressMessages({
  library(dplyr)
  library(readr)
})

ROOT       <- "."

# The sheet and the address source are arguments, not constants. They were hardcoded to
# pe_obgyn_final_calling_sheet_200_dedup.csv, which is NOT the fielded cohort -- it shares only 153 of
# the 400 clinicians in the live REDCap dropdown. Running this against the wrong sheet produced
# a real SVI column for the wrong people, which is why the fielded 400 still had none.
# Addresses come from the study database, which must contain every fielded NPI: the plain
# pe_obgyn_study_database.csv covers 263 of 400 and fails the stopifnot below; the _with_churn
# build covers all 400.
#
# Usage:
#   Rscript build_svi_covariate.R                                    # legacy defaults
#   Rscript build_svi_covariate.R --sheet=FILE.csv --db=FILE.csv     # explicit
argval <- function(flag, default) {
  a <- commandArgs(trailingOnly = TRUE)
  v <- sub(paste0("^", flag, "="), "", grep(paste0("^", flag, "="), a, value = TRUE))
  if (length(v)) v[1] else default
}
SHEET      <- file.path(ROOT, argval("--sheet", "pe_obgyn_final_calling_sheet_200_dedup.csv"))
STUDY_DB   <- file.path(ROOT, argval("--db",    "pe_obgyn_study_database.csv"))
WORK       <- file.path(ROOT, "scratch", "svi")
SVI_YEAR   <- "2022"

dir.create(WORK, showWarnings = FALSE, recursive = TRUE)
source(file.path(ROOT, "R", "pe_helpers.R"))

sheet <- read.csv(SHEET, colClasses = "character", check.names = FALSE)
db    <- read.csv(STUDY_DB, colClasses = "character", check.names = FALSE)

idx <- match(npi_key(sheet$NPI), npi_key(db$NPI))
stopifnot(!anyNA(idx))

# Seven NPPES ZIPs have lost a leading zero somewhere upstream -- 1604 for Worcester MA,
# 6880 for Westport CT, 8901 for New Brunswick NJ. This is the same coercion-through-numeric
# defect as the NPI float suffix, and an unpadded ZIP either fails to geocode or, worse,
# geocodes to a different place. Restore the pad rather than dropping the rows.
zip5 <- function(x) {
  d <- substr(gsub("\\D", "", ifelse(is.na(x), "", x)), 1, 5)
  ifelse(nchar(d) %in% 1:4, formatC(suppressWarnings(as.integer(d)), width = 5, flag = "0"), d)
}

addr <- data.frame(
  id     = seq_len(nrow(sheet)),
  street = trimws(db[["NPPES Address 1"]][idx]),
  city   = trimws(db[["NPPES City"]][idx]),
  state  = toupper(trimws(db[["NPPES State"]][idx])),
  zip    = zip5(db[["NPPES Zip"]][idx]),
  stringsAsFactors = FALSE
)
stopifnot(all(nzchar(addr$street)), all(nzchar(addr$city)),
          all(nchar(addr$state) == 2L), all(nchar(addr$zip) == 5L))

message(sprintf("Geocoding %d fielded clinicians from NPPES practice addresses.", nrow(addr)))

# ---------------------------------------------------------------- 1. address -> tract
#
# The batch endpoint takes an unlabelled CSV and returns one row per input id. vintage
# Census2020_Current is required: SVI 2022 is published on 2020 tract boundaries, so geocoding
# against a different vintage would join to the wrong geography.

batch_in  <- file.path(WORK, "addresses_in.csv")
batch_out <- file.path(WORK, "geocoded_out.csv")

write.table(addr, batch_in, sep = ",", row.names = FALSE, col.names = FALSE,
            qmethod = "double", na = "")

if (!file.exists(batch_out) || file.info(batch_out)$size == 0) {
  cmd <- sprintf(paste("curl -s -m 900 --form addressFile=@%s --form benchmark=Public_AR_Current",
                       "--form vintage=Census2020_Current",
                       "https://geocoding.geo.census.gov/geocoder/geographies/addressbatch",
                       "--output %s"),
                 shQuote(batch_in), shQuote(batch_out))
  status <- system(cmd)
  if (status != 0 || !file.exists(batch_out)) stop("Census batch geocoder call failed.")
}

geo <- read.csv(batch_out, header = FALSE, colClasses = "character")
# Returned layout, 12 columns: id, input address, match status, match type, matched address,
# "lon,lat", tigerline id, side, STATE, COUNTY, TRACT, BLOCK.
stopifnot(ncol(geo) == 12L)
names(geo)[c(1, 3, 9, 10, 11)] <- c("id", "status", "state_fips", "county_fips", "tract_code")

geo$id <- as.integer(geo$id)
geo <- geo[order(geo$id), ]

# sprintf("%02s", x) pads with SPACES in R, not zeros, which is what silently produced a
# zero-row join on the first attempt. formatC(flag = "0") is the padding that is meant here.
pad <- function(x, w) formatC(trimws(x), width = w, flag = "0")

geo$tract_fips <- ifelse(
  geo$status == "Match" & nzchar(geo$state_fips) & nzchar(geo$county_fips) & nzchar(geo$tract_code),
  paste0(pad(geo$state_fips, 2), pad(geo$county_fips, 3), pad(geo$tract_code, 6)),
  NA_character_)
stopifnot(all(is.na(geo$tract_fips) | nchar(geo$tract_fips) == 11L))

message(sprintf("  batch pass matched: %d/%d; usable tract FIPS: %d",
                sum(geo$status == "Match"), nrow(geo), sum(!is.na(geo$tract_fips))))

geo$method <- ifelse(is.na(geo$tract_fips), NA_character_, "address (batch)")

# ---------------------------------------------------------------- 1b. second pass
#
# The batch endpoint fails on a minority of addresses, usually because of a suite designator
# or an abbreviation it will not parse. Retry those one at a time against the single-address
# endpoint with the suite stripped. Anything still unplaced falls back to the stored
# coordinate, which is recorded as a DISTINCT method because some coordinates in this
# database came from a city-centroid gazetteer rather than an address match, and a
# city-centroid tract is a weaker measurement than an address-level one.

strip_suite <- function(s) {
  out <- gsub("\\b(SUITE|STE|UNIT|APT|FLOOR|FL|ROOM|RM|BLDG|BUILDING|DEPT|#)\\b\\.?\\s*[0-9A-Za-z-]*",
              "", toupper(s))
  trimws(gsub("\\s+", " ", out))
}

geo_url <- function(street, city, state, zip) {
  sprintf(paste0("https://geocoding.geo.census.gov/geocoder/geographies/address",
                 "?street=%s&city=%s&state=%s&zip=%s",
                 "&benchmark=Public_AR_Current&vintage=Census2020_Current",
                 "&layers=Census+Tracts&format=json"),
          utils::URLencode(street, reserved = TRUE), utils::URLencode(city, reserved = TRUE),
          state, zip)
}

coord_url <- function(lon, lat) {
  sprintf(paste0("https://geocoding.geo.census.gov/geocoder/geographies/coordinates",
                 "?x=%s&y=%s&benchmark=Public_AR_Current&vintage=Census2020_Current",
                 "&layers=Census+Tracts&format=json"), lon, lat)
}

pull_geoid <- function(url) {
  txt <- tryCatch(paste(readLines(url, warn = FALSE), collapse = ""), error = function(e) "")
  m <- regmatches(txt, regexpr('"GEOID":"[0-9]{11}"', txt))
  if (!length(m)) return(NA_character_)
  sub('"GEOID":"([0-9]{11})"', "\\1", m)
}

# Coordinate columns are looked up case-insensitively. pe_obgyn_study_database.csv spells them
# "latitude"/"longitude"; the _with_churn build spells them "Latitude"/"Longitude". Indexing a
# data frame with a name it does not have returns NULL, and `nzchar(trimws(NULL)) && ...` is a
# zero-length condition, which is an error in R >= 4.2 rather than a skipped branch. So the
# fallback did not merely fail to fire on the churn build -- it halted the whole run.
col_ci <- function(df, nm) {
  hit <- match(tolower(nm), tolower(names(df)))
  if (is.na(hit)) NULL else df[[hit]]
}
LAT <- col_ci(db, "latitude"); LON <- col_ci(db, "longitude")
if (is.null(LAT) || is.null(LON))
  message("  note: no coordinate columns in the address source; stored-coordinate fallback is off")

usable_num <- function(x) {
  if (is.null(x) || length(x) != 1L || is.na(x)) return(FALSE)
  v <- suppressWarnings(as.numeric(trimws(x)))
  !is.na(v) && is.finite(v) && v != 0
}

todo <- which(is.na(geo$tract_fips))
if (length(todo)) {
  message(sprintf("  second pass on %d unplaced addresses...", length(todo)))
  for (i in todo) {
    g <- pull_geoid(geo_url(strip_suite(addr$street[i]), addr$city[i], addr$state[i], addr$zip[i]))
    if (!is.na(g)) { geo$tract_fips[i] <- g; geo$method[i] <- "address (retry, suite stripped)"; next }
    lat <- if (is.null(LAT)) NA else LAT[idx[i]]
    lon <- if (is.null(LON)) NA else LON[idx[i]]
    if (usable_num(lat) && usable_num(lon)) {
      g <- pull_geoid(coord_url(trimws(lon), trimws(lat)))
      if (!is.na(g)) { geo$tract_fips[i] <- g; geo$method[i] <- "stored coordinate" }
    }
  }
  message(sprintf("  after second pass: %d/%d placed", sum(!is.na(geo$tract_fips)), nrow(geo)))
  print(table(geo$method, useNA = "ifany"))
}

# ---------------------------------------------------------------- 2. tract -> SVI
#
# CDC publishes one file per state. Fetch only the states the cohort actually spans.

state_name <- c(
  AL="Alabama", AK="Alaska", AZ="Arizona", AR="Arkansas", CA="California", CO="Colorado",
  CT="Connecticut", DE="Delaware", DC="DistrictofColumbia", FL="Florida", GA="Georgia",
  HI="Hawaii", ID="Idaho", IL="Illinois", IN="Indiana", IA="Iowa", KS="Kansas", KY="Kentucky",
  LA="Louisiana", ME="Maine", MD="Maryland", MA="Massachusetts", MI="Michigan",
  MN="Minnesota", MS="Mississippi", MO="Missouri", MT="Montana", NE="Nebraska", NV="Nevada",
  NH="NewHampshire", NJ="NewJersey", NM="NewMexico", NY="NewYork", NC="NorthCarolina",
  ND="NorthDakota", OH="Ohio", OK="Oklahoma", OR="Oregon", PA="Pennsylvania",
  RI="RhodeIsland", SC="SouthCarolina", SD="SouthDakota", TN="Tennessee", TX="Texas",
  UT="Utah", VT="Vermont", VA="Virginia", WA="Washington", WV="WestVirginia",
  WI="Wisconsin", WY="Wyoming")

states <- sort(unique(addr$state))
message(sprintf("Fetching CDC SVI %s for %d states.", SVI_YEAR, length(states)))

svi_list <- list()
for (st in states) {
  nm <- state_name[[st]]
  if (is.null(nm) || is.na(nm)) { warning("no CDC file name for state ", st); next }
  dest <- file.path(WORK, paste0(nm, ".csv"))
  if (!file.exists(dest) || file.info(dest)$size < 1000) {
    url <- sprintf("https://svi.cdc.gov/Documents/Data/%s/csv/states/%s.csv", SVI_YEAR, nm)
    if (system(sprintf("curl -sfL -m 300 %s --output %s", shQuote(url), shQuote(dest))) != 0) {
      warning("download failed for ", nm); next
    }
  }
  d <- suppressWarnings(read_csv(dest, show_col_types = FALSE,
                                 col_types = cols(.default = col_character())))
  if (!all(c("FIPS", "RPL_THEMES") %in% names(d))) { warning("unexpected columns in ", nm); next }
  svi_list[[st]] <- data.frame(tract_fips = formatC(trimws(d$FIPS), width = 11, flag = "0"),
                               rpl = suppressWarnings(as.numeric(d$RPL_THEMES)),
                               stringsAsFactors = FALSE)
}
svi <- bind_rows(svi_list)
svi$rpl[svi$rpl < 0] <- NA_real_          # CDC codes unavailable tracts as -999
svi <- svi[!duplicated(svi$tract_fips), ]
message(sprintf("  SVI tracts loaded: %d (%d with a usable RPL_THEMES)",
                nrow(svi), sum(!is.na(svi$rpl))))

# ---------------------------------------------------------------- 2b. ZIP-level fallback
#
# A residue of addresses cannot be placed by the Census geocoder at all -- its TIGER address
# ranges do not cover them, so this is not a formatting problem and retrying does not help.
# Left alone the residue is not random: it falls almost entirely in the control arm, because
# PE rows carry a usable stored coordinate and control rows carry the literal string "N/A".
# Exposure-dependent missingness in a model covariate is the specific hazard this whole
# exercise exists to remove, so accepting it would defeat the repair.
#
# These rows get an area-weighted mean SVI over the tracts intersecting their ZCTA, via the
# Census 2020 ZCTA-to-tract relationship file. That is a coarser measurement than an
# address-level tract and is recorded as such in SVI_geocode_via, so any analysis can exclude
# it or adjust for precision. ZIP and ZCTA are not identical; for five-digit residential ZIPs
# the approximation is standard.

zcta_file <- file.path(WORK, "zcta_tract_rel.txt")
if (!file.exists(zcta_file) || file.info(zcta_file)$size < 1e6) {
  system(sprintf("curl -sfL -m 600 %s --output %s",
                 shQuote("https://www2.census.gov/geo/docs/maps-data/data/rel2020/zcta520/tab20_zcta520_tract20_natl.txt"),
                 shQuote(zcta_file)))
}
rel <- read.delim(zcta_file, sep = "|", colClasses = "character", quote = "")
rel <- rel[nzchar(rel$GEOID_ZCTA5_20) & nzchar(rel$GEOID_TRACT_20), ]
rel$area <- suppressWarnings(as.numeric(rel$AREALAND_PART))
rel$rpl  <- svi$rpl[match(formatC(rel$GEOID_TRACT_20, width = 11, flag = "0"), svi$tract_fips)]
rel <- rel[!is.na(rel$rpl) & !is.na(rel$area) & rel$area > 0, ]
zip_svi <- tapply(seq_len(nrow(rel)), rel$GEOID_ZCTA5_20,
                  function(i) sum(rel$rpl[i] * rel$area[i]) / sum(rel$area[i]))
message(sprintf("  ZCTA-level fallback available for %d ZCTAs", length(zip_svi)))

# ---------------------------------------------------------------- 3. join and report

ord <- match(seq_len(nrow(sheet)), geo$id)
sheet$SVI_tract_fips  <- geo$tract_fips[ord]
sheet$SVI_geocode_via <- geo$method[ord]
sheet$CDC_SVI_real    <- svi$rpl[match(sheet$SVI_tract_fips, svi$tract_fips)]

fallback <- which(is.na(sheet$CDC_SVI_real))
if (length(fallback)) {
  z <- unname(zip_svi[addr$zip[fallback]])
  sheet$CDC_SVI_real[fallback]    <- z
  sheet$SVI_geocode_via[fallback] <- ifelse(is.na(z), NA_character_,
                                            "ZCTA area-weighted (address unplaceable)")
  message(sprintf("  ZCTA fallback resolved %d of %d remaining rows", sum(!is.na(z)), length(z)))
}

sheet$SVI_source <- ifelse(is.na(sheet$CDC_SVI_real), NA_character_,
                           paste0("CDC/ATSDR SVI ", SVI_YEAR, " RPL_THEMES"))

cov <- table(sheet$PE_or_Not, ifelse(is.na(sheet$CDC_SVI_real), "missing", "has SVI"))
message("\nReal SVI coverage by arm:")
print(cov)

unmatched <- which(is.na(sheet$SVI_tract_fips))
if (length(unmatched)) {
  message(sprintf("\n%d addresses the geocoder could not place; first few:", length(unmatched)))
  print(utils::head(addr[unmatched, c("street", "city", "state", "zip")], 10))
}

v <- sheet$CDC_SVI_real[!is.na(sheet$CDC_SVI_real)]
stopifnot(length(v) > 0L)
message(sprintf("\nn = %d | mean %.3f | median %.3f | min %.3f | max %.3f",
                length(v), mean(v), median(v), min(v), max(v)))
message(sprintf("KS vs Uniform(0,1): p = %.3f   (a real percentile rank should NOT reject)",
                suppressWarnings(ks.test(v, "punif", 0, 1)$p.value)))
message(sprintf("KS vs Normal:       p = %.3f   (the simulated column returned 0.985)",
                suppressWarnings(ks.test(v, "pnorm", mean(v), sd(v))$p.value)))

pairs_both <- sum(tapply(!is.na(sheet$CDC_SVI_real), sheet[["Matched Pair ID"]], all))
message(sprintf("\nComplete pairs (both members have real SVI): %d of %d",
                pairs_both, length(unique(sheet[["Matched Pair ID"]]))))

write.csv(sheet, SHEET, row.names = FALSE, na = "")
message(sprintf("\nWrote %s (CDC_SVI left untouched; new columns CDC_SVI_real, SVI_tract_fips, SVI_source).",
                basename(SHEET)))
