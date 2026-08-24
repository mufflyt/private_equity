# Cycle 16 -- 4 BVA, 3 semantic, 3 adversarial.
# Targets the enrichment covariates. CDC SVI is a fixed effect in the SAP's wait-time model,
# and the tract and county measures are the contextual adjusters. None had been tested.
# Test 10 closes the false-negative pattern recorded in cycles 5, 13 and 15.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)
sheet <- utils::read.csv(p("pe_obgyn_final_calling_sheet_200_dedup.csv"),
                         colClasses = "character", check.names = FALSE)
num <- function(col) suppressWarnings(as.numeric(sheet[[col]]))

# These names now hold MEASUREMENTS. Until 2026-08-24 they held the seed-1978 rnorm() draws,
# and this file was asserting range and variability properties of a random number generator.
# The draws survive under SIMULATED_ names, quarantined; the real values are joined from
# data/covariates/ on SVI_tract_fips, which the SVI reconstruction produced for all 400.
TRACT <- c("Tract_Pct_Female_Private", "Tract_Pct_Female_Medicaid",
           "Tract_Pct_Female_Medicare", "Tract_Pct_Female_Uninsured")
SIMULATED <- paste0("SIMULATED_", c("CDC_SVI", TRACT, "County_OBGYN_Count",
                                    "County_Medicare_Enrollment", "County_Medicaid_Enrollment"))

# ---------------------------------------------------------------- BVA (4)

test_that("BVA: CDC SVI lies within the percentile interval", {
  v <- num("CDC_SVI_real"); v <- v[!is.na(v)]
  expect_true(length(v) > 0L)
  expect_true(all(v >= 0 & v <= 1),
              info = sprintf("SVI outside [0,1]: min %.3f max %.3f", min(v), max(v)))
})

test_that("BVA: each tract coverage share is a percentage", {
  for (cn in TRACT) {
    v <- num(cn); v <- v[!is.na(v)]
    expect_true(all(v >= 0 & v <= 100),
                info = sprintf("%s outside [0,100]", cn))
  }
})

test_that("BVA: county counts are positive and PE concentration admits a true zero", {
  expect_true(all(num("County_OBGYN_Count") >= 1, na.rm = TRUE),
              info = "a county with a fielded OB-GYN has at least one")
  pc <- num("PE_Concentration_15mi")
  expect_true(all(pc >= 0, na.rm = TRUE))
  expect_true(any(pc == 0, na.rm = TRUE),
              info = "zero nearby PE clinics is a legitimate observation, not missingness")
})

test_that("BVA: the Medicaid fee index sits in a plausible ratio range", {
  v <- num("Medicaid_Fee_Index"); v <- v[!is.na(v)]
  expect_true(all(v > 0 & v <= 2),
              info = "the index is Medicaid fees relative to Medicare; values above 2 are implausible")
  expect_true(length(unique(v)) > 1L, info = "a constant index cannot adjust for anything")
})

# ---------------------------------------------------------------- semantic (3)

test_that("semantic: tract coverage shares are labelled for what they actually measure", {
  tot <- rowSums(sapply(TRACT, num), na.rm = TRUE)
  over <- sum(tot > 100, na.rm = TRUE)
  # ACS coverage types are NOT mutually exclusive: dual eligibles and Medicare supplements
  # are counted in more than one category. The column names read as shares of a population,
  # which is how anyone would treat them in an analysis.
  # CONTRACT CHANGED 2026-08-24. This asserted the four shares sum to at most 100. Until today
  # it could not run at all: these columns held rnorm() draws, so it was asserting a property
  # of a random number generator. Against the real ACS values it fails, and it fails because
  # the premise is wrong rather than the data. ACS insurance categories are NOT mutually
  # exclusive -- a dual eligible is counted under both Medicare and Medicaid, a Medicare
  # supplement under both Medicare and private -- so 389 of 400 tracts sum above 100, median
  # 113.7%, max 174.5%. They are coverage RATES on a common denominator, not a composition,
  # and must never be summed. The fact is pinned rather than denied, so a build that somehow
  # produced exclusive shares fails here and is investigated instead of quietly accepted.
  expect_true(all(tot[!is.na(tot)] >= 0))
  expect_gt(over, 300L)
  expect_gt(median(tot, na.rm = TRUE), 100)
  for (cn in TRACT) {
    v <- num(cn); v <- v[!is.na(v)]
    expect_true(all(v >= 0 & v <= 100),
                info = sprintf("%s is not a valid percentage on its own", cn))
  }
})

test_that("semantic: CDC SVI behaves like a percentile across the cohort", {
  v <- num("CDC_SVI_real"); v <- v[!is.na(v)]
  expect_true(length(unique(v)) > 50L, info = "a percentile should be near-continuous")
  expect_true(abs(median(v) - 0.5) < 0.25,
              info = sprintf("median SVI %.3f is far from the 0.5 a percentile implies", median(v)))
})

test_that("semantic: county enrollment counts are data, not a floor", {
  for (cn in c("County_Medicare_Enrollment", "County_Medicaid_Enrollment")) {
    v <- num(cn); v <- v[!is.na(v)]
    n_at_floor <- sum(v == min(v))
    expect_true(min(v) != 100 || n_at_floor == 1L,
                info = sprintf("%s has %d rows at exactly %.0f, which reads as a placeholder rather than a county total",
                               cn, n_at_floor, min(v)))
  }
})

# ---------------------------------------------------------------- adversarial (3)

test_that("adversarial: no adjuster is constant across the cohort", {
  for (cn in c("CDC_SVI_real", TRACT, "County_OBGYN_Count")) {
    v <- num(cn)
    expect_true(length(unique(v[!is.na(v)])) > 1L,
                info = sprintf("%s is constant and contributes nothing to any model", cn))
  }
})

test_that("adversarial: no two adjusters are the same column under different names", {
  cols <- c("CDC_SVI_real", TRACT, "County_OBGYN_Count", "County_Medicare_Enrollment",
            "County_Medicaid_Enrollment", "Medicaid_Fee_Index")
  m <- sapply(cols, num)
  for (a in seq_along(cols)) for (b in seq_len(a - 1L)) {
    expect_false(isTRUE(all.equal(m[, a], m[, b])),
                 info = sprintf("%s and %s are identical", cols[a], cols[b]))
  }
})

test_that("adversarial: absence assertions in this suite are anchored", {
  # Cycles 5, 13 and 15 each contained a test of mine that PASSED while the defect it
  # targeted was present, every time because an unanchored source-text pattern matched
  # something adjacent. An expect_false(grepl(...)) on source must be anchored or fixed,
  # or it certifies the bug it was written to catch.
  files <- list.files(p("tests", "testthat"), pattern = "\\.R$", full.names = TRUE)
  offenders <- character(0)
  for (f in files) {
    src <- readLines(f, warn = FALSE)
    # Comment lines are prose about the check, not the check. Cycle 16 counted them, and
    # reported its own explanatory comment in test-control-independence.R as an offender.
    src[grepl("^\\s*#", src)] <- ""
    hits <- grep("expect_false\\(\\s*(any\\()?\\s*grepl\\(", src)
    for (h in hits) {
      blk <- paste(src[h:min(length(src), h + 2)], collapse = " ")
      # An escaped literal such as \\. is as specific as an anchor: it cannot match more
      # than the one character it names, which is the false negative this guards against.
      anchored <- grepl("fixed *= *TRUE", blk) || grepl("\\\\\\\\b|\\^|\\$|\\\\\\\\[.]", blk)
      if (!anchored) offenders <- c(offenders, sprintf("%s:%d", basename(f), h))
    }
  }
  expect_length(offenders, 0L)
})


# ---------------------------------------------------------------- quarantine (added 2026-08-24)

test_that("adversarial: the simulated siblings are still present, still labelled, still barred", {
  # The draws are deliberately kept rather than deleted, so nothing downstream silently changes
  # meaning. The contract is that they cannot be mistaken for the measurements beside them.
  man <- read_manifest(p("analysis_manifest.csv"))
  for (cn in SIMULATED) {
    expect_true(cn %in% names(sheet), info = sprintf("%s was deleted rather than quarantined", cn))
    expect_equal(man$status[man$column == cn], "simulated", info = cn)
    expect_error(gate_provenance(sheet, cn, man), "Simulated variable")
  }
})

test_that("semantic: each real covariate differs from the draw it replaced", {
  # A join that silently failed would leave the real column empty or, worse, copied.
  for (cn in c("CDC_SVI_real" , TRACT)) {
    sim_name <- if (cn == "CDC_SVI_real") "SIMULATED_CDC_SVI" else paste0("SIMULATED_", cn)
    a <- num(cn); b <- num(sim_name)
    both <- !is.na(a) & !is.na(b)
    expect_true(sum(both) > 100L, info = sprintf("%s has too few values to compare", cn))
    expect_false(isTRUE(all.equal(a[both], b[both])),
                 info = sprintf("%s is identical to %s; the join copied the draw", cn, sim_name))
  }
})

test_that("semantic: real covariate missingness does not depend on the exposure arm", {
  # The failure this guards is the 94-control / 0-PE block in the unfielded roster: a covariate
  # absent for one arm makes a complete-case fit delete rows on a basis related to exposure.
  for (cn in c("CDC_SVI_real", TRACT, "County_OBGYN_Count")) {
    out <- gate_missingness(sheet, cn)
    expect_false(any(out$dependent), info = sprintf("%s missingness tracks the arm", cn))
  }
})
