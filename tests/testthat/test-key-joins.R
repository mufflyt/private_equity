# Cycle 10 -- 4 BVA, 3 semantic, 3 adversarial.
# Follows cycle 9's lesson: recovering a value by key after the fact is unsafe when the key
# is not unique. This cycle audits every by-NPI recovery site in the pipeline and establishes
# the precondition each one silently assumes.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)
rd <- function(f) utils::read.csv(f, colClasses = "character", check.names = FALSE)

sheet <- rd(p("pe_obgyn_final_calling_sheet_200.csv"))
db    <- rd(p("pe_obgyn_study_database_with_churn.csv"))
k_db  <- npi_key(db$NPI)
blank <- !nzchar(k_db) | is.na(k_db)

# ---------------------------------------------------------------- BVA (4)

test_that("BVA: an NPI is exactly ten digits or is absent, never anything between", {
  real <- k_db[!blank]
  expect_true(all(grepl("^[0-9]{10}$", real)),
              info = "a partial or malformed NPI would join to nothing and be silently dropped")
  expect_true(length(real) > 0L)
})

test_that("BVA: the empty key is not equal to any real key", {
  expect_false(npi_key("") %in% npi_key(c("1003038688", "1912969700")))
  expect_true(is.na(npi_key(NA)) || !nzchar(npi_key(NA)))
  expect_false(identical(npi_key("0000000000"), npi_key("")),
              info = "an all-zero NPI is a value; blank is the absence of one")
})

test_that("BVA: enrichment reaches every fielded clinician, not merely most", {
  idx <- match(npi_key(sheet$NPI), k_db)
  expect_equal(sum(is.na(idx)), 0L)
  for (cn in c("CDC_SVI", "Mean_Annual_Churn")) {
    v <- db[[cn]][idx]
    expect_true(all(nzchar(v)),
                info = sprintf("%s is empty for some fielded clinician", cn))
  }
})

test_that("BVA: a zero HQ distance is a real value, not a missing one", {
  hq <- suppressWarnings(as.numeric(sheet$HQ_Distance_Miles))
  expect_true(any(!is.na(hq)))
  expect_true(all(hq >= 0, na.rm = TRUE))
  # Zero means the practice sits at its platform's headquarters, which is meaningful.
  expect_false(all(hq[!is.na(hq)] > 0) && any(is.na(hq)),
               info = "zeros must not have been converted to NA")
})

# ---------------------------------------------------------------- semantic (3)

test_that("semantic: rows without an NPI are not treated as one clinician", {
  # 258 PE-arm rows carry a provider name but no NPI, having failed NPPES matching. Any
  # join keyed on NPI collapses all of them onto whichever blank-keyed row survives a
  # distinct()/first-row step, giving 258 clinicians one clinician's enrichment.
  n_blank <- sum(blank)
  expect_true(n_blank > 0L)
  expect_true(all(nzchar(db[["Provider Name"]][blank])),
              info = "these are real clinicians, not empty rows")
  expect_equal(length(unique(k_db[blank])), 1L,
               info = sprintf("all %d NPI-less rows share one key and would join to each other", n_blank))
})

test_that("semantic: no NPI-less clinician reaches a fielded artifact", {
  # The blank-key hazard is latent rather than active precisely because nothing NPI-less is
  # fielded. This test is what keeps that true.
  expect_true(all(nzchar(npi_key(sheet$NPI))))
  expect_true(all(grepl("^[0-9]{10}$", npi_key(sheet$NPI))))
  imp <- rd(p("redcap_import_ready_200.csv"))
  expect_equal(nrow(imp), 800L)
})

test_that("semantic: distinct-by-NPI is safe only because real NPIs are unique", {
  # Every distinct(NPI, .keep_all = TRUE) in the pipeline assumes this. State it, so that a
  # future source with genuine duplicates fails here rather than silently picking a row.
  real <- k_db[!blank]
  expect_equal(sum(duplicated(real)), 0L,
               info = "a duplicated real NPI would make every by-NPI enrichment arbitrary")
})

# ---------------------------------------------------------------- adversarial (3)

test_that("adversarial: every by-key recovery site is inventoried", {
  # Cycle 9 found one of these silently wrong. Keep the list visible so a new one is noticed.
  sites <- c("apply_hq_distance.R", "apply_demographic_covariates.R",
             "calculate_cohort_churn.R", "dedup_offices_and_backfill_200.R")
  found <- vapply(sites, function(f) {
    if (!file.exists(p(f))) return(FALSE)
    any(grepl("distinct\\((NPI|npi_key), \\.keep_all = TRUE\\)", readLines(p(f))))
  }, logical(1))
  expect_true(all(found),
              info = paste("expected a by-NPI recovery in:", paste(sites[!found], collapse = ", ")))
})

test_that("adversarial: enrichment does not depend on the order of the source rows", {
  idx1 <- match(npi_key(sheet$NPI), k_db)
  rev_db <- db[rev(seq_len(nrow(db))), , drop = FALSE]
  idx2 <- match(npi_key(sheet$NPI), npi_key(rev_db$NPI))
  expect_equal(db$CDC_SVI[idx1], rev_db$CDC_SVI[idx2],
               info = "reversing the source must not change any fielded clinician's enrichment")
})

test_that("adversarial: the Python phone cross-reference cannot silently pick a row", {
  py <- readLines(p("cross_reference_phones.py"))
  expect_true(any(grepl("db_row\\.iloc\\[0\\]", py)),
              info = "documents the first-row-on-duplicate behaviour")
  # Safe only while NPIs are unique in the study database, which the semantic test above
  # asserts. If that ever fails, this line silently attributes one clinician's phones to
  # another, and phone identity is what the two-calls-per-office guarantee rests on.
  expect_true(any(grepl("isinstance\\(db_row, pd\\.DataFrame\\)", py)),
              info = "the duplicate case is at least detected before being collapsed")
})
