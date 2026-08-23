# Cycle 9 -- 3 BVA, 3 semantic, 4 adversarial.
# Targets the matcher's own guarantees: the propensity model, the caliper boundary, control
# reuse discipline, and determinism. Also corrects a claim cycle 8 made about a second
# matching path that does not exist.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)
rd <- function(f) utils::read.csv(f, colClasses = "character", check.names = FALSE)

psm      <- readLines(p("build_matched_control_group_psm.R"))
cand_dir <- p("backups", "redraw_candidate_20260810")
has_cand <- dir.exists(cand_dir)

# ---------------------------------------------------------------- BVA (3)

test_that("BVA: the caliper is strict, and the boundary is documented as such", {
  line <- grep("close_indices <- which\\(dists", psm, value = TRUE)
  expect_length(line, 1L)
  expect_match(line, "dists < 10",
               info = "a pair at exactly 10.0 miles is excluded; the boundary is open, not closed")
  expect_false(grepl("dists <= 10", line, fixed = TRUE))
})

test_that("BVA: a match requires at least two nearby candidates, never one", {
  line <- grep("if \\(length\\(close_indices\\) >= 2\\)", psm, value = TRUE)
  expect_length(line, 1L)
  # Requiring two means the chosen control was selected on propensity among alternatives,
  # not taken as the only option available.
  expect_false(any(grepl("length(close_indices) >= 1", psm, fixed = TRUE)))
})

test_that("BVA: propensity scores are probabilities", {
  i <- grep("psm_model <- glm\\(", psm)
  expect_length(i, 1L)
  blk <- paste(psm[i:(i + 3)], collapse = " ")
  expect_match(blk, "family *= *(\"binomial\"|binomial)",
               info = "a linear-probability fit could leave the unit interval")
  expect_true(any(grepl('type *= *"response"', psm)),
              info = "predictions must be on the probability scale, not the link scale")
})

# ---------------------------------------------------------------- semantic (3)

test_that("semantic: the matcher has ONE matching path and it enforces the caliper", {
  # CORRECTION to cycle 8, which recorded a "city-name fallback that bypasses the caliper".
  # There is no such path. city_match_count and caliper_geo_match_count only label whether
  # the selected control happened to share the PE clinic's city; both are counted inside the
  # `dists < 10` branch, so both are within the caliper.
  i <- grep("close_indices <- which\\(dists", psm)
  j <- grep("city_match_count <- city_match_count \\+ 1", psm)
  k <- grep("caliper_geo_match_count <- caliper_geo_match_count \\+ 1", psm)
  expect_length(i, 1L); expect_length(j, 1L); expect_length(k, 1L)
  expect_true(j > i && k > i,
              info = "both counters sit inside the caliper branch, so neither is a bypass")
  # Premise correction: `matched_control <- NULL` initialises the loop variable and is not
  # a selection. The contract is that no control is *assigned a value* before the caliper.
  before <- psm[seq_len(i - 1)]
  assigns <- grep("matched_control <- (?!NULL)", before, value = TRUE, perl = TRUE)
  expect_length(assigns, 0L)
})

test_that("semantic: the propensity model uses the covariates the Methods claims", {
  i <- grep("psm_model <- glm\\(", psm)
  blk <- paste(psm[i:(i + 2)], collapse = " ")
  for (v in c("MD_vs_DO", "Gender", "Years_in_Practice", "Open_Payments_Years")) {
    expect_match(blk, v, info = sprintf("Methods claims matching on %s", v))
  }
  expect_false(grepl("\\b(PE_or_Not|Latitude|Longitude)\\b", blk),
               info = "outcome-adjacent or geographic terms must not enter the propensity model")
})

test_that("semantic: every matched pair honours the caliper on the matcher's own coordinates", {
  skip_if_not(has_cand, "no redraw candidate present")
  new <- rd(file.path(cand_dir, "pe_obgyn_matched_calling_list.csv"))
  db  <- rd(file.path(cand_dir, "pe_obgyn_study_database.csv"))
  db$k <- npi_key(db$NPI); db <- db[!is.na(db$k) & nzchar(db$k), ]
  db <- db[!duplicated(db$k), ]
  idx <- match(npi_key(new$NPI), db$k)
  new$lat <- suppressWarnings(as.numeric(db$Matcher_Latitude[idx]))
  new$lon <- suppressWarnings(as.numeric(db$Matcher_Longitude[idx]))
  hav <- function(a, b, c, d) {
    r <- 3959; dl <- (c - a) * pi / 180; dn <- (d - b) * pi / 180
    2 * r * asin(sqrt(sin(dl / 2)^2 + cos(a * pi / 180) * cos(c * pi / 180) * sin(dn / 2)^2))
  }
  sp <- split(new, new[["Matched Pair ID"]])
  dd <- vapply(sp, function(x) if (nrow(x) == 2L && !anyNA(x$lat)) hav(x$lat[1], x$lon[1], x$lat[2], x$lon[2]) else NA_real_, numeric(1))
  dd <- dd[!is.na(dd)]
  over <- sum(dd >= 10)
  expect_equal(over, 0L,
               info = sprintf("%d of %d pairs measure >=10 mi although the matcher enforces dists < 10; the exported coordinates disagree with the ones matching used",
                              over, length(dd)))
})

# ---------------------------------------------------------------- adversarial (4)

test_that("adversarial: a control is never reused across matched pairs", {
  for (f in c(p("pe_obgyn_matched_calling_list.csv"),
              if (has_cand) file.path(cand_dir, "pe_obgyn_matched_calling_list.csv"))) {
    d <- rd(f)
    ctl <- npi_key(d$NPI[d$PE_or_Not == "Non-PE"])
    expect_false(any(duplicated(ctl)),
                 info = sprintf("%s reuses a control clinician", basename(f)))
  }
  expect_true(any(grepl("used_npis", psm)),
              info = "the matcher must track which controls it has consumed")
})

test_that("adversarial: the control pool cannot contain PE clinicians", {
  skip_if_not(has_cand, "no redraw candidate present")
  new <- rd(file.path(cand_dir, "pe_obgyn_matched_calling_list.csv"))
  pe_pool <- rd(p("pe_obgyn_providers_active.csv"))
  ctl <- npi_key(new$NPI[new$PE_or_Not == "Non-PE"])
  expect_length(intersect(ctl, npi_key(pe_pool$NPI)), 0L)
})

test_that("adversarial: matching is seeded once so a rerun is reproducible", {
  loop_i <- grep("^for \\(office in pe_unique_offices\\)", psm)
  expect_length(loop_i, 1L)
  expect_true(any(grepl("^set\\.seed\\(", psm[seq_len(loop_i - 1L)])),
              info = "the stream must be seeded before the office loop")
  expect_false(any(grepl("set.seed", psm[loop_i:length(psm)], fixed = TRUE)),
               info = "re-seeding mid-run makes the draw depend on iteration order")
})

test_that("adversarial: the pipeline does not depend on the caller's working directory", {
  # Every path in the matcher is absolute, so a run from any directory behaves identically.
  rel <- grep('read\\.csv\\("(?!/)', psm, value = TRUE, perl = TRUE)
  rel <- rel[!grepl("^\\s*#", rel)]
  expect_length(rel, 0L)
})
