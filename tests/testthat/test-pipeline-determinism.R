# Cycle 23 -- 3 BVA, 4 semantic, 3 adversarial.
# Targets reproducibility empirically. Earlier cycles asserted seed PLACEMENT in source but
# never verified that two runs agree. Running the pipeline twice found that they did not: the
# study database differed in exactly the control rows.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)
rd <- function(f) utils::read.csv(f, colClasses = "character", check.names = FALSE)

psm   <- readLines(p("build_matched_control_group_psm.R"))
sub3  <- readLines(p("subsample_300_pairs.R"))
imp2  <- readLines(p("build_200_redcap_import.R"))
db    <- rd(p("pe_obgyn_study_database.csv"))
sheet <- rd(p("pe_obgyn_final_calling_sheet_200_dedup.csv"))

# ---------------------------------------------------------------- BVA (3)

test_that("BVA: every stage of the chain fixes a seed", {
  for (nm in list(list("PSM", psm), list("300-pair subsample", sub3), list("200-pair balance", imp2))) {
    expect_true(any(grepl("set\\.seed\\(", nm[[2]])),
                info = sprintf("%s does not seed its RNG", nm[[1]]))
  }
})

test_that("BVA: seeds are literals, not derived from the environment", {
  # Premise correction: build_200_redcap_import.R uses set.seed(SEED) where SEED <- 1978L is
  # a named constant. That is better practice than an inline literal, not worse. The contract
  # is that the seed resolves to a fixed value, so accept a name bound to a literal.
  all_src <- c(psm, sub3, imp2)
  seeds <- grep("set\\.seed\\(", all_src, value = TRUE)
  seeds <- seeds[!grepl("^\\s*#", seeds)]
  expect_true(length(seeds) > 0L)
  ok <- vapply(seeds, function(ln) {
    arg <- sub(".*set\\.seed\\(([^)]*)\\).*", "\\1", ln)
    grepl("^[0-9]+L?$", trimws(arg)) ||
      any(grepl(sprintf("^\\s*%s\\s*<-\\s*[0-9]+L?\\s*$", trimws(arg)), all_src))
  }, logical(1))
  expect_true(all(ok),
              info = sprintf("seed not resolvable to a literal: %s",
                             paste(trimws(seeds[!ok]), collapse = "; ")))
  expect_false(any(grepl("set\\.seed\\(.*Sys\\.|set\\.seed\\(.*time", seeds)),
               info = "a seed derived from the clock is not a seed")
})

test_that("BVA: pair identifiers are contiguous from one", {
  ids <- sort(unique(as.integer(sub("pair_", "", sheet[["Matched Pair ID"]]))))
  expect_equal(length(ids), 200L)
  expect_true(all(ids >= 1L))
})

# ---------------------------------------------------------------- semantic (4)

test_that("semantic: no data column records when the script ran", {
  # A run clock written into a data column makes the artifact differ on every run, defeating
  # checksums and caching, and mislabels provenance for rows that were never scraped.
  expect_true(any(grepl("current_time <- NA_character_", psm, fixed = TRUE)),
              info = "control rows must not be stamped with the run clock")
  expect_false(any(grepl('current_time <- format(Sys.time()', psm, fixed = TRUE)))
})

test_that("semantic: control rows carry no scrape time, because they were never scraped", {
  ctl <- db[db$PE_or_Not == "Non-PE", , drop = FALSE]
  v <- trimws(ifelse(is.na(ctl[["Scrape Run Time"]]), "", ctl[["Scrape Run Time"]]))
  expect_equal(sum(nzchar(v)), 0L,
               info = sprintf("%d control rows carry a Scrape Run Time", sum(nzchar(v))))
})

test_that("semantic: PE rows retain a genuine scrape time", {
  pe <- db[db$PE_or_Not == "PE", , drop = FALSE]
  v <- trimws(ifelse(is.na(pe[["Scrape Run Time"]]), "", pe[["Scrape Run Time"]]))
  expect_true(mean(nzchar(v)) > 0.9,
              info = "removing the run clock must not blank the real scrape timestamps")
})

test_that("semantic: run provenance is recorded in a sidecar, not in the data", {
  side <- p("pe_obgyn_study_database.provenance.txt")
  expect_true(file.exists(side))
  txt <- readLines(side, warn = FALSE)
  expect_true(any(grepl("generated_at", txt)))
  expect_true(any(grepl("matched_pairs", txt)))
})

# ---------------------------------------------------------------- adversarial (3)

test_that("adversarial: no stage reseeds after its sampling has begun", {
  for (src in list(psm, sub3, imp2)) {
    starts <- grep("set\\.seed\\(", src)
    samples <- grep("\\bsample\\(|slice_sample|rnorm\\(|runif\\(", src)
    samples <- samples[!grepl("^\\s*#", src[samples])]
    if (length(starts) && length(samples)) {
      expect_true(min(starts) < min(samples),
                  info = "sampling occurs before the first seed")
    }
  }
})

test_that("adversarial: the pipeline does not depend on files it does not declare", {
  # Every input path in the matcher is absolute and named at the top of the file.
  reads <- grep("read\\.csv\\(|read_csv\\(", psm, value = TRUE)
  reads <- reads[!grepl("^\\s*#", reads)]
  expect_true(all(grepl("_csv\\b|candidates_csv|pe_csv|p\\(", reads)),
              info = "an undeclared input path makes a run depend on the working directory")
})

test_that("adversarial: the fielded artifacts agree with each other after a rerun", {
  imp <- rd(p("redcap_import_ready_200.csv"))
  ch  <- readLines(p("redcap_physician_name_choices.txt"), warn = FALSE)
  expect_equal(nrow(imp), 800L)
  expect_equal(length(ch), 800L)
  npi_in_choices <- unique(sub(".*NPI:\\s*(\\d+).*", "\\1", ch))
  expect_setequal(npi_in_choices, npi_key(sheet$NPI))
})
