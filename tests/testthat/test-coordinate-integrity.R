# Cycle 6 -- 3 BVA, 3 semantic, 4 adversarial.
# Cycle 5 recorded that the transposition test passed while the coordinates were badly
# wrong, because it only checked value ranges. This cycle asserts the contract that
# actually matters: a clinician's coordinate must lie inside the state they practise in.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)
rd <- function(f) utils::read.csv(f, colClasses = "character", check.names = FALSE)

sheet <- rd(p("pe_obgyn_final_calling_sheet_200.csv"))
db    <- rd(p("pe_obgyn_study_database.csv"))
psm   <- readLines(p("build_matched_control_group_psm.R"))

# Generous bounding boxes (lat_min, lat_max, lon_min, lon_max) for the 26 cohort states,
# padded outward so a coordinate on a genuine border still passes. A point outside these
# is not a borderline case, it is in the wrong state.
BOX <- list(
  AL = c(30.1, 35.1, -88.6, -84.8), AZ = c(31.2, 37.1, -115.0, -108.9),
  CA = c(32.4, 42.1, -124.5, -114.0), CO = c(36.9, 41.1, -109.1, -101.9),
  CT = c(40.9, 42.1, -73.8, -71.7),  DC = c(38.7, 39.1, -77.2, -76.8),
  DE = c(38.4, 39.9, -75.9, -74.9),  FL = c(24.4, 31.1, -87.7, -79.9),
  GA = c(30.3, 35.1, -85.7, -80.7),  IL = c(36.9, 42.6, -91.6, -87.4),
  IN = c(37.7, 41.9, -88.2, -84.7),  MA = c(41.1, 42.9, -73.6, -69.8),
  MD = c(37.8, 39.8, -79.6, -74.9),  MI = c(41.6, 48.4, -90.5, -82.3),
  MN = c(43.4, 49.5, -97.3, -89.4),  MO = c(35.9, 40.7, -95.9, -88.9),
  NC = c(33.7, 36.7, -84.4, -75.4),  NJ = c(38.8, 41.5, -75.7, -73.8),
  NV = c(34.9, 42.1, -120.1, -113.9),NY = c(40.4, 45.1, -79.9, -71.8),
  OH = c(38.3, 42.4, -85.0, -80.4),  PA = c(39.6, 42.4, -80.6, -74.6),
  TN = c(34.9, 36.8, -90.4, -81.5),  TX = c(25.7, 36.6, -106.7, -93.4),
  UT = c(36.9, 42.1, -114.1, -108.9),VA = c(36.4, 39.5, -83.8, -75.1)
)

coords <- data.frame(
  npi = npi_key(db$NPI),
  lat = suppressWarnings(as.numeric(db$Latitude)),
  lon = suppressWarnings(as.numeric(db$Longitude)),
  stringsAsFactors = FALSE
)
fielded <- merge(data.frame(npi = npi_key(sheet$NPI), state = toupper(trimws(sheet$State)),
                            stringsAsFactors = FALSE),
                 coords, by = "npi")
fielded <- fielded[!is.na(fielded$lat) & !is.na(fielded$lon) & fielded$state %in% names(BOX), ]

in_state <- function(st, lat, lon) {
  b <- BOX[[st]]
  lat >= b[1] & lat <= b[2] & lon >= b[3] & lon <= b[4]
}
fielded$ok <- mapply(in_state, fielded$state, fielded$lat, fielded$lon)

# ---------------------------------------------------------------- BVA (3)

test_that("BVA: the bounding boxes accept a point on the border and reject one clearly outside", {
  expect_true(in_state("PA", 39.6, -80.6), info = "exact south-west corner of the PA box")
  expect_true(in_state("PA", 42.4, -74.6), info = "exact north-east corner of the PA box")
  expect_false(in_state("PA", 37.867, -104.920), info = "this is Colorado")
  expect_false(in_state("FL", 30.421, -78.102), info = "this is the Atlantic Ocean")
})

test_that("BVA: coordinate granularity has a floor of one point per distinct location", {
  n_distinct <- length(unique(paste(coords$lat, coords$lon)))
  expect_gte(n_distinct, 1L)
  expect_lte(n_distinct, nrow(coords))
  # 2,048 clinicians resolve to only a few hundred points, which is city-level at best.
  expect_true(n_distinct < nrow(coords) / 2,
              info = "documents that coordinates are shared, not address-specific")
})

test_that("BVA: haversine resolves separations below one mile", {
  d <- haversine_km <- function(lat1, lon1, lat2, lon2) {
    r <- 3959; dlat <- (lat2 - lat1) * pi / 180; dlon <- (lon2 - lon1) * pi / 180
    a <- sin(dlat / 2)^2 + cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dlon / 2)^2
    2 * r * asin(sqrt(a))
  }
  expect_gt(d(39.7392, -104.9903, 39.7492, -104.9903), 0.5)
  expect_lt(d(39.7392, -104.9903, 39.7492, -104.9903), 1.0)
})

# ---------------------------------------------------------------- semantic (3)

test_that("semantic: every fielded clinician's coordinate lies inside their stated state", {
  bad <- fielded[!fielded$ok, ]
  expect_equal(nrow(bad), 0L,
               info = sprintf("%d of %d fielded clinicians are geocoded outside their state (e.g. %s)",
                              nrow(bad), nrow(fielded),
                              if (nrow(bad)) sprintf("%s -> (%.3f, %.3f)", bad$state[1], bad$lat[1], bad$lon[1]) else ""))
})

test_that("semantic: the state abbreviation lookup maps full names to abbreviations", {
  i <- grep("^full_to_abbrev <- names\\(c\\(", psm)
  expect_length(i, 1L)
  blk <- paste(psm[i:(i + 25)], collapse = " ")
  pairs <- regmatches(blk, gregexpr("'[A-Z]{2}'='[A-Za-z ]+'", blk))[[1]]
  expect_gt(length(pairs), 40L)
  ab <- sub("'([A-Z]{2}).*", "\\1", pairs)
  nm <- sub(".*='([A-Za-z ]+)'", "\\1", pairs)
  expect_equal(ab[nm == "Pennsylvania"], "PA")
  expect_equal(ab[nm == "Colorado"], "CO")
  expect_false(any(duplicated(nm)), info = "a duplicated state name would silently shadow a mapping")
})

test_that("semantic: HQ distance is a plausible distance, not an artefact of bad coordinates", {
  hq <- suppressWarnings(as.numeric(sheet$HQ_Distance_Miles))
  hq <- hq[!is.na(hq)]
  expect_gt(length(hq), 0L)
  expect_true(all(hq >= 0), info = "a negative distance is impossible")
  expect_true(all(hq <= 3000), info = "a CONUS distance cannot exceed the width of the country")
})

# ---------------------------------------------------------------- adversarial (4)

test_that("adversarial: one coordinate is never shared across different states", {
  key <- paste(fielded$lat, fielded$lon)
  by_pt <- tapply(fielded$state, key, function(x) length(unique(x)))
  offenders <- sum(by_pt > 1L)
  expect_equal(offenders, 0L,
               info = sprintf("%d coordinates are assigned to clinicians in more than one state",
                              offenders))
})

test_that("adversarial: PE concentration is a count-like quantity, never negative", {
  pc <- suppressWarnings(as.numeric(sheet$PE_Concentration_15mi))
  pc <- pc[!is.na(pc)]
  expect_gt(length(pc), 0L)
  expect_true(all(pc >= 0))
})

test_that("adversarial: the SAP-revision truths are derived from cells, never typed in", {
  src <- paste(readLines(p("dry_run_sap_revision.R")), collapse = "\n")
  expect_true(grepl("TRUE_OR_MEDICAID <- \\(P_OBTAIN", src),
              info = "the primary estimand's truth must be computed from P_OBTAIN")
  expect_true(grepl("TRUE_IRR_INT *<- *\\(MU_WAIT", src))
  expect_false(grepl("TRUE_OR_MEDICAID *<- *0\\.[0-9]", src),
               info = "a literal would drift silently from the cell constants")
})

test_that("adversarial: the fielded sheet and study database agree on state", {
  st <- merge(data.frame(npi = npi_key(sheet$NPI), sheet_state = toupper(trimws(sheet$State)),
                         stringsAsFactors = FALSE),
              data.frame(npi = npi_key(db$NPI),
                         db_state = toupper(trimws(ifelse(nzchar(db$`DAC State`), db$`DAC State`, db$`NPPES State`))),
                         stringsAsFactors = FALSE),
              by = "npi")
  st <- st[nzchar(st$db_state), ]
  expect_equal(sum(st$sheet_state != st$db_state), 0L,
               info = "a state disagreement between artifacts breaks same-state matching")
})
