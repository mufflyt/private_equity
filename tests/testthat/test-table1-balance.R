# Cycle 14 -- 3 BVA, 4 semantic, 3 adversarial.
# Targets Table 1, the baseline balance table. It is the first thing a reviewer reads and the
# basis for the claim that propensity matching worked. Nothing has tested whether its numbers
# come from the cohort it describes.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)
rd <- function(f) utils::read.csv(f, colClasses = "character", check.names = FALSE)

ms    <- readLines(p("manuscript", "manuscript_cite.md"))
sheet <- rd(p("pe_obgyn_final_calling_sheet_200.csv"))
db    <- rd(p("pe_obgyn_study_database.csv"))

db$k <- npi_key(db$NPI)
i    <- match(npi_key(sheet$NPI), db$k)
gcol <- function(col) trimws(ifelse(is.na(db[[col]][i]), "", db[[col]][i]))
sheet$mdo    <- gcol("MD vs. DO")
sheet$gender <- gcol("Gender")
sheet$yrs    <- suppressWarnings(as.numeric(gcol("Years in Practice")))
sheet$op     <- suppressWarnings(as.numeric(gcol("Open Payments Years")))

arm <- function(a) sheet[sheet$PE_or_Not == a, , drop = FALSE]
ctl <- arm("Non-PE"); pe <- arm("PE")

# Parse the stated values out of Table 1.
t1row <- function(label) {
  # Premise correction: rows are "| MD | ... |", not "| - MD | ...". The hyphenated labels
  # came from manuscript_content.txt, the stale scratch copy at the repo root, not from
  # manuscript/manuscript_cite.md which the README names as the source of truth.
  ln <- grep(paste0("^\\| *", label, " *\\|"), ms, value = TRUE)[1]
  if (is.na(ln)) return(NULL)
  cells <- trimws(strsplit(ln, "\\|")[[1]])
  cells[nzchar(cells)]
}
firstnum <- function(x) as.numeric(sub("^[^0-9.]*([0-9.]+).*", "\\1", x))

# ---------------------------------------------------------------- BVA (3)

test_that("BVA: Table 1 credential counts sum to the arm size", {
  md <- t1row("MD"); do <- t1row("DO")
  expect_false(is.null(md)); expect_false(is.null(do))
  expect_equal(firstnum(md[2]) + firstnum(do[2]), 200,
               info = "independent arm credentials must account for all 200 clinicians")
  expect_equal(firstnum(md[3]) + firstnum(do[3]), 200,
               info = "PE arm credentials must account for all 200 clinicians")
})

test_that("BVA: Table 1 percentages agree with its own counts", {
  for (lbl in c("MD", "DO", "Female", "Male")) {
    r <- t1row(lbl)
    if (is.null(r)) next
    for (j in 2:3) {
      n <- firstnum(r[j])
      pct <- as.numeric(sub(".*\\(([0-9.]+)%\\).*", "\\1", r[j]))
      expect_equal(round(100 * n / 200, 1), pct,
                   info = sprintf("%s column %d: %s does not equal %.1f%%", lbl, j, r[j], 100 * n / 200))
    }
  }
})

test_that("BVA: dispersion is positive and central values are plausible", {
  for (a in list(ctl, pe)) {
    expect_true(sd(a$yrs, na.rm = TRUE) > 0)
    expect_true(mean(a$yrs, na.rm = TRUE) > 0 && mean(a$yrs, na.rm = TRUE) < 60)
    expect_true(sd(a$op, na.rm = TRUE) > 0)
  }
})

# ---------------------------------------------------------------- semantic (4)

test_that("semantic: Table 1 credential counts match the fielded cohort", {
  md <- t1row("MD"); do <- t1row("DO")
  expect_equal(firstnum(md[2]), sum(ctl$mdo == "MD"),
               info = sprintf("Table 1 says %s independent MDs; cohort has %d", md[2], sum(ctl$mdo == "MD")))
  expect_equal(firstnum(do[2]), sum(ctl$mdo == "DO"),
               info = sprintf("Table 1 says %s independent DOs; cohort has %d", do[2], sum(ctl$mdo == "DO")))
  expect_equal(firstnum(md[3]), sum(pe$mdo == "MD"),
               info = sprintf("Table 1 says %s PE MDs; cohort has %d", md[3], sum(pe$mdo == "MD")))
  expect_equal(firstnum(do[3]), sum(pe$mdo == "DO"),
               info = sprintf("Table 1 says %s PE DOs; cohort has %d", do[3], sum(pe$mdo == "DO")))
})

test_that("semantic: Table 1 gender counts match the fielded cohort", {
  f <- t1row("Female")
  expect_equal(firstnum(f[2]), sum(ctl$gender == "Female"),
               info = sprintf("Table 1 says %s independent women; cohort has %d", f[2], sum(ctl$gender == "Female")))
  expect_equal(firstnum(f[3]), sum(pe$gender == "Female"),
               info = sprintf("Table 1 says %s PE women; cohort has %d", f[3], sum(pe$gender == "Female")))
})

test_that("semantic: Table 1 years in practice match the fielded cohort", {
  r <- t1row("Years in Practice \\(mean . SD\\)")
  expect_equal(firstnum(r[2]), round(mean(ctl$yrs, na.rm = TRUE), 1),
               info = sprintf("Table 1 independent mean %s vs cohort %.1f", r[2], mean(ctl$yrs, na.rm = TRUE)))
  expect_equal(firstnum(r[3]), round(mean(pe$yrs, na.rm = TRUE), 1),
               info = sprintf("Table 1 PE mean %s vs cohort %.1f", r[3], mean(pe$yrs, na.rm = TRUE)))
})

test_that("semantic: Table 1 open payments years match the fielded cohort", {
  r <- t1row("Open Payments Years \\(mean . SD\\)")
  expect_equal(firstnum(r[2]), round(mean(ctl$op, na.rm = TRUE), 1),
               info = sprintf("Table 1 independent mean %s vs cohort %.1f", r[2], mean(ctl$op, na.rm = TRUE)))
  expect_equal(firstnum(r[3]), round(mean(pe$op, na.rm = TRUE), 1),
               info = sprintf("Table 1 PE mean %s vs cohort %.1f", r[3], mean(pe$op, na.rm = TRUE)))
})

# ---------------------------------------------------------------- adversarial (3)

test_that("adversarial: missing covariate values are disclosed, not averaged over silently", {
  n_miss_yrs <- sum(is.na(pe$yrs)) + sum(is.na(ctl$yrs))
  n_miss_op  <- sum(is.na(pe$op)) + sum(is.na(ctl$op))
  disclosed <- any(grepl("missing|not reported|imputed", ms, ignore.case = TRUE))
  expect_true(n_miss_yrs == 0L || disclosed,
              info = sprintf("%d clinicians lack years in practice and %d lack Open Payments years; Table 1 reports means with no denominator",
                             n_miss_yrs, n_miss_op))
})

test_that("adversarial: a covariate imputed for matching is disclosed as imputed", {
  psm <- readLines(p("build_matched_control_group_psm.R"))
  imputes <- any(grepl("Years_in_Practice\\[is.na\\(.*\\)\\] *<- *pe_years_med", psm))
  expect_true(!imputes || any(grepl("imput", ms, ignore.case = TRUE)),
              info = "matching imputes missing years with the median; the Methods does not say so")
})

test_that("adversarial: Table 1 is generated from the cohort, not typed by hand", {
  gen <- list.files(p("."), pattern = "\\.R$", full.names = TRUE)
  makes_t1 <- any(vapply(gen, function(f) {
    any(grepl("Table 1|table1|baseline", readLines(f, warn = FALSE), ignore.case = TRUE))
  }, logical(1)))
  expect_true(makes_t1,
              info = "no script produces Table 1, so its numbers cannot track the cohort")
})
