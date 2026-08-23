# Scientific CI: statistical/code correctness -- the primary outcome's own arithmetic.
# gate_business_days_correct() re-derives a "business days until appointment" column from raw
# call/appointment dates via mysterycall::mysterycall_count_business_days() and asserts
# agreement, rather than trusting whatever arithmetic produced the column. Nothing in this
# repo computes business days from real dates yet (the calling campaign has not launched), so
# these tests build small synthetic data frames rather than reading a cohort CSV -- this file is
# nodata/CI-safe on purpose, so the check exists before the first real REDCap export needs it,
# not after.

df <- function(call, appt, computed) {
  data.frame(call_date = call, appointment_date = appt,
            business_days_until_appointment = computed, stringsAsFactors = FALSE)
}

test_that("semantic: correctly computed business days pass against the canonical calculator", {
  # Both documented examples from ?mysterycall_count_business_days, cross-checked against the
  # function directly (below) rather than only restating the doc's claimed numbers.
  d <- df(
    call = c("2026-02-02", "2026-02-13", "2026-02-02"),  # Mon; Fri before Presidents Day; Mon
    appt = c("2026-02-06", "2026-02-20", "2026-02-02"),  # Fri same wk; spans the holiday; same day
    computed = c(4L, 4L, 0L)
  )
  expect_error(gate_business_days_correct(d), NA,
               info = paste("Mon->Fri same week = 4, a span crossing Presidents Day 2026 also",
                            "= 4 (not 5, since Feb 16 2026 is a federal holiday), same-day = 0"))
})

test_that("BVA: a multi-week span excluding two weekends and a holiday is counted correctly", {
  # Mon 2026-02-02 to Mon 2026-02-16 (Presidents Day itself): computed from the function, not
  # asserted from arithmetic done in this comment, then pinned so a future silent change to
  # mysterycall's holiday handling shows up as a changed expectation, not a passing gate.
  want <- mysterycall::mysterycall_count_business_days("2026-02-02", "2026-02-16")
  expect_equal(want, 9L,
               info = "10 weekdays in the span minus the 1 federal holiday (Presidents Day)")
  d <- df("2026-02-02", "2026-02-16", want)
  expect_error(gate_business_days_correct(d), NA)
})

test_that("adversarial: naive calendar-day arithmetic (as.numeric(appt - call)) is caught", {
  # Friday -> Monday is the case where naive calendar-day counting and business-day counting
  # must diverge (3 calendar days vs. 1 business day); a same-week Mon-Fri pair would coincide
  # by chance and not actually exercise the defect this gate exists to catch.
  call <- as.Date("2026-02-06"); appt <- as.Date("2026-02-09")  # Fri -> Mon
  naive <- as.numeric(appt - call)
  canonical <- mysterycall::mysterycall_count_business_days(call, appt)
  expect_equal(naive, 3)
  expect_equal(canonical, 1L)
  d <- df(as.character(call), as.character(appt), naive)
  expect_error(gate_business_days_correct(d), "disagree",
               info = "the naive count (3) must be rejected against the canonical value (1)")
})

test_that("adversarial: an inclusive-start off-by-one is caught", {
  # A common alternative (and wrong, for this contract) convention: counting the call date
  # itself as day 1. Mon->Fri would then read 5, not the documented 4.
  d <- df("2026-02-02", "2026-02-06", 5L)
  expect_error(gate_business_days_correct(d), "disagree",
               info = paste("start_date is documented as EXCLUSIVE; a column built on an",
                            "inclusive convention is off by one and must not pass silently"))
})

test_that("BVA: NA and reversed dates propagate to the documented NA, not to a false mismatch", {
  d <- df(c(NA, "2026-02-06"), c("2026-02-06", "2026-02-02"), c(NA, NA))
  expect_error(suppressWarnings(gate_business_days_correct(d)), NA,
               info = paste("NA call_date and a reversed date pair both canonically resolve to",
                            "NA; the reversed pair emits a mysterycall warning, which is",
                            "expected and not itself a gate failure"))
})

test_that("provenance: a missing required column fails clearly instead of a downstream NA cascade", {
  broken <- df("2026-02-02", "2026-02-06", 4L)[, c("call_date", "business_days_until_appointment")]
  expect_error(gate_business_days_correct(broken), "missing column",
               info = paste("silently skipping the check because a column got renamed is",
                            "worse than failing loudly"))
})
