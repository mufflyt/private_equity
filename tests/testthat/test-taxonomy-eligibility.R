# Cycle 13 -- 4 BVA, 3 semantic, 3 adversarial.
# Follows cycle 12's CNM to its source. The Subspecialty column reads "Generalist" for all
# 400 fielded clinicians, but that column is produced by a classifier that returns
# "Generalist" for any taxonomy it does not recognise. This cycle checks the taxonomy itself.
#
# CMS taxonomy: OB-GYN and its subspecialties are the 207V* family. Anything else is a
# different specialty, a trainee, or a non-physician.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)
rd <- function(f) utils::read.csv(f, colClasses = "character", check.names = FALSE)

sheet <- rd(p("pe_obgyn_final_calling_sheet_200_dedup.csv"))
psm   <- readLines(p("build_matched_control_group_psm.R"))

# Taxonomy comes from the sheet's own committed column, not from a join.
# It used to be joined out of pe_obgyn_study_database.csv, which contains 263 of the 400
# fielded clinicians -- so 137 taxonomies came back empty and every contract below was
# evaluated on a hole. NPPES_Taxonomy_Code is on the sheet, covers all 400, and was retrieved
# from the CMS registry, so the checks now run against the cohort they name.
tax <- trimws(ifelse(is.na(sheet[["NPPES_Taxonomy_Code"]]), "", sheet[["NPPES_Taxonomy_Code"]]))
sheet$tax <- tax

# The analytic population SAP.lock declares. The frame is called as fielded; the estimand
# refers to this subset. Contracts below are stated against whichever of the two they mean.
eligible <- toupper(trimws(sheet$Eligible)) == "TRUE"

IS_OBGYN   <- grepl("^207V", tax)
IS_CODE    <- grepl("^[0-9]{3}[A-Z0-9]{6}X$", tax)
STUDENT    <- "390200000X"
MIDLEVEL_TAX <- c("^363L", "^363A", "^364S", "^367A")   # NP, PA, CNS, CNM families

# ---------------------------------------------------------------- BVA (4)

test_that("BVA: every taxonomy value is a well-formed CMS code", {
  bad <- unique(tax[nzchar(tax) & !IS_CODE])
  expect_length(bad, 0L)
})

test_that("BVA: the OB-GYN prefix boundary is 207V, not 207", {
  expect_true(grepl("^207V", "207V00000X"), info = "generalist OB-GYN")
  expect_true(grepl("^207V", "207VG0400X"), info = "gynecology")
  expect_false(grepl("^207V", "207Q00000X"), info = "207Q is family medicine, not OB-GYN")
  expect_false(grepl("^207V", "207R00000X"), info = "207R is internal medicine")
})

test_that("BVA: taxonomy is present for every fielded clinician", {
  expect_equal(sum(!nzchar(tax)), 0L)
  expect_equal(length(tax), nrow(sheet))
})

test_that("BVA: arm sizes are exactly 200 and sum to the cohort", {
  tb <- table(sheet$PE_or_Not)
  expect_equal(as.integer(tb[["PE"]]), 200L)
  expect_equal(as.integer(tb[["Non-PE"]]), 200L)
  expect_equal(sum(tb), nrow(sheet))
})

# ---------------------------------------------------------------- semantic (3)

test_that("semantic: every clinician in the analytic population practises obstetrics and gynecology", {
  # CONTRACT CHANGED 2026-08-24, narrowed to the population the estimand refers to.
  #
  # The frame does contain non-OB-GYN clinicians -- 33 by primary taxonomy. They were admitted
  # because get_subspecialty_from_tax() failed open, returning "Generalist" for any taxonomy it
  # did not recognise while the caller filtered TO "Generalist". That is fixed at source. The
  # frame cannot be un-fielded, so SAP.lock excludes them from the analytic population instead
  # (amended 2026-08-24), and the contract is stated there, where it must hold absolutely.
  bad <- sheet[eligible & nzchar(tax) & !IS_OBGYN, c("Provider Name", "State", "PE_or_Not", "tax")]
  expect_equal(nrow(bad), 0L,
               info = sprintf("%d clinicians inside the analytic population are not OB-GYN: %s",
                              nrow(bad), paste(utils::head(unique(bad$tax), 6), collapse = ", ")))
})

test_that("semantic: every non-OB-GYN clinician in the frame is flagged and excluded", {
  # The frame-level statement. Contamination is permitted to exist, but never to be silent:
  # each one must carry the flags that keep it out of the analytic population.
  contaminated <- nzchar(tax) & !IS_OBGYN
  expect_true(all(toupper(trimws(sheet$Taxonomy_Is_OBGYN[contaminated])) == "FALSE"),
              info = "a non-OB-GYN taxonomy must set Taxonomy_Is_OBGYN to FALSE")
  expect_false(any(eligible[contaminated]),
               info = "a non-OB-GYN clinician must be outside the analytic population")
  expect_equal(sum(contaminated), 33L,
               info = sprintf("frame carries %d non-OB-GYN clinicians", sum(contaminated)))
})

test_that("semantic: the taxonomy-derived subspecialty is authoritative, and the roster label is not", {
  # CONTRACT CHANGED, and split in two. The roster's Subspecialty column reads "Generalist" for
  # all 400, including a urologist and a midwife: it is a scraped label, not a derivation, and
  # asserting it agrees with the taxonomy asserts something it was never built to do. The sheet
  # now carries Subspecialty_Taxonomy, derived by the same 207V family test the fixed
  # classifier uses. THAT is required to agree with the taxonomy, absolutely.
  expect_true(all(trimws(sheet$Subspecialty) == "Generalist"),
              info = "the roster label is uniform; it is retained only as source data")
  st  <- trimws(sheet$Subspecialty_Taxonomy)
  expect_equal(sum(st == "Not OB-GYN" & IS_OBGYN), 0L,
               info = "a 207V taxonomy must never be labelled Not OB-GYN")
  expect_equal(sum(st == "Generalist" & !IS_OBGYN), 0L,
               info = "a non-207V taxonomy must never be labelled Generalist")
  # And the derived label, not the roster one, is what tracks eligibility.
  expect_false(any(eligible & st == "Not OB-GYN"))
})

test_that("adversarial: OB-GYN subspecialists are present in a generalist-only frame", {
  # Found by this cycle. The study samples generalist OB-GYNs; the PSM filter drops the four
  # 207V subspecialties. Four subspecialists reached the frame anyway -- three FPMRS and one
  # gynecologic oncologist -- because they were admitted through the non-pool path that also
  # carried the excluded platforms. They ARE obstetrics and gynecology, so Eligible does not
  # exclude them and SAP.lock's analytic_population retains them.
  #
  # Recorded, not silently fixed: narrowing the population further is an amendment, and the
  # plan is already hashed. This pins the count so a change is visible.
  sub <- trimws(sheet$Subspecialty_Taxonomy)
  n <- sum(!sub %in% c("Generalist", "Not OB-GYN", "Unknown"))
  expect_equal(n, 4L, info = sprintf("%d OB-GYN subspecialists in the frame", n))
  expect_true(all(eligible[!sub %in% c("Generalist", "Not OB-GYN", "Unknown")]),
              info = "subspecialists are currently inside the analytic population by design")
})

test_that("semantic: the classifier must positively confirm OB-GYN, not fail open", {
  # Strengthened: the first version passed merely because the four subspecialty codes in the
  # body begin with 207V. That is a false negative of exactly the kind this exercise exists
  # to catch. The contract is a positive family test on the prefix, so that a taxonomy
  # outside 207V cannot reach the "Generalist" return at all.
  i <- grep("^get_subspecialty_from_tax", psm)[1]
  blk <- paste(psm[i:(i + 10)], collapse = " ")
  has_family_test <- grepl('substr\\([^)]*1, *4\\) *[!=]= *"207V"', blk) ||
                     grepl('grepl\\("\\^207V"', blk) ||
                     grepl('startsWith\\([^)]*"207V"\\)', blk)
  expect_true(has_family_test,
              info = "no prefix test on the 207V OB-GYN family; any unrecognised taxonomy returns Generalist")
})

# ---------------------------------------------------------------- adversarial (3)

test_that("adversarial: no trainee is fielded as a practising physician", {
  n <- sum(tax == STUDENT)
  expect_equal(n, 0L,
               info = sprintf("%d fielded clinicians carry the student/trainee taxonomy %s",
                              n, STUDENT))
})

test_that("adversarial: no non-physician clinician is in the analytic population", {
  mid <- Reduce(`|`, lapply(MIDLEVEL_TAX, function(rx) grepl(rx, tax)))
  expect_equal(sum(mid & eligible), 0L,
               info = "a midwife or nurse practitioner inside the analytic population")
  # One CNM is in the frame. It must be flagged, and it must be out.
  expect_equal(sum(mid), 1L, info = sprintf("frame carries %d mid-level clinicians", sum(mid)))
})

test_that("adversarial: contamination is differential by arm in the frame, and absent from the population", {
  # This is the finding that matters most, and the reason the restriction is not optional.
  # Differential contamination biases the comparison rather than adding noise: an office that
  # does not provide the service refuses or redirects, and concentrated in one arm that reads
  # as an access difference. The frame is contaminated asymmetrically; the analytic population
  # is not contaminated at all.
  bad <- nzchar(tax) & !IS_OBGYN
  pe  <- sum(bad & sheet$PE_or_Not == "PE")
  ctl <- sum(bad & sheet$PE_or_Not == "Non-PE")
  expect_gt(pe, ctl)
  expect_equal(c(pe, ctl), c(29L, 4L),
               info = sprintf("frame contamination PE %d vs control %d", pe, ctl))
  expect_equal(sum(bad & eligible), 0L,
               info = "the analytic population must carry none of it, in either arm")
})
