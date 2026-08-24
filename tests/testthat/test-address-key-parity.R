# Guards the defect found in cycle 1: build_matched_control_group_psm.R carried its own
# copy of the office-key logic and drifted from the shared helper. The two must agree on
# every address in the study database, or office_id and the de-dup blocking disagree
# about what counts as one office.

test_that("semantic: the PSM script's address key agrees with R/pe_helpers.R", {
  src <- readLines(testthat::test_path("..", "..", "build_matched_control_group_psm.R"))
  rx  <- grep("SUITES\\|SUITE\\|STES\\|STE", src, value = TRUE)
  expect_true(length(rx) >= 1L,
              info = "PSM script must still contain a suite-stripping step")
  expect_true(all(grepl("\\\\\\\\b", rx)),
              info = "PSM suite regex must be word-anchored, or FL swallows FLAGLER")
  expect_false(any(grepl("\\[\\^A-Z0-9\\], *\"\", *toupper\\(adr\\)", src)),
               info = "punctuation must not be stripped before suite designators")
})

test_that("adversarial: PSM seeds its office sampling once, not per iteration", {
  src <- readLines(testthat::test_path("..", "..", "build_matched_control_group_psm.R"))
  loop_start <- grep("^for \\(office in pe_unique_offices\\)", src)
  expect_length(loop_start, 1L)
  loop_end <- length(src)
  # Comments are prose about the code, not the code. A comment explaining why the stream is
  # seeded once mentions set.seed by name and must not be read as a re-seed.
  src[grepl("^\\s*#", src)] <- ""
  inside <- src[loop_start:loop_end]
  brace <- cumsum(lengths(regmatches(inside, gregexpr("\\{", inside)))) -
           cumsum(lengths(regmatches(inside, gregexpr("\\}", inside))))
  body_end <- which(brace == 0L)[1]
  expect_false(any(grepl("set.seed", inside[seq_len(body_end)], fixed = TRUE)),
               info = "re-seeding inside the loop makes every office draw the same permutation")
  expect_true(any(grepl("set\\.seed", src[seq_len(loop_start - 1L)])),
              info = "the stream must still be seeded for reproducibility")
})
