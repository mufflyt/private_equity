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
#
# Premise correction, 2026-08-10. This helper used to carry a seven-state stub of
# full_to_abbrev. That passed for years only because mysterycall's bundled gazetteer used
# two-letter states, which sent every row down the nchar == 2 branch and made the stub
# irrelevant. When the gazetteer was rebuilt upstream with full state names ("Alabama") the
# stub dropped 25,698 of 31,909 rows and this file went red -- not because the pipeline is
# wrong, but because the test only ever tested half of what it claimed to.
#
# The map is now read from build_matched_control_group_psm.R itself, so the test cannot drift
# from the script again. That is the contract test-address-key-parity.R already enforces for
# the address key.
script_full_to_abbrev <- local({
  src <- readLines(file.path(root, "build_matched_control_group_psm.R"), warn = FALSE)
  i <- grep("^full_to_abbrev <- names\\(c\\(", src)[1]
  j <- grep("^names\\(full_to_abbrev\\) <-", src)[1]
  # Both assignments span several lines; take everything from the first to the end of the
  # second, which is the first line after `j` whose parentheses balance.
  k <- j
  repeat {
    blk <- paste(src[j:k], collapse = "\n")
    if (lengths(regmatches(blk, gregexpr("\\(", blk))) ==
        lengths(regmatches(blk, gregexpr("\\)", blk)))) break
    k <- k + 1L
  }
  env <- new.env()
  eval(parse(text = paste(src[i:k], collapse = "\n")), envir = env)
  env$full_to_abbrev
})

build_ref <- function(g) {
  ifelse(nchar(trimws(g$state)) == 2L, toupper(trimws(g$state)),
         script_full_to_abbrev[g$state])
}

test_that("the test's state map is the script's, not a stub of it", {
  # expect_gte does not accept `info`; use expect_true so the diagnosis survives a failure.
  expect_true(length(script_full_to_abbrev) >= 50L,
              info = sprintf("map has %d entries; a partial map silently drops gazetteer rows and hides join failures",
                             length(script_full_to_abbrev)))
  expect_true(all(nchar(script_full_to_abbrev) == 2L))
  expect_true(all(c("Alabama", "Wyoming", "California") %in% names(script_full_to_abbrev)))
})

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
  # This is the defect the script's normalisation exists for: full_to_abbrev is keyed by full
  # state names, and if the gazetteer's own vocabulary does not match, mapping one through the
  # other yields NA for every row and the downstream !is.na() filter empties the gazetteer.
  #
  # Premise correction, 2026-08-10: this used to assert that the gazetteer stores
  # abbreviations. That is the dependency's storage choice, not a contract of this pipeline,
  # and it changed upstream -- mysterycall's gazetteer now stores full names ("Alabama"). The
  # contract is that the script's normalisation resolves EVERY row whichever vocabulary is in
  # use, which is what its stop() guard protects.
  ab <- build_ref(gz)
  expect_true(all(!is.na(ab)),
              info = sprintf("%d of %d gazetteer rows unresolvable; unmapped states: %s",
                             sum(is.na(ab)), nrow(gz),
                             paste(utils::head(unique(gz$state[is.na(ab)]), 5), collapse = ", ")))
  expect_true(all(nchar(ab) == 2L))
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
  # Select on the NORMALISED abbreviation, which is what the matcher joins on, rather than on
  # the gazetteer's raw state column, whose vocabulary is the dependency's to choose.
  gz_ab <- build_ref(gz)
  for (st in names(BOX)) {
    rows <- gz[!is.na(gz_ab) & gz_ab == st, ]
    expect_true(nrow(rows) > 0L,
                info = sprintf("no gazetteer rows normalise to %s", st))
    b <- BOX[[st]]
    # The gazetteer's coordinate columns were renamed latitude/longitude upstream
    # (mysterycall 22d0777, "rename data objects to snake_case"). build_matched_control_group_
    # _psm.R:437 still reads $lat and $long and survives only on `$` partial matching, which
    # is silent and would break the moment any other lat*/long* column is added. Resolve the
    # names here rather than depending on that.
    lat <- if (!is.null(rows[["latitude"]])) rows[["latitude"]] else rows[["lat"]]
    lon <- if (!is.null(rows[["longitude"]])) rows[["longitude"]] else rows[["long"]]
    inside <- mean(lat >= b[1] & lat <= b[2] & lon >= b[3] & lon <= b[4])
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
