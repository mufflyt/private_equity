# Cycle 17 -- 3 BVA, 4 semantic, 3 adversarial.
# Targets the exposure variable. PE_or_Not is the study's independent variable and nothing
# has tested how it is attributed: which platform owns a clinic, when it was acquired, and
# whether that platform can even provide the service the vignette requests.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)
rd <- function(f) utils::read.csv(f, colClasses = "character", check.names = FALSE)

sheet <- rd(p("pe_obgyn_final_calling_sheet_200.csv"))
db    <- rd(p("pe_obgyn_study_database.csv"))
ms_lines <- readLines(p("manuscript", "manuscript_cite.md"))
ms    <- paste(ms_lines, collapse = "\n")

db$k <- npi_key(db$NPI)
i    <- match(npi_key(sheet$NPI), db$k)
g    <- function(col) trimws(ifelse(is.na(db[[col]][i]), "", db[[col]][i]))
sheet$plat <- g("Platform/Practice")
sheet$acq  <- g("Acquisition Year")

pe  <- sheet[sheet$PE_or_Not == "PE", , drop = FALSE]
ctl <- sheet[sheet$PE_or_Not == "Non-PE", , drop = FALSE]
acq_num <- suppressWarnings(as.numeric(pe$acq))

# Platforms whose business model cannot supply a generalist new-patient GYN appointment.
FERTILITY   <- c("US Fertility", "IVI RMA Global", "Kindbody", "CCRM Fertility")
HOSPITALIST <- c("OB Hospitalist Group")

# ---------------------------------------------------------------- BVA (3)

test_that("BVA: acquisition years fall inside the study's observable window", {
  v <- acq_num[!is.na(acq_num)]
  expect_true(length(v) > 0L)
  expect_true(all(v >= 2000 & v <= 2026),
              info = sprintf("acquisition years outside 2000-2026: %s",
                             paste(unique(v[v < 2000 | v > 2026]), collapse = ", ")))
})

test_that("BVA: acquisition year is stored as a year, not a float", {
  raw <- pe$acq[nzchar(pe$acq)]
  expect_true(all(grepl("^[0-9]{4}$", raw)),
              info = sprintf("acquisition years carry a decimal suffix, e.g. %s", raw[1]))
})

test_that("BVA: the PE arm draws on more than a single platform", {
  n <- length(unique(pe$plat[nzchar(pe$plat)]))
  expect_true(n > 1L)
  # Concentration is a design property worth pinning: if one platform dominated, the
  # comparison would be that platform versus independents, not PE versus independents.
  top <- max(table(pe$plat[nzchar(pe$plat)]))
  expect_true(top < nrow(pe),
              info = "a single platform accounts for the entire PE arm")
})

# ---------------------------------------------------------------- semantic (4)

test_that("semantic: every PE clinician has a dated acquisition", {
  n_missing <- sum(!nzchar(pe$acq))
  expect_equal(n_missing, 0L,
               info = sprintf("%d PE clinicians have no acquisition year, so exposure timing is unknown for them",
                              n_missing))
})

test_that("semantic: platform names are canonical, not near-duplicates", {
  plats <- unique(pe$plat[nzchar(pe$plat)])
  base <- sub(" */.*$", "", plats)
  dupes <- base[duplicated(base)]
  expect_length(dupes, 0L)
})

test_that("semantic: every platform can supply the appointment the vignette requests", {
  # The single fielded vignette is abnormal uterine bleeding, a generalist outpatient GYN
  # visit. A fertility practice is a subspecialty referral setting and an OB hospitalist
  # group has no outpatient clinic at all, so neither can schedule this visit.
  bad <- pe[pe$plat %in% c(FERTILITY, HOSPITALIST), c("Provider Name", "State", "plat")]
  expect_equal(nrow(bad), 0L,
               info = sprintf("%d PE clinicians sit at platforms that cannot provide a generalist GYN visit: %s",
                              nrow(bad),
                              paste(sprintf("%s (%d)", names(table(bad$plat)), as.integer(table(bad$plat))),
                                    collapse = ", ")))
})

test_that("semantic: the control arm carries a sentinel, not platform metadata", {
  vals <- unique(ctl$plat)
  expect_length(vals, 1L)
  expect_true(grepl("control", vals[1], ignore.case = TRUE),
              info = sprintf("control arm platform value is '%s'", vals[1]))
  expect_equal(sum(nzchar(ctl$acq)), 0L,
               info = "a control with an acquisition year would be exposure leaking into the comparison")
})

# ---------------------------------------------------------------- adversarial (3)

test_that("adversarial: exposure precedes the outcome window for every PE clinician", {
  # A clinic acquired after the calling week was not PE-owned when it was called.
  CALL_YEAR <- 2026
  late <- sum(acq_num > CALL_YEAR, na.rm = TRUE)
  expect_equal(late, 0L,
               info = sprintf("%d clinics were acquired after the calling year", late))
})

test_that("adversarial: platform-level clustering is accounted for in the analysis plan", {
  # 200 PE clinicians belong to 12 corporate parents, the largest holding a quarter of the
  # arm. Clinics under one parent share scheduling policy, call centres and payer contracts,
  # so they are not independent. The SAP declares random intercepts for matched pair and
  # clinician only.
  # Strengthened: the first version accepted any mention of "platform" anywhere in the
  # manuscript and so passed on the Introduction's descriptive use. The contract is that
  # platform appears as a RANDOM-EFFECT TERM in the analysis plan.
  re_lines <- grep("random intercept", ms_lines, value = TRUE, ignore.case = TRUE)
  expect_true(length(re_lines) > 0L)
  models_platform <- any(grepl("platform", re_lines, ignore.case = TRUE))
  top_share <- max(table(pe$plat[nzchar(pe$plat)])) / nrow(pe)
  expect_true(top_share < 0.10 || models_platform,
              info = sprintf("largest platform holds %.0f%% of the PE arm across %d parents; random effects declared are: %s",
                             100 * top_share, length(unique(pe$plat[nzchar(pe$plat)])),
                             "matched pair and individual clinician only"))
})

test_that("adversarial: no control clinician is attributable to a PE platform", {
  pe_plats <- unique(pe$plat[nzchar(pe$plat)])
  expect_length(intersect(ctl$plat, pe_plats), 0L)
  expect_length(intersect(npi_key(pe$NPI), npi_key(ctl$NPI)), 0L)
})
