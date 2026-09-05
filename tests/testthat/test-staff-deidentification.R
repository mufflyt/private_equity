# Study-staff deidentification: 2 BVA, 3 semantic, 3 adversarial.
#
# WHAT THIS GOVERNS. Caller identity is data about a person that the study collected. On
# 2026-09-05 three real study-staff given names sat in tests/testthat/test-pipeline-output-
# regression.R as the `initials` fixture and again in its expected `caller` output. They were
# not flagged by anything: every existing test asked whether the pipeline computed the right
# answer, none asked whose name was in the input. This file is that question.
#
# SCOPE, stated rather than implied. The contract is "no real staff name appears as DATA".
#   IN scope   tests/** -- test fixtures are exactly where the leak happened, and a fixture
#              never needs a real person's name to prove a normalisation works.
#              Tracked .csv/.xlsx -- checked at the COLUMN level (guard 2): a committed
#              artifact must not carry a caller-identity column at all.
#   OUT of scope, deliberately, each for a stated reason:
#     - manuscript/ author bylines. That is attribution, governed by authorship, not
#       deidentification. Removing a co-author's name from a byline is not a privacy fix.
#     - Sibling-repository provenance references (e.g. a comment naming the repo a helper was
#       ported from). Same character as a byline: it credits a source, it is not study data.
#     - Free-text cells inside a committed .csv. Guard 2 covers the column-level vector; a
#       staff name buried in a `notes` cell would not be caught. The mitigation is upstream --
#       no REDCap free-text export is ever committed (.gitignore blanket-ignores *.csv, and the
#       tracked ones are generated calling artifacts with fixed schemas). Recorded here so the
#       gap is known rather than assumed closed.
#
# The hashes live in config/staff_name_hashes.txt so this repository can DETECT a real name
# without CONTAINING one. That file documents the limits of that trick, including that it does
# not touch the names already in git history.
#
# MUTATION EVIDENCE (Law 1, docs/SCIENTIFIC_CI_LAWS.md). Both controls are executed live in
# this file rather than recorded as a past observation, because a scanner that silently stops
# matching is precisely the failure this guards against and a comment cannot detect it:
#   negative control  scan_for_staff_names() over a string containing a known-hashed token
#                     must return that token (test 3), so the scanner is known to be able to
#                     match at all.
#   positive control  the same scanner over staff-free text must return nothing (test 4), so
#                     a pass cannot come from a matcher that never matches.
#   end-to-end        2026-09-05: a real staff given name was planted in a scratch file under
#                     tests/ (tests/testthat/zz_mutation_probe.R, `initials <- c("<name>", "x")`).
#                     The suite went red with exactly one failure, and it was the intended one --
#                     "adversarial: no real staff name appears anywhere under tests/" -- not a
#                     collateral failure elsewhere. Removing the probe returned the file to
#                     17 passed / 0 failed. Re-run that way after any change to the tokenizer
#                     or the scan set; the probe is deliberately not committed.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)

SALT <- "pe-obgyn-staff-deid-v1"

staff_hash <- function(name) {
  vapply(tolower(name),
         function(n) digest::digest(paste0(SALT, n), algo = "sha256", serialize = FALSE),
         character(1), USE.NAMES = FALSE)
}

read_hashes <- function(path = p("config", "staff_name_hashes.txt")) {
  ln <- readLines(path, warn = FALSE)
  ln <- trimws(ln[!grepl("^\\s*#", ln) & nzchar(trimws(ln))])
  ln
}

# Split text into candidate given-name tokens. Letters only: a name never contains a digit,
# and splitting on non-letters means "Dr. Avery Smith", "avery,", and c("avery") all yield the
# same token. Two characters or fewer cannot be a given name and would only add noise.
tokenize <- function(txt) {
  tok <- unlist(strsplit(paste(txt, collapse = "\n"), "[^A-Za-z]+"))
  unique(tolower(tok[nchar(tok) > 2L]))
}

scan_for_staff_names <- function(txt, hashes = read_hashes()) {
  tok <- tokenize(txt)
  if (!length(tok)) return(character(0))
  tok[staff_hash(tok) %in% hashes]
}

test_files <- list.files(p("tests"), recursive = TRUE, full.names = TRUE,
                         pattern = "\\.(R|r|txt|csv|md)$")
# This file necessarily discusses the guard; it holds no name, but exclude it so the contract
# is about the suite rather than about itself.
test_files <- test_files[basename(test_files) != "test-staff-deidentification.R"]

# ---------------------------------------------------------------- BVA (2)

test_that("BVA: the hash list is present, non-empty and well-formed", {
  h <- read_hashes()
  expect_true(length(h) > 0L, info = "config/staff_name_hashes.txt lists no hashes")
  expect_true(all(grepl("^[0-9a-f]{64}$", h)),
              info = "every entry must be a bare lowercase sha256 hex digest")
  expect_false(any(duplicated(h)))
})

test_that("BVA: the tokenizer keeps real name-shaped tokens and drops what cannot be a name", {
  expect_true("avery" %in% tokenize('initials = c("avery", "BRIAR")'))
  expect_true("briar" %in% tokenize('initials = c("avery", "BRIAR")'),
              info = "matching must be case-insensitive; MERILYN and merilyn are one name")
  expect_false(any(c("a", "of") %in% tokenize("a of xy")),
               info = "tokens of 2 characters or fewer cannot be a given name")
  expect_true("avery" %in% tokenize("Dr. Avery, 1234"),
              info = "punctuation and digits must not hide a name from the scanner")
})

# ---------------------------------------------------------------- semantic (3)

test_that("semantic: NEGATIVE CONTROL - the scanner detects a name it should detect", {
  # Hash a synthetic name, hand the scanner that hash set, and confirm it finds the token.
  # This proves the mechanism end to end without putting a real name in this file.
  planted <- staff_hash("zzsynthetic")
  found <- scan_for_staff_names('initials <- c("zzSynthetic", "other")', hashes = planted)
  expect_equal(found, "zzsynthetic",
               info = "the scanner failed to find a name that IS in the hash set")
})

test_that("semantic: POSITIVE CONTROL - the scanner is not matching vacuously", {
  planted <- staff_hash("zzsynthetic")
  expect_length(scan_for_staff_names("initials <- c('avery', 'briar')", hashes = planted), 0L)
  expect_length(scan_for_staff_names("", hashes = planted), 0L)
  expect_length(scan_for_staff_names("no names here at all", hashes = read_hashes()), 0L)
})

test_that("semantic: the regression fixture that leaked is clean and still exercises casing", {
  src <- readLines(p("tests", "testthat", "test-pipeline-output-regression.R"), warn = FALSE)
  expect_length(scan_for_staff_names(src), 0L)
  fixture <- grep("initials\\s*=\\s*c\\(", src, value = TRUE)
  expect_true(length(fixture) > 0L, info = "the initials fixture has gone; this test is stale")
  # The mixed case is the point of the fixture. A replacement that quietly normalised the
  # casing would leave the assertion below it passing while testing nothing.
  expect_true(any(grepl('"[a-z]+", "[A-Z]+"', fixture)),
              info = "the fixture must keep a lowercase and an UPPERCASE spelling")
})

# ---------------------------------------------------------------- adversarial (3)

test_that("adversarial: no real staff name appears anywhere under tests/", {
  hits <- lapply(test_files, function(f) {
    found <- scan_for_staff_names(readLines(f, warn = FALSE))
    if (length(found)) sprintf("%s (%d token(s))", basename(f), length(found)) else NULL
  })
  hits <- unlist(hits)
  expect_null(hits, info = paste("staff name(s) present in:", paste(hits, collapse = ", ")))
})

test_that("adversarial: no committed artifact carries a caller-identity column", {
  # `initials` is REDCap's "Name of person completing form"; mysterycall derives `caller` from
  # it. Either column in a committed file publishes who made each call.
  banned <- "^(initials|caller|caller_name|rater|interviewer|staff)$"
  csvs <- list.files(root, pattern = "\\.csv$", recursive = TRUE, full.names = TRUE)
  csvs <- csvs[!grepl("/(\\.git|\\.venv|__pycache__)/", csvs)]
  offenders <- character(0)
  for (f in csvs) {
    hdr <- tryCatch(names(utils::read.csv(f, nrows = 1L, check.names = FALSE)),
                    error = function(e) character(0))
    if (any(grepl(banned, trimws(tolower(hdr))))) {
      offenders <- c(offenders, sub(paste0(root, "/"), "", f, fixed = TRUE))
    }
  }
  expect_length(offenders, 0L)
})

test_that("adversarial: the hash file itself carries no plaintext name", {
  # A well-meaning edit that documents "hash of <name>" alongside the digest would undo the
  # whole point of storing hashes.
  expect_length(scan_for_staff_names(readLines(p("config", "staff_name_hashes.txt"),
                                               warn = FALSE)), 0L)
})
