# Scientific CI: statistical/code correctness -- denominators, and Inf/NaN guards.
# Targets power_analysis_new_results.csv, the one power-curve output tracked in git (the
# .gitignore blanket-ignores *.csv with an explicit exception for this file). gate_analytic_n's
# own docstring records that this pipeline once gave all 800 calls a wait time when the study
# would observe about 622 -- a denominator bug that a naive "Power is a number in [0,1]" check
# would not catch, because it changes which N produced the number, not whether the number looks
# plausible. This file checks the arithmetic the table's own columns imply, and that a silently
# failed model fit (NA/NaN/Inf) cannot pass as a small-but-real power estimate.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)

pc <- utils::read.csv(p("power_analysis_new_results.csv"), check.names = FALSE)

test_that("semantic: the tracked power curve is internally arithmetic-consistent and finite", {
  expect_error(gate_power_curve_integrity(pc), NA,
               info = paste("Physicians should be 2x Pairs and Total_Calls should be 2x",
                            "Physicians for every row of this file as committed; if this ever",
                            "fails, the file was regenerated with a column edited independently",
                            "of its dependents"))
})

test_that("BVA: Power exactly at the 0 and 1 boundaries is accepted, not flagged as suspicious", {
  edge <- pc[1, ]
  edge$Power <- 0
  expect_error(gate_power_curve_integrity(edge), NA,
               info = paste("0 is a legitimate power estimate (e.g. an underpowered",
                            "conservative scenario at a tiny N), not a sentinel for a failed",
                            "fit"))
  edge$Power <- 1
  expect_error(gate_power_curve_integrity(edge), NA,
               info = "1 is a legitimate power estimate (a saturated design), not an error code")
})

test_that("adversarial: NaN/Inf/NA in Power is caught, not treated as an unusually small effect", {
  for (bad_value in list(NA_real_, NaN, Inf, -Inf)) {
    broken <- pc[1:3, ]
    broken$Power[2] <- bad_value
    expect_error(gate_power_curve_integrity(broken), "non-finite",
                 info = paste("Power =", format(bad_value), "must fail the gate, not be",
                              "silently coerced or compared as if it were a real probability"))
  }
})

test_that("adversarial: Power outside [0,1] is caught even when perfectly finite", {
  broken <- pc[1, ]
  broken$Power <- 1.05
  expect_error(gate_power_curve_integrity(broken), "outside \\[0,1\\]",
               info = paste("a finite value outside [0,1] is not a valid probability regardless",
                            "of how it was produced"))
  broken$Power <- -0.01
  expect_error(gate_power_curve_integrity(broken), "outside \\[0,1\\]")
})

test_that("adversarial: editing Pairs without regenerating Physicians/Total_Calls is caught", {
  broken <- pc[1, ]
  broken$Pairs <- broken$Pairs + 1L  # Physicians/Total_Calls now stale
  expect_error(gate_power_curve_integrity(broken), "1 PE \\+ 1 control",
               info = paste("this is exactly the failure mode gate_analytic_n's docstring",
                            "describes: a design column edited to explore a new grid point",
                            "without regenerating the derived counts"))
})

test_that("adversarial: Total_Calls that ignores the insurance-arm multiplier is caught", {
  broken <- pc[1, ]
  broken$Total_Calls <- broken$Physicians  # forgot the x2 for Medicaid + BCBS
  expect_error(gate_power_curve_integrity(broken), "insurance arm",
               info = paste("each physician in this design is called under both Medicaid and",
                            "BCBS (README: 400 physicians x 2 arms = 800 records); Total_Calls",
                            "that only counts one arm silently halves the calling burden the",
                            "number implies"))
})

test_that("provenance: a missing required column fails clearly instead of a downstream NA cascade", {
  broken <- pc[, setdiff(names(pc), "Total_Calls")]
  expect_error(gate_power_curve_integrity(broken), "missing column",
               info = paste("silently skipping the check because a column got",
                            "renamed/dropped is worse than failing loudly"))
})
