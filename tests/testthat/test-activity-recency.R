# Activity recency exclusion.
#
# Clinicians not observed practising within MAX_INACTIVE_YEARS are dropped before clustering
# and matching, because a clinician who has left is recorded as a failure to contact and
# enters the primary obtainment outcome as if it were a refusal.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)
rd <- function(f) utils::read.csv(f, colClasses = "character", check.names = FALSE)

sheet <- rd(p("pe_obgyn_final_calling_sheet_200_dedup.csv"))
db    <- rd(p("pe_obgyn_study_database.csv"))
psm   <- readLines(p("build_matched_control_group_psm.R"))

db$k <- npi_key(db$NPI)
i <- match(npi_key(sheet$NPI), db$k)
last_f <- suppressWarnings(as.numeric(trimws(ifelse(is.na(db[["Last Active Year"]][i]), "",
                                                    db[["Last Active Year"]][i]))))
last_pe <- suppressWarnings(as.numeric(trimws(ifelse(
  is.na(db[["Last Active Year"]]), "", db[["Last Active Year"]]))))[db$PE_or_Not == "PE"]

test_that("no fielded clinician is outside the activity window", {
  ref <- suppressWarnings(max(last_pe, na.rm = TRUE))
  expect_true(is.finite(ref))
  cutoff <- ref - 1L
  stale <- sum(last_f < cutoff, na.rm = TRUE)
  expect_equal(stale, 0L,
               info = sprintf("%d fielded clinicians were last active before %d", stale, cutoff))
})

test_that("the threshold is anchored to the data, not to the calling year", {
  # Anchoring to the calling year would demand activity in 2024 or later against a source
  # that stops at 2021, removing every clinician in the cohort.
  expect_true(any(grepl("ACTIVITY_REFERENCE_YEAR <- suppressWarnings(max(", psm, fixed = TRUE)),
              info = "the reference year must be read from the data")
  expect_false(any(grepl("MAX_INACTIVE_YEARS <- 2\\s*$", psm) &
                   grepl("CALL_YEAR", psm, fixed = TRUE)),
               info = "the cutoff must not be computed from the calling year")
})

test_that("a missing activity year is not treated as inactivity", {
  # Excluding unknowns would drop hundreds of clinicians on a missing value rather than an
  # observation. They are retained deliberately.
  expect_true(any(grepl("retained with no activity year recorded", psm, fixed = TRUE)))
  expect_true(sum(is.na(last_f)) > 0L,
              info = "clinicians with no recorded activity year remain in the fielded cohort")
})

test_that("the exclusion refuses to run away with the cohort", {
  expect_true(any(grepl("would remove more than half the cohort", psm, fixed = TRUE)),
              info = "a guard must stop the filter if the activity column is empty or stale")
})

test_that("the exclusion is applied before clustering and matching", {
  i_rec <- grep("Activity recency exclusion", psm)[1]
  i_clu <- grep("Clustering Physical Practice Locations", psm)[1]
  expect_true(!is.na(i_rec) && !is.na(i_clu) && i_rec < i_clu)
})

test_that("the recency rule is applied symmetrically to both arms", {
  # Filtering only the treated arm gives the arms different eligibility criteria, so any
  # difference in reachability would partly reflect the filter rather than ownership.
  expect_true(any(grepl("candidates_df <- candidates_df[!.cand_stale, ]", psm, fixed = TRUE)),
              info = "the control pool must be filtered by the same rule")
  ref <- suppressWarnings(max(last_pe, na.rm = TRUE)); cutoff <- ref - 1L
  for (arm in c("PE", "Non-PE")) {
    v <- last_f[sheet$PE_or_Not == arm]
    expect_equal(sum(v < cutoff, na.rm = TRUE), 0L,
                 info = sprintf("%s arm retains clinicians last active before %d", arm, cutoff))
  }
})
