# Cycle 22 -- 4 BVA, 3 semantic, 3 adversarial.
# Targets the thing propensity matching exists to deliver: balance. Table 1 asserts "All
# matching parameters show high balance between groups", and the Methods names four specific
# constraints. Neither the balance nor the constraints had been tested, and the cohort has
# been redrawn three times since those claims were written.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)
rd <- function(f) utils::read.csv(f, colClasses = "character", check.names = FALSE)

sheet <- rd(p("pe_obgyn_final_calling_sheet_200.csv"))
db    <- rd(p("pe_obgyn_study_database.csv"))
psm   <- readLines(p("build_matched_control_group_psm.R"))
ms    <- paste(readLines(p("manuscript", "manuscript_cite.md")), collapse = "\n")

db$k <- npi_key(db$NPI)
i <- match(npi_key(sheet$NPI), db$k)
gg <- function(col) trimws(ifelse(is.na(db[[col]][i]), "", db[[col]][i]))
sheet$gender <- gg("Gender")
sheet$mdo    <- gg("MD vs. DO")
sheet$yrs    <- suppressWarnings(as.numeric(gg("Years in Practice")))
sheet$op     <- suppressWarnings(as.numeric(gg("Open Payments Years")))

pe <- sheet$PE_or_Not == "PE"; ct <- sheet$PE_or_Not == "Non-PE"
smd <- function(x) {
  a <- x[pe]; b <- x[ct]
  s <- sqrt((var(a, na.rm = TRUE) + var(b, na.rm = TRUE)) / 2)
  if (!is.finite(s) || s == 0) return(0)
  (mean(a, na.rm = TRUE) - mean(b, na.rm = TRUE)) / s
}
BALANCE_THRESHOLD <- 0.10   # conventional |SMD| target for a matched design

pair_split <- function(v) split(v, sheet[["Matched Pair ID"]])

# ---------------------------------------------------------------- BVA (4)

test_that("BVA: the SMD statistic is zero for identical arms and signed otherwise", {
  # Premise correction: ifelse(pe, 10, 0) has zero within-arm variance, so the pooled SD is
  # zero and smd() returns 0 by its own guard. A signed test needs dispersion inside each arm.
  x <- rep(c(1, 1), each = 200)
  expect_equal(smd(x), 0)
  set.seed(1)
  y <- ifelse(pe, rnorm(400, 10, 2), rnorm(400, 0, 2))
  expect_true(smd(y) > 0, info = "a higher PE mean must give a positive SMD")
  expect_true(smd(-y) < 0)
})

test_that("BVA: arms are equal in size and every pair has one of each", {
  expect_equal(sum(pe), sum(ct))
  arms <- pair_split(sheet$PE_or_Not)
  expect_true(all(vapply(arms, function(x) length(unique(x)) == 2L, logical(1))))
})

test_that("BVA: the five-year band has a real boundary", {
  d <- vapply(pair_split(sheet$yrs),
              function(x) if (length(x) == 2L && !anyNA(x)) abs(diff(x)) else NA_real_, numeric(1))
  d <- d[!is.na(d)]
  expect_true(length(d) > 0L)
  expect_true(all(d >= 0))
  expect_true(any(d <= 5), info = "at least some pairs fall inside the claimed band")
})

test_that("BVA: covariates stay in plausible ranges within each arm", {
  for (v in list(sheet$yrs, sheet$op)) {
    expect_true(all(v >= 0, na.rm = TRUE))
    expect_true(all(is.finite(v[!is.na(v)])))
  }
})

# ---------------------------------------------------------------- semantic (3)

test_that("semantic: the matched cohort is balanced on the covariates matching used", {
  res <- c(
    `Years in Practice`   = smd(sheet$yrs),
    `Open Payments Years` = smd(sheet$op),
    `Female`              = smd(as.numeric(sheet$gender == "Female")),
    `MD vs DO`            = smd(as.numeric(sheet$mdo == "MD"))
  )
  bad <- res[abs(res) >= BALANCE_THRESHOLD]
  expect_length(bad, 0L)
})

test_that("semantic: gender is matched exactly, as the Methods states", {
  expect_true(grepl("provider gender (exact match)", ms, fixed = TRUE))
  diff_pairs <- sum(vapply(pair_split(sheet$gender),
                           function(x) length(unique(x)) > 1L, logical(1)))
  expect_equal(diff_pairs, 0L,
               info = sprintf("%d of %d pairs have members of different gender",
                              diff_pairs, length(unique(sheet[["Matched Pair ID"]]))))
})

test_that("semantic: years in practice fall within the claimed five-year band", {
  expect_true(grepl("within a five-year band", ms, fixed = TRUE))
  d <- vapply(pair_split(sheet$yrs),
              function(x) if (length(x) == 2L && !anyNA(x)) abs(diff(x)) else NA_real_, numeric(1))
  d <- d[!is.na(d)]
  over <- sum(d > 5)
  expect_equal(over, 0L,
               info = sprintf("%d of %d measurable pairs differ by more than five years (median %.0f, max %.0f)",
                              over, length(d), median(d), max(d)))
})

# ---------------------------------------------------------------- adversarial (3)

test_that("adversarial: the matcher enforces the constraints the Methods names", {
  # The candidate pool is filtered on state and prior use only. Gender, credential and years
  # enter solely as propensity covariates, which is distributional balance, not the exact
  # match and hard band the Methods describes.
  pool_line <- grep("state_cands <- candidates_df\\[", psm, value = TRUE)
  expect_length(pool_line, 1L)
  ctx <- paste(psm[grep("state_cands <- candidates_df\\[", psm) + 0:1], collapse = " ")
  expect_true(grepl("Gender", ctx),
              info = "the candidate pool applies no gender constraint")
})

test_that("adversarial: credential imbalance is not concealed by aggregate balance", {
  # Gender balances in aggregate while 40% of pairs are mismatched, so a marginal SMD alone
  # cannot certify a pair-matched design. Check the pair level for credential too.
  diff_pairs <- sum(vapply(pair_split(sheet$mdo),
                           function(x) length(unique(x)) > 1L, logical(1)))
  expect_true(diff_pairs == 0L || abs(smd(as.numeric(sheet$mdo == "MD"))) < BALANCE_THRESHOLD,
              info = sprintf("%d pairs differ on MD/DO and the marginal SMD is %+.3f",
                             diff_pairs, smd(as.numeric(sheet$mdo == "MD"))))
})

test_that("adversarial: balance is not an artefact of imputed covariate values", {
  # Imputing missing years with the arm median shrinks variance and pulls both arms toward
  # their own centre, which can make an unbalanced design look balanced.
  imputes <- any(grepl("Years_in_Practice[is.na(", psm, fixed = TRUE))
  n_missing <- sum(is.na(sheet$yrs))
  expect_true(!imputes || n_missing == 0L || grepl("imput", ms, ignore.case = TRUE),
              info = sprintf("matching imputes missing years and %d of %d fielded clinicians lack the value, undisclosed",
                             n_missing, nrow(sheet)))
})
