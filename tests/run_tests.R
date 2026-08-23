#!/usr/bin/env Rscript
# Repository test runner. Sources the pure helpers and the gates, then runs every test file.
#
# FIXED: this used to source only R/pe_helpers.R, not R/analysis_gates.R. Every test file that
# calls a gate_*() function (test-analysis-gates.R, test-tract-geoid-vintage.R,
# test-power-curve-integrity.R, test-manifest-sources-populated.R, and others) therefore errored
# on "could not find function" regardless of whether the test itself was correct -- a runner
# defect masquerading as a wall of unrelated test failures. run_blocking.R already sourced both
# files; this now matches it.
suppressMessages(library(testthat))
root <- normalizePath(file.path(dirname(sub("^--file=", "",
          grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), ".."))
source(file.path(root, "R", "pe_helpers.R"))
source(file.path(root, "R", "analysis_gates.R"))
res <- test_dir(file.path(root, "tests", "testthat"), reporter = "summary", stop_on_failure = FALSE)
df <- as.data.frame(res)
cat(sprintf("\nTOTALS  pass=%d  fail=%d  warn=%d  skip=%d\n",
            sum(df$passed), sum(df$failed), sum(df$warning), sum(df$skipped)))
quit(status = if (sum(df$failed) > 0 || sum(df$error) > 0) 1 else 0)
