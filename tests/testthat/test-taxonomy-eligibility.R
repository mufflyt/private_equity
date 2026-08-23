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

sheet <- rd(p("pe_obgyn_final_calling_sheet_200.csv"))
db    <- rd(p("pe_obgyn_study_database.csv"))
psm   <- readLines(p("build_matched_control_group_psm.R"))

db$k <- npi_key(db$NPI)
idx  <- match(npi_key(sheet$NPI), db$k)
tax  <- trimws(ifelse(is.na(db[["NPPES Taxonomy"]][idx]), "", db[["NPPES Taxonomy"]][idx]))
sheet$tax <- tax

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

test_that("semantic: every fielded clinician practises obstetrics and gynecology", {
  bad <- sheet[nzchar(tax) & !IS_OBGYN, c("Provider Name", "State", "PE_or_Not", "tax")]
  expect_equal(nrow(bad), 0L,
               info = sprintf("%d of %d fielded clinicians have a non-OB-GYN taxonomy; examples: %s",
                              nrow(bad), nrow(sheet),
                              paste(utils::head(unique(bad$tax), 6), collapse = ", ")))
})

test_that("semantic: the Subspecialty column reflects the taxonomy it claims to summarise", {
  # Subspecialty reads "Generalist" for the whole cohort. If that were derived from the
  # taxonomy, no non-207V clinician could carry it.
  gen <- trimws(sheet$Subspecialty) == "Generalist"
  contradiction <- sum(gen & nzchar(tax) & !IS_OBGYN)
  expect_equal(contradiction, 0L,
               info = sprintf("%d clinicians are labelled Generalist OB-GYN while their taxonomy says otherwise",
                              contradiction))
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

test_that("adversarial: no non-physician clinician is fielded", {
  mid <- Reduce(`|`, lapply(MIDLEVEL_TAX, function(rx) grepl(rx, tax)))
  n <- sum(mid)
  expect_equal(n, 0L,
               info = sprintf("%d fielded clinicians carry a nurse-practitioner or midwife taxonomy", n))
})

test_that("adversarial: cohort contamination is not differential by ownership arm", {
  # Differential contamination is worse than symmetric contamination: it biases the
  # comparison rather than merely adding noise.
  pe  <- sum(nzchar(tax) & !IS_OBGYN & sheet$PE_or_Not == "PE")
  ctl <- sum(nzchar(tax) & !IS_OBGYN & sheet$PE_or_Not == "Non-PE")
  expect_equal(pe, 0L, info = sprintf("PE arm carries %d non-OB-GYN clinicians", pe))
  expect_equal(ctl, 0L, info = sprintf("control arm carries %d non-OB-GYN clinicians", ctl))
})
