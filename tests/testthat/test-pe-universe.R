# Cycle 20 -- 3 BVA, 4 semantic, 3 adversarial.
# Targets the definition of the PE universe: the PitchBook keyword filter that decides which
# companies count as private-equity-owned OB-GYN. It sits upstream of the roster, the cohort,
# the exposure variable and every result, and had not been tested.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)
rd <- function(f) utils::read.csv(f, colClasses = "character", check.names = FALSE)

filt  <- readLines(p("filter_pe_obgyn.py"))
comp  <- rd(p("pe_obgyn_companies_clean.csv"))
deals <- rd(p("pe_obgyn_deals_clean.csv"))
sheet <- rd(p("pe_obgyn_final_calling_sheet_200.csv"))
db    <- rd(p("pe_obgyn_study_database.csv"))
ms    <- paste(readLines(p("manuscript", "manuscript_cite.md")), collapse = "\n")

norm <- function(x) gsub("[^A-Z0-9]", "", toupper(trimws(x)))
universe <- unique(c(norm(comp[["Company Name"]]), norm(deals[["Company Name"]])))
universe <- universe[nzchar(universe)]

db$k <- npi_key(db$NPI)
plat <- unique(trimws(ifelse(is.na(db[["Platform/Practice"]][match(npi_key(sheet$NPI), db$k)]), "",
                             db[["Platform/Practice"]][match(npi_key(sheet$NPI), db$k)])))
plat <- plat[nzchar(plat) & plat != "Control Group"]

EXCLUDED_PLATFORMS <- c("CCRM Fertility", "IVI RMA Global", "US Fertility", "Kindbody",
                        "OB Hospitalist Group")

# ---------------------------------------------------------------- BVA (3)

test_that("BVA: the keyword patterns are word-anchored where ambiguity would bite", {
  kw <- grep("^\\s*r?['\"]", filt, value = TRUE)
  expect_true(length(kw) > 0L)
  # Single common words must be anchored or they match inside longer words.
  for (w in c("fertility", "ivf", "obgyn")) {
    line <- grep(w, kw, value = TRUE, ignore.case = TRUE)[1]
    expect_true(is.na(line) || grepl("\\\\b", line),
                info = sprintf("keyword '%s' is not word-anchored", w))
  }
})

test_that("BVA: the filtered universe is a non-empty subset of what it filtered", {
  expect_true(nrow(comp) > 0L)
  expect_true(nrow(deals) > 0L)
  expect_true(length(universe) >= length(unique(norm(comp[["Company Name"]]))),
              info = "the union of companies and deals cannot be smaller than companies alone")
})

test_that("BVA: every filtered company carries a name", {
  nm <- trimws(comp[["Company Name"]])
  expect_equal(sum(!nzchar(nm)), 0L)
})

# ---------------------------------------------------------------- semantic (4)

test_that("semantic: every fielded platform traces to the PitchBook universe", {
  # The Methods states PE clinics "were identified using the PitchBook financial database".
  # A platform absent from that universe has its PE status from an undocumented source.
  untraced <- plat[!vapply(plat, function(x) {
    n <- norm(x)
    any(grepl(substr(n, 1, 10), universe, fixed = TRUE)) || any(grepl(n, universe, fixed = TRUE))
  }, logical(1))]
  expect_length(untraced, 0L)
})

test_that("semantic: the exposure universe and the eligibility rule do not contradict", {
  # The keyword list deliberately includes fertility and IVF, and 58% of the resulting
  # company universe is fertility. Those platforms are then removed at the eligibility step
  # because they cannot supply a generalist GYN visit. Defining the universe around a segment
  # the study then excludes is a contradiction that belongs in one place or the other.
  kw_block <- paste(filt[grep("KEYWORDS", filt)[1]:(grep("KEYWORDS", filt)[1] + 10)], collapse = " ")
  targets_fertility <- grepl("fertility|ivf", kw_block, ignore.case = TRUE)
  cn <- toupper(comp[["Company Name"]])
  fert_share <- mean(grepl("FERTIL|IVF", cn))
  expect_false(targets_fertility && fert_share > 0.25,
               info = sprintf("keywords target fertility and %.0f%% of the universe is fertility, yet those platforms are excluded downstream",
                              100 * fert_share))
})

test_that("semantic: the filter searches relevant fields, not every cell in the row", {
  # df.map(...).any(axis=1) matches a company if ANY cell contains a keyword, including the
  # investor name or a free-text description. A generalist healthcare fund whose description
  # mentions women's health would enter the OB-GYN universe.
  expect_false(any(grepl("df.map(lambda x: matches_keywords(str(x))).any(axis=1)", filt, fixed = TRUE)),
               info = "the keyword mask is applied across all columns")
})

test_that("semantic: excluded platforms are absent from the treated cohort but not from the roster", {
  # The eligibility exclusion must remove them from the study, while the roster keeps them so
  # they stay ineligible as controls. Both halves matter.
  expect_length(intersect(plat, EXCLUDED_PLATFORMS), 0L)
  roster <- rd(p("pe_obgyn_providers_active.csv"))
  rp <- trimws(ifelse(is.na(roster[["Platform/Practice"]]), "", roster[["Platform/Practice"]]))
  expect_true(length(intersect(unique(rp), EXCLUDED_PLATFORMS)) > 0L,
              info = "the roster must retain excluded platforms for control ineligibility")
})

# ---------------------------------------------------------------- adversarial (3)

test_that("adversarial: no filtered company is a pure keyword coincidence", {
  # A row whose only OB-GYN signal is a stray word is not an OB-GYN company. Require the
  # company NAME itself to carry a relevant term for the large majority of the universe.
  cn <- toupper(comp[["Company Name"]])
  rel <- grepl("OBGYN|OB/GYN|OBSTETRIC|GYNECOL|WOMEN|FERTIL|IVF|MATERNAL|REPRODUCT|UROGYN", cn)
  expect_true(mean(rel) > 0.9,
              info = sprintf("only %.0f%% of filtered company names carry an OB-GYN term; the rest matched on another column",
                             100 * mean(rel)))
})

test_that("adversarial: deal records carry a date and a type", {
  for (col in c("Deal Date", "Deal Type")) {
    expect_true(col %in% names(deals), info = sprintf("%s column is missing", col))
    v <- trimws(deals[[col]])
    expect_true(mean(nzchar(v)) > 0.5,
                info = sprintf("%s is populated for only %.0f%% of deals", col, 100 * mean(nzchar(v))))
  }
})

test_that("adversarial: the manuscript's identification claim matches the implementation", {
  expect_true(grepl("PitchBook", ms, fixed = TRUE))
  # The Methods says acquisitions "by major women's-health platforms" were tracked. If the
  # universe is majority fertility, that description understates what was searched.
  cn <- toupper(comp[["Company Name"]])
  expect_true(mean(grepl("FERTIL|IVF", cn)) < 0.5 || grepl("fertility", ms, ignore.case = TRUE),
              info = "the Methods does not mention fertility although it dominates the search universe")
})
