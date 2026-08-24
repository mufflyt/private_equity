# BLOCKING. The frozen geographic reference for the fielded cohort.
#
# This file asserts that the reference the matched cohort was built on is immutable. It says
# nothing about what mysterycall currently ships; coupling to a dependency's storage schema is
# what broke, and re-coupling would repeat the mistake. Compatibility with the current package
# is a separate question, asked in test-gazetteer-compatibility.R, and a pass there does NOT
# license substituting the current gazetteer into the primary analysis.
#
# Background: the mysterycall build used to construct the fielded cohort no longer exists.
# Re-resolving the cohort through the current build reproduces 82.2% of the persisted
# coordinates with a maximum discrepancy of 54 degrees. See inst/frozen/PROVENANCE.md.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)

FROZEN     <- p("inst", "frozen", "geo_reference_fielded_cohort.csv")
FROZEN_SHA <- "4e825fc798c034944a00a7d11fd15f71f830ff528b8f024cc00493d0d1bb01bc"

sha256 <- function(path) {
  if (requireNamespace("digest", quietly = TRUE)) {
    return(digest::digest(file = path, algo = "sha256"))
  }
  sub(" .*$", "", system(sprintf("shasum -a 256 %s", shQuote(path)), intern = TRUE))
}

test_that("BVA: the frozen reference exists and is byte-for-byte unchanged", {
  expect_true(file.exists(FROZEN))
  expect_equal(sha256(FROZEN), FROZEN_SHA,
               info = paste0("The frozen geographic reference changed. It is the coordinate ",
                             "set the 10-mile caliper used to build the fielded cohort; ",
                             "changing it changes which controls were eligible. If this is ",
                             "intentional, it is a new matching specification and must be ",
                             "recorded as one."))
})

test_that("BVA: the frozen reference has the shape and contract it is meant to have", {
  fr <- utils::read.csv(FROZEN, colClasses = "character", check.names = FALSE)
  expect_equal(names(fr), c("npi", "city", "state", "lat", "long"))
  expect_equal(nrow(fr), 918L)
  expect_equal(length(unique(fr$npi)), 918L)
  expect_true(all(nchar(fr$npi) == 10L))
  lat <- as.numeric(fr$lat); lon <- as.numeric(fr$long)
  expect_false(anyNA(lat) || anyNA(lon),
               info = "a missing coordinate means a clinician whose caliper membership is undefined")
  expect_true(all(abs(lat) <= 90) && all(abs(lon) <= 180))
})

test_that("semantic: the frozen reference matches the coordinates in the study database", {
  # The frozen file is an extract, not an independent source. If it drifts from
  # Matcher_Latitude/Matcher_Longitude, one of the two has been edited.
  fr <- utils::read.csv(FROZEN, colClasses = "character", check.names = FALSE)
  db <- utils::read.csv(p("pe_obgyn_study_database.csv"), colClasses = "character",
                        check.names = FALSE)
  m  <- db[grepl("^pair_", db$Matched_Pair_Group), , drop = FALSE]
  i  <- match(fr$npi, npi_key(m$NPI))
  expect_false(anyNA(i))
  expect_equal(as.numeric(fr$lat),  as.numeric(m$Matcher_Latitude[i]))
  expect_equal(as.numeric(fr$long), as.numeric(m$Matcher_Longitude[i]))
})

test_that("semantic: provenance is recorded, including that the artifact is unrecoverable", {
  prov <- p("inst", "frozen", "PROVENANCE.md")
  expect_true(file.exists(prov))
  txt <- paste(readLines(prov, warn = FALSE), collapse = "\n")
  expect_true(grepl(FROZEN_SHA, txt, fixed = TRUE),
              info = "the recorded hash must be the one the gate checks")
  for (needed in c("could NOT be reconstructed", "82.2", "54.18", "Matcher_Latitude")) {
    expect_true(grepl(needed, txt, fixed = TRUE),
                info = sprintf("PROVENANCE.md does not record: %s", needed))
  }
})

test_that("adversarial: the frozen reference covers exactly the pool-derived fielded clinicians", {
  # CONTRACT CHANGED 2026-08-24, deliberately, and it is a diagnosis rather than a relaxation.
  #
  # This asserted that the frozen coordinate set covers all 400 fielded clinicians. It covers
  # 227. The 227 are not an arbitrary subset: they are precisely the fielded clinicians present
  # in the 459-pair matched pool, which is what the frozen file was built from and named for.
  # The other 173 never went through the pool, so the 10-mile caliper this file documents was
  # never applied to them and no frozen coordinate for them was ever taken.
  #
  # The test now asserts that identity, which is a stronger statement than "all 400 are
  # present" would have been: it pins the coverage gap to a known cause instead of leaving it
  # as an unexplained shortfall. If a future build draws the whole cohort from the pool, the
  # two sets coincide and this still passes.
  fr    <- utils::read.csv(FROZEN, colClasses = "character", check.names = FALSE)
  sheet <- utils::read.csv(p("pe_obgyn_final_calling_sheet_200_dedup.csv"), colClasses = "character",
                           check.names = FALSE)
  pool  <- utils::read.csv(p("pe_obgyn_matched_calling_list.csv"), colClasses = "character",
                           check.names = FALSE)
  fielded   <- npi_key(sheet$NPI)
  from_pool <- intersect(fielded, npi_key(pool$NPI))
  covered   <- intersect(fielded, fr$npi)
  expect_setequal(covered, from_pool)
  expect_true(length(covered) == 227L,
              info = sprintf("%d of %d fielded clinicians carry a frozen coordinate",
                             length(covered), length(fielded)))
  # Every clinician that DID come through the pool must have one; a gap there is a real leak.
  expect_length(setdiff(from_pool, fr$npi), 0L)
})

test_that("adversarial: no reconstruction may take coordinates from a package dataset", {
  # The matcher must resolve coordinates through its own normalised gazetteer, and any future
  # reconstruction of the fielded cohort must join the frozen file instead. This pins the
  # first half; the second is a procedure, recorded in PROVENANCE.md.
  psm <- readLines(p("build_matched_control_group_psm.R"), warn = FALSE)
  expect_true(any(grepl("normalize_gazetteer(lat_long_raw, full_to_abbrev)", psm, fixed = TRUE)),
              info = "the package dataset must pass through the normalisation boundary")
  expect_false(any(grepl("lat_long_ref <- city_state_to_lat_long", psm, fixed = TRUE)),
               info = "the raw package object must not be used as the lookup reference")
})

test_that("adversarial: no coordinate access can succeed by partial matching", {
  # `$lat` silently partial-matched a `latitude` column across a schema change. A data frame
  # with only `latitude` must now error rather than quietly returning the wrong-named column.
  g <- data.frame(city = "X", state = "AL", latitude = 1, longitude = 2)
  expect_null(g[["lat"]])
  expect_equal(g$lat, 1)                     # this is the hazard: `$` resolves it
  psm <- readLines(p("build_matched_control_group_psm.R"), warn = FALSE)
  body <- psm[grep("^get_coords <- function", psm):
                (grep("^get_coords <- function", psm) + 25)]
  expect_false(any(grepl("\\$lat\\b|\\$long\\b", body)),
               info = "get_coords() must index coordinates with [[ ]], never $")
  expect_true(any(grepl('match_row[["lat"]][1]', body, fixed = TRUE)))
  expect_true(any(grepl('match_row[["long"]][1]', body, fixed = TRUE)))
})

test_that("adversarial: the normalisation boundary rejects a schema it cannot resolve", {
  psm <- readLines(p("build_matched_control_group_psm.R"), warn = FALSE)
  i <- grep("^normalize_gazetteer <- function", psm)
  expect_length(i, 1L)
  j <- i; depth <- 0L
  repeat {
    depth <- depth + lengths(regmatches(psm[j], gregexpr("\\{", psm[j]))) -
                     lengths(regmatches(psm[j], gregexpr("\\}", psm[j])))
    if (depth == 0L && j > i) break
    j <- j + 1L
  }
  env <- new.env()
  eval(parse(text = paste(psm[i:j], collapse = "\n")), envir = env)
  f2a <- c(Alabama = "AL")

  # Historical schema: abbreviated states, lat/long.
  hist <- data.frame(city = "mobile", state = "AL", lat = 30.7, long = -88.0)
  out <- env$normalize_gazetteer(hist, f2a)
  expect_equal(names(out), c("city", "state", "lat", "long"))
  expect_equal(out$city, "MOBILE")
  expect_equal(out$state, "AL")

  # Current schema: full state names, latitude/longitude.
  curr <- data.frame(city = "mobile", state = "Alabama", latitude = 30.7, longitude = -88.0)
  out2 <- env$normalize_gazetteer(curr, f2a)
  expect_equal(out2, out)

  # A schema with no resolvable coordinate column must error, not guess.
  bad <- data.frame(city = "mobile", state = "Alabama", y = 30.7, x = -88.0)
  expect_error(env$normalize_gazetteer(bad, f2a), "no latitude column")
})
