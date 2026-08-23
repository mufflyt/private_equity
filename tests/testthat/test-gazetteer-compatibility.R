# NON-BLOCKING. Can the CURRENT mysterycall gazetteer be normalised to the pipeline contract?
#
# This is a forward-compatibility question, deliberately separated from
# test-frozen-geo-reference.R, which asserts that the reference the fielded cohort was built on
# is immutable.
#
# A PASS HERE DOES NOT LICENSE SUBSTITUTION. The current gazetteer reproduces only 82.2% of the
# fielded cohort's persisted coordinates, with a maximum discrepancy of 54 degrees; swapping it
# into the primary analysis would change which controls fell inside the 10-mile caliper and is
# therefore a new matching specification. Running it is a sensitivity analysis, and that is what
# the last test here measures.
#
# Nothing in this file asserts that mysterycall must export any particular column name. That
# coupling is exactly what broke: the package renamed its columns and a test that pinned
# `c("city","state","lat","long") %in% names(gz)` went red for a reason that had nothing to do
# with whether this pipeline works.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)

skip_if_no_gazetteer <- function() {
  if (!requireNamespace("mysterycall", quietly = TRUE)) testthat::skip("mysterycall not installed")
}

psm <- readLines(p("build_matched_control_group_psm.R"), warn = FALSE)

# Load the boundary function and the state map straight out of the matcher, so this file cannot
# drift from the code it is testing.
matcher <- local({
  env <- new.env()
  i <- grep("^normalize_gazetteer <- function", psm)
  j <- i; depth <- 0L
  repeat {
    depth <- depth + lengths(regmatches(psm[j], gregexpr("\\{", psm[j]))) -
                     lengths(regmatches(psm[j], gregexpr("\\}", psm[j])))
    if (depth == 0L && j > i) break
    j <- j + 1L
  }
  eval(parse(text = paste(psm[i:j], collapse = "\n")), envir = env)

  a <- grep("^full_to_abbrev <- names\\(c\\(", psm)[1]
  b <- grep("^names\\(full_to_abbrev\\) <-", psm)[1]
  k <- b
  repeat {
    blk <- paste(psm[b:k], collapse = "\n")
    if (lengths(regmatches(blk, gregexpr("\\(", blk))) ==
        lengths(regmatches(blk, gregexpr("\\)", blk)))) break
    k <- k + 1L
  }
  eval(parse(text = paste(psm[a:k], collapse = "\n")), envir = env)
  env
})

gz <- local({
  skip_if_no_gazetteer()
  e <- new.env()
  utils::data(city_state_to_lat_long, package = "mysterycall", envir = e)
  e$city_state_to_lat_long
})

test_that("the current gazetteer normalises to the pipeline contract", {
  skip_if_no_gazetteer()
  out <- matcher$normalize_gazetteer(gz, matcher$full_to_abbrev)
  expect_equal(names(out), c("city", "state", "lat", "long"))
  expect_true(is.numeric(out$lat) && is.numeric(out$long))
  expect_true(all(abs(out$lat) <= 90, na.rm = TRUE))
  expect_true(all(abs(out$long) <= 180, na.rm = TRUE))
})

test_that("normalisation resolves every row of the current gazetteer", {
  skip_if_no_gazetteer()
  out <- matcher$normalize_gazetteer(gz, matcher$full_to_abbrev)
  unresolved <- is.na(out$state)
  expect_false(any(unresolved),
               info = sprintf("%d of %d rows have a state the matcher's map cannot resolve: %s",
                              sum(unresolved), nrow(out),
                              paste(utils::head(unique(gz$state[unresolved]), 5), collapse = ", ")))
  expect_true(all(nchar(out$state[!unresolved]) == 2L))
})

test_that("normalised coordinates fall inside the state they claim", {
  skip_if_no_gazetteer()
  out <- matcher$normalize_gazetteer(gz, matcher$full_to_abbrev)
  BOX <- list(PA = c(39.6, 42.4, -80.6, -74.6), MI = c(41.6, 48.4, -90.5, -82.3),
              FL = c(24.4, 31.1, -87.7, -79.9), CO = c(36.9, 41.1, -109.1, -101.9))
  for (st in names(BOX)) {
    rows <- out[!is.na(out$state) & out$state == st, ]
    expect_true(nrow(rows) > 0L, info = sprintf("no rows normalise to %s", st))
    b <- BOX[[st]]
    inside <- mean(rows$lat >= b[1] & rows$lat <= b[2] & rows$long >= b[3] & rows$long <= b[4])
    expect_true(inside > 0.95,
                info = sprintf("%s: %.0f%% of rows fall inside the state", st, 100 * inside))
  }
})

test_that("the current gazetteer is recorded as NOT reproducing the fielded coordinates", {
  # The sensitivity result, asserted so that it cannot quietly become true-by-substitution.
  # If a future gazetteer DOES reproduce the frozen coordinates, this test fails and that is
  # the signal to revisit the freeze -- deliberately, not by drift.
  skip_if_no_gazetteer()
  fr <- utils::read.csv(p("inst", "frozen", "geo_reference_fielded_cohort.csv"),
                        colClasses = "character", check.names = FALSE)
  out <- matcher$normalize_gazetteer(gz, matcher$full_to_abbrev)
  out <- out[!duplicated(paste(out$city, out$state)), ]
  i <- match(paste(toupper(trimws(fr$city)), toupper(trimws(fr$state))),
             paste(out$city, out$state))
  ok <- !is.na(i)
  same <- abs(as.numeric(fr$lat[ok])  - out$lat[i[ok]])  < 1e-6 &
          abs(as.numeric(fr$long[ok]) - out$long[i[ok]]) < 1e-6
  agreement <- mean(same)
  expect_true(agreement < 0.99,
              info = sprintf(paste0("The current gazetteer now reproduces %.1f%% of the frozen ",
                                    "coordinates. If it reproduces them all, the dependency ",
                                    "drift may be resolvable -- revisit inst/frozen/PROVENANCE.md ",
                                    "deliberately rather than letting the freeze lapse."),
                             100 * agreement))
  message(sprintf("  [sensitivity] current gazetteer reproduces %.1f%% of %d frozen coordinates",
                  100 * agreement, sum(ok)))
})
