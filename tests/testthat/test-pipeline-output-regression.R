# Ten regression tests pinning exact outputs of the functions that turn raw inputs into "the
# data" this study reports -- so that a change to this repo's code, or to mysterycall's, that
# silently alters a computed value is caught as a diff against a known-correct answer, not
# discovered later. Existing tests mostly check CONTRACTS (a formula matches SAP.lock, a
# permutation is blinded); these pin actual VALUES, computed once here and verified by hand
# against the documentation or an independent source before being trusted.
#
# Three of the ten (gate_analytic_n, gate_clustering, key_join_index) had zero nodata coverage
# anywhere before this file -- the same "important gate, no real CI protection" gap already
# found and closed for gate_sap() in test-sap-contract-gates.R.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)

# ---------------------------------------------------------------------------- 1
test_that("regression: mysterycall_count_business_days() golden vector", {
  starts <- as.Date(c("2026-02-02", "2026-02-06", "2026-02-13", "2026-02-02", "2026-02-09"))
  ends   <- as.Date(c("2026-02-02", "2026-02-09", "2026-02-20", "2026-02-06", "2026-02-06"))
  # same day = 0; Fri->Mon = 1 (weekend only); Fri before Presidents Day -> spans the holiday,
  # still 4 (not 5); Mon->Fri same week = 4; reversed (end before start) = NA. Each pair was
  # independently verified against ?mysterycall_count_business_days in
  # test-business-days-correct.R; this pins them together as one vectorized golden call.
  expect_equal(
    suppressWarnings(mysterycall::mysterycall_count_business_days(starts, ends)),
    c(0L, 1L, 4L, 4L, NA_integer_)
  )
})

# ---------------------------------------------------------------------------- 2
test_that("regression: mysterycall_prepare_calls() golden output on its own documented example", {
  df <- data.frame(
    calldate1   = c("2024-01-10", "2024-01-11", "2024-01-12", NA, "2024-01-14"),
    contacted1  = c(1, 1, 0, 1, 1),
    contacted2  = c(99, 99, 1, 99, 99),
    appdate     = c("2024-02-01", "", "2024-02-05", "2024-02-03", "2024-02-10"),
    exclusions  = c(0, 9, 0, 0, 7),
    # Synthetic caller given names. These were real study-staff names until 2026-09-05;
    # caller identity is data about a person, and it does not belong in a public fixture.
    # The mixed case is load-bearing -- it is what exercises the normalisation asserted
    # below -- so the shapes ("x", "Y", "X", other, "y") are preserved exactly.
    # tests/testthat/test-staff-deidentification.R stops the real names coming back.
    initials    = c("avery", "BRIAR", "Avery", "carson", "briar"),
    stringsAsFactors = FALSE
  )
  result <- suppressWarnings(mysterycall::mysterycall_prepare_calls(df))
  expect_equal(result$logistic_data$appt_offered, c(1L, 0L, 1L, 1L))
  expect_equal(result$logistic_data$caller, c("Avery", "Briar", "Avery", "Briar"))
  expect_equal(result$waittime_data$business_days_until_appointment, c(15L, 15L))
  expect_equal(result$waittime_data$calendar_days, c(22, 24))
  expect_equal(result$waterfall$n_remaining, c(5L, 4L, 4L, 2L))
})

# ---------------------------------------------------------------------------- 3
test_that("regression: decode_redcap_transfers() golden table across every documented input", {
  d <- decode_redcap_transfers(c(1, 2, 3, 4, NA))
  expect_equal(d$transfers, c(0L, 1L, 2L, 3L, NA_integer_))
  expect_equal(d$transfers_censored, c(FALSE, FALSE, FALSE, TRUE, FALSE))
})

# ---------------------------------------------------------------------------- 4
test_that("regression: gate_analytic_n() golden pass/fail boundary at tol=0.05", {
  obs <- c(pe_medicaid = 95, ctrl_medicaid = 100)
  expect_error(gate_analytic_n(obs, c(pe_medicaid = 100, ctrl_medicaid = 100), tol = 0.05), NA,
              info = "exactly 5% off must still pass: the check is strictly greater-than tol")
  expect_error(gate_analytic_n(obs, c(pe_medicaid = 80, ctrl_medicaid = 100), tol = 0.05),
              "departs from the powered design")
})

# ---------------------------------------------------------------------------- 5
test_that("regression: gate_clustering() golden pass/fail on a known cluster structure", {
  d <- data.frame(unit = c("a", "a", "b", "c", "c", "c"))
  expect_error(gate_clustering(d, "unit", expect_n = 3L, max_size = 3L), NA)
  expect_error(gate_clustering(d, "unit", expect_n = 4L), "3 clusters; 4 were expected")
  expect_error(gate_clustering(d, "unit", max_size = 2L), "largest unit cluster holds 3 rows")
})

# ---------------------------------------------------------------------------- 6
test_that("regression: sap_restrict() golden output -- a half-eligible pair is dropped whole", {
  sap2 <- list(analytic_population_column = "Eligible")
  d <- data.frame(`Matched Pair ID` = c("p1", "p1", "p2", "p2", "p3", "p3"),
                 Eligible = c("TRUE", "TRUE", "TRUE", "FALSE", "FALSE", "FALSE"),
                 check.names = FALSE, stringsAsFactors = FALSE)
  r <- sap_restrict(d, sap2)
  expect_equal(r[["Matched Pair ID"]], c("p1", "p1"),
              info = "p2 has one TRUE and one FALSE member and must be dropped entirely, not half-kept")
})

# ---------------------------------------------------------------------------- 7
test_that("regression: artifact_sha256() against an externally-known SHA-256 test vector", {
  tmp <- tempfile()
  on.exit(unlink(tmp))
  writeLines("hello", tmp, sep = "")
  expect_equal(artifact_sha256(tmp),
              "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
              info = "the well-known published SHA-256 of the 5-byte string 'hello', not derived from this repo's own code")
})

# ---------------------------------------------------------------------------- 8
test_that("regression: norm_formula() golden output -- a formula object and its string both normalize the same way", {
  f_obj <- business_days ~ pe * medicaid   +   svi_z + (1|pair) +   (1 | npi)
  f_str <- "business_days ~ pe * medicaid + svi_z + (1 | pair) + (1 | npi)"
  expect_equal(norm_formula(f_obj), "business_days ~ pe * medicaid + svi_z + (1 | pair) + (1 | npi)")
  expect_identical(norm_formula(f_obj), norm_formula(f_str),
                   info = "gate_sap() compares these two forms directly; if normalization ever diverges between them, gate_sap() would wrongly reject a correctly-specified model")
})

# ---------------------------------------------------------------------------- 9
test_that("regression: key_join_index() golden output on a known partial match", {
  x   <- c("1003038688.0", "9999999999", "1234567893.0")
  tbl <- c("1003038688", "1234567893", "5555555555")
  expect_equal(key_join_index(x, tbl, min_match = 0, label = "t", key_fun = npi_key),
              c(1L, NA_integer_, 2L))
})

# ---------------------------------------------------------------------------- 10
test_that("regression: read_sap() golden parse of a small fixed SAP-formatted file", {
  tf <- tempfile()
  on.exit(unlink(tf))
  writeLines(c("# comment", "", "alpha = 0.05", "sided = two",
              "key_with_spaces =   value with spaces  "), tf)
  parsed <- read_sap(tf)
  expect_equal(parsed, list(alpha = "0.05", sided = "two",
                            key_with_spaces = "value with spaces"))
})
