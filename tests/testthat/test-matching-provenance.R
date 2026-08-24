# Cycle 3 -- 3 BVA, 3 semantic, 4 adversarial.
# Moves off code written today and into the matching/provenance layer: the geocoding that
# backs the "strict 10-mile radius" claim, the fail-open subspecialty filter, wall-clock
# dependence, and the input contract the pipeline silently assumes.

# MUTATION EVIDENCE (2026-08-24). A green scientific test is not evidence unless it has been
# shown to fail on the defect it names. Both contracts changed in this file were checked by
# planting a violation, confirming the failure and its reason, then reverting:
#
#   city-level geocoding   plant: give every clinician a unique coordinate
#                          result: share fell to 0.358, contract failed (-0.142 below 0.5)
#   provenance gap         plant: delete one fielded clinician's row from the study database
#                          result: missing_npi 137 -> 138, contract failed with that exact diff
#
# Before the col_ci fix below, both geocoding contracts had never read a coordinate at all:
# db$Latitude was NULL on a database spelling the column "latitude", nzchar(NULL) is
# logical(0), and any() of nothing is FALSE while mean() of nothing is NaN. They failed while
# appearing to test 1397 clinicians.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)
rd <- function(f) utils::read.csv(f, check.names = FALSE, colClasses = "character")

sheet <- rd(p("pe_obgyn_final_calling_sheet_200_dedup.csv"))
db    <- rd(p("pe_obgyn_study_database.csv"))
psm   <- readLines(p("build_matched_control_group_psm.R"))

city_of  <- function(d) toupper(trimws(ifelse(nzchar(d[["DAC City"]]), d[["DAC City"]], d[["NPPES City"]])))
state_of <- function(d) toupper(trimws(ifelse(nzchar(d[["DAC State"]]), d[["DAC State"]], d[["NPPES State"]])))

# Coordinates are read case-insensitively. pe_obgyn_study_database.csv spells them
# "latitude"/"longitude"; db$Latitude is therefore NULL, nzchar(NULL) is logical(0), and the
# two geocoding contracts below silently evaluated an empty vector -- any() on nothing is
# FALSE and mean() on nothing is NaN, so they failed while appearing to test the data. They
# had never looked at a single coordinate. See col_ci() in R/pe_helpers.R.
db_lat <- col_ci(db, "latitude")
db_lon <- col_ci(db, "longitude")
stopifnot(!is.null(db_lat), !is.null(db_lon))

# ---------------------------------------------------------------- BVA (3)

test_that("BVA: an address consisting only of a designator yields no key", {
  only_desig <- data.frame(`NPPES Address 1` = c("SUITE 400", "STE 12", "FL 3"),
                           `NPPES City` = "MIAMI", `NPPES State` = "FL",
                           `NPPES Zip` = "33130", check.names = FALSE)
  expect_true(all(is.na(address_key(only_desig))),
              info = "stripping the designator leaves nothing; that must be NA, not a shared empty key")
})

test_that("BVA: a ZIP of exactly five digits is required, not merely five characters", {
  d <- function(z) data.frame(`NPPES Address 1` = "100 MAIN ST", `NPPES City` = "MIAMI",
                              `NPPES State` = "FL", `NPPES Zip` = z, check.names = FALSE)
  expect_true(is.na(address_key(d("ABCDE"))), info = "non-numeric ZIP is not a ZIP")
  expect_true(is.na(address_key(d("331"))))
  expect_match(address_key(d("03313")), "_03313$", info = "a leading zero must survive")
})

test_that("BVA: matched-pair distance has a real zero, and zeros are common", {
  key <- paste(city_of(db), state_of(db), sep = "_")
  coord <- paste(db_lat, db_lon, sep = ",")
  ok <- nzchar(db_lat) & nzchar(db_lon) & nzchar(key)
  per_city <- tapply(coord[ok], key[ok], function(x) length(unique(x)))
  expect_true(all(per_city >= 1L))
  expect_true(any(per_city == 1L),
              info = "cities where every clinician shares one coordinate are the zero-distance case")
})

# ---------------------------------------------------------------- semantic (3)

test_that("semantic: geocoding is city-level, so a 10-mile caliper cannot discriminate within a city", {
  key <- paste(city_of(db), state_of(db), sep = "_")
  coord <- paste(db_lat, db_lon, sep = ",")
  ok <- nzchar(db_lat) & nzchar(db_lon) & nzchar(key)
  per_city <- tapply(coord[ok], key[ok], function(x) length(unique(x)))
  share <- mean(per_city == 1L)

  # This is a property of the data, asserted so that nobody later claims address-level
  # precision without the geocoding actually being address-level.
  expect_gt(share, 0.5)
  expect_true(any(grepl("10-mile|10 mile", readLines(p("manuscript", "manuscript_cite.md")))),
              info = "the Methods still asserts a 10-mile radius that this geocoding cannot support")
})

test_that("semantic: the subspecialty filter fails open, admitting unknown taxonomies as generalists", {
  fn_start <- grep("^get_subspecialty_from_tax", psm)[1]
  body_txt <- paste(psm[fn_start:(fn_start + 10)], collapse = " ")
  expect_match(body_txt, 'return\\("Generalist"\\)',
               info = "an unrecognised taxonomy code is classified Generalist")
  known <- c("207VE0102X", "207VX0201X", "207VM2500X", "207VF0040X")
  for (k in known) expect_match(body_txt, k, info = sprintf("%s must still be excluded", k))
  # A taxonomy that is neither blank nor one of the four is silently a generalist. Any new
  # subspecialty code CMS issues enters the cohort without anyone noticing.
  expect_false(grepl("\\b(stop|warning)\\(", body_txt),
               info = "no signal is raised for an unrecognised taxonomy")
})

test_that("semantic: no clinician appears in both ownership arms", {
  pe  <- sheet$NPI[sheet$PE_or_Not == "PE"]
  ctl <- sheet$NPI[sheet$PE_or_Not == "Non-PE"]
  expect_length(intersect(pe, ctl), 0L)
  expect_length(intersect(db$NPI[db$PE_or_Not == "PE"], db$NPI[db$PE_or_Not == "Non-PE"]), 0L)
})

# ---------------------------------------------------------------- adversarial (4)

test_that("adversarial: pipeline results must not depend on the wall-clock year", {
  # Sys.time() recording *when* a run happened is provenance and is fine. Sys.Date()
  # feeding a computed quantity is not: the cohort would change on 1 January.
  hits <- grep("Sys\\.Date\\(\\)", psm, value = TRUE)
  hits <- hits[!grepl("^\\s*#", hits)]
  expect_length(hits, 0L)
  expect_true(any(grepl("^STUDY_YEAR *<- *[0-9]{4}", psm)),
              info = "the study year must be pinned to a literal, not read from the clock")
})

test_that("adversarial: the control-candidate input carries the columns matching requires", {
  # KNOWN OPEN BLOCKER (see TESTING_LEDGER.md, out-of-band entry). The matching step
  # applies a 10-mile geographic caliper, but control_candidates_raw.csv has no
  # coordinates, so the caliper never fires and the cohort cannot be reproduced
  # (2 pairs regenerated vs 511 on disk). Preserved as a failing test rather than
  # weakened, because the fix requires input data the repository does not contain.
  cand <- utils::read.csv(p("control_candidates_raw.csv"), nrows = 1, check.names = FALSE)
  expect_true(any(grepl("^lat|latitude", names(cand), ignore.case = TRUE)),
              info = "no latitude column: the 10-mile caliper cannot fire on this input")
})

test_that("adversarial: every fielded clinician exists in the study database", {
  # This test previously PINNED the float-vs-int hazard, asserting that a raw join matched
  # nothing. The hazard has since been fixed at source: match_all_providers.py now casts NPI
  # to pandas' nullable Int64 so it is written without a decimal, and the nine affected
  # artifacts were normalised. The contract is therefore inverted: the raw join must now
  # succeed, and normalising must remain a no-op rather than a repair.
  # The float-vs-int hazard IS fixed, and that part of the contract holds absolutely.
  expect_false(any(grepl(".", sheet$NPI, fixed = TRUE)))
  expect_false(any(grepl(".", db$NPI, fixed = TRUE)))

  # CONTRACT SPLIT 2026-08-24. What remains is MISSING PROVENANCE, not incorrect matching, and
  # the two must not be conflated. 137 of the 400 fielded clinicians and 18 of the 200 fielded
  # pairs have no row in pe_obgyn_study_database.csv -- the post-exclusion, matched database
  # that the study frame is supposed to be drawn from.
  #
  # It is tempting to close this by pointing at pe_obgyn_study_database_with_churn.csv, which
  # does contain all 400 NPIs and all 200 pair groups. That would be reconstruction by
  # inference and it would be wrong: the _with_churn build carries 1537 PE rows including 215
  # clinicians from the five protocol-excluded platforms, so it is the PRE-exclusion universe
  # with churn columns appended, not a fuller study database. Appearing in it is not evidence
  # of having passed the exclusion or the matching. The narrow database (938 PE rows) and the
  # matched pool (459 pairs) both contain zero excluded-platform clinicians, which is what
  # tells them apart.
  #
  # So the gap is recorded at its true size rather than closed. Any further drift fails here.
  missing_npi  <- setdiff(npi_key(sheet$NPI), npi_key(db$NPI))
  missing_pair <- setdiff(sheet$`Matched Pair ID`, db$Matched_Pair_Group)
  expect_equal(length(missing_npi), 137L,
               info = sprintf("%d fielded clinicians have no row in the matched study database",
                              length(missing_npi)))
  expect_equal(length(missing_pair), 18L,
               info = sprintf("%d fielded pairs have no group in the matched study database",
                              length(missing_pair)))
  # Whatever their provenance, the 263 that DO trace must trace cleanly -- a partial join here
  # would be the float hazard returning, and is a different defect from an absent row.
  traced <- intersect(npi_key(sheet$NPI), npi_key(db$NPI))
  expect_equal(length(traced), nrow(sheet) - length(missing_npi))
  expect_true(all(traced %in% npi_key(db$NPI)))
})

test_that("adversarial: manuscript Table 4 stays consistent with its own Tables 2 and 3", {
  txt <- paste(readLines(p("manuscript", "manuscript_cite.md")), collapse = "\n")
  odds <- function(a, b) (a[1] / a[2]) / (b[1] / b[2])
  cb <- c(197, 3); pb <- c(198, 2); cm <- c(145, 55); pm <- c(82, 118)
  want <- c(odds(pm, cm), odds(cm, cb), odds(pb, cb),
            odds(pm, cm) / odds(pb, cb), 23.4 / 12.1, 14.5 / 12.1,
            (36.8 / 14.5) / (23.4 / 12.1))
  for (v in want)
    expect_true(grepl(sprintf("[%.2f]", v), txt, fixed = TRUE),
                info = sprintf("Table 4 must state [%.2f], implied by the cell values", v))
})
