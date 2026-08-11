# Guards against a simulated covariate being carried as a measurement.
#
# The CDC_SVI column shipped in the fielded sheet was not data. It was Normal(0.434, 0.193)
# truncated to [0.01, 0.99], generated the same way apply_demographic_covariates.R generates
# the Tract_* and County_* columns, which that script's own header describes as "standard
# fallback simulations to ensure full dataset completeness".
#
# The cycle-16 tests in test-enrichment-covariates.R did not catch it. They asserted that SVI
# lay in [0,1], that it was near-continuous, and that its median was within 0.25 of 0.5 -- all
# of which a plausible-looking simulation passes trivially. This file asks the question those
# tests did not: is the column DISTRIBUTED like the thing it claims to be, and does it carry
# provenance? A percentile rank is uniform by construction. Normality is disqualifying.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)

sheet <- utils::read.csv(p("pe_obgyn_final_calling_sheet_200.csv"), check.names = FALSE)
real  <- suppressWarnings(as.numeric(sheet$CDC_SVI_real))
obs   <- real[!is.na(real)]

test_that("BVA: the reconstructed SVI is a percentile rank in range", {
  expect_true("CDC_SVI_real" %in% names(sheet))
  expect_true(length(obs) > 0L)
  expect_true(all(obs >= 0 & obs <= 1),
              info = sprintf("outside [0,1]: min %.4f max %.4f", min(obs), max(obs)))
})

test_that("BVA: no row is pinned to a truncation floor or ceiling", {
  # pmax(0.01, pmin(0.99, rnorm(...))) leaves a visible pile at the bounds. The simulated
  # column had six rows at exactly 0.010 and one at exactly 0.990.
  #
  # Premise correction: the first version of this test forbade ANY tie at the extremes, and
  # failed on real data. Two clinicians in Little Silver NJ share one address, therefore one
  # tract, therefore one SVI of 0.0125 -- a legitimate tie, and 57 of the 400 fielded
  # clinicians share a tract with someone else. The clamp signature is not a tie; it is a pile
  # at a ROUND bound that the underlying data would never produce exactly.
  expect_false(isTRUE(all.equal(min(obs), 0.01)) || isTRUE(all.equal(max(obs), 0.99)),
               info = sprintf("extremes are %.4f and %.4f; 0.01 or 0.99 is a pmax/pmin clamp",
                              min(obs), max(obs)))
  expect_true(mean(obs == min(obs)) < 0.02,
              info = sprintf("%d of %d rows (%.1f%%) sit at the minimum %.4f",
                             sum(obs == min(obs)), length(obs),
                             100 * mean(obs == min(obs)), min(obs)))
  expect_true(mean(obs == max(obs)) < 0.02,
              info = sprintf("%d of %d rows (%.1f%%) sit at the maximum %.4f",
                             sum(obs == max(obs)), length(obs),
                             100 * mean(obs == max(obs)), max(obs)))
})

test_that("semantic: SVI is distributed like a percentile, not like a Normal draw", {
  ks_unif <- suppressWarnings(stats::ks.test(obs, "punif", 0, 1)$p.value)
  expect_true(ks_unif > 0.01,
              info = sprintf("KS against Uniform(0,1) rejects at p = %.4g; a national percentile rank should not",
                             ks_unif))
})

test_that("semantic: every non-missing SVI value names its source and its geography", {
  ok <- !is.na(real)
  expect_true(all(nzchar(trimws(ifelse(is.na(sheet$SVI_source[ok]), "", sheet$SVI_source[ok])))),
              info = "a covariate with no recorded source cannot be distinguished from a simulation")
  expect_true(all(grepl("CDC/ATSDR SVI", sheet$SVI_source[ok])))
  expect_true(all(nzchar(trimws(ifelse(is.na(sheet$SVI_geocode_via[ok]), "",
                                       sheet$SVI_geocode_via[ok])))),
              info = "the geocoding method determines the precision of the value and must be recorded")
})

test_that("adversarial: SVI missingness is independent of exposure", {
  # This is the defect the reconstruction exists to remove. The simulated column was present
  # for 200/200 PE clinicians and 106/200 controls -- missingness perfectly confounded with
  # the exposure, so a complete-case fit of the SAP model would have deleted 47% of the
  # control arm on a basis related to how those controls entered the sample.
  tb <- table(sheet$PE_or_Not, ifelse(is.na(real), "missing", "has"))
  pv <- stats::fisher.test(tb)$p.value
  expect_true(pv > 0.05,
              info = sprintf("SVI missingness differs by arm (Fisher p = %.3g):\n%s",
                             pv, paste(utils::capture.output(print(tb)), collapse = "\n")))
})

test_that("adversarial: the reconstruction reaches nearly every fielded clinician", {
  expect_true(mean(!is.na(real)) > 0.95,
              info = sprintf("only %d of %d fielded clinicians have a real SVI",
                             sum(!is.na(real)), nrow(sheet)))
  both <- tapply(!is.na(real), sheet[["Matched Pair ID"]], all)
  expect_true(sum(both) >= 190L,
              info = sprintf("%d of %d pairs are complete; a complete-case model keeps only these",
                             sum(both), length(both)))
})

test_that("adversarial: the simulated column is never silently reused as the real one", {
  # CDC_SVI is deliberately left in place so nothing downstream changes meaning by surprise.
  # The contract is that it is never equal to the reconstructed column, which would mean the
  # reconstruction had quietly copied it.
  old <- suppressWarnings(as.numeric(sheet$CDC_SVI))
  both <- !is.na(old) & !is.na(real)
  expect_true(sum(both) > 0L)
  expect_false(isTRUE(all.equal(old[both], real[both])),
               info = "the reconstructed column is identical to the simulated one")
  expect_true(stats::cor(old[both], real[both]) < 0.2,
              info = sprintf("the simulated and reconstructed columns correlate at r = %.3f, which they should not",
                             stats::cor(old[both], real[both])))
})
