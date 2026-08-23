# Scientific CI: statistical/code correctness.
# gate_overdispersion() checks the standard Pearson chi-square/df dispersion statistic on a
# fitted Poisson model and fails with a named remedy (MASS::glm.nb / glmmTMB nbinom2) when it
# is overdispersed -- a Poisson fit on overdispersed count data understates standard errors and
# overstates significance, silently, which is exactly why this study's own frozen plan already
# specifies negative-binomial for its count outcomes (wait time, hold time, transfers). Uses
# base glm() throughout, not glmmTMB, since glmmTMB is not a CI dependency
# (.github/workflows/gates.yml) and the dispersion arithmetic is identical for either.

set.seed(2026)
n <- 400
x <- rbinom(n, 1, 0.5)
mu_true <- exp(1 + 0.4 * x)

# Genuinely overdispersed DGP (negative binomial, small theta = more overdispersion) and a
# genuinely equidispersed one (true Poisson), both fit with a plain Poisson glm. Built once at
# file scope and reused, rather than re-simulated per test, so a given test's pass/fail can't
# depend on which random draw it happened to get -- the seed is fixed but re-drawing per test
# would still couple unrelated tests' outcomes to draw order.
y_overdispersed <- MASS::rnegbin(n, mu = mu_true, theta = 1.2)
y_poisson       <- rpois(n, lambda = mu_true)

fit_overdispersed <- glm(y_overdispersed ~ x, family = poisson)
fit_poisson        <- glm(y_poisson ~ x, family = poisson)
fit_nb              <- MASS::glm.nb(y_overdispersed ~ x)

test_that("semantic: a Poisson fit on genuinely overdispersed data is flagged with the ratio and a remedy", {
  err <- tryCatch({ gate_overdispersion(fit_overdispersed); NULL },
                  error = function(e) conditionMessage(e))
  expect_false(is.null(err), info = "the overdispersed fixture must fail the gate")
  expect_match(err, "dispersion ratio", info = "message must report the actual statistic")
  expect_match(err, "glm\\.nb|nbinom2",
               info = paste("message must name the specific remedy this study's SAP already",
                            "uses, not just say 'try something else'"))
})

test_that("semantic: a Poisson fit on genuinely equidispersed data passes", {
  expect_error(gate_overdispersion(fit_poisson), NA,
               info = paste("a well-specified Poisson model (true Poisson DGP) must not be",
                            "flagged; the check is for overdispersion, not for using Poisson",
                            "per se"))
})

test_that("BVA: the dispersion ratio sits close to 1 for the true-Poisson fixture", {
  ratio <- sum(residuals(fit_poisson, type = "pearson")^2) / df.residual(fit_poisson)
  expect_true(ratio > 0.7 && ratio < 1.4,
              info = sprintf(paste("ratio = %.2f; a correctly specified Poisson model has",
                                   "Pearson dispersion near 1 by construction -- this is a",
                                   "sanity check on the fixture itself, not on the gate"), ratio))
})

test_that("semantic: an already-negative-binomial fit passes without complaint", {
  expect_error(gate_overdispersion(fit_nb), NA,
               info = paste("MASS::glm.nb is already the recommended remedy; the gate must not",
                            "re-flag a model that has already been refit correctly"))
})

test_that("BVA: a threshold set below the true ratio still fails; above it, still passes", {
  ratio <- sum(residuals(fit_overdispersed, type = "pearson")^2) / df.residual(fit_overdispersed)
  expect_error(gate_overdispersion(fit_overdispersed, threshold = ratio - 0.01), "dispersion ratio")
  expect_error(gate_overdispersion(fit_overdispersed, threshold = ratio + 0.01), NA,
               info = "boundary sanity check on the threshold comparison direction")
})

test_that("adversarial: a non-count family (gaussian/binomial) is not applicable, not flagged", {
  fit_gaussian <- glm(rnorm(n) ~ x)
  expect_error(gate_overdispersion(fit_gaussian), NA,
               info = paste("this gate is specifically about Poisson-vs-NB; it must not",
                            "misfire on a family it was never meant to police"))
  fit_binomial <- glm(rbinom(n, 1, 0.5) ~ x, family = binomial)
  expect_error(gate_overdispersion(fit_binomial), NA)
})

test_that("provenance: an object with no usable family() fails clearly rather than silently passing", {
  expect_error(gate_overdispersion(list(not_a_model = TRUE)), "family",
               info = paste("something that is not a fitted model at all must not be silently",
                            "treated as 'not applicable' -- that would make the gate a no-op",
                            "on a broken call site"))
})

test_that("adversarial: raising the threshold to force a pass is not something the gate enables silently", {
  # This does not (and cannot) stop a caller from passing threshold = 100. It documents, in a
  # way that will break loudly if the default ever regresses, what the default protects.
  expect_equal(formals(gate_overdispersion)$threshold, 1.5,
               info = paste("the default threshold is a scientific judgment call recorded",
                            "once, here; a change to it should be a deliberate, reviewed edit",
                            "to R/analysis_gates.R, not an accidental one this test would miss"))
})
