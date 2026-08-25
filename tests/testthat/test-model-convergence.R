# Laws about whether a fitted model may be believed.
#
# Taken from the ENT mystery-caller analysis, where the lesson survives only as a comment
# beside a commented-out model call: the mixed model did not converge, and a person noticing
# was the entire detection mechanism. In this repository the standard errors from these fits
# are exponentiated straight into the Abstract's 95% intervals, so a false convergence does not
# produce a visibly broken result. It produces a publishable one that is wrong.

testthat::local_edition(3)

src <- readLines(testthat::test_path("..", "..", "R", "analysis_gates.R"))
eval(parse(text = paste(src[!grepl("^\\s*(library|suppressMessages\\(library)", src)], collapse = "\n")))

pa <- paste(readLines(testthat::test_path("..", "..", "primary_analysis.Rmd"), warn = FALSE), collapse = "\n")

# glmmTMB is not installed here -- the analysis has never been run in this environment, which
# is consistent with no outcome export existing. The gate is therefore exercised against fit
# objects built to the structure glmmTMB documents, with VarCorr stubbed. This tests the gate's
# logic, not glmmTMB's; if the upstream structure ever changes, the first negative control
# below ("fit carries no convergence code") is what fires.
mk <- function(conv = 0L, pd = TRUE, sds = c(pair = 0.8, npi = 0.4)) {
  structure(list(fit = list(convergence = conv), sdr = list(pdHess = pd), .sds = sds),
            class = "glmmTMB")
}
gc2 <- gate_convergence
body(gc2) <- parse(text = gsub("glmmTMB::VarCorr", ".stub_varcorr",
  paste(deparse(body(gate_convergence)), collapse = "\n"), fixed = TRUE))[[1]]
.stub_varcorr <- function(x) {
  list(cond = lapply(x$.sds, function(s)
    matrix(s^2, 1, 1, dimnames = list("(Intercept)", "(Intercept)"))))
}
environment(gc2) <- environment()

test_that("POSITIVE CONTROL: a healthy fit passes the gate", {
  # Without this, a gate that stopped on everything would look like a working gate.
  expect_true(gc2(mk(), label = "healthy"))
})

test_that("LAW: a fit that did not converge stops the analysis", {
  expect_error(gc2(mk(conv = 1L), label = "m"), "convergence code 1")
  expect_error(gc2(structure(list(sdr = list(pdHess = TRUE)), class = "glmmTMB"), label = "m"),
               "no convergence code")
})

test_that("LAW: an indefinite Hessian stops the analysis", {
  # This is the dangerous one. The optimiser can report success while the Hessian is not
  # positive-definite, and summary() will still print standard errors -- the exact quantities
  # that become the reported intervals.
  expect_error(gc2(mk(pd = FALSE), label = "m"), "not positive-definite")
  expect_error(gc2(structure(list(fit = list(convergence = 0L)), class = "glmmTMB"), label = "m"),
               "no sdreport")
})

test_that("LAW: a singular random-effect term stops the analysis", {
  # A boundary SD means the grouping term is estimating nothing while the model still
  # "converges" -- so the matched-pair clustering the design depends on is silently absent.
  expect_error(gc2(mk(sds = c(pair = 0, npi = 0.4)), label = "m"), "singular fit")
  expect_error(gc2(mk(sds = c(pair = 0.8, npi = 1e-9)), label = "m"), "singular fit")
  # NEGATIVE CONTROL on the threshold itself: a small but real variance must NOT be called
  # singular, or the gate would block legitimate fits and get switched off.
  expect_true(gc2(mk(sds = c(pair = 0.01, npi = 0.4)), label = "m"))
})

test_that("LAW: every fitted model in the analysis is gated before it is read", {
  # The gate is worth nothing if a fit can be summarised or extracted without passing it.
  code <- grep("^\\s*#", strsplit(pa, "\n", fixed = TRUE)[[1]], invert = TRUE, value = TRUE)
  fits <- unique(sub("^\\s*([A-Za-z_.][A-Za-z0-9_.]*)\\s*<-\\s*glmmTMB\\(.*$", "\\1",
                     grep("<-\\s*glmmTMB\\(", code, value = TRUE)))
  expect_true(length(fits) >= 3L,
              info = "expected at least the three models SAP.lock prespecifies")
  for (f in fits) {
    expect_true(any(grepl(paste0("gate_convergence(", f, ")"), code, fixed = TRUE)),
                info = paste0(f, " is fitted but never checked for convergence"))
  }
})
