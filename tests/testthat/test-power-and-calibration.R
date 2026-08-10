# Cycle 4 -- 4 BVA, 3 semantic, 3 adversarial.
# Targets the power/calibration layer, which justified the 200-pair sample size, plus the
# derived truth constants in the dry-run analysis. A power analysis that overstates power
# is a scientific error even though every line of it runs without complaint.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)

pw  <- readLines(p("run_new_power_analysis.R"))
dr  <- readLines(p("dry_run_analysis.R"))
res <- utils::read.csv(p("power_analysis_new_results.csv"))

# ---------------------------------------------------------------- BVA (4)

test_that("BVA: the negative-binomial theta is undefined when variance does not exceed the mean", {
  theta <- function(mu, sd) mu^2 / (sd^2 - mu)
  expect_gt(theta(12.1, 6.8), 0)
  # Premise correction: sqrt(10)^2 - 10 is 1.78e-15, not 0, so theta is a finite 5.6e16
  # rather than Inf. The hazard is the explosion, not the infinity, and a float-exact
  # equality test would have been the wrong contract.
  expect_true(theta(10, sqrt(10)) > 1e12,
              info = "variance approaching the mean makes NB theta explode toward Poisson")
  expect_true(theta(10, 2) < 0,
              info = "underdispersed input yields a negative theta, which is not a valid NB size")
  # dry_run_analysis.R averages theta across four cells with no guard on this boundary.
  expect_false(any(grepl("sd\\^2 *[<>]=? *mu|is.finite\\(th\\)|stopifnot.*th", dr)),
               info = "documents that no guard exists; a single underdispersed cell would poison the mean")
})

test_that("BVA: the hardcoded theta constants match their stated derivation", {
  expect_equal(round(23^2 / (100 - 23), 2), 6.87)
  expect_equal(round(23^2 / (400 - 23), 2), 1.40)
  expect_true(any(grepl("theta_val *<- *6\\.87", pw)))
  expect_true(any(grepl("theta_val *<- *1\\.40", pw)))
})

test_that("BVA: the power grid covers the sample size actually fielded", {
  expect_true(200L %in% res$Pairs,
              info = "the fielded design is 200 pairs; power must be reported at that point")
  expect_true(all(res$Total_Calls == 2L * res$Physicians))
  expect_true(all(res$Physicians == 2L * res$Pairs))
  expect_true(all(res$Power >= 0 & res$Power <= 1))
})

test_that("BVA: coalesce_cols takes the first non-blank in priority order", {
  d <- data.frame(a = c("", "N/A", "first"), b = c("second", "second", "second"),
                  stringsAsFactors = FALSE)
  expect_equal(coalesce_cols(d, c("a", "b")), c("second", "second", "first"),
               info = "a later column must fill in only where the earlier one is blank")
  expect_equal(coalesce_cols(d, c("missing_col", "b")), rep("second", 3L),
               info = "an absent column is skipped, not an error")
})

# ---------------------------------------------------------------- semantic (3)

test_that("semantic: the power simulation must analyse the correlation it generates", {
  # It draws one random intercept per physician and gives each physician two calls, then
  # fits glm.nb, which assumes independent observations. Ignoring within-physician
  # correlation understates the standard errors and therefore OVERSTATES power, which is
  # the number that justified the 200-pair sample size.
  simulates_re <- any(grepl("u_j *<- *rep\\(rnorm", pw))
  expect_true(simulates_re, info = "the simulation does generate a physician random intercept")
  fits_marginal <- any(grepl("glm\\.nb\\(", pw))
  fits_clustered <- any(grepl("glmer\\.nb\\(|glmmTMB\\(|\\(1 *\\| *physician\\)|vcovCL|sandwich", pw))
  expect_false(simulates_re && fits_marginal && !fits_clustered,
               info = "correlated data fitted with an independence model: reported power is anticonservative")
})

test_that("semantic: every declared effect actually enters the linear predictor", {
  declared <- grep("^beta_[a-z_]+ *<-", pw, value = TRUE)
  declared <- sub(" *<-.*", "", declared)
  eta_i <- grep("eta *<-", pw)
  eta_block <- paste(pw[eta_i:(eta_i + 6)], collapse = " ")
  unused <- declared[!vapply(declared, function(b) grepl(b, eta_block, fixed = TRUE), logical(1))]
  expect_length(unused, 0L)
})

test_that("semantic: the dry-run truth constants equal the values implied by the cells", {
  src <- paste(dr, collapse = "\n")
  expect_true(grepl("TRUE_IRR_INT", src) && grepl("TRUE_OR_INT", src))
  irr <- (36.8 / 14.5) / (23.4 / 12.1)
  orr <- ((0.410 / 0.590) / (0.990 / 0.010)) / ((0.725 / 0.275) / (0.985 / 0.015))
  expect_equal(round(irr, 3), 1.312)
  expect_equal(round(orr, 3), 0.175)
  expect_true(grepl("MU_WAIT\\[\"pe_medicaid\"\\] */ *MU_WAIT\\[\"pe_bcbs\"\\]", src),
              info = "truth must be derived from the cell constants, never typed in separately")
})

# ---------------------------------------------------------------- adversarial (3)

test_that("adversarial: no shipped artifact stores NPI in a lossy float form", {
  # Third sweep for the float-vs-int hazard. The calling sheets and REDCap files are the
  # artifacts other people consume; a float NPI there would break every downstream join.
  for (f in c("pe_obgyn_final_calling_sheet_200.csv", "redcap_import_ready_200.csv",
              "pe_obgyn_matched_calling_list.csv")) {
    d <- utils::read.csv(p(f), colClasses = "character", check.names = FALSE, nrows = 50)
    if (!"NPI" %in% names(d)) next
    expect_false(any(grepl("\\.", d$NPI)),
                 info = sprintf("%s stores NPI with a decimal point", f))
  }
})

test_that("adversarial: documented random-intercept magnitude matches the code", {
  doc <- grep("Random intercept SD", pw, value = TRUE)
  expect_length(doc, 1L)
  code_sd <- as.numeric(sub(".*sd *= *([0-9.]+).*", "\\1", grep("u_j *<- *rep\\(rnorm", pw, value = TRUE)[1]))
  doc_num <- as.numeric(sub(".*?([0-9.]+).*", "\\1", sub(".*Random intercept SD[^0-9]*", "", doc)))
  expect_equal(code_sd, doc_num,
               info = sprintf("comment says %s, code uses %s; they are on different scales", doc_num, code_sd))
})

test_that("adversarial: the power results artifact matches the grid the script declares", {
  ns <- eval(parse(text = sub(".*<- *", "", grep("^ns_to_test", pw, value = TRUE)[1])))
  sds <- eval(parse(text = sub(" *#.*", "", sub(".*<- *", "", grep("^sds_to_test", pw, value = TRUE)[1]))))
  expect_setequal(unique(res$Pairs), ns)
  expect_setequal(unique(res$SD), sds)
  expect_equal(nrow(res), length(ns) * length(sds),
               info = "a stale results file would have a different number of rows than the grid")
})
