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
