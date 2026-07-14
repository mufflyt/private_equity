# =============================================================================
# Adversarial + semantic tests for the real demographic covariates that replace
# the seed-1978 rnorm() placeholders in pe_obgyn_final_calling_sheet_300.csv.
#
# ADVERSARIAL: try to prove the columns are still fake (match the rnorm
#   signature, vary per-row within a shared geography, sit outside valid ranges).
# SEMANTIC: prove the values mean what a real covariate should (geography nests
#   correctly, percentages are proportions, supply/enrollment scale together).
#
# Tests skip cleanly until the pipeline outputs exist, so they can run
# incrementally as each stage lands.
# =============================================================================

find_file <- function(name) {
  for (p in c(name, file.path("..", "..", name), file.path("..", "..", "..", name)))
    if (file.exists(p)) return(p)
  NA_character_
}
load_sheet <- function() {
  f <- find_file("pe_obgyn_final_calling_sheet_300.csv")
  if (is.na(f)) testthat::skip("calling sheet not found")
  read.csv(f, colClasses = c(NPI = "character"), check.names = FALSE)
}
load_geo <- function() {
  f <- find_file("data/covariates/npi_geography.csv")
  if (is.na(f)) testthat::skip("npi_geography.csv not built yet")
  read.csv(f, colClasses = "character")
}

TRACT_COLS <- c("Tract_Pct_Female_Private", "Tract_Pct_Female_Medicaid",
                "Tract_Pct_Female_Medicare", "Tract_Pct_Female_Uninsured")
COUNTY_COLS <- c("County_OBGYN_Count", "County_Medicare_Enrollment",
                 "County_Medicaid_Enrollment")

# Exact placeholder signature from apply_demographic_covariates.R (seed 1978).
fake_columns <- function(n) {
  set.seed(1978)
  list(
    Tract_Pct_Female_Private    = round(rnorm(n, 68.2, 8.5), 1),
    Tract_Pct_Female_Medicaid   = round(rnorm(n, 18.4, 5.2), 1),
    Tract_Pct_Female_Medicare   = round(rnorm(n, 11.1, 2.8), 1),
    Tract_Pct_Female_Uninsured  = round(rnorm(n, 7.9,  3.6), 1),
    County_OBGYN_Count          = pmax(1,   round(rnorm(n, 42.6, 22.4))),
    County_Medicare_Enrollment  = pmax(100, round(rnorm(n, 75400, 38500))),
    County_Medicaid_Enrollment  = pmax(100, round(rnorm(n, 89200, 45200)))
  )
}

# ---------------------------------------------------------------------------
# ADVERSARIAL
# ---------------------------------------------------------------------------
test_that("columns no longer match the seed-1978 rnorm placeholders", {
  sh <- load_sheet()
  present <- intersect(c(TRACT_COLS, COUNTY_COLS), names(sh))
  if (!length(present)) skip("covariate columns absent")
  fk <- fake_columns(nrow(sh))
  for (col in present) {
    real <- suppressWarnings(as.numeric(sh[[col]]))
    if (all(is.na(real))) next
    # Not a byte-for-byte match to the placeholder vector.
    expect_false(isTRUE(all.equal(real, fk[[col]], tolerance = 1e-6)),
                 info = paste(col, "still equals the rnorm placeholder"))
    # Sample mean should have moved off the placeholder mean for at least
    # the count/enrollment columns (real geography is not centered there).
  }
})

test_that("county-level columns are invariant within a county (kills per-row rnorm)", {
  sh  <- load_sheet(); geo <- load_geo()
  if (!"County_OBGYN_Count" %in% names(sh)) skip("county columns absent")
  m <- merge(sh[, c("NPI", COUNTY_COLS)], geo[, c("NPI", "county_fips")], by = "NPI")
  m <- m[nzchar(m$county_fips), ]
  dup_counties <- names(which(table(m$county_fips) > 1))
  if (!length(dup_counties)) skip("no county has >1 NPI to compare")
  for (col in COUNTY_COLS) {
    ok <- vapply(dup_counties, function(cf) {
      v <- suppressWarnings(as.numeric(m[[col]][m$county_fips == cf]))
      length(unique(v[!is.na(v)])) <= 1L
    }, logical(1))
    expect_true(all(ok),
      info = sprintf("%s differs across NPIs in the same county (was per-row rnorm)", col))
  }
})

test_that("tract-level columns are invariant within a tract", {
  sh  <- load_sheet(); geo <- load_geo()
  if (!all(TRACT_COLS %in% names(sh))) skip("tract columns absent")
  m <- merge(sh[, c("NPI", TRACT_COLS)], geo[, c("NPI", "tract_geoid")], by = "NPI")
  m <- m[nzchar(m$tract_geoid), ]
  dup <- names(which(table(m$tract_geoid) > 1))
  if (!length(dup)) skip("no tract has >1 NPI to compare")
  for (col in TRACT_COLS) {
    ok <- vapply(dup, function(tg) {
      v <- suppressWarnings(as.numeric(m[[col]][m$tract_geoid == tg]))
      length(unique(round(v[!is.na(v)], 1))) <= 1L
    }, logical(1))
    expect_true(all(ok), info = sprintf("%s differs within a shared tract", col))
  }
})

# ---------------------------------------------------------------------------
# SEMANTIC
# ---------------------------------------------------------------------------
test_that("geography nests correctly and matches the provider's state", {
  geo <- load_geo()
  ok <- geo[geo$status == "ok", ]
  if (!nrow(ok)) skip("no successfully geocoded rows")
  expect_true(all(nchar(ok$tract_geoid) == 11))
  expect_true(all(nchar(ok$county_fips) == 5))
  expect_equal(substr(ok$tract_geoid, 1, 5), ok$county_fips)         # tract in county
  expect_equal(substr(ok$county_fips, 1, 2), ok$state_fips)          # county in state
  fips <- c(AL="01",AK="02",AZ="04",AR="05",CA="06",CO="08",CT="09",DE="10",DC="11",
    FL="12",GA="13",HI="15",ID="16",IL="17",IN="18",IA="19",KS="20",KY="21",LA="22",
    ME="23",MD="24",MA="25",MI="26",MN="27",MS="28",MO="29",MT="30",NE="31",NV="32",
    NH="33",NJ="34",NM="35",NY="36",NC="37",ND="38",OH="39",OK="40",OR="41",PA="42",
    RI="44",SC="45",SD="46",TN="47",TX="48",UT="49",VT="50",VA="51",WA="53",WV="54",
    WI="55",WY="56")
  have <- ok$state %in% names(fips)
  expect_equal(unname(fips[ok$state[have]]), ok$state_fips[have])     # FIPS matches NPPES state
})

test_that("female insurance percentages are valid proportions with real spread", {
  sh <- load_sheet()
  if (!all(TRACT_COLS %in% names(sh))) skip("tract columns absent")
  for (col in TRACT_COLS) {
    v <- suppressWarnings(as.numeric(sh[[col]])); v <- v[!is.na(v)]
    if (!length(v)) next
    expect_true(all(v >= 0 & v <= 100), info = paste(col, "out of [0,100]"))
    expect_gt(length(unique(v)), 1)                     # not a constant fill
  }
  # More Medicaid coverage tends to accompany less private coverage.
  med <- suppressWarnings(as.numeric(sh$Tract_Pct_Female_Medicaid))
  prv <- suppressWarnings(as.numeric(sh$Tract_Pct_Female_Private))
  keep <- !is.na(med) & !is.na(prv)
  if (sum(keep) > 30) expect_lt(cor(med[keep], prv[keep]), 0.1)
})

test_that("county supply and enrollment are non-negative and scale together", {
  sh <- load_sheet()
  if (!all(COUNTY_COLS %in% names(sh))) skip("county columns absent")
  ob  <- suppressWarnings(as.numeric(sh$County_OBGYN_Count))
  mcr <- suppressWarnings(as.numeric(sh$County_Medicare_Enrollment))
  mcd <- suppressWarnings(as.numeric(sh$County_Medicaid_Enrollment))
  expect_true(all(ob[!is.na(ob)]   >= 0))
  expect_true(all(mcr[!is.na(mcr)] >  0))
  expect_true(all(mcd[!is.na(mcd)] >  0))
  expect_true(all(ob[!is.na(ob)] == round(ob[!is.na(ob)])))          # counts are integers
  keep <- !is.na(ob) & !is.na(mcr)
  # Physician supply and Medicare enrollment both grow with county population.
  if (sum(keep) > 30) expect_gt(cor(ob[keep], mcr[keep], method = "spearman"), 0.2)
})
