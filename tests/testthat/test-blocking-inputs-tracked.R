# ADVISORY (deliberately not in tests/BLOCKING).
#
# A blocking test that reads a file git does not track is green only on the machine that built
# the file. The whole suite then certifies nothing about a fresh clone, which is the state a
# reviewer, a collaborator, or CI actually sees.
#
# Found 2026-08-25: `git add -A data/comparator` silently added nothing, because .gitignore
# blankets *.csv and *.json. PR #22 shipped build_comparator_adjudication.py, Supplementary
# Appendix S3, and a blocking test reading comparator_adjudication.csv -- without the file. The
# comparator artifacts are now excepted and tracked.
#
# This test is ADVISORY because 18 further inputs remain in the same state after that
# work, several of them carrying provider rosters whose versioning is the owner's decision, not
# a side effect of a test. It is here so the number is visible and can only shrink. Promote it
# to blocking once the backlog below is empty.
#
# The count is 18. manuscript/PROVENANCE.csv came off the list on 2026-08-29 -- the test that
# audits provenance had been reading a ledger that existed on one machine only -- but the same
# day's rebase brought six further test files from main that reference inputs in the same
# state, so the total did not fall. The remainder are provider rosters, pipeline outputs, and
# inst/frozen/geo_reference_fielded_cohort.csv, which inst/frozen/PROVENANCE.md describes as
# the frozen reference the cohort was matched against and which exists nowhere but one disk.

testthat::local_edition(3)
ROOT <- normalizePath(testthat::test_path("..", ".."))
tracked <- function(p) {
  suppressWarnings(system2("git", c("-C", shQuote(ROOT), "ls-files", "--error-unmatch",
                                    shQuote(p)), stdout = FALSE, stderr = FALSE) == 0L)
}

spec <- readLines(file.path(ROOT, "tests", "BLOCKING"), warn = FALSE)
spec <- spec[!grepl("^\\s*#", spec) & nzchar(trimws(spec))]
files <- trimws(sub("^\\S+\\s+", "", trimws(spec)))

missing <- list()
for (t in files) {
  f <- file.path(ROOT, "tests", "testthat", t)
  if (!file.exists(f)) next
  src <- paste(readLines(f, warn = FALSE), collapse = "\n")
  refs <- unique(regmatches(src, gregexpr('"[A-Za-z0-9_./-]+\\.(csv|json|lock|txt|Rmd|md|duckdb)"', src))[[1]])
  refs <- gsub('"', "", refs)
  for (r in refs) {
    for (cand in c(r, file.path("data", "covariates", r), file.path("data", "comparator", r),
                   file.path("inst", "frozen", r), file.path("manuscript", r))) {
      if (file.exists(file.path(ROOT, cand)) && !tracked(cand))
        missing[[cand]] <- unique(c(missing[[cand]], t))
    }
  }
}

test_that("POSITIVE CONTROL: the scan finds the inputs blocking tests actually read", {
  # Without this, a scan that silently matched nothing would look like a clean result.
  expect_true(length(files) > 20L, info = "the blocking registry should list many files")
})

test_that("ADVISORY: every input a blocking test reads is tracked by git", {
  if (length(missing)) {
    cat("\n  untracked inputs read by blocking tests:\n")
    for (p in sort(names(missing)))
      cat(sprintf("    %-52s <- %s\n", p, paste(missing[[p]], collapse = ", ")))
    cat(sprintf("    total: %d\n\n", length(missing)))
  }
  # The comparator artifacts this session added must never be among them again.
  ours <- grep("^data/comparator/", names(missing), value = TRUE)
  expect_true(length(ours) == 0L,
              info = paste("comparator artifacts untracked again:", paste(ours, collapse = ", ")))
  # The backlog is allowed to exist, and is not allowed to grow.
  expect_true(length(missing) <= 18L,
              info = paste("untracked blocking inputs grew to", length(missing)))
})
