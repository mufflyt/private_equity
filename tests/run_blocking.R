#!/usr/bin/env Rscript
# Runs the blocking subset of the suite and exits non-zero on any failure.
#
# This is the gate. tests/run_tests.R runs everything and is advisory; this runs the files
# listed in tests/BLOCKING and is not. The two are deliberately different: the full suite has
# a documented backlog of failures, and a gate that is always red teaches people to bypass it.
#
# Usage:
#   Rscript tests/run_blocking.R              # everything in tests/BLOCKING
#   Rscript tests/run_blocking.R --no-data    # only files that need no cohort CSV (for CI)
#
# The cohort CSVs are gitignored, so continuous integration can run only the --no-data subset
# plus the configuration checks below. The pre-commit hook runs the full blocking set locally,
# where the data exists, and is the stronger of the two.

suppressMessages(library(testthat))

root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE),
                                                                value = TRUE)[1])), ".."),
                      mustWork = FALSE)
if (is.na(root) || !dir.exists(root)) root <- normalizePath(".")
setwd(root)

args    <- commandArgs(trailingOnly = TRUE)
no_data <- "--no-data" %in% args

source("R/pe_helpers.R")
source("R/analysis_gates.R")

spec <- readLines("tests/BLOCKING", warn = FALSE)
spec <- spec[!grepl("^\\s*#", spec) & nzchar(trimws(spec))]
kind <- sub("\\s.*$", "", trimws(spec))
file <- trimws(sub("^\\S+\\s+", "", trimws(spec)))
if (no_data) { file <- file[kind == "nodata"]; kind <- kind[kind == "nodata"] }

cat(sprintf("\n=== blocking suite%s: %d file(s) ===\n\n",
            if (no_data) " (--no-data)" else "", length(file)))

# ---------------------------------------------------------------- configuration gates
# These run before any test file, because a broken manifest or an unhashed plan invalidates
# everything downstream and should be reported as itself rather than as a cascade.

cfg_fail <- character(0)
cfg <- function(label, expr) {
  ok <- tryCatch({ force(expr); TRUE }, error = function(e) {
    cfg_fail <<- c(cfg_fail, sprintf("%s: %s", label, conditionMessage(e))); FALSE })
  cat(sprintf("  [%s] %s\n", if (ok) "ok  " else "FAIL", label))
}

cfg("provenance manifest parses", read_manifest())
cfg("frozen plan parses",         read_sap())
cfg("assumed constants sourced",  gate_sourced_constants())
cfg("SAP.lock hash current", {
  rec <- sub(".*= *", "", grep("^# *sha256", readLines("SAP.lock", warn = FALSE), value = TRUE)[1])
  if (!nzchar(rec)) stop("SAP.lock carries no hash; run sap_write_hash()")
  if (!identical(sap_hash("SAP.lock"), rec))
    stop("SAP.lock was edited without regenerating its hash")
})
cfg("analysis runs preflight before fitting", {
  src <- readLines("dry_run_analysis.R", warn = FALSE)
  pre <- grep("analysis_preflight\\(", src); fit <- grep("glmmTMB\\(", src)
  if (!length(pre)) stop("dry_run_analysis.R does not call analysis_preflight()")
  if (min(pre) > min(fit)) stop("a model is fitted before the preflight runs")
})

cat("\n")

# ---------------------------------------------------------------- test files

rows <- list()
for (f in file) {
  path <- file.path("tests", "testthat", f)
  if (!file.exists(path)) {
    rows[[f]] <- data.frame(file = f, pass = 0L, fail = 0L, err = 1L)
    cat(sprintf("  [FAIL] %-34s file not found\n", f))
    next
  }
  r <- tryCatch(as.data.frame(test_file(path, reporter = "silent")),
                error = function(e) NULL)
  if (is.null(r)) {
    rows[[f]] <- data.frame(file = f, pass = 0L, fail = 0L, err = 1L)
    cat(sprintf("  [FAIL] %-34s could not be sourced\n", f))
    next
  }
  d <- data.frame(file = f, pass = sum(r$passed), fail = sum(r$failed), err = sum(r$error))
  rows[[f]] <- d
  cat(sprintf("  [%s] %-34s %3d passed, %d failed, %d error\n",
              if (d$fail + d$err == 0L) "ok  " else "FAIL", f, d$pass, d$fail, d$err))
  if (d$fail + d$err > 0L) {
    bad <- r[r$failed > 0 | r$error > 0, ]
    for (i in seq_len(nrow(bad))) cat(sprintf("           - %s\n", bad$test[i]))
  }
}

res <- do.call(rbind, rows)
n_fail <- if (is.null(res)) 0L else sum(res$fail) + sum(res$err)

cat(sprintf("\n=== %d passed, %d failed across %d file(s); %d configuration gate(s) failed ===\n",
            if (is.null(res)) 0L else sum(res$pass), n_fail,
            if (is.null(res)) 0L else nrow(res), length(cfg_fail)))
for (m in cfg_fail) cat("  ", m, "\n")

if (n_fail > 0L || length(cfg_fail) > 0L) {
  cat("\nBLOCKED. Fix the failure, or if the contract genuinely changed, change the contract\n",
      "deliberately and say so in the commit message. Do not remove the test.\n", sep = "")
  quit(status = 1L)
}
cat("\nAll blocking gates passed.\n")
quit(status = 0L)
