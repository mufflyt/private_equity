# CI contract: 3 BVA, 3 semantic, 4 adversarial.
#
# WHAT THIS GOVERNS. Every other frozen contract here is checked by CI -- SAP.lock by
# gate_sap(), analysis_manifest.csv by gate_provenance(), the dependency set by
# test-dependency-lockfile.R. Nothing checked CI itself. A workflow edit that dropped a step,
# widened a trigger, or quietly stopped running the blocking suite would land green, because
# the thing that would have complained is the thing being edited.
#
# config/ci_contract.yml states the guarantees; this file enforces them. Changing what CI
# guarantees now takes two deliberate edits in one commit, and the diff says which guarantee moved.
#
# WHY A CONTRACT FILE AND NOT JUST ASSERTIONS HERE. The assertions would be equally enforceable
# written inline, but then the guarantee and its rationale live in a test file that only a
# developer reads. The point of the split is that someone can read config/ci_contract.yml and
# learn what CI promises without reading R.
#
# MUTATION EVIDENCE (Law 1, docs/SCIENTIFIC_CI_LAWS.md):
#   negative control  the trigger, command and timeout checks are run against a synthetic
#                     workflow that violates each one, and must fail (test 7). Run live.
#   positive control  the same checks against a compliant synthetic workflow must pass, so a
#                     green result cannot come from a matcher that never matches (test 7).
#   end-to-end        2026-09-05, three separate weakenings of gates.yml, each producing
#                     exactly one failure and exactly the right one:
#                       deleted `timeout-minutes: 15`  -> "adversarial: the blocking job cannot
#                                                          hang for hours"
#                       ran tests/run_tests.R instead  -> "semantic: CI runs this repository's
#                                                          blocking suite, not merely some script"
#                       deleted the `pull_request:` trigger -> "semantic: gates.yml triggers on
#                                                          everything the contract requires"
#                     All three reverted clean to 37 passed / 0 failed.
#
# ONE TRAP WORTH KNOWING, found here. yaml::read_yaml() returns a workflow's `on:` block under
# the name "TRUE", because YAML 1.1 reads bare `on` as a boolean. wf[["on"]] is NULL and
# wf[[TRUE]] is a POSITIONAL index that silently returns element 1. Every trigger assertion
# written the obvious way passes vacuously. wf_on() handles it and test 3 exists solely to
# prove the reader still returns something -- without it, mutation 3 above would not have been
# caught.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)

contract <- yaml::read_yaml(p("config", "ci_contract.yml"))

read_workflow <- function(rel) {
  path <- p(rel)
  if (!file.exists(path)) stop("workflow not found: ", rel)
  yaml::read_yaml(path)
}

# YAML 1.1 reads a bare `on:` key as a boolean ("on"/"off"/"yes"/"no" are booleans in that
# spec), so yaml::read_yaml() returns it under the NAME "TRUE" -- not under "on", and not
# reachable as wf[[TRUE]], which is a positional index and silently returns element 1. A naive
# wf$on is NULL for every GitHub workflow ever written, and every trigger assertion built on it
# would pass vacuously. Ask for the key by any spelling it can land under.
wf_on <- function(wf) {
  idx <- which(names(wf) %in% c("on", "TRUE", "True", "true", "yes", "y"))
  if (!length(idx)) NULL else wf[[idx[1]]]
}
wf_triggers <- function(wf) {
  key <- wf_on(wf)
  if (is.null(key)) character(0) else names(key)
}

gates <- read_workflow(contract$workflows$gates$path)

# ---------------------------------------------------------------- BVA (3)

test_that("BVA: the contract parses and declares every section the enforcement reads", {
  for (k in c("version", "workflows", "blocking_suite", "configuration_gates")) {
    expect_true(k %in% names(contract), info = sprintf("contract has no '%s' section", k))
  }
  expect_match(contract$version, "^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
  expect_true(length(contract$blocking_suite$must_remain_blocking) > 0L)
})

test_that("BVA: every workflow the contract names exists on disk", {
  for (nm in names(contract$workflows)) {
    expect_true(file.exists(p(contract$workflows[[nm]]$path)),
                info = sprintf("contract names %s, which does not exist", nm))
  }
})

test_that("BVA: the trigger reader survives YAML's on/True quirk", {
  # If this ever returns character(0) for a real workflow, every trigger assertion below
  # becomes vacuous while still reporting green.
  expect_true(length(wf_triggers(gates)) > 0L,
              info = "trigger reader returned nothing for gates.yml; the checks below are vacuous")
})

# ---------------------------------------------------------------- semantic (3)

test_that("semantic: gates.yml triggers on everything the contract requires", {
  got <- wf_triggers(gates)
  for (t in contract$workflows$gates$must_trigger_on) {
    expect_true(t %in% got,
                info = sprintf("gates.yml no longer triggers on '%s'; work can merge unchecked", t))
  }
  on_key <- wf_on(gates)
  for (b in contract$workflows$gates$must_push_branches) {
    expect_true(b %in% on_key$push$branches,
                info = sprintf("a direct push to '%s' would not run the gates", b))
  }
})

test_that("semantic: CI runs this repository's blocking suite, not merely some script", {
  want <- contract$workflows$gates$jobs$blocking$must_run
  steps <- gates$jobs$blocking$steps
  runs <- unlist(lapply(steps, function(s) s$run))
  expect_true(any(grepl(want, runs, fixed = TRUE)),
              info = sprintf("no step runs '%s'. Steps run: %s", want,
                             paste(runs, collapse = " | ")))
})

test_that("semantic: the R version in CI equals the one recorded in the lockfile", {
  skip_if_not(isTRUE(contract$workflows$gates$jobs$blocking$r_version_matches_lockfile))
  source(p("R", "dependency_lock.R"))
  locked <- read_lockfile(p("config", "dependencies.lock"))$meta$r_version
  steps <- gates$jobs$blocking$steps
  rv <- unlist(lapply(steps, function(s) if (!is.null(s$with)) s$with[["r-version"]]))
  expect_true(length(rv) > 0L, info = "gates.yml pins no r-version")
  expect_equal(as.character(rv[1]), as.character(locked),
               info = "two files name the R version independently; they have drifted")
})

# ---------------------------------------------------------------- adversarial (4)

test_that("adversarial: the blocking job cannot hang for hours", {
  cap <- contract$workflows$gates$jobs$blocking$max_step_timeout_minutes
  steps <- gates$jobs$blocking$steps
  runner <- Filter(function(s) !is.null(s$run), steps)
  expect_true(length(runner) > 0L)
  tos <- unlist(lapply(runner, function(s) s[["timeout-minutes"]]))
  expect_true(length(tos) > 0L,
              info = "no step timeout: an unset one inherits GitHub's 360-minute default")
  expect_true(all(tos <= cap),
              info = sprintf("a step timeout exceeds the contracted %d minutes", cap))
})

test_that("adversarial: NEGATIVE and POSITIVE control on the workflow checks", {
  mk <- function(txt) { f <- tempfile(fileext = ".yml"); writeLines(txt, f); yaml::read_yaml(f) }

  bad <- mk(c("name: x", "on:", "  push:", "    branches: [ other ]",
              "jobs:", "  blocking:", "    steps:",
              "      - run: Rscript something/else.R"))
  # negative controls: each check must actually fail on a workflow that violates it
  expect_false("pull_request" %in% wf_triggers(bad))
  expect_false("main" %in% wf_on(bad)$push$branches)
  expect_false(any(grepl("Rscript tests/run_blocking.R --no-data",
                         unlist(lapply(bad$jobs$blocking$steps, function(s) s$run)), fixed = TRUE)))
  expect_length(unlist(lapply(bad$jobs$blocking$steps, function(s) s[["timeout-minutes"]])), 0L)

  good <- mk(c("name: x", "on:", "  push:", "    branches: [ main ]", "  pull_request:",
               "jobs:", "  blocking:", "    steps:",
               "      - run: Rscript tests/run_blocking.R --no-data",
               "        timeout-minutes: 15"))
  # positive controls: the same checks must pass on a compliant one
  expect_true(all(c("push", "pull_request") %in% wf_triggers(good)))
  expect_true(any(grepl("Rscript tests/run_blocking.R --no-data",
                        unlist(lapply(good$jobs$blocking$steps, function(s) s$run)), fixed = TRUE)))
  expect_equal(unlist(lapply(good$jobs$blocking$steps, function(s) s[["timeout-minutes"]])), 15L)
})

test_that("adversarial: no contracted test file has quietly left tests/BLOCKING", {
  spec <- readLines(p("tests", "BLOCKING"), warn = FALSE)
  spec <- spec[!grepl("^\\s*#", spec) & nzchar(trimws(spec))]
  listed <- trimws(sub("^\\S+\\s+", "", trimws(spec)))
  for (e in contract$blocking_suite$must_remain_blocking) {
    expect_true(e$file %in% listed,
                info = sprintf("%s left tests/BLOCKING. It guards: %s", e$file, e$guards))
  }
})

test_that("adversarial: the nodata suite has not been quietly shrunk", {
  spec <- readLines(p("tests", "BLOCKING"), warn = FALSE)
  spec <- spec[!grepl("^\\s*#", spec) & nzchar(trimws(spec))]
  n <- sum(sub("\\s.*$", "", trimws(spec)) == "nodata")
  expect_gte(n, contract$blocking_suite$min_nodata_files)
  # And every configuration gate the contract names must still be invoked by the runner.
  runner <- readLines(p("tests", "run_blocking.R"), warn = FALSE)
  for (g in contract$configuration_gates$must_run) {
    expect_true(any(grepl(g, runner, fixed = TRUE)),
                info = sprintf("run_blocking.R no longer runs the '%s' gate", g))
  }
})
