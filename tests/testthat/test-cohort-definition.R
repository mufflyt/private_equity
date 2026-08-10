# Cycle 12 -- 3 BVA, 3 semantic, 4 adversarial.
# Targets who is actually in the cohort, and the public-facing figure that describes how they
# got there. The study is defined as OB-GYN physicians; Figure 1 is the STROBE flow diagram a
# reviewer will check first.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)
rd <- function(f) utils::read.csv(f, colClasses = "character", check.names = FALSE)

sheet  <- rd(p("pe_obgyn_final_calling_sheet_200.csv"))
pool   <- rd(p("pe_obgyn_matched_calling_list.csv"))
strobe <- readLines(p("manuscript", "strobe_diagram.R"))
ms     <- paste(readLines(p("manuscript", "manuscript_cite.md")), collapse = "\n")
matcher <- readLines(p("match_all_providers.py"))

stage <- function(name) {
  # Stage names contain regex metacharacters, e.g. "De-clustered (1/Office)". Match fixed.
  ln <- grep(paste0('"', name, '"'), strobe, value = TRUE, fixed = TRUE)
  ln <- grep("= *[0-9]+", ln, value = TRUE)[1]
  as.integer(sub('.*= *([0-9]+).*', "\\1", ln))
}
STAGES <- c("Initial Scraped PE Roster", "Unique NPI Verified", "OB-GYN Generalist Only",
            "De-clustered (1/Office)", "Geographically Matched", "Fielded Cohort")
counts <- vapply(STAGES, stage, integer(1))

MIDLEVEL <- c("CNM", "NP", "PA", "PAC", "PA-C", "RN", "MSN", "DNP", "APRN", "WHNP",
              "LPN", "FNP", "ARNP", "CRNP", "APN")

# ---------------------------------------------------------------- BVA (3)

test_that("BVA: the STROBE funnel never widens", {
  expect_false(any(is.na(counts)))
  expect_true(all(diff(counts) <= 0L),
              info = sprintf("stages: %s", paste(counts, collapse = " -> ")))
  expect_equal(unname(counts[length(counts)]), 200L)
})

test_that("BVA: STROBE exclusion annotations equal the gaps they describe", {
  ann <- function(name) {
    ln <- grep(paste0('"', name, '"'), strobe, value = TRUE, fixed = TRUE)
    ln <- grep('= *"[0-9]+', ln, value = TRUE)[1]
    if (is.na(ln)) return(NA_integer_)
    as.integer(sub('.*= *"([0-9]+).*', "\\1", ln))
  }
  expect_equal(ann("Unique NPI Verified"), unname(counts[1] - counts[2]))
  expect_equal(ann("OB-GYN Generalist Only"), unname(counts[2] - counts[3]))
  expect_equal(ann("De-clustered (1/Office)"), unname(counts[3] - counts[4]))
})

test_that("BVA: credentials fall in the allowed physician set", {
  cred <- trimws(sheet$Credentials)
  present <- unique(cred[nzchar(cred)])
  expect_true(length(present) > 0L)
  expect_true(all(present %in% c("MD", "DO")),
              info = sprintf("unexpected credentials in the fielded cohort: %s",
                             paste(setdiff(present, c("MD", "DO")), collapse = ", ")))
})

# ---------------------------------------------------------------- semantic (3)

test_that("semantic: STROBE stage counts match the artifacts they describe", {
  n_pool <- length(unique(pool[["Matched Pair ID"]]))
  expect_equal(unname(counts[which(STAGES == "Geographically Matched")]), n_pool,
               info = sprintf("Figure 1 states %d matched pairs; the calling list holds %d",
                              counts[5], n_pool))
})

test_that("semantic: the manuscript text and Figure 1 agree on the matched pool", {
  txt_pool <- as.integer(sub(".*matched pool of ([0-9]+) pairs.*", "\\1",
                             regmatches(ms, regexpr("matched pool of [0-9]+ pairs", ms))))
  expect_equal(txt_pool, unname(counts[which(STAGES == "Geographically Matched")]),
               info = sprintf("Methods says %d pairs, Figure 1 says %d", txt_pool, counts[5]))
})

test_that("semantic: no mid-level provider is in a physician cohort", {
  cred <- toupper(trimws(sheet$Credentials))
  offenders <- sheet[cred %in% MIDLEVEL, c("Provider Name", "City", "State", "PE_or_Not"), drop = FALSE]
  expect_equal(nrow(offenders), 0L,
               info = sprintf("mid-level clinicians fielded: %s",
                              paste(offenders$`Provider Name`, offenders$Credentials, collapse = "; ")))
})

# ---------------------------------------------------------------- adversarial (4)

test_that("adversarial: every fielded clinician has a recorded credential", {
  cred <- trimws(sheet$Credentials)
  n_missing <- sum(!nzchar(cred) | is.na(cred))
  expect_equal(n_missing, 0L,
               info = sprintf("%d of %d fielded clinicians have no credential, so MD/DO cannot be verified",
                              n_missing, nrow(sheet)))
})

test_that("adversarial: the fielded cohort is generalist OB-GYN only", {
  sub <- trimws(sheet$Subspecialty)
  expect_true(all(sub == "Generalist" | !nzchar(sub)),
              info = sprintf("non-generalist subspecialties fielded: %s",
                             paste(unique(sub[sub != "Generalist" & nzchar(sub)]), collapse = ", ")))
})

test_that("adversarial: the matcher's mid-level exclusion list is applied, not merely declared", {
  # Premise correction: the identifier is EXCLUDED_CREDENTIALS, not MIDLEVEL. It is used in
  # four places. The exclusion is implemented; what fails is downstream, where a CNM whose
  # NPPES taxonomy is "Midwife" is classified Generalist by the fail-open subspecialty
  # mapper and stamped "MD" by a derivation that treats anything not DO as MD.
  i <- grep("EXCLUDED_CREDENTIALS", matcher)
  expect_true(length(i) > 1L,
              info = "the list must be referenced somewhere beyond its own definition")
  expect_true(any(grepl('is_mid_level = True', matcher, fixed = TRUE)))
})

test_that("adversarial: the caller sheet export cannot mangle NPIs or phone numbers", {
  gs <- readLines(p("build_balanced_google_sheet.R"))
  expect_true(any(grepl("col_character", gs)),
              info = "reading numerically would turn a 10-digit NPI into scientific notation")
  expect_true(any(grepl("write_csv|write\\.csv", gs)))
})
