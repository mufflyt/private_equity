# Cycle 18 -- 3 BVA, 3 semantic, 4 adversarial.
# Cycle 17 tested the exposure; this cycle tests the comparator. The Methods claims controls
# were "restricted to independent private practices (excluding academic and hospital-system
# settings)". That claim is the counterfactual the whole study rests on.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)
rd <- function(f) utils::read.csv(f, colClasses = "character", check.names = FALSE)

sheet <- rd(p("pe_obgyn_final_calling_sheet_200.csv"))
cand  <- rd(p("control_candidates_raw.csv"))
expo  <- readLines(p("export_control_candidates.py"))
ms    <- paste(readLines(p("manuscript", "manuscript_cite.md")), collapse = "\n")

ctl <- sheet[sheet$PE_or_Not == "Non-PE", , drop = FALSE]
cand$k <- npi_key(cand$npi)
i <- match(npi_key(ctl$NPI), cand$k)
org <- suppressWarnings(as.numeric(cand$num_org_mem[i]))
fac <- trimws(ifelse(is.na(cand$facility_name[i]), "", cand$facility_name[i]))

# ---------------------------------------------------------------- BVA (3)

test_that("BVA: organisation size is a positive count with a real floor of one", {
  v <- org[!is.na(org)]
  expect_true(length(v) > 0L)
  expect_true(all(v >= 1),
              info = "a clinician belongs to at least their own organisation")
  expect_true(all(v == floor(v)), info = "organisation membership is a count")
})

test_that("BVA: every fielded control resolves in the candidate pool it was drawn from", {
  expect_equal(sum(is.na(i)), 0L)
  expect_equal(nrow(ctl), 200L)
})

test_that("BVA: the practice-setting classifier covers its categories exhaustively", {
  blk <- paste(expo, collapse = " ")
  for (cat in c("Academic", "Government", "Community", "Private Practice")) {
    expect_true(grepl(sprintf("'%s'", cat), blk, fixed = TRUE),
                info = sprintf("category %s is not assigned anywhere", cat))
  }
})

# ---------------------------------------------------------------- semantic (3)

test_that("semantic: controls are independent private practices, as the Methods claims", {
  # An organisation with hundreds or thousands of members is a group or health system, not
  # an independent private practice. Ten is a generous ceiling for "independent".
  big <- sum(org > 10, na.rm = TRUE)
  expect_equal(big, 0L,
               info = sprintf("%d of %d fielded controls belong to organisations larger than 10 clinicians (median %.0f, max %.0f)",
                              big, sum(!is.na(org)), median(org, na.rm = TRUE), max(org, na.rm = TRUE)))
})

test_that("semantic: the classifier positively confirms private practice rather than failing open", {
  # get_practice_setting() returns 'Private Practice' when the facility name is empty and
  # again when it matches none of the academic, government or community keyword lists. Every
  # unrecognised organisation is therefore admitted as independent.
  i0 <- grep("def get_practice_setting", expo)
  expect_length(i0, 1L)
  body <- expo[i0:(i0 + 12)]
  empty_defaults <- any(grepl("if not fac or fac == 'NAN'", body, fixed = TRUE))
  falls_through   <- any(grepl("return 'Private Practice'", body, fixed = TRUE))
  expect_false(empty_defaults && falls_through,
               info = "an unnamed or unrecognised facility is classified as an independent private practice")
})

test_that("semantic: the manuscript's exclusion claim matches what the code excludes", {
  claims_exclusion <- grepl("excluding academic and hospital-system", ms, fixed = TRUE)
  expect_true(claims_exclusion)
  # The code excludes on facility-name keywords only. Nothing excludes on organisation size,
  # so a 7,694-member organisation with an unremarkable name is retained as independent.
  excludes_by_size <- any(grepl("num_org_mem *[<>]", expo))
  expect_true(excludes_by_size,
              info = "exclusion is by facility name alone; organisation size is never tested")
})

# ---------------------------------------------------------------- adversarial (4)

test_that("adversarial: an unnamed facility is not silently called independent", {
  n_unnamed <- sum(!nzchar(fac))
  expect_equal(n_unnamed, 0L,
               info = sprintf("%d fielded controls have no facility name and were classified Private Practice by default",
                              n_unnamed))
})

test_that("adversarial: no fielded control sits inside a very large organisation", {
  huge <- sum(org > 1000, na.rm = TRUE)
  expect_equal(huge, 0L,
               info = sprintf("%d fielded controls belong to organisations with more than 1,000 clinicians",
                              huge))
})

test_that("adversarial: fail-open classifiers are inventoried across the repository", {
  # Third instance of this shape: subspecialty (cycles 3, 13), MD vs DO (cycle 15), and
  # practice setting here. Each defaults to the category that ADMITS a record.
  sites <- c("build_matched_control_group_psm.R", "export_control_candidates.py",
             "add_backup_physicians.py")
  present <- vapply(sites, function(f) file.exists(p(f)), logical(1))
  expect_true(all(present))
  fail_open <- vapply(sites[present], function(f) {
    src <- readLines(p(f), warn = FALSE)
    any(grepl("return\\(\"Generalist\"\\)|return 'Generalist'|return 'Private Practice'", src))
  }, logical(1))
  expect_equal(sum(fail_open), 0L,
               info = sprintf("fail-open defaults remain in: %s",
                              paste(names(fail_open)[fail_open], collapse = ", ")))
})

test_that("adversarial: no assertion in this suite can be satisfied by adjacent text", {
  # Widened from cycle 16, which covered only unanchored expect_false(grepl(...)). Cycle 17
  # showed a PRESENCE assertion can pass on text adjacent to the target: grepl("platform", ms)
  # matched the Introduction's prose rather than a random-effect term. Flag any grepl over a
  # whole-document haystack whose pattern is a single bare word.
  files <- list.files(p("tests", "testthat"), pattern = "[.]R$", full.names = TRUE)
  offenders <- character(0)
  for (f in files) {
    src <- readLines(f, warn = FALSE)
    src <- src[!grepl("^\\s*#", src)]   # comments are prose, not assertions
    hits <- grep('grepl\\("[A-Za-z]{3,}"[^,]*, *(ms|txt|src|blk)\\b', src)
    for (h in hits) {
      if (grepl("ignore.case|fixed *= *TRUE", src[h])) next
      offenders <- c(offenders, sprintf("%s:%d", basename(f), h))
    }
  }
  expect_length(offenders, 0L)
})
