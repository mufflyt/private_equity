# Cycle 7 -- 4 BVA, 3 semantic, 3 adversarial.
# Isolates the geocoding lookup itself, as cycle 6 directed. Cycles 3, 5 and 6 measured the
# symptoms; this cycle tests the join that causes them.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)
psm <- readLines(p("build_matched_control_group_psm.R"))

skip_if_no_gazetteer <- function() {
  if (!requireNamespace("mysterycall", quietly = TRUE)) testthat::skip("mysterycall not installed")
}

gz <- local({
  skip_if_no_gazetteer()
  e <- new.env()
  utils::data(city_state_to_lat_long, package = "mysterycall", envir = e)
  e$city_state_to_lat_long
})

# Reproduces the script's mapping construction so the join can be tested directly.
build_ref <- function(g) {
  full_to_abbrev <- c(Alabama = "AL", Arizona = "AZ", Colorado = "CO", Michigan = "MI",
                      Missouri = "MO", Pennsylvania = "PA", Florida = "FL")
  ifelse(nchar(trimws(g$state)) == 2L, toupper(trimws(g$state)), full_to_abbrev[g$state])
}

# ---------------------------------------------------------------- BVA (4)

test_that("BVA: the gazetteer retains rows after state normalisation", {
  ab <- build_ref(gz)
  kept <- sum(!is.na(ab))
  expect_gt(kept, 0L)
  expect_equal(kept, nrow(gz),
               info = "every gazetteer row carries a usable state; none may be dropped")
})

test_that("BVA: state tokens are classified by length, at the two-character boundary", {
  norm <- function(s) ifelse(nchar(trimws(s)) == 2L, toupper(trimws(s)), NA_character_)
  expect_equal(norm("AL"), "AL")
  expect_equal(norm("al"), "AL")
  expect_equal(norm(" pa "), "PA")
  expect_true(is.na(norm("Alabama")), info = "a full name is not a two-character token")
  expect_true(is.na(norm("A")), info = "one character is not a state abbreviation")
})

test_that("BVA: a city+state key resolves to at most a handful of rows", {
  k <- paste(toupper(trimws(gz$city)), toupper(trimws(gz$state)), sep = "_")
  tb <- table(k)
  expect_gte(min(tb), 1L)
  expect_true(mean(tb == 1L) > 0.99,
              info = "city+state is essentially unique; city alone is not")
})

test_that("BVA: an unknown city yields no coordinate rather than a default", {
  k <- paste(toupper(gz$city), toupper(gz$state), sep = "_")
  expect_false("ZZZZNOTACITY_ZZ" %in% k)
  hit <- gz[k == "ZZZZNOTACITY_ZZ", ]
  expect_equal(nrow(hit), 0L,
               info = "a miss must return nothing, never row 1 of the table")
})

# ---------------------------------------------------------------- semantic (3)

test_that("semantic: the gazetteer and the mapping table speak the same state vocabulary", {
  # This is the defect. The gazetteer stores abbreviations; full_to_abbrev is keyed by
  # full names. Mapping one through the other yielded NA for all 31,909 rows and the
  # downstream !is.na() filter then emptied the gazetteer entirely.
  expect_true(all(nchar(trimws(gz$state)) == 2L),
              info = "the gazetteer's state column is abbreviations")
  i <- grep("lat_long_ref\\$state_abbrev <-", psm)
  expect_length(i, 1L)
  blk <- paste(psm[i:(i + 5)], collapse = " ")
  expect_match(blk, "nchar\\(trimws\\(lat_long_ref\\$state\\)\\) == 2",
               info = "the script must accept an already-abbreviated state")
})

test_that("semantic: joining on city alone is ambiguous and must not be used", {
  dup_city <- sum(duplicated(toupper(trimws(gz$city))))
  expect_gt(dup_city, 1000L)
  spr <- gz[toupper(trimws(gz$city)) == "SPRINGFIELD", ]
  expect_true(nrow(spr) > 5L,
              info = "Springfield exists in many states; a city-only join picks an arbitrary one")
  expect_false(any(grepl("city_upper *== *[^&]*\\)\\s*,\\s*\\]", psm) &
                   !grepl("state_upper", psm)),
               info = "every gazetteer lookup must constrain on state as well as city")
})

test_that("semantic: a resolved coordinate lies inside the state that was requested", {
  BOX <- list(PA = c(39.6, 42.4, -80.6, -74.6), MI = c(41.6, 48.4, -90.5, -82.3),
              FL = c(24.4, 31.1, -87.7, -79.9), CO = c(36.9, 41.1, -109.1, -101.9))
  for (st in names(BOX)) {
    rows <- gz[toupper(trimws(gz$state)) == st, ]
    expect_gt(nrow(rows), 0L)
    b <- BOX[[st]]
    inside <- mean(rows$lat >= b[1] & rows$lat <= b[2] & rows$long >= b[3] & rows$long <= b[4])
    expect_true(inside > 0.95,
                info = sprintf("%s: only %.0f%% of gazetteer rows fall inside the state", st, 100 * inside))
  }
})

# ---------------------------------------------------------------- adversarial (3)

test_that("adversarial: emptying a reference table must not pass silently", {
  # The failure mode that hid this for a month: the filter removed every row and the
  # script continued, producing NA coordinates and a matching run that reported success.
  i <- grep("lat_long_ref <- lat_long_ref\\[!is.na\\(lat_long_ref\\$state_upper\\)", psm)
  expect_length(i, 1L)
  after <- paste(psm[i:min(length(psm), i + 6)], collapse = " ")
  expect_match(after, "stop\\(|nrow\\(lat_long_ref\\)|cat\\(",
               info = "an emptied gazetteer must be detected, not carried forward as NA coordinates")
})

test_that("adversarial: the manual fallback cannot stand in for a working gazetteer", {
  i <- grep("^manual_coords <-", psm)
  expect_length(i, 1L)
  blk <- paste(psm[i:(i + 40)], collapse = " ")
  n <- length(regmatches(blk, gregexpr("\"[A-Z .'-]+_[A-Z]{2}\" *= *c\\(", blk))[[1]])
  expect_lt(n, 100L)
  expect_true(nrow(gz) > 100L * n,
              info = "the gazetteer is orders of magnitude larger; silently relying on the fallback loses nearly all cities")
})

test_that("adversarial: the gazetteer package contract is stable", {
  expect_true(all(c("city", "state", "lat", "long") %in% names(gz)))
  expect_true(is.numeric(gz$lat) && is.numeric(gz$long))
  expect_true(all(abs(gz$lat) <= 90, na.rm = TRUE))
  expect_true(all(abs(gz$long) <= 180, na.rm = TRUE))
})
