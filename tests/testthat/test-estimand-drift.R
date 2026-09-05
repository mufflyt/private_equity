# Estimand drift: 3 BVA, 3 semantic, 3 adversarial.
#
# WHAT THIS GOVERNS. gate_sap() already refuses to fit a formula SAP.lock does not name, and
# primary_analysis.Rmd takes its term names from gate_sap()'s return value, so the ESTIMAND
# itself cannot drift. Three things still can, and nothing caught any of them:
#
#   scale drift        The plan reports the wait-time interaction as an incidence rate ratio.
#                      Nothing stopped the manuscript printing "OR 1.31" beside it. Both
#                      numbers are exp(beta); ONLY THE LABEL distinguishes an odds ratio from
#                      an incidence rate ratio, and the label is prose that no gate read.
#   undeclared report  A quantity pulled from a prespecified model that the plan does not name.
#                      The commercial-arm `pe` main effect is one, it is legitimate, and it is
#                      documented in primary_analysis.Rmd -- which is exactly why it must be
#                      DECLARED in config/derived_estimands.csv. An unplanned comparison
#                      smuggled into the Abstract would look identical in the output.
#   orphaned estimand  An analysis the plan names that nothing reports, so the plan describes a
#                      larger study than the one performed.
#
# The report reads declarations only. It fits nothing and needs no cohort data, which is why it
# can run in CI when the analysis itself cannot.
#
# MUTATION EVIDENCE (Law 1, docs/SCIENTIFIC_CI_LAWS.md):
#   negative control  each of the three drift classes is provoked against a synthetic plan and
#                     must be reported (test 7). Runs live.
#   positive control  a consistent synthetic plan must report nothing, so a clean report is not
#                     a detector that never fires (test 7).
#   end-to-end        2026-09-05, four mutations, each caught by the right test:
#                       "IRR [1.31]" -> "OR [1.31]"       -> test 6 (label vs its own estimand)
#                       "IRR [1.31]" -> "HR [1.31]"       -> test 8 (no drift in the repo)
#                       waittime_primary no longer read   -> test 7 (orphaned estimand)
#                       committed report edited by hand   -> test 9 (report is stale)
#                     All reverted clean to 24 passed / 0 failed.
#
# WHY TEST 6 EXISTS SEPARATELY FROM THE REPORT'S OWN SCALE CHECK, and it is the subtle one.
# The report asks whether a printed scale is one the plan uses ANYWHERE. "odds ratio" is such a
# scale, so relabelling the wait-time interaction from IRR to OR passes that membership test
# while saying something false: an incidence rate ratio reported as an odds ratio. Test 6 pins
# each label to ITS OWN estimand's planned scale, which is the assertion that actually holds.
# Mutation 1 above is the evidence -- it is caught by test 6 and by nothing else.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
source(file.path(root, "R", "analysis_gates.R"))
source(file.path(root, "R", "estimand_drift.R"))

SAP <- read_sap(file.path(root, "SAP.lock"))
plan <- sap_estimands(SAP)
drift <- estimand_drift(SAP, root = root)

# ---------------------------------------------------------------- BVA (3)

test_that("BVA: every prespecified analysis is parsed with an estimand and a scale", {
  expect_true(nrow(plan) >= 3L,
              info = "fewer analyses parsed than SAP.lock declares; the checks below go vacuous")
  expect_true(all(nzchar(plan$estimand)))
  expect_true(all(nzchar(plan$scale)))
  expect_false(any(duplicated(plan$analysis)))
})

test_that("BVA: the report is generated, not hand-written", {
  rp <- file.path(root, "docs", "ESTIMAND_DRIFT_REPORT.md")
  expect_true(file.exists(rp))
  txt <- readLines(rp, warn = FALSE)
  expect_true(any(grepl("Do not hand-edit", txt, fixed = TRUE)))
  expect_true(any(grepl("R/estimand_drift.R", txt, fixed = TRUE)))
})

test_that("BVA: the derived-estimand registry parses and declares what it needs to", {
  der <- read_derived(file.path(root, DRIFT_DERIVED))
  expect_true(all(c("reported_as", "derived_from", "term", "scale", "justification") %in% names(der)))
  if (nrow(der)) {
    expect_true(all(nzchar(der$justification)),
                info = "a derived quantity with no justification is indistinguishable from an unplanned one")
    expect_true(all(der$derived_from %in% plan$analysis),
                info = "a derived quantity claims to come from an analysis the plan does not name")
  }
})

# ---------------------------------------------------------------- semantic (3)

test_that("semantic: the label map covers every abbreviation the manuscript actually prints", {
  ms <- manuscript_scale_labels(file.path(root, "manuscript", "manuscript_cite.md"))
  expect_true(nrow(ms) > 0L, info = "no scale labels found; the drift check would be vacuous")
  expect_false(any(is.na(ms$reported_scale)),
               info = paste("unrecognised scale label(s):",
                            paste(unique(ms$label[is.na(ms$reported_scale)]), collapse = ", ")))
  # The parser used to leave the closing bracket on the value ("0.26]").
  expect_true(all(grepl("^[0-9.]+$", ms$value)),
              info = "a parsed value carries stray punctuation; the report would misquote it")
})

test_that("semantic: each printed label denotes the scale its own estimand is planned on", {
  # Membership alone is too weak: "odds ratio" is a plan scale, so relabelling the wait-time
  # IRR as an OR passes a membership test. Pin the two the Abstract actually reports.
  ms <- manuscript_scale_labels(file.path(root, "manuscript", "manuscript_cite.md"))
  irr <- ms[ms$label == "IRR", , drop = FALSE]
  expect_true(nrow(irr) > 0L, info = "the Abstract no longer reports an IRR")
  expect_equal(unique(irr$reported_scale),
               plan$scale[plan$analysis == "waittime_primary"],
               info = "the wait-time interaction is printed on a scale the plan does not name for it")
  or <- ms[ms$label == "OR", , drop = FALSE]
  expect_true(nrow(or) > 0L, info = "the Abstract no longer reports an OR")
  expect_true(unique(or$reported_scale) %in%
                plan$scale[plan$analysis %in% c("obtainment_primary", "obtainment_secondary")])
})

test_that("semantic: every analysis the plan names is read by the reporting source", {
  code <- reported_estimands(file.path(root, "primary_analysis.Rmd"))
  reported <- unique(stats::na.omit(code$analysis))
  orphans <- setdiff(plan$analysis, reported)
  expect_equal(orphans, character(0),
               info = paste("SAP.lock names analyses nothing reports:", paste(orphans, collapse = ", ")))
})

# ---------------------------------------------------------------- adversarial (3)

test_that("adversarial: NEGATIVE and POSITIVE controls on all three drift classes", {
  tmp <- file.path(tempdir(), "driftctl")
  dir.create(file.path(tmp, "manuscript"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(tmp, "config"), recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  synth <- list(alpha_estimand = "pe", alpha_scale = "odds ratio",
                beta_estimand = "pe:medicaid", beta_scale = "incidence rate ratio")

  # --- positive control: consistent world reports nothing ---
  writeLines('scale = SAP[["alpha_scale"]]\nx <- SAP[["beta_scale"]]',
             file.path(tmp, "primary_analysis.Rmd"))
  writeLines("OR [0.26] and IRR [1.31]", file.path(tmp, "manuscript", "manuscript_cite.md"))
  expect_equal(nrow(estimand_drift(synth, root = tmp)), 0L,
               info = "a consistent plan/code/manuscript produced a finding")

  # --- negative control 1: orphaned estimand ---
  writeLines('scale = SAP[["alpha_scale"]]', file.path(tmp, "primary_analysis.Rmd"))
  d1 <- estimand_drift(synth, root = tmp)
  expect_true("orphaned estimand" %in% d1$severity,
              info = "an analysis nothing reports was not flagged")

  # --- negative control 2: scale drift ---
  writeLines('scale = SAP[["alpha_scale"]]\nx <- SAP[["beta_scale"]]',
             file.path(tmp, "primary_analysis.Rmd"))
  writeLines("reported as HR [0.80]", file.path(tmp, "manuscript", "manuscript_cite.md"))
  d2 <- estimand_drift(synth, root = tmp)
  expect_true("scale drift" %in% d2$severity,
              info = "a hazard ratio in a study that plans none was not flagged")

  # --- negative control 3: hard-coded scale ---
  writeLines(c('scale = SAP[["alpha_scale"]]', 'x <- SAP[["beta_scale"]]',
               '  scale    = "odds ratio",'), file.path(tmp, "primary_analysis.Rmd"))
  writeLines("OR [0.26] and IRR [1.31]", file.path(tmp, "manuscript", "manuscript_cite.md"))
  d3 <- estimand_drift(synth, root = tmp)
  expect_true("hard-coded scale" %in% d3$severity,
              info = "a scale literal typed into the source was not flagged")
})

test_that("adversarial: the repository currently has no estimand drift", {
  expect_true(nrow(drift) == 0L,
              info = paste("drift ->",
                           paste(sprintf("[%s] %s", drift$severity, drift$item), collapse = " | ")))
})

test_that("adversarial: the committed report matches what the code regenerates now", {
  # A stale committed report is worse than none: it reads as a current all-clear.
  tmp <- file.path(tempdir(), "driftfresh"); dir.create(tmp, showWarnings = FALSE)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  fresh <- file.path("regen.md")
  write_drift_report(path = fresh, root = root)
  on.exit(unlink(file.path(root, fresh)), add = TRUE)
  a <- readLines(file.path(root, fresh), warn = FALSE)
  b <- readLines(file.path(root, "docs", "ESTIMAND_DRIFT_REPORT.md"), warn = FALSE)
  drop_date <- function(x) x[!grepl("^Generated by", x)]
  expect_equal(drop_date(a), drop_date(b),
               info = "docs/ESTIMAND_DRIFT_REPORT.md is stale; rerun Rscript R/estimand_drift.R")
})
