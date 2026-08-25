# Every analysis the Methods promises must be named in the plan and implemented on real data.
#
# THE DEFECT THIS CATCHES. The Methods have pre-specified an unconditional access analysis
# since before fielding -- "failure to obtain an appointment is ranked as the worst access
# outcome rather than treated as missing data" -- and it appeared nowhere in SAP.lock. Its only
# implementation was in dry_run_sap_revision.R, a simulation script, so the analysis existed
# for fake data and not for real. Nothing failed, because nothing was checked: a promised
# analysis that is simply absent produces no error, only a manuscript that describes work
# nobody did.
#
# Found by reading mysterycall's own vignettes -- matched-pair-analysis, statistical-analysis,
# logistic-model -- and asking which canonical tools this study should be using and is not.
# mysterycall exports mysterycall_cumulative_access_curve(), which is precisely the instrument
# the Methods describe.

# MUTATION EVIDENCE, all reverted:
#   removed the analysis from primary_analysis.Rmd  -> failed: "named in the plan but absent"
#   pointed the plan at a non-exported function     -> failed: "which mysterycall does not export"
#   dropped non-obtained calls instead of ranking   -> failed: "must be placed beyond the
#                                                      horizon, not removed"
#
# The third is the one worth having. That mutation still runs, still produces a plausible
# cumulative access curve, and is silently the conditional analysis again -- the exact thing
# this analysis exists to avoid.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p    <- function(...) file.path(root, ...)

sap  <- read_sap(p("SAP.lock"))
ms   <- paste(readLines(p("manuscript", "manuscript_cite.md"), warn = FALSE), collapse = "\n")
pa   <- paste(readLines(p("primary_analysis.Rmd"), warn = FALSE), collapse = "\n")

test_that("LAW: an analysis the Methods pre-specifies is named in the frozen plan", {
  # The Methods sentence is the promise. If it is there, the plan must carry the analysis.
  promised <- grepl("pre-specify an unconditional access analysis", ms, fixed = TRUE)
  expect_true(promised,
              info = "if this sentence was removed, remove the plan keys and this contract together")
  for (k in c("access_unconditional_estimand", "access_unconditional_subset",
              "access_unconditional_scale", "access_unconditional_horizon",
              "access_unconditional_function")) {
    expect_true(nzchar(trimws(sap[[k]])),
                info = sprintf("the Methods promise this analysis; SAP.lock does not define %s", k))
  }
})

test_that("LAW: a named analysis is implemented where REAL data runs, not only in a dry run", {
  # dry_run_sap_revision.R had it. That is a simulation. The distinction is the whole point.
  expect_true(grepl("mysterycall_cumulative_access_curve", pa, fixed = TRUE),
              info = "the analysis is named in the plan but absent from primary_analysis.Rmd")
  expect_true(grepl("access_unconditional_horizon", pa, fixed = TRUE),
              info = "the horizon must be read from the plan, not chosen inside the document")
  # POSITIVE CONTROL: the document really is the real-data path, so this is not vacuous.
  expect_true(grepl("glmmTMB(F_WT_PRIMARY", pa, fixed = TRUE),
              info = "primary_analysis.Rmd should fit the plan's primary models")
  expect_false(grepl("rnorm(", pa, fixed = TRUE),
               info = "the real-data document must not be simulating its own inputs")
})

test_that("LAW: the implementation uses the canonical function the plan names", {
  # Naming a function in the plan and calling a different one locally is the reimplementation
  # pattern CANONICAL_SOURCES_AUDIT.md records; it also makes the plan unfalsifiable.
  named <- trimws(sap[["access_unconditional_function"]])
  expect_true(grepl("^mysterycall::", named),
              info = "the plan should name a canonical function, not a local one")
  fn <- sub("^mysterycall::", "", named)
  expect_true(fn %in% getNamespaceExports("mysterycall"),
              info = sprintf("SAP names %s, which mysterycall does not export", named))
  expect_true(grepl(fn, pa, fixed = TRUE),
              info = "the document must call the function the plan names")
})

test_that("semantic: non-obtainment is ranked worst rather than dropped", {
  # The scientific content of the analysis. A version that filtered to obtained == 1 would run,
  # produce a plausible curve, and silently be the conditional analysis again.
  expect_false(grepl("d_access <- d_medicaid %>%\n  filter(obtained == 1)", pa, fixed = TRUE))
  expect_true(grepl("HORIZON + 1", pa, fixed = TRUE),
              info = "a non-obtained call must be placed beyond the horizon, not removed")
  expect_true(grepl("medicaid", trimws(sap[["access_unconditional_subset"]]), fixed = TRUE),
              info = "the plan restricts this analysis to Medicaid calls")
})

# --------------------------------------------- numbers the Abstract promises must be computed

test_that("LAW: cell-level numbers the Abstract reports are computed by the analysis", {
  # The Abstract carries placeholders for four ownership-by-payer cells, on both outcomes.
  # An interaction coefficient is the estimand but not the quantity: it says how the payer gap
  # differs by ownership, not how long anybody waits. If the manuscript promises cell means,
  # something must produce them, or they will be transcribed from somewhere unaccountable --
  # which is exactly how the two simulated figures came to exist.
  promises_wait   <- grepl("business days", ms, fixed = TRUE)
  promises_obtain <- grepl("Medicaid acceptance was substantially lower", ms, fixed = TRUE)
  expect_true(promises_wait && promises_obtain,
              info = "if the Abstract no longer reports cell means, retire this contract with it")
  expect_true(grepl("mysterycall_marginal_effects", pa, fixed = TRUE),
              info = "the Abstract reports cell means; the analysis computes none")
  # Both outcomes, not just the one that was easier.
  # Check the ASSIGNMENTS, not merely the names. The first version looked for "mm_obtain"
  # anywhere, which the saveRDS() line satisfies on its own -- so renaming the assignment and
  # computing nothing still passed. The mutation that renamed it was not caught until this
  # was tightened, which is the whole reason mutations are run.
  expect_true(grepl("mm_wait <- mysterycall::mysterycall_marginal_effects(", pa, fixed = TRUE),
              info = "wait-time cell means must actually be computed")
  expect_true(grepl("mm_obtain <- mysterycall::mysterycall_marginal_effects(", pa, fixed = TRUE),
              info = "cell means must be produced for obtainment as well as wait time")
  # POSITIVE CONTROL: computed on the response scale, or they are not interpretable numbers.
  expect_true(grepl('type = "response"', pa, fixed = TRUE),
              info = "link-scale means are not the quantity the Abstract reports")
})

test_that("LAW: results are written out rather than left to be transcribed", {
  # A number that exists only in a rendered console is a number that gets retyped.
  expect_true(grepl("saveRDS(list(wait_time = mm_wait, obtainment = mm_obtain)", pa, fixed = TRUE),
              info = "cell means must be persisted for the manuscript to format")
  expect_true(grepl("primary_analysis_access_curve.rds", pa, fixed = TRUE))
})

# ------------------------------------- effect estimates must be extracted, not read off a print

test_that("LAW: every estimand SAP.lock names is extracted on the scale SAP.lock names", {
  # Each prespecified estimand carries a reporting scale in the frozen plan, and the Abstract
  # reports each with a 95% interval. summary() prints the LINK scale. Filling `OR [0.26],
  # 95% CI [0.17 to 0.40]` from a printed summary means a person reading log-odds off a screen
  # and exponentiating by hand -- a transcription step and an arithmetic step, unrecorded, for
  # numbers that go in an abstract. This is the same defect as the simulated figures, one level
  # up: the manuscript promises a number the analysis does not produce.
  scales <- c("obtainment_primary_scale", "waittime_primary_scale", "obtainment_secondary_scale")
  for (k in scales) {
    expect_true(nzchar(trimws(sap[[k]] %||% "")),
                info = paste0("SAP must name a reporting scale for ", k))
  }
  expect_true(grepl("sap_effect <- function", pa, fixed = TRUE),
              info = "the Abstract reports effect estimates; the analysis extracts none")
  # Each of the three fits, by name -- not one extraction standing in for three.
  for (fit in c("fit_ob_primary", "fit_wt_primary", "fit_ob_secondary")) {
    expect_true(grepl(paste0("sap_effect(", fit, ","), pa, fixed = TRUE),
                info = paste0("no effect estimate is extracted from ", fit))
  }
  # The estimand comes from SAP.lock's own term, never a term typed into the analysis.
  # Checked at the CALL SITE. A bare grepl("TERM_WT_PRIMARY", pa) is satisfied by the line that
  # DEFINES the constant, so replacing the argument with the literal "pe:medicaid" still passed
  # -- the second time in this file that a name-anywhere check proved to be decoration. Found by
  # mutation, not by reading it.
  call_sites <- grep("sap_effect(fit_", strsplit(pa, "\n", fixed = TRUE)[[1]], fixed = TRUE, value = TRUE)
  expect_true(length(call_sites) == 3L,
              info = "expected exactly three sap_effect() call sites, one per prespecified estimand")
  for (cs in call_sites) {
    expect_true(grepl("TERM_", cs, fixed = TRUE),
                info = paste0("the estimand must come from the frozen plan, not a literal: ", trimws(cs)))
  }
  expect_true(any(grepl("TERM_OB_PRIMARY", call_sites, fixed = TRUE)) &&
              any(grepl("TERM_WT_PRIMARY", call_sites, fixed = TRUE)) &&
              any(grepl("TERM_OB_SECONDARY", call_sites, fixed = TRUE)),
              info = "each of the three frozen estimands must appear at a call site")
  # POSITIVE CONTROL: a ratio scale requires the exponential. An OR reported as a log-odds is
  # not merely imprecise, it is a different number, and 0.26 vs -1.35 is not a rounding matter.
  expect_true(grepl("tf <- if (scale %in% c(\"odds ratio\", \"incidence rate ratio\")) exp", pa, fixed = TRUE),
              info = "ratio-scale estimands must be exponentiated onto the reporting scale")
  # NEGATIVE CONTROL: the interval must be built on the link scale and transformed, not built
  # on the ratio scale, which can put a lower bound at or below zero for an odds ratio.
  expect_true(grepl("tf(est - z * se)", pa, fixed = TRUE) && grepl("tf(est + z * se)", pa, fixed = TRUE),
              info = "the Wald interval must be formed on the link scale, then transformed")
  expect_true(grepl("primary_analysis_effects.rds", pa, fixed = TRUE),
              info = "effect estimates must be persisted for the manuscript to format")
})

test_that("LAW: the commercial-arm claim comes from a prespecified model, not a new test", {
  # The Abstract reports `[98.5]% independent vs. [99.0]% PE, [p = 0.68]` for commercial calls.
  # SAP.lock names no commercial-arm analysis. The honest route is that the secondary model is
  # fitted over both payers as `obtained ~ pe * medicaid`, so the `pe` main effect IS the
  # ownership contrast at medicaid = 0. The dishonest route is a fresh test run to fill the
  # bracket -- an unplanned comparison entering an abstract. This pins the honest route.
  if (!grepl("98.5", ms, fixed = TRUE)) skip("Abstract no longer reports a commercial-arm comparison")
  expect_true(grepl("commercial-arm ownership contrast (pe main effect, medicaid = 0)", pa, fixed = TRUE),
              info = "the commercial-arm claim must be derived from the secondary model")
  expect_true(grepl("co_sec <- summary(fit_ob_secondary)", pa, fixed = TRUE),
              info = "it must be read off fit_ob_secondary, which SAP.lock prespecifies")
  # NEGATIVE CONTROL: no separate model may be fitted to the commercial subset. A glmmTMB call
  # restricted to medicaid == 0 is precisely the unplanned analysis this law exists to forbid.
  fits_commercial <- grepl("glmmTMB(", pa, fixed = TRUE) &&
    any(grepl("medicaid == 0", strsplit(pa, "\n", fixed = TRUE)[[1]], fixed = TRUE))
  expect_false(fits_commercial,
               info = "a model fitted to the commercial subset alone is an unplanned analysis")
})
