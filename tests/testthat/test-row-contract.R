# Row-level data contract: 3 BVA, 3 semantic, 4 adversarial.
#
# WHAT THIS GOVERNS. analysis_manifest.csv is a COLUMN contract: what each column means, where
# it came from, what distribution it should have. It cannot express anything about ROWS -- how
# many there should be, which must be unique, that every matched pair holds exactly one PE and
# one non-PE clinician, that the 800 call slots cover 1..800 once each, or that three artifacts
# describe the same 400 people.
#
# Those are the invariants that carry the design. A calling sheet that silently gained a row, a
# pair that lost its control, a record id issued twice: none is a column-level defect, none
# would fail gate_provenance(), and each quietly changes what the study is.
#
# WHY THIS RUNS IN CI WHEN MOST DATA CHECKS CANNOT. The calling artifacts are committed, not
# gitignored, so these run against the real files on a runner rather than only on a machine
# that happens to hold the cohort.
#
# WHAT IT FOUND ON ITS FIRST RUN. redcap/redcap_import_ready_200.csv carried a completion
# column named acost_three_dx_urogyn_2_complete -- the form of a DIFFERENT study, the IC vs POP
# vs SUI urogynecology project this repository was seeded from. The project's own dictionary
# has one form, taylor_private_equity. REDCap silently ignores a completion column for a form
# it does not have: all 800 records would have imported with none marked complete, and nothing
# would have reported it. Fixed in build_200_redcap_import.R (the FORM constant, its only use)
# and in the artifact header. Project 40415 held zero records at the time, so nothing had been
# loaded under the wrong name.
#
# MUTATION EVIDENCE (Law 1, docs/SCIENTIFIC_CI_LAWS.md):
#   negative control  every rule type is provoked against synthetic data and must report
#                     (tests 4-6). Runs live -- these are the rules, not a sample of them.
#   positive control  each rule returns nothing on data that satisfies it, so a clean run is
#                     not an engine that never fires.
#   end-to-end        2026-09-05: the complete_form rule found the real defect above on its
#                     first execution, before any mutation was needed.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
source(file.path(root, "R", "row_contract.R"))

contract <- read_row_contract(file.path(root, ROW_CONTRACT))
violations <- validate_row_contract(contract, root = root)

# ---------------------------------------------------------------- BVA (3)

test_that("BVA: the contract parses and declares datasets and cross-dataset rules", {
  expect_true(!is.null(contract$datasets))
  expect_true(length(contract$datasets) >= 4L,
              info = "fewer datasets under contract than expected; coverage has shrunk")
  expect_true(length(contract$cross_dataset) >= 1L)
  expect_match(contract$version, "^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
})

test_that("BVA: every dataset the contract names exists and is readable", {
  for (nm in names(contract$datasets)) {
    p <- file.path(root, contract$datasets[[nm]]$path)
    expect_true(file.exists(p), info = sprintf("%s: %s missing", nm, contract$datasets[[nm]]$path))
    expect_true(nrow(read_dataset(p)) > 0L, info = sprintf("%s parsed to zero rows", nm))
  }
})

test_that("BVA: every declared rule type is one the engine implements", {
  known <- c("path", "rows", "unique", "non_empty", "domains", "group_size",
             "balanced_groups", "id_coverage", "columns_differ", "complete_form")
  for (nm in names(contract$datasets)) {
    unknown <- setdiff(names(contract$datasets[[nm]]), known)
    expect_equal(unknown, character(0),
                 info = sprintf("%s declares rule(s) the engine ignores silently: %s",
                                nm, paste(unknown, collapse = ", ")))
  }
})

# ---------------------------------------------------------------- semantic (3)

test_that("semantic: NEGATIVE and POSITIVE control on the counting and uniqueness rules", {
  d <- data.frame(id = c("1", "2", "2"), v = c("a", "", "c"), stringsAsFactors = FALSE)
  expect_length(rule_rows(d, 3L), 0L)
  expect_match(rule_rows(d, 4L), "row count is 3")
  expect_length(rule_unique(d, "v"), 0L)
  expect_match(rule_unique(d, "id"), "1 duplicate")
  expect_length(rule_non_empty(d, "id"), 0L)
  expect_match(rule_non_empty(d, "v"), "blank in 1 row")
  # A rule naming a column that does not exist must report, never silently pass.
  expect_match(rule_unique(d, "nope"), "no column")
  expect_match(rule_non_empty(d, "nope"), "no column")
})

test_that("semantic: NEGATIVE and POSITIVE control on the design-structure rules", {
  ok <- data.frame(pair = c("p1", "p1", "p2", "p2"), arm = c("PE", "Non-PE", "PE", "Non-PE"),
                   stringsAsFactors = FALSE)
  expect_length(rule_group_size(ok, list(column = "pair", size = 2L)), 0L)
  expect_length(rule_balanced_groups(ok, list(group = "pair", arm = "arm")), 0L)

  # A pair with two PE members is not a comparison. Group SIZE is still 2, so only the
  # balance rule can see it -- which is why both rules exist.
  unbal <- ok; unbal$arm <- c("PE", "PE", "PE", "Non-PE")
  expect_length(rule_group_size(unbal, list(column = "pair", size = 2L)), 0L)
  expect_match(rule_balanced_groups(unbal, list(group = "pair", arm = "arm")),
               "do not hold exactly one row per")

  expect_match(rule_group_size(ok[1:3, ], list(column = "pair", size = 2L)), "not size 2")
  expect_match(rule_domains(ok, list(arm = c("PE"))), "outside its domain")
  expect_length(rule_domains(ok, list(arm = c("PE", "Non-PE"))), 0L)
})

test_that("semantic: NEGATIVE and POSITIVE control on id coverage and column difference", {
  good <- data.frame(a = c("1", "2"), b = c("3", "4"), stringsAsFactors = FALSE)
  expect_length(rule_id_coverage(good, list(columns = c("a", "b"), max = 4L)), 0L)
  expect_length(rule_columns_differ(good, c("a", "b")), 0L)

  dup <- data.frame(a = c("1", "2"), b = c("2", "4"), stringsAsFactors = FALSE)
  expect_true(any(grepl("duplicate id", rule_id_coverage(dup, list(columns = c("a", "b"), max = 4L)))))
  gap <- data.frame(a = c("1", "2"), b = c("3", "5"), stringsAsFactors = FALSE)
  expect_true(any(grepl("never issued", rule_id_coverage(gap, list(columns = c("a", "b"), max = 5L)))))
  same <- data.frame(a = c("1", "2"), b = c("1", "4"), stringsAsFactors = FALSE)
  expect_match(rule_columns_differ(same, c("a", "b")), "equals")
})

# ---------------------------------------------------------------- adversarial (4)

test_that("adversarial: the committed artifacts satisfy every row-level invariant", {
  expect_true(nrow(violations) == 0L,
              info = paste("violation(s) ->",
                           paste(sprintf("[%s] %s", violations$dataset, violations$violation),
                                 collapse = " | ")))
})

test_that("adversarial: the completion column names a form the project actually has", {
  # The defect this file was written against. REDCap accepts the import and marks nothing
  # complete, so the failure is silent on both sides.
  spec <- contract$datasets$redcap_import_200
  df <- read_dataset(file.path(root, spec$path))
  expect_length(rule_complete_form(df, spec$complete_form, root), 0L)
  cc <- grep("_complete$", names(df), value = TRUE)
  expect_equal(cc, "taylor_private_equity_complete")
  # And the generator must not reintroduce it: the artifact and the script that writes it are
  # two places the form name lives.
  gen <- readLines(file.path(root, "build_200_redcap_import.R"), warn = FALSE)
  form_line <- grep('^FORM\\s*<-', gen, value = TRUE)
  expect_length(form_line, 1L)
  expect_match(form_line, "taylor_private_equity")
})

test_that("adversarial: NEGATIVE control on complete_form", {
  spec <- contract$datasets$redcap_import_200
  df <- read_dataset(file.path(root, spec$path))
  wrong <- df
  names(wrong)[names(wrong) == "taylor_private_equity_complete"] <- "some_other_form_complete"
  expect_match(rule_complete_form(wrong, spec$complete_form, root), "not in")
})

test_that("adversarial: the artifacts describing the same clinicians agree on who they are", {
  for (nm in names(contract$cross_dataset)) {
    expect_length(rule_key_agreement(contract$cross_dataset[[nm]], root), 0L)
  }
  # NEGATIVE control: a key set that genuinely differs must be reported.
  tmp <- file.path(tempdir(), "xw"); dir.create(tmp, showWarnings = FALSE)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  utils::write.csv(data.frame(NPI = c("1", "2")), file.path(tmp, "a.csv"), row.names = FALSE)
  utils::write.csv(data.frame(NPI = c("2", "3")), file.path(tmp, "b.csv"), row.names = FALSE)
  expect_match(rule_key_agreement(list(left = list(path = "a.csv", column = "NPI"),
                                       right = list(path = "b.csv", column = "NPI")), tmp),
               "disagree")
})
