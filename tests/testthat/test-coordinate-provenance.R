# Cycle 8 -- 3 BVA, 4 semantic, 3 adversarial.
# Cycle 7 fixed the geocoder. This cycle asks a question cycles 5 and 6 did not: WHICH
# coordinates were being measured. The matcher computes coordinates for its caliper but
# never writes them out, so the Latitude/Longitude columns audited in cycles 5 and 6 came
# from a different, downstream step. Two coordinate sources, one persisted, neither
# reconciled.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)
rd <- function(f) utils::read.csv(f, colClasses = "character", check.names = FALSE)

psm      <- readLines(p("build_matched_control_group_psm.R"))
db_old   <- rd(p("pe_obgyn_study_database.csv"))
cand_dir <- p("backups", "redraw_candidate_20260810")
has_cand <- dir.exists(cand_dir)

# ---------------------------------------------------------------- BVA (3)

test_that("BVA: years in practice stay inside a human career span", {
  y <- suppressWarnings(as.numeric(db_old[["Years in Practice"]]))
  y <- y[!is.na(y)]
  expect_true(length(y) > 0L)
  expect_true(all(y >= 0), info = "a negative career length is impossible")
  expect_true(all(y <= 70), info = "a 70+ year practising career is a data error, not a long career")
})

test_that("BVA: open payments years cannot exceed the programme's lifetime", {
  op <- suppressWarnings(as.numeric(db_old[["Open Payments Years"]]))
  op <- op[!is.na(op)]
  expect_true(length(op) > 0L)
  expect_true(all(op >= 0))
  # Open Payments began reporting in 2013; through 2026 that is at most 14 distinct years.
  expect_true(all(op <= 14),
              info = "more Open Payments years than the programme has existed indicates a counting error")
})

test_that("BVA: the matched calling list has exactly two arms per pair, at both cohort sizes", {
  for (f in c(p("pe_obgyn_matched_calling_list.csv"),
              if (has_cand) file.path(cand_dir, "pe_obgyn_matched_calling_list.csv"))) {
    d <- rd(f)
    tb <- table(d[["Matched Pair ID"]])
    expect_true(all(tb == 2L),
                info = sprintf("%s has pairs of the wrong size", basename(f)))
    expect_equal(as.integer(table(d$PE_or_Not)[["PE"]]),
                 as.integer(table(d$PE_or_Not)[["Non-PE"]]))
  }
})

# ---------------------------------------------------------------- semantic (4)

test_that("semantic: the matcher persists the coordinates its caliper relied on", {
  # The caliper is the study's central geographic claim. If the coordinates behind it are
  # never written out, no downstream consumer, reviewer or test can verify the claim, and
  # any audit silently measures some other source instead. That is exactly what happened.
  writes_coords <- any(grepl("Latitude *=|latitude *=", psm)) &&
                   any(grepl("study_output_csv", psm))
  expect_true(writes_coords,
              info = "PSM computes latitude/longitude for matching but exports neither")
})

test_that("semantic: the persisted coordinates come from the matcher, not a later step", {
  # apply_hq_distance.R and calculate_pair_distances.R also touch Latitude. If matching and
  # auditing use different sources, agreement between them is coincidence.
  writers <- c("apply_hq_distance.R", "calculate_pair_distances.R")
  present <- writers[file.exists(p(writers))]
  expect_true(length(present) > 0L)
  psm_writes <- any(grepl("\\$Latitude *<-", psm))
  expect_true(psm_writes,
              info = sprintf("Latitude is written by %s but not by the matcher",
                             paste(present, collapse = ", ")))
})

test_that("semantic: a redraw carries the same columns the pipeline downstream expects", {
  skip_if_not(has_cand, "no redraw candidate present")
  new <- rd(file.path(cand_dir, "pe_obgyn_study_database.csv"))
  missing <- setdiff(names(db_old), names(new))
  expect_length(missing, 0L)
})

test_that("semantic: the Python and R address normalisers agree on suite stripping", {
  # match_all_providers.py already used the word-anchored form; add_symmetric_backups.py
  # still carries the unanchored one fixed in R at cycle 1.
  py <- readLines(p("add_symmetric_backups.py"))
  rx <- grep("SUITE\\|STE\\|UNIT", py, value = TRUE)
  expect_true(length(rx) > 0L)
  expect_true(all(grepl("\\\\b", rx)),
              info = "add_symmetric_backups.py:34 still strips suites without word boundaries")
})

# ---------------------------------------------------------------- adversarial (3)

test_that("adversarial: a redraw does not silently change cohort scale", {
  skip_if_not(has_cand, "no redraw candidate present")
  old_pairs <- length(unique(rd(p("pe_obgyn_matched_calling_list.csv"))[["Matched Pair ID"]]))
  new_pairs <- length(unique(rd(file.path(cand_dir, "pe_obgyn_matched_calling_list.csv"))[["Matched Pair ID"]]))
  expect_true(abs(new_pairs - old_pairs) / old_pairs < 0.25,
              info = sprintf("cohort moved from %d to %d pairs", old_pairs, new_pairs))
})

test_that("adversarial: no clinician is matched to themselves or duplicated within the pool", {
  for (f in c(p("pe_obgyn_matched_calling_list.csv"),
              if (has_cand) file.path(cand_dir, "pe_obgyn_matched_calling_list.csv"))) {
    d <- rd(f)
    expect_false(any(duplicated(npi_key(d$NPI))),
                 info = sprintf("%s repeats an NPI", basename(f)))
    sp <- split(npi_key(d$NPI), d[["Matched Pair ID"]])
    expect_true(all(vapply(sp, function(x) length(unique(x)) == length(x), logical(1))),
                info = "a pair whose two members are the same clinician is not a comparison")
  }
})

test_that("adversarial: the redraw's controls are drawn from the control pool, not the PE cohort", {
  skip_if_not(has_cand, "no redraw candidate present")
  new <- rd(file.path(cand_dir, "pe_obgyn_matched_calling_list.csv"))
  pe  <- npi_key(new$NPI[new$PE_or_Not == "PE"])
  ctl <- npi_key(new$NPI[new$PE_or_Not == "Non-PE"])
  expect_length(intersect(pe, ctl), 0L)
  expect_equal(length(pe), length(ctl))
})
