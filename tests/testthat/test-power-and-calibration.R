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
  # Var = mu + mu^2/theta solved at a reference mean of 23 days, the average of the four cells.
  # Pattern update: the script now selects theta through theta_for_sd() rather than assigning
  # theta_val inline, so the constants are matched wherever they appear. The contract is that
  # both constants are present and both equal their derivation, which is unchanged.
  expect_equal(round(23^2 / (100 - 23), 2), 6.87)
  expect_equal(round(23^2 / (400 - 23), 2), 1.40)
  expect_true(any(grepl("\\b6\\.87\\b", pw)),
              info = "the SD-10 dispersion constant is absent from the script")
  expect_true(any(grepl("\\b1\\.40\\b", pw)),
              info = "the SD-20 dispersion constant is absent from the script")
  expect_true(any(grepl("23\\^2|mean of about 23|reference mean of 23", pw)),
              info = "the reference mean the constants are solved at must be stated in the script")
})

test_that("BVA: the power grid covers the sample size actually fielded", {
  expect_true(200L %in% res$Pairs,
              info = "the fielded design is 200 pairs; power must be reported at that point")
  expect_true(all(res$Total_Calls == 2L * res$Physicians))
  expect_true(all(res$Physicians == 2L * res$Pairs))
  expect_true(all(res$Power >= 0 & res$Power <= 1))
})

test_that("BVA: the grid reports the fielded design under every effect-size scenario", {
  # The script now sweeps three literature-anchored scenarios rather than one invented IRR.
  # A scenario that silently dropped out would leave the manuscript quoting whichever cells
  # happened to survive.
  fielded <- res[res$Pairs == 200L & res$SD == 10, ]
  expect_setequal(fielded$Scenario, c("conservative", "primary", "larger"))
  expect_setequal(round(fielded$IRR, 2), c(1.10, 1.22, 1.35))
  expect_equal(nrow(fielded), 3L)
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
  # The comment must state the SD the code actually draws with, and must say it is on the LOG
  # scale -- an earlier version documented 0.2 in a way that read as days.
  doc <- grep("Random intercept SD", pw, value = TRUE)
  expect_length(doc, 1L)
  doc_num <- as.numeric(sub(".*?([0-9.]+).*", "\\1", sub(".*Random intercept SD[^0-9]*", "", doc)))
  code_sd <- as.numeric(sub(".*RE_SD *<- *([0-9.]+).*", "\\1",
                            grep("^RE_SD *<-", pw, value = TRUE)[1]))
  expect_equal(code_sd, doc_num,
               info = sprintf("comment says %s, code uses %s", doc_num, code_sd))
  expect_true(any(grepl("rnorm\\([^,]+, *0, *RE_SD\\)", pw)),
              info = "the random intercept must be drawn with the documented constant, not a literal")
  expect_true(grepl("LOG scale|log scale", doc),
              info = "the comment must say which scale the SD is on; 0.2 days and 0.2 log units differ")
})

test_that("adversarial: the power results artifact matches the grid the script declares", {
  ns <- eval(parse(text = sub(".*<- *", "", grep("^ns_to_test", pw, value = TRUE)[1])))
  sds <- eval(parse(text = sub(" *#.*", "", sub(".*<- *", "", grep("^sds_to_test", pw, value = TRUE)[1]))))
  scen <- eval(parse(text = sub(".*<- *", "", grep("^IRR_SCENARIOS", pw, value = TRUE)[1])))
  expect_setequal(unique(res$Pairs), ns)
  expect_setequal(unique(res$SD), sds)
  expect_setequal(unique(res$Scenario), names(scen))
  expect_equal(nrow(res), length(ns) * length(sds) * length(scen),
               info = "a stale results file would have a different number of rows than the grid")
  expect_true(all(res$Usable_Fits == 200L),
              info = "a cell with non-converging fits reports power on a selected subset")
})

test_that("the power simulation analyses with the model the SAP specifies", {
  # Cycle 4 recorded that the simulation drew a per-physician random intercept then fitted
  # glm.nb, which assumes independence. It now fits glmmTMB with (1 | physician).
  src <- readLines(testthat::test_path("..", "..", "run_new_power_analysis.R"))
  expect_true(any(grepl("glmmTMB(wait_time ~ pe * insurance + (1 | physician)", src, fixed = TRUE)),
              info = "the simulation must analyse the clustering it generates")
  expect_false(any(grepl("glm.nb(wait_time ~", src, fixed = TRUE)),
               info = "no marginal fit may remain in the power simulation")
})

test_that("power is reported for the estimand the SAP names, not a joint test", {
  # An earlier version compared `~ pe * insurance` against `~ insurance`, dropping the ownership
  # main effect AND the interaction: a 2-df joint test of any ownership effect. The SAP's
  # primary wait-time estimand is the interaction alone.
  #
  # Contract update: the script no longer reports the joint test at all, so the earlier
  # assertion that both columns exist no longer describes the artifact. What must be preserved
  # is the reason that test existed -- that reported power belongs to the single interaction
  # parameter -- so the source is checked directly rather than a column name.
  expect_true(any(grepl('co\\["pe:insurance", "Pr\\(>\\|z\\|\\)"\\]', pw)),
              info = "power must be read off the interaction coefficient, not a model comparison")
  expect_false(any(grepl("anova\\(|lrtest\\(", pw)),
               info = "a model comparison here would reintroduce the 2-df joint test")
  expect_true(all(res$Power >= 0 & res$Power <= 1))
})

test_that("power at the fielded design is reported honestly", {
  # Pinned so that no claim of adequate power can rest on the uncensored grid alone. The
  # censored figure at 200 pairs is 0.690 (Appendix S1 Table S1.4); the uncensored primary
  # cell below is the optimistic bound on it.
  row <- res[res$Pairs == 200 & res$SD == 10 & res$Scenario == "primary", ]
  expect_equal(nrow(row), 1L)
  expect_true(row$Power < 0.90,
              info = sprintf("uncensored power at the fielded design is %.3f", row$Power))
  cons <- res[res$Pairs == 400 & res$SD == 10 & res$Scenario == "conservative", ]
  expect_true(cons$Power < 0.80,
              info = sprintf("the conservative scenario reaches %.3f even at 400 pairs, so no feasible sample rescues it",
                             cons$Power))
})

test_that("adversarial: power is monotone in sample size and in effect size", {
  # Monte Carlo noise permits small reversals; a systematic one would mean the grid is not
  # measuring what it claims. Tolerance is two Monte Carlo standard errors at the worst case.
  tol <- 2 * sqrt(0.25 / 200)
  for (sc in unique(res$Scenario)) for (sd in unique(res$SD)) {
    r <- res[res$Scenario == sc & res$SD == sd, ]
    r <- r[order(r$Pairs), ]
    expect_true(all(diff(r$Power) > -tol),
                info = sprintf("power falls with sample size in %s at SD %d: %s",
                               sc, sd, paste(r$Power, collapse = ", ")))
  }
  for (n in unique(res$Pairs)) for (sd in unique(res$SD)) {
    r <- res[res$Pairs == n & res$SD == sd, ]
    r <- r[order(r$IRR), ]
    expect_true(all(diff(r$Power) > -tol),
                info = sprintf("power falls with effect size at %d pairs, SD %d", n, sd))
  }
})
