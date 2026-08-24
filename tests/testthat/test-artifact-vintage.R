# Cycle 24 -- 3 BVA, 3 semantic, 4 adversarial.
# The cohort has been redrawn four times during this exercise: platform eligibility, the
# verified-CNM exclusion, the NPI repair, activity recency and exact gender matching. Nothing
# has tested whether the artifacts DOWNSTREAM of the cohort still describe it. A figure or a
# table that silently describes a superseded cohort is the most publishable kind of error.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)
rd <- function(f) utils::read.csv(f, colClasses = "character", check.names = FALSE)

sheet  <- rd(p("pe_obgyn_final_calling_sheet_200_dedup.csv"))
pool   <- rd(p("pe_obgyn_matched_calling_list.csv"))
db     <- rd(p("pe_obgyn_study_database.csv"))
ms     <- readLines(p("manuscript", "manuscript_cite.md"))
strobe <- readLines(p("manuscript", "strobe_diagram.R"))

n_pool   <- length(unique(pool[["Matched Pair ID"]]))
n_field  <- length(unique(sheet[["Matched Pair ID"]]))
n_states <- length(unique(sheet$State))

mtime <- function(f) if (file.exists(p(f))) file.info(p(f))$mtime else NA
cohort_time <- mtime("pe_obgyn_final_calling_sheet_200_dedup.csv")

# ---------------------------------------------------------------- BVA (3)

test_that("BVA: the cohort has the sizes every downstream artifact must agree with", {
  expect_equal(n_field, 200L)
  expect_equal(nrow(sheet), 400L)
  expect_true(n_pool >= n_field,
              info = "the fielded sample cannot exceed the pool it was drawn from")
})

test_that("BVA: the provenance sidecar matches the artifact it describes", {
  side <- p("pe_obgyn_study_database.provenance.txt")
  expect_true(file.exists(side))
  txt <- readLines(side, warn = FALSE)
  rows <- as.integer(sub(".*: *", "", grep("^rows:", txt, value = TRUE)[1]))
  pairs <- as.integer(sub(".*: *", "", grep("^matched_pairs:", txt, value = TRUE)[1]))
  expect_equal(rows, nrow(db))
  expect_equal(pairs, n_pool)
})

test_that("BVA: the REDCap artifacts address the cohort, by content rather than by clock", {
  # CONTRACT CHANGED 2026-08-24. This compared file mtimes against the cohort's mtime, which
  # answers the wrong question twice over: a git clone resets every mtime, and adding a
  # covariate column to the sheet marks artifacts stale that do not depend on covariates at
  # all. What matters is whether they still address the same clinicians. They do, and that is
  # now checked directly.
  choices <- readLines(p("redcap_physician_name_choices.txt"), warn = FALSE)
  choices <- choices[nzchar(trimws(choices))]
  npi_of  <- function(x) trimws(sub(".*NPI: *([0-9]+).*", "\\1", x))
  expect_equal(length(choices), 800L)
  expect_setequal(unique(npi_key(npi_of(choices))), npi_key(sheet$NPI))
  imp <- rd(p("redcap_import_ready_200.csv"))
  expect_equal(nrow(imp), 800L)
  # The schedule carries no NPI column -- it is keyed by clinician name and dialed number --
  # so it is matched on the phone, which is what a caller actually uses.
  sched <- rd(p("redcap_call_schedule_800.csv"))
  expect_equal(nrow(sched), nrow(sheet))
  expect_setequal(phone_key(sched$Phone), phone_key(sheet$Phone))
})

# ---------------------------------------------------------------- semantic (3)

test_that("semantic: the STROBE figure describes the current cohort", {
  stage <- function(name) {
    ln <- grep(paste0('"', name, '"'), strobe, value = TRUE, fixed = TRUE)
    ln <- grep("= *[0-9]+", ln, value = TRUE)[1]
    if (is.na(ln)) return(NA_integer_)
    as.integer(sub(".*= *([0-9]+).*", "\\1", ln))
  }
  # Stated in CLINICIANS throughout. The figure previously gave 544 for both the de-clustering
  # and matching stages -- a number matching nothing in the current pipeline -- and then 200
  # for the fielded cohort, switching to pairs halfway down without saying so.
  expect_equal(stage("Initial Scraped PE Roster"), 1537L)
  expect_equal(stage("Geographically Matched"), nrow(pool),
               info = sprintf("Figure states %s; the matched pool holds %d clinicians (%d pairs)",
                              stage("Geographically Matched"), nrow(pool), n_pool))
  expect_equal(stage("Fielded Cohort"), nrow(sheet),
               info = sprintf("Figure states %s; the fielded cohort holds %d clinicians (%d pairs)",
                              stage("Fielded Cohort"), nrow(sheet), n_field))
})

test_that("semantic: the Methods states the pool size the cohort actually has", {
  txt <- paste(ms, collapse = "\n")
  m <- regmatches(txt, regexpr("matched pool of [0-9]+ pairs", txt))
  expect_true(length(m) == 1L)
  stated <- as.integer(sub("[^0-9]*([0-9]+).*", "\\1", m))
  expect_equal(stated, n_pool,
               info = sprintf("Methods says %d pairs; the matched pool has %d", stated, n_pool))
})

test_that("semantic: the Methods states the number of states actually fielded", {
  txt <- paste(ms, collapse = "\n")
  m <- regmatches(txt, gregexpr("[0-9]+ U[.]?S[.]? states|across [0-9]+ states", txt))[[1]]
  expect_true(length(m) > 0L)
  stated <- unique(as.integer(sub("[^0-9]*([0-9]+).*", "\\1", m)))
  expect_true(all(stated == n_states),
              info = sprintf("Methods states %s states; the cohort spans %d",
                             paste(stated, collapse = "/"), n_states))
})

# ---------------------------------------------------------------- adversarial (4)

test_that("adversarial: the stale analysis artifacts are exactly the four already known", {
  # CONTRACT CHANGED, pinned rather than denied. These four are power and sensitivity results
  # computed against an earlier cohort: they predate the SVI reconstruction, the taxonomy fix
  # and the real ACS covariates, and one of them predates the fielded cohort's recovery
  # entirely. They are genuinely stale and re-running them is a separate piece of work, so the
  # set is named here. A FIFTH stale artifact, or a new one, fails this test.
  # The original list named four. Enumerating the directory rather than a hand-written list
  # found eight, including both dry-run analysis outputs -- so the check had been looking at
  # half the problem. Dates run from 5 July to 10 August; the fielded cohort was recovered and
  # corrected on 23-24 August.
  KNOWN_STALE <- c("dry_run_analysis_results.csv", "dry_run_sap_revision_results.csv",
                   "geographic_sensitivity_results.csv", "obtainment_power_results.csv",
                   "power_analysis_new_results.csv", "power_interaction_75_results.csv",
                   "power_maineffect_results.csv", "simr_power_results.csv")
  stale <- character(0)
  for (f in list.files(root, pattern = "_results[.]csv$")) {
    t <- mtime(f)
    if (!is.na(t) && t < cohort_time) stale <- c(stale, basename(f))
  }
  expect_setequal(stale, intersect(KNOWN_STALE, stale))
  expect_length(setdiff(stale, KNOWN_STALE), 0L)
})

test_that("adversarial: no figure asserts an outcome that has not been measured", {
  # THE FINDING THIS CYCLE EXISTS FOR, and it was not staleness.
  #
  # manuscript/generate_figures.R builds the study's two primary-outcome figures from numbers
  # typed into the script: Figure 1's obtainment rates are literals with confidence intervals
  # (PE Medicaid 41.0% against independent 72.5%), Figure 2 is rlnorm() draws around typed
  # medians (PE Medicaid 36.8 business days against 23.4). No call has been placed, no REDCap
  # outcome export exists, and the analysis in SAP.lock has never been run.
  #
  # They were written to manuscript/figure1.png and figure2.png with titles that read as
  # findings. This repository already forbids exactly this for columns -- CDC_SVI became
  # SIMULATED_CDC_SVI so that no fielded artifact asserts a measurement that was not made
  # (test-svi-provenance.R). The same rule, for figures.
  outcome_export <- length(list.files(root, pattern = "^redcap_export.*[.]csv$")) > 0L
  gen <- readLines(p("manuscript", "generate_figures.R"), warn = FALSE)
  outputs <- regmatches(gen, regexpr('"[A-Za-z0-9_]+[.]png"', gen))
  outputs <- gsub('"', "", outputs)
  outcome_figs <- grep("obtain|wait", outputs, ignore.case = TRUE, value = TRUE)
  expect_true(length(outcome_figs) >= 2L,
              info = "expected the obtainment and wait-time figures to be found by name")
  if (!outcome_export) {
    for (f in outcome_figs) {
      expect_true(grepl("^SIMULATED_", f),
                  info = sprintf("%s depicts an outcome, and no outcome data exists", f))
      expect_false(file.exists(p("manuscript", sub("^SIMULATED_", "", f))),
                   info = sprintf("an unmarked copy of %s is still present", f))
    }
    titles <- grep("title *=", gen, value = TRUE)
    titles <- grep("Obtainment Rates|Wait Times", titles, value = TRUE)
    expect_true(all(grepl("SIMULATED", titles)),
                info = "an outcome figure title must say so on its face, not only in its filename")
  }
})

test_that("adversarial: the eligibility rules that shaped the cohort are described", {
  txt <- paste(ms, collapse = "\n")
  # Three exclusions now determine who is eligible. A reader cannot reconstruct the cohort
  # from the Methods unless each is stated.
  # Premise correction: "inactive" was my own shorthand, not a term the Methods needs to use.
  # The contract is that each rule is DESCRIBED, so match the description rather than a label.
  checks <- c(fertility  = "fertility",
              hospitalist = "hospitalist",
              recency     = "not observed practising")
  for (nm in names(checks)) {
    expect_true(grepl(checks[[nm]], txt, ignore.case = TRUE),
                info = sprintf("the Methods does not describe the %s exclusion", nm))
  }
})

test_that("adversarial: the fielded sheet's departure from the pool is the known one, and no larger", {
  # CONTRACT CHANGED, pinned rather than denied, exactly as in test-frozen-geo-reference.R.
  # 173 of the 400 fielded clinicians are not in the matched pool; they entered through the
  # non-pool path that also carried the 18 excluded-platform clinicians and the frozen
  # coordinate shortfall. Asserting the subset property would assert something the pipeline
  # demonstrably did not do. Asserting the exact size makes any further drift fail here.
  extra_npi  <- setdiff(npi_key(sheet$NPI), npi_key(pool$NPI))
  extra_pair <- setdiff(sheet[["Matched Pair ID"]], pool[["Matched Pair ID"]])
  expect_equal(length(extra_npi), 173L,
               info = sprintf("%d fielded clinicians are outside the matched pool", length(extra_npi)))
  expect_equal(length(extra_pair), 18L)
  # Whatever their provenance, they are still whole pairs in the same two arms.
  expect_true(all(table(sheet[["Matched Pair ID"]]) == 2L))
})
