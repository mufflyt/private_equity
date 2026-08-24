# Fielded-frame eligibility.
#
# The regression test for the incident recorded in docs/MATCHING_LINEAGE.md as Finding C: 18
# clinicians from protocol-excluded platforms reached the fielded frame because the frame was
# drawn from a 511-pair matching run that never applied the platform exclusion, rather than
# from the 459-pair post-exclusion universe.
#
# STATUS: THIS FILE IS EXPECTED TO FAIL ON THE CURRENT FRAME. That is its purpose. It states
# the two laws the corrected frame must satisfy, and it currently reports how far the frame is
# from them. It is registered ADVISORY rather than blocking only because promoting it now would
# block the very commits that fix it; tests/BLOCKING records the trigger for promotion.
#
# Both laws carry positive and planted-negative controls, per docs/SCIENTIFIC_CI_LAWS.md.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p    <- function(...) file.path(root, ...)
rd   <- function(f) utils::read.csv(f, colClasses = "character", check.names = FALSE)

sheet <- rd(p("pe_obgyn_final_calling_sheet_200_dedup.csv"))
pool  <- rd(p("pe_obgyn_matched_calling_list.csv"))   # the post-exclusion eligible universe

# --------------------------------------------------------------- law: no ineligible clinician

test_that("LAW: no clinician marked Eligible = FALSE may enter a fielded study frame", {
  bad <- sheet[toupper(trimws(sheet$Eligible)) != "TRUE", , drop = FALSE]
  expect_equal(nrow(bad), 0L,
               info = sprintf("%d of %d fielded clinicians are ineligible (%d excluded-platform, %d non-OB-GYN taxonomy, %d credential)",
                              nrow(bad), nrow(sheet),
                              sum(toupper(trimws(bad$Platform_Excluded)) == "TRUE"),
                              sum(toupper(trimws(bad$Taxonomy_Is_OBGYN)) != "TRUE"),
                              sum(!toupper(trimws(bad$Credentials)) %in% c("MD", "DO"))))
})

test_that("POSITIVE CONTROL: the eligibility flag is populated and discriminating", {
  # Without this, the law above could be satisfied by a column that is TRUE for everyone, or
  # absent entirely, which is the vacuous-pass failure mode.
  expect_true("Eligible" %in% names(sheet))
  v <- toupper(trimws(sheet$Eligible))
  expect_true(all(v %in% c("TRUE", "FALSE")), info = "eligibility must be decided for every row")
  expect_gt(sum(v == "TRUE"), 0L)
  expect_gt(sum(v == "FALSE"), 0L)
  # And it must be derived from its declared inputs rather than asserted.
  for (col in c("Platform_Excluded", "Taxonomy_Is_OBGYN", "Credentials")) {
    expect_true(col %in% names(sheet), info = sprintf("Eligible cannot be checked without %s", col))
  }
})

# --------------------------------------------------------------- law: subset of the eligible universe

test_that("LAW: the fielded frame is a subset of the POST-EXCLUSION eligible matching universe", {
  # The precise law that would have prevented Finding C. Being a subset of *some* matching
  # artifact is not enough -- the frame was a subset of the 511-pair run, which is exactly how
  # the excluded platforms arrived. It must be a subset of the run that applied the exclusion.
  outside <- setdiff(npi_key(sheet$NPI), npi_key(pool$NPI))
  expect_equal(length(outside), 0L,
               info = sprintf("%d of %d fielded clinicians are absent from the %d-pair post-exclusion universe",
                              length(outside), nrow(sheet), length(unique(pool[["Matched Pair ID"]]))))
})

test_that("LAW: every fielded pair exists as a pair in that universe, not merely its members", {
  # Two eligible clinicians can be individually present and never have been matched to each
  # other. Membership is necessary and not sufficient; the pairing is the analytic unit.
  su <- vapply(split(npi_key(sheet$NPI), sheet[["Matched Pair ID"]]),
               function(x) paste(sort(x), collapse = "|"), character(1))
  pu <- vapply(split(npi_key(pool$NPI), pool[["Matched Pair ID"]]),
               function(x) paste(sort(x), collapse = "|"), character(1))
  expect_equal(sum(!su %in% pu), 0L,
               info = sprintf("%d of %d fielded pairs do not exist as a pair in the eligible universe",
                              sum(!su %in% pu), length(su)))
})

test_that("POSITIVE CONTROL: the eligible universe is non-empty, exclusion-clean, and usable", {
  # Without this the subset laws could pass against an empty or unfiltered pool.
  EXCLUDED <- c("CCRM Fertility", "IVI RMA Global", "US Fertility", "Kindbody",
                "OB Hospitalist Group")
  roster <- rd(p("pe_obgyn_providers_active.csv"))
  plat <- stats::setNames(trimws(roster[["Platform/Practice"]]), npi_key(roster$NPI))
  expect_true(length(unique(pool[["Matched Pair ID"]])) > 200L,
              info = "the universe must be larger than the frame it supplies")
  expect_equal(sum(plat[npi_key(pool$NPI)] %in% EXCLUDED, na.rm = TRUE), 0L,
               info = "this pool is not post-exclusion; the subset laws would be meaningless")
  expect_true(all(table(pool[["Matched Pair ID"]]) == 2L),
              info = "every pair in the universe must have exactly two members")
})
