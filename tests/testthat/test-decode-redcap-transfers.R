# decode_redcap_transfers() -- the REDCap `transfers` field is a dropdown, not a raw count:
# 1 = "No transfers", 2 = "One transfer", 3 = "Two transfers", 4 = "More than two transfers".
# Treating the stored integer as the transfer count itself is off by one for every single row --
# exactly the class of defect this repo's business-days gate exists to catch for dates, applied
# here to a different field with the same shape of trap.

test_that("semantic: the dropdown value is decoded, not used as the count", {
  d <- decode_redcap_transfers(c(1, 2, 3, 4))
  expect_equal(d$transfers, c(0L, 1L, 2L, 3L))
})

test_that("adversarial: treating the raw value as the count is what this function exists to prevent", {
  d <- decode_redcap_transfers(c(1, 2, 3, 4))
  raw_value_used_directly <- c(1L, 2L, 3L, 4L)
  expect_false(identical(d$transfers, raw_value_used_directly),
              info = "if this ever passes, decode_redcap_transfers() has regressed to a no-op")
})

test_that("semantic: value 4 ('more than two') is censored at 3, not asserted as exactly 3", {
  d <- decode_redcap_transfers(4)
  expect_equal(d$transfers, 3L)
  expect_true(d$transfers_censored)
})

test_that("semantic: values 1-3 are not censored", {
  d <- decode_redcap_transfers(c(1, 2, 3))
  expect_false(any(d$transfers_censored))
})

test_that("BVA: NA propagates to NA, not to a censoring flag or a coerced zero", {
  d <- decode_redcap_transfers(c(1, NA, 4))
  expect_equal(d$transfers, c(0L, NA_integer_, 3L))
  expect_equal(d$transfers_censored, c(FALSE, FALSE, TRUE))
})

test_that("provenance: a value outside the documented 1-4 range fails loudly", {
  expect_error(decode_redcap_transfers(0), "1-4")
  expect_error(decode_redcap_transfers(5), "1-4")
  expect_error(decode_redcap_transfers(-1), "1-4")
})

test_that("BVA: a vector of only valid values round-trips through both output columns", {
  d <- decode_redcap_transfers(c(1, 1, 2, 3, 4, 4))
  expect_equal(d$transfers, c(0L, 0L, 1L, 2L, 3L, 3L))
  expect_equal(d$transfers_censored, c(FALSE, FALSE, FALSE, FALSE, TRUE, TRUE))
})
