# REDCap pull contract: 3 BVA, 3 semantic, 3 adversarial.
#
# WHAT THIS GOVERNS. build_study_database_from_redcap.R reads
# redcap/redcap_raw_export_800.csv and fails closed because nothing produced it -- no script in
# this repository had ever reached the REDCap API, so the export arrived by hand through the
# web UI: unversioned, unattributed, and impossible to tie an analysis to.
#
# redcap_pull.R closes that. This file asserts the two ends still agree, because they are
# joined by a filename in two separate scripts and nothing else. Rename it in one place and the
# merge script fails with "export not found", which reads like "calling has not finished yet"
# rather than "the pull writes somewhere else now".
#
# THE SAFETY CONTRACT, and it is the one that matters most here. A real export carries
# `initials` -- REDCap's "Name of person completing form". .gitignore un-ignores redcap/ as a
# whole so the fielded calling artifacts can be versioned, which means the pull writes into a
# directory that is otherwise committable. If those outputs were not re-ignored by name,
# the first person to run this script after calling begins would publish which staff member
# made each call: exactly the exposure docs/APPENDIX_DEIDENTIFICATION.md exists to prevent.
#
# This file needs no network and no token. It reads the two scripts and .gitignore.
#
# MUTATION EVIDENCE (Law 1, docs/SCIENTIFIC_CI_LAWS.md):
#   negative control  test 7 asserts git itself ignores a representative pull output, and
#                     test 8 asserts it does NOT ignore the committed calling artifacts. Both
#                     run live against real git, so a rule that stopped matching is caught.
#   positive control  test 8's second half proves the ignore check can return FALSE, so test 7
#                     passing is not "check-ignore always says yes".
#   end-to-end        2026-09-05: this contract was written after the pull script was pointed
#                     at redcap/ and `git check-ignore` reported redcap_raw_export_800.csv as
#                     TRACKABLE -- a real hole, found before any export existed, fixed by the
#                     re-ignore block this file now pins.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)

pull_src  <- readLines(p("redcap_pull.R"), warn = FALSE)
merge_src <- readLines(p("build_study_database_from_redcap.R"), warn = FALSE)

git_ignores <- function(rel) {
  st <- suppressWarnings(system2("git", c("-C", shQuote(root), "check-ignore", "-q", shQuote(rel)),
                                 stdout = FALSE, stderr = FALSE))
  identical(as.integer(st), 0L)
}

# ---------------------------------------------------------------- BVA (3)

test_that("BVA: both ends of the contract exist and parse as R", {
  expect_true(file.exists(p("redcap_pull.R")))
  expect_true(file.exists(p("build_study_database_from_redcap.R")))
  expect_error(parse(p("redcap_pull.R")), NA)
})

test_that("BVA: the pull declares the stable filename as a named constant", {
  # A literal repeated inline is a rename waiting to be done in one of two places.
  hit <- grep('^STABLE_RAW\\s*<-', pull_src, value = TRUE)
  expect_length(hit, 1L)
  expect_match(hit, '"redcap_raw_export_800\\.csv"')
})

test_that("BVA: the pull never accepts a token on the command line", {
  # A token in argv lands in shell history and in the process table, where any local user can
  # read it. ~/.Renviron is the only supported route.
  one <- paste(pull_src, collapse = "\n")
  expect_true(grepl("REDCAP_PE_TOKEN", one, fixed = TRUE))
  expect_false(grepl("commandArgs", one, fixed = TRUE),
               info = "redcap_pull.R reads command-line arguments; a token must not arrive that way")
})

# ---------------------------------------------------------------- semantic (3)

test_that("semantic: the pull writes exactly the filename the merge script reads", {
  read_line <- grep("RAW_EXPORT_PATH\\s*<-", merge_src, value = TRUE)
  expect_length(read_line, 1L)
  expect_match(read_line, "redcap_raw_export_800\\.csv",
               info = "the merge script reads a filename the pull does not write")
  expect_match(read_line, '"redcap"',
               info = "the merge script reads from a directory the pull does not write to")
})

test_that("semantic: the pull checks the payload, not just the HTTP status", {
  one <- paste(pull_src, collapse = "\n")
  # REDCap answers 200 with a JSON error body for a bad token, and 200 with an HTML login page
  # for a moved instance. Both parse as a valid zero-row CSV, so status_code alone reports
  # success having downloaded nothing.
  expect_true(grepl('\\{\\\\\\\\s\\*"error"', one) || grepl('"error"', one, fixed = TRUE),
              info = "no guard against REDCap's JSON error body behind HTTP 200")
  expect_true(grepl('"\\^\\\\\\\\s\\*<"', one) || grepl("HTML, not data", one, fixed = TRUE),
              info = "no guard against an HTML login page behind HTTP 200")
  expect_true(grepl("status_code", one, fixed = TRUE))
})

test_that("semantic: the stable file is copied, not symlinked", {
  one <- paste(pull_src, collapse = "\n")
  expect_true(grepl("file.copy", one, fixed = TRUE))
  expect_false(grepl("file.symlink", one, fixed = TRUE),
               info = "a dangling symlink fails as 'missing export', which reads like 'calling has not finished'")
})

# ---------------------------------------------------------------- adversarial (3)

test_that("adversarial: every pull output is gitignored", {
  # A real export carries `initials`: REDCap's "Name of person completing form".
  for (f in c("redcap/redcap_raw_export_800.csv",
              "redcap/redcap_raw_export_2026-01-01_0000.csv",
              "redcap/redcap_labels_2026-01-01_0000.csv",
              "redcap/redcap_metadata_2026-01-01_0000.csv",
              "redcap/redcap_project_info_2026-01-01_0000.json")) {
    expect_true(git_ignores(f),
                info = sprintf("%s is committable; a real export would publish caller identity", f))
  }
})

test_that("adversarial: re-ignoring the exports did not un-track the calling artifacts", {
  # POSITIVE CONTROL for the test above: if check-ignore said yes to everything, test 7 would
  # pass vacuously. These must come back FALSE.
  for (f in c("redcap/redcap_slot_crosswalk_400.csv",
              "redcap/redcap_call_schedule_800.csv",
              "redcap/PrivateVsPublicDoesEquityOwner_DataDictionary_2026-08-24_blinded.csv")) {
    expect_false(git_ignores(f),
                 info = sprintf("%s became ignored; a versioned calling artifact was lost", f))
  }
})

test_that("adversarial: no pull output has been committed", {
  tracked <- suppressWarnings(system2("git", c("-C", shQuote(root), "ls-files", "redcap/"),
                                      stdout = TRUE, stderr = FALSE))
  skip_if(!length(tracked), "git not available to enumerate tracked files")
  leaked <- grep("redcap_(raw_export|labels_|metadata_|project_info_)", tracked, value = TRUE)
  expect_equal(leaked, character(0),
               info = paste("a pull output is in the repository:", paste(leaked, collapse = ", ")))
})
