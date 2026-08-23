# Scientific CI: provenance / trust-a-number.
# Targets the ACS 2010-vs-2020 tract-boundary vintage footgun -- tract_geoid is a bare string
# on both sides of every geographic join in this pipeline, with no vintage column anywhere, so
# a future re-fetch on the wrong vintage would join without error and silently attach each
# clinician's covariates to the wrong tract. gate_tract_geoid_vintage() catches that by match
# rate, since real cross-vintage boundaries share only a small fraction of GEOIDs.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)

geo <- utils::read.csv(p("data", "covariates", "npi_geography.csv"), colClasses = "character")
fi  <- utils::read.csv(p("data", "covariates", "tract_female_insurance.csv"), colClasses = "character")

test_that("semantic: npi_geography and tract_female_insurance share one Census vintage", {
  expect_error(gate_tract_geoid_vintage(geo, fi), NA,
               info = paste("these two covariate files are joined on tract_geoid throughout the",
                            "pipeline (R/replace_fake_covariates.R); if this ever fails, check",
                            "which ACS survey year / geocoder vintage each side was fetched on",
                            "before assuming it is an ordinary coverage problem"))
})

test_that("BVA: a synthetic 2010-vintage-shaped mismatch is caught, not silently joined", {
  # Real vintage mismatches don't change GEOID length -- they change which 11-digit numbers
  # exist. Simulate that by scrambling the tract suffix of every GEOID on one side; the true
  # overlap collapses even though every value still looks like a valid GEOID. npi_geography.csv
  # has a handful of blank tract_geoid rows (ungeocoded addresses); drop those first so this
  # test isolates the overlap-collapse scenario from the separate blank/short-GEOID case below.
  scrambled <- geo[nzchar(geo$tract_geoid), ]
  scrambled$tract_geoid <- paste0(substr(scrambled$tract_geoid, 1, 5),
                                  sprintf("%06d", (as.integer(substr(scrambled$tract_geoid, 6, 11)) + 500000) %% 999999))
  expect_true(all(nchar(scrambled$tract_geoid) == 11L),
              info = paste("test precondition: the scramble must stay 11 characters or this",
                           "would also trip the length check and no longer isolate the",
                           "overlap case"))
  expect_error(gate_tract_geoid_vintage(scrambled, fi, min_overlap = 0.90),
               "vintage boundary",
               info = "a collapsed match rate must fail loudly, not be treated as missing data")
})

test_that("adversarial: a short GEOID (dropped leading zero) is rejected, not silently accepted", {
  truncated <- geo
  truncated$tract_geoid[1] <- substr(truncated$tract_geoid[1], 2, 11)  # 10 chars, not 11
  expect_error(gate_tract_geoid_vintage(truncated, fi), "11 characters",
               info = paste("sprintf/as.integer round-trips on GEOIDs have dropped leading",
                            "zeros before in this pipeline (see npi_key/address_key); this must",
                            "be caught by shape, not just by match rate, since a truncated GEOID",
                            "can still coincidentally match something on the right"))
})

test_that("BVA: an empty left side fails clearly rather than reporting spurious 100% overlap", {
  expect_error(gate_tract_geoid_vintage(geo[0, ], fi), "no non-empty",
               info = paste("length(intersect(character(0), r)) / length(unique(character(0)))",
                            "is 0/0 = NaN in R, which must not be allowed to read as a passing",
                            "overlap"))
})
