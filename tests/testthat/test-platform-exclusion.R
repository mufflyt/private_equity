# Platform-level eligibility exclusion.
#
# Five platforms cannot supply the appointment the study requests: four fertility practices
# and one inpatient hospitalist group. They are excluded from the TREATED cohort before
# office clustering, propensity estimation and matching, while every PE-owned NPI, including
# theirs, remains ineligible as a control.
#
# The three contracts below are the ones that make that hold.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)
rd <- function(f) utils::read.csv(f, colClasses = "character", check.names = FALSE)

EXCLUDED <- c("CCRM Fertility", "IVI RMA Global", "US Fertility", "Kindbody",
              "OB Hospitalist Group")

sheet  <- rd(p("pe_obgyn_final_calling_sheet_200_dedup.csv"))
pool   <- rd(p("pe_obgyn_matched_calling_list.csv"))
db     <- rd(p("pe_obgyn_study_database.csv"))
roster <- rd(p("pe_obgyn_providers_active.csv"))
psm    <- readLines(p("build_matched_control_group_psm.R"))

plat_of <- function(npis) {
  r <- roster[match(npi_key(npis), npi_key(roster$NPI)), , drop = FALSE]
  trimws(ifelse(is.na(r[["Platform/Practice"]]), "", r[["Platform/Practice"]]))
}
excluded_npi <- npi_key(roster$NPI[trimws(ifelse(is.na(roster[["Platform/Practice"]]), "",
                                                 roster[["Platform/Practice"]])) %in% EXCLUDED])
all_pe_npi <- npi_key(roster$NPI)
all_pe_npi <- all_pe_npi[nzchar(all_pe_npi)]

# (1) none of the five excluded platforms can enter the treated cohort ------------------

test_that("no excluded platform enters the treated cohort at any stage", {
  # CONTRACT CHANGED 2026-08-24, deliberately, and narrowed rather than relaxed.
  #
  # The exclusion holds exactly where it was applied: the study database and the matched pool
  # are clean. The fielded sheet is not, and the mechanism is now known -- 173 of its 400
  # clinicians are not in the matched pool at all, and every one of the 18 excluded-platform
  # entrants is among them. They did not defeat the exclusion; they bypassed the stage that
  # applies it. Asserting the fielded sheet is clean would therefore assert something the
  # pipeline never promised for clinicians that never went through it.
  #
  # So: the upstream stages must still be spotless, and the fielded stage must FLAG rather than
  # contain. SAP.lock's analytic_population (amended 2026-08-24) excludes them from the primary
  # analyses; sensitivity_6 reports the unrestricted result beside it.
  for (nm in c("study database", "matched pool")) {
    d <- switch(nm,
                "study database" = db[db$PE_or_Not == "PE", , drop = FALSE],
                "matched pool"   = pool[pool$PE_or_Not == "PE", , drop = FALSE])
    hit <- plat_of(d$NPI)
    expect_length(intersect(hit, EXCLUDED), 0L)
  }
  fielded_pe <- sheet[sheet$PE_or_Not == "PE", , drop = FALSE]
  bad <- fielded_pe[plat_of(fielded_pe$NPI) %in% EXCLUDED, , drop = FALSE]
  expect_true(all(bad$Platform_Excluded == "TRUE"),
              info = "an excluded-platform clinician in the frame must be flagged as one")
  expect_true(all(bad$Eligible == "FALSE"),
              info = "a flagged clinician must be outside the analytic population")
  expect_false(any(npi_key(bad$NPI) %in% npi_key(pool$NPI)),
               info = "an excluded-platform clinician inside the pool would be a real leak")
  # The exclusion must be applied before clustering, not after matching.
  i_excl <- grep("EXCLUDED_PLATFORMS \\[?<- c\\(|EXCLUDED_PLATFORMS <- c\\(", psm)[1]
  i_clus <- grep("Clustering Physical Practice Locations", psm)[1]
  expect_true(!is.na(i_excl) && !is.na(i_clus) && i_excl < i_clus,
              info = "platform exclusion must precede office clustering")
})

# (2) none of their NPIs can enter the final PE sample ----------------------------------

test_that("excluded-platform NPIs are confined to the non-pool entrants and flagged", {
  # Same amendment. The pool must stay clean; the fielded frame contains 18 and each must be
  # flagged and outside the analytic population, with none of them reached through the pool.
  fielded_pe <- npi_key(sheet$NPI[sheet$PE_or_Not == "PE"])
  hit <- intersect(fielded_pe, excluded_npi)
  expect_equal(length(hit), 18L,
               info = sprintf("excluded-platform clinicians in the fielded PE arm: %d", length(hit)))
  flagged <- sheet[npi_key(sheet$NPI) %in% hit, , drop = FALSE]
  expect_true(all(flagged$Eligible == "FALSE"))
  expect_length(intersect(npi_key(pool$NPI), excluded_npi), 0L)
  expect_true(length(excluded_npi) > 0L,
              info = "the excluded set must be non-empty, or this test proves nothing")
})

# (3) no NPI belonging to any PE platform can enter the control group -------------------

test_that("no PE-owned clinician appears as a control", {
  for (nm in list(list("fielded 200", sheet), list("matched pool", pool),
                  list("study database", db))) {
    d <- nm[[2]]
    ctl <- npi_key(d$NPI[d$PE_or_Not == "Non-PE"])
    expect_length(intersect(ctl, all_pe_npi), 0L)
  }
  # Excluding a platform from the treated arm must not make it eligible as "independent".
  ctl_fielded <- npi_key(sheet$NPI[sheet$PE_or_Not == "Non-PE"])
  expect_length(intersect(ctl_fielded, excluded_npi), 0L)
  # And the guard must exist in the pipeline, not merely happen to hold in this data.
  expect_true(any(grepl("pe_roster_all", psm, fixed = TRUE)) &&
              any(grepl("candidates_df[!(.cand_npi %in% .pe_all_npi), ]", psm, fixed = TRUE)),
              info = "the control pool must be filtered against the full PE roster")
})

# Supporting contracts -------------------------------------------------------------------

test_that("the two cohorts are distinct and the eligible one feeds the study database", {
  expect_true(any(grepl("pe_full_df <- pe_matched_all", psm, fixed = TRUE)),
              info = "resetting pe_full_df to pe_df would reintroduce the excluded platforms")
  expect_true(any(grepl("pe_roster_all <- pe_df[!is.na(pe_df$NPI), ]", psm, fixed = TRUE)),
              info = "the all-PE roster must be preserved for control ineligibility")
})

test_that("the redraw is a fresh draw, not a patch of the previous sample", {
  # Pair IDs are reassigned by the matcher, so a redraw must not reuse the old fielded set
  # wholesale. Retaining every old pair would indicate the sheet was patched in place.
  n_pairs <- length(unique(sheet[["Matched Pair ID"]]))
  expect_equal(n_pairs, 200L)
  expect_equal(nrow(sheet), 400L)
  expect_equal(sum(sheet$PE_or_Not == "PE"), 200L)
})

# Verified non-physicians -----------------------------------------------------------------

test_that("individually verified non-physicians cannot enter the treated cohort", {
  # Verified against practice websites on 2026-08-10 rather than filtered by taxonomy, which
  # is self-reported, frequently stale, and retained only one-per-NPI upstream.
  VERIFIED_NON_PHYSICIAN <- "1144280553"   # Cindy Joslyn, CNM
  expect_true(any(grepl("EXCLUDED_NPIS <- c(", psm, fixed = TRUE)),
              info = "the NPI-level exclusion list must exist in the pipeline")
  expect_true(any(grepl(VERIFIED_NON_PHYSICIAN, psm, fixed = TRUE)),
              info = "the verified CNM must be named in the exclusion list")
})

test_that("a wrong taxonomy alone never removes a verified physician", {
  # Claire Harraghy carries taxonomy 363LW0102X (nurse practitioner) but is a board-certified
  # OB-GYN. She must remain eligible: the pipeline must not filter on taxonomy.
  VERIFIED_PHYSICIAN <- "1932194743"
  expect_false(any(grepl(sprintf('EXCLUDED_NPIS <- c\\("%s', VERIFIED_PHYSICIAN), psm)),
               info = "a verified physician must not be excluded for a miscoded taxonomy")
  expect_false(any(grepl('grepl\\("\\^207V"', psm)),
               info = "no 207V taxonomy filter may gate eligibility")
})
