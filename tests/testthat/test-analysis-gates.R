# Tests for the gates themselves.
#
# A gate that cannot fail is decoration. Every test here constructs the defect the gate exists
# to stop and asserts that it throws, then asserts the clean case passes. The defects are the
# real ones from this project, not invented ones.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)

sheet <- utils::read.csv(p("pe_obgyn_final_calling_sheet_200.csv"), check.names = FALSE)
sheet$CDC_SVI_real <- suppressWarnings(as.numeric(sheet$CDC_SVI_real))
sheet$SIMULATED_CDC_SVI <- suppressWarnings(as.numeric(sheet$SIMULATED_CDC_SVI))
man <- read_manifest(p("analysis_manifest.csv"))
sap <- read_sap(p("SAP.lock"))

# ---------------------------------------------------------------- manifest

test_that("BVA: the manifest declares every column of the fielded sheet", {
  undeclared <- setdiff(names(sheet), man$column)
  expect_length(undeclared, 0L)
})

test_that("BVA: the manifest uses only recognised statuses and families", {
  expect_true(all(man$status %in% c("measured", "derived", "simulated", "identifier", "outcome")))
  expect_true(all(man$family %in% c("percentile", "proportion", "count", "continuous",
                                    "identifier", "categorical")))
  expect_true(all(nzchar(trimws(man$source))),
              info = "a declared column with a blank source declares nothing")
})

test_that("semantic: the manifest agrees with the audit about what is simulated", {
  sim <- man$column[man$status == "simulated"]
  expect_true(all(paste0("SIMULATED_", c("CDC_SVI", "Tract_Pct_Female_Private",
                    "Tract_Pct_Female_Medicaid", "Tract_Pct_Female_Medicare",
                    "Tract_Pct_Female_Uninsured", "County_OBGYN_Count",
                    "County_Medicare_Enrollment", "County_Medicaid_Enrollment")) %in% sim))
  # No column may carry a measurement-sounding name while being simulated.
  expect_true(all(grepl("^SIMULATED_", sim)),
              info = sprintf("simulated column without the prefix: %s",
                             paste(sim[!grepl("^SIMULATED_", sim)], collapse = ", ")))
  expect_false("CDC_SVI_real" %in% sim)
  expect_equal(man$status[man$column == "CDC_SVI_real"], "measured")
})

# ---------------------------------------------------------------- provenance gate

test_that("adversarial: the provenance gate rejects a simulated covariate", {
  expect_error(gate_provenance(sheet, "SIMULATED_CDC_SVI", man), "Simulated variable")
})

test_that("adversarial: the provenance gate rejects an undeclared column", {
  d <- sheet; d$invented_score <- runif(nrow(d))
  expect_error(gate_provenance(d, "invented_score", man), "absent from analysis_manifest")
})

test_that("the provenance gate accepts the reconstructed covariate", {
  expect_true(gate_provenance(sheet, "CDC_SVI_real", man))
})

test_that("adversarial: the percentile family check rejects the simulated column's shape", {
  # Reproduces the generator: Normal, clamped to [0.01, 0.99].
  set.seed(1)
  v <- pmax(0.01, pmin(0.99, rnorm(400, 0.434, 0.193)))
  expect_error(gate_family(v, "fake_svi", "percentile"))
  # A genuine percentile rank must pass.
  expect_true(gate_family(runif(400), "real_svi", "percentile"))
})

test_that("BVA: the family check catches out-of-range and non-integer values", {
  expect_error(gate_family(c(0.5, 1.5), "x", "percentile"), "outside")
  expect_error(gate_family(c(1, 2, -3), "x", "count"), "negative")
  expect_error(gate_family(c(1, 2.5), "x", "count"), "non-integer")
  expect_error(gate_family(1, "x", "not_a_family"), "unknown family")
})

# ---------------------------------------------------------------- missingness gate

test_that("adversarial: the missingness gate reproduces and rejects the original SVI pattern", {
  # 200/200 PE and 106/200 control, which is what shipped.
  expect_error(gate_missingness(sheet, "SIMULATED_CDC_SVI"), "depends on PE_or_Not")
  # The message must carry the per-arm counts, not only a p-value, so the reader can see the
  # pattern rather than take the test's word for it.
  msg <- tryCatch(gate_missingness(sheet, "SIMULATED_CDC_SVI"), error = conditionMessage)
  expect_match(msg, "94 / 0")
  expect_match(msg, "complete-case")
})

test_that("the missingness gate accepts the reconstructed covariate", {
  out <- gate_missingness(sheet, "CDC_SVI_real")
  expect_s3_class(out, "tbl_df")
  expect_false(any(out$dependent))
})

test_that("semantic: the missingness gate ignores a covariate that is wholly present or absent", {
  d <- sheet; d$all_there <- 1; d$none_there <- NA_real_
  out <- gate_missingness(d, c("all_there", "none_there"))
  expect_false(any(out$dependent))
})

# ---------------------------------------------------------------- join gate

test_that("adversarial: the join gate catches the float-suffix and zero-truncation defects", {
  expect_error(key_join_index(c("1003038688", "1144280553"),
                              c("1003038688.0", "1144280553.0"), label = "npi"))
  expect_error(key_join_index(c("01604", "06880"), c("1604", "6880"), label = "zip"))
})

test_that("the join gate passes when the key function repairs the type", {
  idx <- key_join_index(c("1003038688", "1144280553"),
                        c("1003038688.0", "1144280553.0"), label = "npi", key_fun = npi_key)
  expect_equal(idx, c(1L, 2L))
})

test_that("BVA: the join gate honours a partial-match tolerance exactly at the boundary", {
  expect_true(is.integer(key_join_index(c("a", "b"), "a", min_match = 0.5, label = "half")))
  expect_error(key_join_index(c("a", "b"), "a", min_match = 0.51, label = "half"))
})

test_that("semantic: the join coverage check is the canonical one, not a local reimplementation", {
  src <- readLines(p("R", "analysis_gates.R"), warn = FALSE)
  expect_true(any(grepl("mysterycall_safe_left_join", src, fixed = TRUE)),
              info = "coverage must be checked by mysterycall, not by local arithmetic")
  expect_false(any(grepl("^assert_join <- function", src)),
               info = "the local join gate was replaced by the canonical one and must not return")
})

test_that("semantic: the missingness gate delegates to the canonical mysterycall function", {
  src <- readLines(p("R", "analysis_gates.R"), warn = FALSE)
  expect_true(any(grepl("mysterycall_gate_missingness", src, fixed = TRUE)),
              info = "gate_missingness was promoted into mysterycall; the local copy must delegate")
  expect_true(is.function(mysterycall::mysterycall_gate_missingness))
})

test_that("adversarial: no script defines a name an attached canonical package exports", {
  # The defect that produced the simulated covariates: extract_demographic_covariates.R defined
  # four functions under names mysterycall exports, so which definition won depended on source
  # order. See docs/CANONICAL_SOURCES_AUDIT.md (A1, A9).
  canon <- getNamespaceExports("mysterycall")
  files <- list.files(root, pattern = "\\.R$", full.names = TRUE)
  files <- c(files, list.files(file.path(root, "R"), pattern = "\\.R$", full.names = TRUE))
  offenders <- character(0)
  for (f in files) {
    src <- readLines(f, warn = FALSE)
    defs <- trimws(sub("\\s*<-\\s*function.*$", "",
                       grep("^\\s*[A-Za-z._][A-Za-z0-9._]*\\s*<-\\s*function", src, value = TRUE)))
    hit <- intersect(defs, canon)
    if (length(hit)) offenders <- c(offenders, sprintf("%s: %s", basename(f),
                                                       paste(hit, collapse = ", ")))
  }
  expect_length(offenders, 0L)
})

# ---------------------------------------------------------------- SAP lock

test_that("BVA: the frozen plan names a formula, an estimand and a family for each model", {
  for (k in c("waittime_primary", "obtainment_primary", "obtainment_secondary")) {
    for (suffix in c("_formula", "_family", "_estimand")) {
      expect_true(nzchar(trimws(sap[[paste0(k, suffix)]])),
                  info = sprintf("SAP.lock lacks %s%s", k, suffix))
    }
  }
})

test_that("semantic: the frozen wait-time estimand is the interaction, not a joint test", {
  expect_equal(sap[["waittime_primary_estimand"]], "pe:medicaid")
  expect_true(grepl("pe \\* medicaid", sap[["waittime_primary_formula"]]))
  expect_equal(sap[["svi_column"]], "CDC_SVI_real",
               info = "the plan must name the reconstructed covariate, not the simulated one")
})

test_that("adversarial: gate_sap rejects the 2-df joint-test substitution", {
  # Dropping the ownership main effect AND the interaction is the substitution that was
  # actually made and reported as though it were the interaction.
  expect_error(gate_sap(business_days ~ medicaid + svi_z + (1 | pair) + (1 | npi),
                        "waittime_primary", sap = sap), "does not match the frozen")
  # Dropping only the covariate is also a different model and must not slip through.
  expect_error(gate_sap(business_days ~ pe * medicaid + (1 | pair) + (1 | npi),
                        "waittime_primary", sap = sap), "does not match the frozen")
})

test_that("gate_sap accepts the specified model and is insensitive to whitespace", {
  expect_equal(gate_sap(business_days ~ pe * medicaid + svi_z + (1 | pair) + (1 | npi),
                        "waittime_primary", family = "nbinom2", sap = sap), "pe:medicaid")
})

test_that("adversarial: gate_sap rejects the right formula fitted with the wrong family", {
  expect_error(gate_sap(business_days ~ pe * medicaid + svi_z + (1 | pair) + (1 | npi),
                        "waittime_primary", family = "poisson", sap = sap), "family")
})

test_that("adversarial: every assumed magnitude in the plan carries a source", {
  expect_true(gate_sourced_constants(sap))
  stripped <- sap[setdiff(names(sap), "effect_primary_irr_source")]
  expect_error(gate_sourced_constants(stripped), "no recorded source")
})

test_that("adversarial: the frozen plan has not been edited without rehashing", {
  recorded <- sub(".*= *", "", grep("^# *sha256", readLines(p("SAP.lock"), warn = FALSE),
                                    value = TRUE)[1])
  expect_true(nzchar(recorded), info = "SAP.lock carries no hash; run sap_write_hash()")
  expect_equal(sap_hash(p("SAP.lock")), recorded,
               info = "SAP.lock was edited without regenerating its hash")
})

# ---------------------------------------------------------------- structure gates

test_that("adversarial: the clustering gate rejects a unit with blank values", {
  d <- sheet; d$phone_id[3] <- NA
  expect_error(gate_clustering(d, "phone_id"), "blank values")
})

test_that("the clustering gate reports the structure the audit found", {
  expect_true(gate_clustering(sheet, "phone_id", expect_n = 385L, max_size = 4L))
  expect_error(gate_clustering(sheet, "phone_id", expect_n = 400L), "385 clusters")
})

test_that("adversarial: the analytic-N gate catches obtainment censoring", {
  # The powered design assumed all 800 calls yield a wait time; roughly 622 will.
  powered  <- c(ctrl_bcbs = 200, ctrl_medicaid = 200, pe_bcbs = 200, pe_medicaid = 200)
  realised <- c(ctrl_bcbs = 197, ctrl_medicaid = 145, pe_bcbs = 198, pe_medicaid = 82)
  expect_error(gate_analytic_n(realised, powered), "departs from the powered design")
  expect_true(gate_analytic_n(powered, powered))
})

# ---------------------------------------------------------------- wiring

test_that("semantic: the analysis script runs the preflight before it fits anything", {
  src <- readLines(p("dry_run_analysis.R"), warn = FALSE)
  pre <- grep("analysis_preflight\\(", src)
  fit <- grep("glmmTMB\\(", src)
  expect_true(length(pre) > 0L, info = "the analysis does not call the preflight")
  expect_true(length(fit) > 0L)
  expect_true(min(pre) < min(fit),
              info = "the preflight must run before the first model is fitted")
})

test_that("semantic: the analysis reads its covariate and estimand from the frozen plan", {
  src <- paste(readLines(p("dry_run_analysis.R"), warn = FALSE), collapse = "\n")
  expect_true(grepl('SVI_COL <- SAP[["svi_column"]]', src, fixed = TRUE),
              info = "the deprivation covariate must come from SAP.lock, not a literal")
  expect_true(grepl("gate_sap(F_WT", src, fixed = TRUE))
  expect_false(grepl('as.numeric(CDC_SVI)', src, fixed = TRUE),
               info = "the simulated column must not be read by name anywhere in the analysis")
})
