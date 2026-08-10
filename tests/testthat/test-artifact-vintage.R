# Cycle 24 -- 3 BVA, 3 semantic, 4 adversarial.
# The cohort has been redrawn four times during this exercise: platform eligibility, the
# verified-CNM exclusion, the NPI repair, activity recency and exact gender matching. Nothing
# has tested whether the artifacts DOWNSTREAM of the cohort still describe it. A figure or a
# table that silently describes a superseded cohort is the most publishable kind of error.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)
rd <- function(f) utils::read.csv(f, colClasses = "character", check.names = FALSE)

sheet  <- rd(p("pe_obgyn_final_calling_sheet_200.csv"))
pool   <- rd(p("pe_obgyn_matched_calling_list.csv"))
db     <- rd(p("pe_obgyn_study_database.csv"))
ms     <- readLines(p("manuscript", "manuscript_cite.md"))
strobe <- readLines(p("manuscript", "strobe_diagram.R"))

n_pool   <- length(unique(pool[["Matched Pair ID"]]))
n_field  <- length(unique(sheet[["Matched Pair ID"]]))
n_states <- length(unique(sheet$State))

mtime <- function(f) if (file.exists(p(f))) file.info(p(f))$mtime else NA
cohort_time <- mtime("pe_obgyn_final_calling_sheet_200.csv")

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

test_that("BVA: every fielded artifact is at least as new as the cohort", {
  for (f in c("redcap_import_ready_200.csv", "redcap_physician_name_choices.txt",
              "redcap_call_schedule_800.csv")) {
    t <- mtime(f)
    expect_true(!is.na(t) && t >= cohort_time - 60,
                info = sprintf("%s predates the fielded cohort and is stale", f))
  }
})

# ---------------------------------------------------------------- semantic (3)

test_that("semantic: the STROBE figure describes the current cohort", {
  stage <- function(name) {
    ln <- grep(paste0('"', name, '"'), strobe, value = TRUE, fixed = TRUE)
    ln <- grep("= *[0-9]+", ln, value = TRUE)[1]
    if (is.na(ln)) return(NA_integer_)
    as.integer(sub(".*= *([0-9]+).*", "\\1", ln))
  }
  expect_equal(stage("Geographically Matched"), n_pool,
               info = sprintf("Figure 1 states %s matched pairs; the cohort has %d",
                              stage("Geographically Matched"), n_pool))
  expect_equal(stage("Fielded Cohort"), n_field)
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

test_that("adversarial: no analysis artifact predates the cohort it analyses", {
  stale <- character(0)
  for (f in c("geographic_sensitivity_results.csv", "power_analysis_new_results.csv",
              "obtainment_power_results.csv", "simr_power_results.csv")) {
    t <- mtime(f)
    if (!is.na(t) && t < cohort_time) stale <- c(stale, basename(f))
  }
  expect_length(stale, 0L)
})

test_that("adversarial: no published figure predates the cohort it depicts", {
  figs <- c(list.files(p("manuscript"), pattern = "[.]png$", full.names = FALSE))
  stale <- figs[vapply(figs, function(f) {
    t <- mtime(file.path("manuscript", f)); !is.na(t) && t < cohort_time
  }, logical(1))]
  expect_length(stale, 0L)
})

test_that("adversarial: the eligibility rules that shaped the cohort are described", {
  txt <- paste(ms, collapse = "\n")
  # Three exclusions now determine who is eligible. A reader cannot reconstruct the cohort
  # from the Methods unless each is stated.
  for (claim in c("fertility", "hospitalist", "inactive")) {
    expect_true(grepl(claim, txt, ignore.case = TRUE),
                info = sprintf("the Methods does not mention the %s exclusion", claim))
  }
})

test_that("adversarial: the fielded sheet and the pool it came from are the same vintage", {
  # A fielded sheet drawn from a superseded pool would pass every internal check while
  # containing pairs the current pool no longer holds.
  expect_length(setdiff(sheet[["Matched Pair ID"]], pool[["Matched Pair ID"]]), 0L)
  expect_length(setdiff(npi_key(sheet$NPI), npi_key(pool$NPI)), 0L)
})
