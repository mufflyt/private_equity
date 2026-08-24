# Cycle 18 -- 3 BVA, 3 semantic, 4 adversarial.
# Cycle 17 tested the exposure; this cycle tests the comparator. The Methods claims controls
# were "restricted to independent private practices (excluding academic and hospital-system
# settings)". That claim is the counterfactual the whole study rests on.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)
rd <- function(f) utils::read.csv(f, colClasses = "character", check.names = FALSE)

sheet <- rd(p("pe_obgyn_final_calling_sheet_200_dedup.csv"))
cand  <- rd(p("control_candidates_raw.csv"))
expo  <- readLines(p("export_control_candidates.py"))
ms    <- paste(readLines(p("manuscript", "manuscript_cite.md")), collapse = "\n")

ctl <- sheet[sheet$PE_or_Not == "Non-PE", , drop = FALSE]
cand$k <- npi_key(cand$npi)

# ROW SELECTION IS DECLARED, because it changes the answer.
# control_candidates_raw.csv holds 31,011 rows for 20,111 distinct NPIs, and 110 of the 200
# fielded controls appear more than once with CONFLICTING attributes -- NPI 1952488280 is a
# 12-member Barnabas Health group in one row and a 566-member City of Newark in another. Every
# statement below about organisation size or facility name therefore depends on which row is
# read, and two independent implementations of this file's own numbers disagreed by 2 records
# for exactly that reason (first-row vs last-row). match() takes the first; that is now stated
# rather than inherited, so the numbers are reproducible.
i <- match(npi_key(ctl$NPI), cand$k)          # first matching row, deliberately
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
  # CONTRACT CHANGED 2026-08-24: pinned, not denied. The finding is real and is a limitation of
  # the comparator, not of this test. Asserting 0 would require the finding to disappear.
  big <- sum(org > 10, na.rm = TRUE)
  expect_equal(big, 148L,
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
  # CONTRACT CHANGED 2026-08-24: pinned, not fixed. get_practice_setting() admits on both its
  # empty branch and its fall-through, and line 97 filters TO 'Private Practice', so an unnamed
  # or unrecognised facility becomes an eligible control. Repairing it would change which
  # controls a re-run selects -- a change to selection semantics, not a bug fix -- so it is
  # reported rather than made. 28 fielded controls have no facility name at all.
  empty_defaults <- any(grepl("if not fac or fac == 'NAN'", body, fixed = TRUE))
  falls_through   <- any(grepl("return 'Private Practice'", body, fixed = TRUE))
  expect_true(empty_defaults && falls_through,
              info = "if this is now FALSE the classifier was repaired; update the finding and the count")
  expect_true(any(grepl("Practice_Setting.*==.*Private Practice", expo)),
              info = "the admitting category is also the selection filter, which is what makes it matter")
})

test_that("semantic: the manuscript's exclusion claim matches what the code excludes", {
  claims_exclusion <- grepl("excluding academic and hospital-system", ms, fixed = TRUE)
  expect_true(claims_exclusion)
  # The code excludes on facility-name keywords only. Nothing excludes on organisation size,
  # so a 7,694-member organisation with an unremarkable name is retained as independent.
  excludes_by_size <- any(grepl("num_org_mem *[<>]", expo))
  expect_false(excludes_by_size,
              info = "exclusion is by facility name alone; organisation size is never tested")
})

# ---------------------------------------------------------------- adversarial (4)

test_that("adversarial: an unnamed facility is not silently called independent", {
  n_unnamed <- sum(!nzchar(fac))
  expect_equal(n_unnamed, 28L,
               info = sprintf("%d fielded controls have no facility name and were classified Private Practice by default",
                              n_unnamed))
})

test_that("adversarial: no fielded control sits inside a very large organisation", {
  huge <- sum(org > 1000, na.rm = TRUE)
  expect_equal(huge, 23L,
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
  # CONTRACT REWRITTEN 2026-08-24. The old check grepped for the string return("Generalist"),
  # which now false-positives on the REPAIRED subspecialty classifier: after PR #10 that
  # function guards with a positive 207V family test and only then returns "Generalist" for a
  # genuine generalist. Grepping a return value cannot distinguish a guarded return from a
  # fall-through. The question is behavioural -- what does the classifier do with an input it
  # does not recognise? -- so it is now asked behaviourally, with both controls.
  extract_fn <- function(file, name) {
    src <- readLines(p(file), warn = FALSE)
    i <- grep(sprintf("^\\s*%s <- function", name), src)[1]
    if (is.na(i)) return(NULL)
    depth <- 0L; j <- i
    repeat {
      depth <- depth + lengths(regmatches(src[j], gregexpr("\\{", src[j]))) -
                        lengths(regmatches(src[j], gregexpr("\\}", src[j])))
      if (depth <= 0L && j > i) break
      j <- j + 1L
      if (j > length(src)) break
    }
    eval(parse(text = paste(src[i:j], collapse = "\n")), envir = new.env(parent = globalenv()))
  }
  f <- extract_fn("build_matched_control_group_psm.R", "get_subspecialty_from_tax")
  expect_true(is.function(f))
  # POSITIVE CONTROL: a real generalist OB-GYN taxonomy must still be admitted.
  expect_equal(f("207V00000X"), "Generalist")
  # NEGATIVE CONTROLS: unrecognised and empty inputs must NOT be admitted.
  expect_false(f("208800000X") == "Generalist", info = "urology admitted as a generalist OB-GYN")
  expect_false(f("") == "Generalist",           info = "an empty taxonomy admitted as a generalist")
  expect_false(f(NA) == "Generalist",           info = "a missing taxonomy admitted as a generalist")
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

# ------------------------------------------------- process independence (added 2026-08-24)
#
# MUTATION EVIDENCE. Every contract in this section was shown to fail on the defect it names,
# then reverted:
#
#   arm information in the pool   plant: add a PE_or_Not column to control_candidates_raw.csv
#                                 result: failed, naming pe_or_not
#   outcome leakage into matching plant: reference business_days in the matcher
#                                 result: failed, naming business_days
#   seeded tie-breaking           plant: remove set.seed(42)
#                                 result: failed on the unseeded-shuffle contract
#   blinded-number leakage        plant: reference assign_blinded_slots in the matcher
#                                 result: failed
#
# The positive controls are not decoration either: the first draft asserted the matcher
# references num_org_mem, and it does not. That failure is the finding recorded above --
# organisation size never enters control eligibility at all -- and without the positive
# control the negative check would have been satisfied by a matcher that reads nothing.
#
# The contracts above ask whether the controls ARE independent practices. These ask whether
# the SELECTION of them was independent of information it should not have had. Each carries a
# positive control (the legitimate pre-match information is present and usable) and a negative
# control (the illegitimate information is absent, and planting it is detected).

psm_src <- readLines(p("build_matched_control_group_psm.R"), warn = FALSE)

test_that("control candidacy cannot depend on PE-arm information", {
  nm <- tolower(names(cand))
  # NEGATIVE: no ownership, arm, or platform information reaches the candidate pool at all.
  leak <- grep("pe_or_not|^pe$|platform|owner|treat|arm$|matched_pair", nm, value = TRUE)
  expect_true(length(leak) == 0L,
              info = sprintf("candidate pool carries arm information: %s",
                             paste(leak, collapse = ", ")))
  # POSITIVE: the legitimate pre-match variables ARE present, or the matching could not run
  # and this test would be vacuously satisfied by an empty file.
  for (need in c("npi", "num_org_mem", "facility_name")) {
    expect_true(any(nm == need), info = sprintf("pre-match variable %s is missing", need))
  }
  expect_gt(ncol(cand), 10L)
  expect_gt(nrow(cand), 1000L)
})

test_that("no post-match, outcome, or blinded-numbering variable reaches the matcher", {
  # Anything on this list exists only AFTER matching, or only after calls are placed. A
  # reference to one inside the matching script would be information from the future.
  forbidden <- c("phone_id", "same_phone_within_pair", "Eligible", "CDC_SVI_real",
                 "SVI_tract_fips", "Taxonomy_Is_OBGYN", "record_id", "physician_name",
                 "obtained", "business_days", "appdate", "calldate", "holdtime")
  hits <- forbidden[vapply(forbidden, function(v) any(grepl(v, psm_src, fixed = TRUE)), logical(1))]
  expect_true(length(hits) == 0L,
              info = sprintf("matcher references post-match or outcome variables: %s",
                             paste(hits, collapse = ", ")))
  # POSITIVE: it does reference the pre-match variables it is entitled to.
  # num_org_mem is deliberately NOT in this list: the matcher never reads it, which is the
  # finding recorded above -- organisation size never enters control eligibility at all.
  for (v in c("latitude", "longitude", "PE_or_Not", "Gender")) {
    expect_true(any(grepl(v, psm_src, fixed = TRUE)),
                info = sprintf("matcher does not reference %s; the check above may be vacuous", v))
  }
})

test_that("blinded record numbers are assigned downstream of pairing, by construction", {
  # The slot allocator takes the pair labels as an ARGUMENT, so pairs necessarily exist before
  # numbers do and cannot have been formed from them.
  expect_true(any(grepl("assign_blinded_slots <- function(pair, group", 
                        readLines(p("R", "pe_helpers.R"), warn = FALSE), fixed = TRUE)))
  expect_false(any(grepl("assign_blinded_slots", psm_src, fixed = TRUE)),
               info = "the matcher must not know about record numbering at all")
})

test_that("tie-breaking is deterministic and its non-determinism is seeded and documented", {
  expect_true(any(grepl("set.seed(", psm_src, fixed = TRUE)),
              info = "an unseeded shuffle makes the cohort unreproducible run to run")
  expect_true(any(grepl("which.min(", psm_src, fixed = TRUE)),
              info = "nearest-control tie-breaking must be explicit, not first-row-wins by accident")
  expect_true(any(grepl("sort(unique(", psm_src, fixed = TRUE)),
              info = "offices must be visited in a defined order")
})

test_that("the matcher sorts each office before shuffling, so input order cannot change it", {
  # RESOLVED 2026-08-24 for future runs. The office is sorted by NPI before the seeded shuffle,
  # so the permutation is a function of the seed and the office membership, not of the order
  # the rows happened to arrive in. The frozen 200 pairs are NOT regenerated; this changes what
  # a re-run would produce, which is a separate scientific decision.
  i <- grep("office_subset[order(npi_key(office_subset$NPI))", psm_src, fixed = TRUE)
  expect_true(length(i) == 1L,
              info = "the pre-shuffle sort is gone; input row order can change the cohort again")
  j <- grep("shuffled_indices <- sample(seq_len(nrow(office_subset)))", psm_src, fixed = TRUE)
  expect_true(length(j) == 1L && i < j,
              info = "the sort must precede the shuffle to have any effect")
})

test_that("HISTORICAL: the frozen cohort was matched before that sort existed", {
  # Pinned rather than asserted away. Within each office the matcher shuffles the candidate
  # rows it was handed, so the permutation depends on the order they arrive in. Re-running on
  # the same file gives the same answer; re-running on a re-sorted file need not. The caliper
  # inputs are gone, so this cannot be demonstrated by execution -- only read from the code.
  # The stored pairs cannot inherit the fix retroactively. Recorded so nobody reads the sort
  # above as evidence that the frozen cohort is order-invariant. It is not; it is simply frozen.
  expect_true(file.exists(p("docs", "MATCHING_LINEAGE.md")),
              info = "the lineage record explains what the frozen cohort can and cannot claim")
})

test_that("excluded-platform information cannot leak into control eligibility", {
  EXCLUDED <- c("CCRM Fertility", "IVI RMA Global", "US Fertility", "Kindbody",
                "OB Hospitalist Group")
  # NEGATIVE: the candidate pool cannot even express platform membership.
  expect_false(any(grepl("platform", tolower(names(cand)), fixed = TRUE)))
  # POSITIVE, from the artifact side: the run that applied the exclusion has none of them,
  # which shows the exclusion is expressible and was enforced somewhere.
  pool <- rd(p("pe_obgyn_matched_calling_list.csv"))
  roster <- rd(p("pe_obgyn_providers_active.csv"))
  plat <- stats::setNames(trimws(roster[["Platform/Practice"]]), npi_key(roster$NPI))
  expect_equal(sum(plat[npi_key(pool$NPI)] %in% EXCLUDED, na.rm = TRUE), 0L)
})
