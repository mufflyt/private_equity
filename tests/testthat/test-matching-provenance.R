# Cycle 3 -- 3 BVA, 3 semantic, 4 adversarial.
# Moves off code written today and into the matching/provenance layer: the geocoding that
# backs the "strict 10-mile radius" claim, the fail-open subspecialty filter, wall-clock
# dependence, and the input contract the pipeline silently assumes.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)
rd <- function(f) utils::read.csv(f, check.names = FALSE, colClasses = "character")

sheet <- rd(p("pe_obgyn_final_calling_sheet_200.csv"))
db    <- rd(p("pe_obgyn_study_database.csv"))
psm   <- readLines(p("build_matched_control_group_psm.R"))

city_of  <- function(d) toupper(trimws(ifelse(nzchar(d[["DAC City"]]), d[["DAC City"]], d[["NPPES City"]])))
state_of <- function(d) toupper(trimws(ifelse(nzchar(d[["DAC State"]]), d[["DAC State"]], d[["NPPES State"]])))

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
  coord <- paste(db$Latitude, db$Longitude, sep = ",")
  ok <- nzchar(db$Latitude) & nzchar(db$Longitude) & nzchar(key)
  per_city <- tapply(coord[ok], key[ok], function(x) length(unique(x)))
  expect_true(all(per_city >= 1L))
  expect_true(any(per_city == 1L),
              info = "cities where every clinician shares one coordinate are the zero-distance case")
})

# ---------------------------------------------------------------- semantic (3)

test_that("semantic: geocoding is city-level, so a 10-mile caliper cannot discriminate within a city", {
  key <- paste(city_of(db), state_of(db), sep = "_")
  coord <- paste(db$Latitude, db$Longitude, sep = ",")
  ok <- nzchar(db$Latitude) & nzchar(db$Longitude) & nzchar(key)
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
  # Premise correction: the contract is clinician identity, which requires the key to be
  # normalised. The raw columns disagree because the study database was written by pandas
  # with a float NPI ("1003038688.0") while the calling sheets carry integers. Both facts
  # are pinned: the semantic contract holds under npi_key, and the raw-join hazard is
  # asserted so nobody joins on the bare column and silently gets an empty result.
  expect_length(setdiff(npi_key(sheet$NPI), npi_key(db$NPI)), 0L)
  expect_length(setdiff(sheet$`Matched Pair ID`, db$Matched_Pair_Group), 0L)
  expect_equal(sum(sheet$NPI %in% db$NPI), 0L,
               info = "raw join matches nothing; this is the float-vs-int hazard, not a coincidence")
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
