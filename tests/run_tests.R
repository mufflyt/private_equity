#!/usr/bin/env Rscript
# Repository test runner. Sources the pure helpers, then runs every test file.
suppressMessages(library(testthat))
root <- normalizePath(file.path(dirname(sub("^--file=", "",
          grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), ".."))
source(file.path(root, "R", "pe_helpers.R"))
res <- test_dir(file.path(root, "tests", "testthat"), reporter = "summary", stop_on_failure = FALSE)
df <- as.data.frame(res)
cat(sprintf("\nTOTALS  pass=%d  fail=%d  warn=%d  skip=%d\n",
            sum(df$passed), sum(df$failed), sum(df$warning), sum(df$skipped)))
quit(status = if (sum(df$failed) > 0 || sum(df$error) > 0) 1 else 0)
