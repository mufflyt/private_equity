# Cycle 5 -- 3 BVA, 4 semantic, 3 adversarial.
# Targets the geographic matching constraint the Methods asserts, the sensitivity analysis
# built on it, and the churn accounting. Cycle 3 showed the geocoding is city-centroid;
# this cycle asks what that did to the fielded pairs.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)
rd <- function(f, ...) utils::read.csv(f, colClasses = "character", check.names = FALSE, ...)

sheet <- rd(p("pe_obgyn_final_calling_sheet_200_dedup.csv"))
db    <- rd(p("pe_obgyn_study_database.csv"))
churn <- readLines(p("calculate_cohort_churn.R"))

haversine <- function(lat1, lon1, lat2, lon2) {
  r <- 3959
  dlat <- (lat2 - lat1) * pi / 180
  dlon <- (lon2 - lon1) * pi / 180
  a <- sin(dlat / 2)^2 + cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dlon / 2)^2
  2 * r * asin(sqrt(a))
}

pair_distance <- local({
  d <- merge(
    data.frame(k = npi_key(sheet$NPI), pair = sheet$`Matched Pair ID`, stringsAsFactors = FALSE),
    data.frame(k = npi_key(db$NPI), lat = suppressWarnings(as.numeric(db$Latitude)),
               lon = suppressWarnings(as.numeric(db$Longitude)), stringsAsFactors = FALSE),
    by = "k")
  s <- split(d, d$pair)
  v <- vapply(s, function(x) if (nrow(x) == 2L && !anyNA(x$lat) && !anyNA(x$lon))
    haversine(x$lat[1], x$lon[1], x$lat[2], x$lon[2]) else NA_real_, numeric(1))
  v[!is.na(v)]
})

# ---------------------------------------------------------------- BVA (3)

test_that("BVA: haversine is zero at zero separation and symmetric", {
  expect_equal(haversine(39.7392, -104.9903, 39.7392, -104.9903), 0)
  expect_equal(haversine(40.7128, -74.0060, 34.0522, -118.2437),
               haversine(34.0522, -118.2437, 40.7128, -74.0060))
  # Premise correction: with r = 3959 and these city-hall coordinates the great-circle
  # distance is 2,446 mi, not the 2,451 I first asserted. The contract this test exists to
  # enforce is that the formula returns a plausible great-circle distance and has not
  # transposed its arguments, so a band around the true value is the right assertion.
  nyc_la <- haversine(40.7128, -74.0060, 34.0522, -118.2437)
  expect_true(nyc_la > 2400 && nyc_la < 2500,
              info = sprintf("New York to Los Angeles should be near 2,450 mi; got %.0f", nyc_la))
})

test_that("BVA: churn accounting starts at the second year, never the first", {
  loop_txt <- paste(churn, collapse = "\n")
  expect_match(loop_txt, "if \\(j > 1\\)",
               info = "year one has no prior year; everyone present would otherwise be an entrant")
  expect_match(loop_txt, "baseline_staff <- length\\(prev_npis\\)",
               info = "the churn denominator must be prior-year staff, not current-year")
  expect_match(loop_txt, "\\(joined \\+ left\\) / baseline_staff")
})

test_that("BVA: caliper membership is monotone in the radius", {
  n3 <- sum(pair_distance <= 3); n5 <- sum(pair_distance <= 5); n10 <- sum(pair_distance <= 10)
  expect_lte(n3, n5)
  expect_lte(n5, n10)
  expect_lte(n10, length(pair_distance))
})

# ---------------------------------------------------------------- semantic (4)

test_that("semantic: fielded pairs satisfy the 10-mile matching radius the Methods asserts", {
  # The Methods states matching "within a strict 10-mile radius in the same state".
  over <- sum(pair_distance > 10)
  expect_equal(over, 0L,
               info = sprintf("%d of %d fielded pairs exceed 10 miles (max %.0f mi)",
                              over, length(pair_distance), max(pair_distance)))
})

test_that("semantic: the 3/5/10-mile sensitivity calipers are not degenerate", {
  # If the same pairs qualify at every radius, the sensitivity analysis cannot detect
  # sensitivity to the radius: it is reporting robustness it never tested.
  n3 <- sum(pair_distance <= 3); n5 <- sum(pair_distance <= 5); n10 <- sum(pair_distance <= 10)
  expect_false(n3 == n5 && n5 == n10,
               info = sprintf("identical qualifying sets at 3, 5 and 10 miles (n = %d)", n10))
})

test_that("semantic: churn labels describe the quantity actually computed", {
  txt <- paste(churn, collapse = "\n")
  expect_match(txt, "Total_Exits = total_left", info = "exits must be departures, not arrivals")
  expect_match(txt, "Total_Entries = total_joined")
  expect_match(txt, "Mean_Annual_Churn = if \\(length\\(churn_rates\\) > 0\\) round\\(mean\\(churn_rates\\), 3\\)",
               info = "the mean of per-year rates, not a rate computed from summed counts")
})

test_that("semantic: manuscript and protocol agree on vignettes and payer arms", {
  ms <- paste(readLines(p("manuscript", "manuscript_cite.md")), collapse = "\n")
  expect_true(grepl("single", ms, ignore.case = TRUE) && grepl("AUB|abnormal uterine", ms, ignore.case = TRUE),
              info = "manuscript standardises on one AUB vignette")
  expect_false(grepl("\\bMedicare\\b", ms),
               info = "manuscript fields two arms; a Medicare mention would contradict the design")
})

# ---------------------------------------------------------------- adversarial (3)

test_that("adversarial: latitude and longitude are not transposed anywhere in the cohort", {
  lat <- suppressWarnings(as.numeric(db$Latitude))
  lon <- suppressWarnings(as.numeric(db$Longitude))
  ok <- !is.na(lat) & !is.na(lon)
  expect_true(all(abs(lat[ok]) <= 90), info = "a latitude beyond +/-90 means the pair is swapped")
  expect_true(all(lon[ok] < 0), info = "every CONUS practice has a negative longitude")
  expect_true(all(lat[ok] > 15 & lat[ok] < 72))
})

test_that("adversarial: the sensitivity artifact is reproducible from the cohort coordinates", {
  gs <- utils::read.csv(p("geographic_sensitivity_results.csv"), check.names = FALSE)
  n10 <- sum(pair_distance <= 10)
  reported10 <- gs$Pairs[grepl("10-mile", gs$Caliper)][1]
  expect_equal(reported10, n10,
               info = sprintf("artifact reports %s pairs within 10 miles; coordinates give %d",
                              reported10, n10))
})

test_that("adversarial: an office with a single year of history yields no fabricated churn", {
  txt <- paste(churn, collapse = "\n")
  expect_match(txt, "if \\(length\\(churn_rates\\) > 0\\) round\\(mean\\(churn_rates\\), 3\\) else 0\\.0",
               info = "a one-year office has no transitions; 0 must mean 'no transitions observed'")
  expect_match(txt, "Mean_Annual_Churn = NA",
               info = "an office with no history at all must be NA, distinct from an observed zero")
})
