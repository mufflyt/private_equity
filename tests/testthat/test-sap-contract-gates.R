# gate_sap() and gate_sourced_constants() are what stop a fitted model, or an assumed effect
# size, from silently drifting away from the frozen plan -- the exact failure SAP.lock's own
# header describes: "an earlier power analysis reported a two-degree-of-freedom joint test of
# 'any ownership effect' as though it were the interaction the plan names."
#
# Both take only `sap` (parsed from the committed SAP.lock) and, for gate_sap(), a bare R
# formula -- no cohort data at all. Despite that, until this file, gate_sap() was only ever
# exercised (positively or negatively) against ONE of the three frozen models
# (waittime_primary, in test-analysis-gates.R), and neither gate was registered nodata, so this
# study's single most consequential scientific-contract check had zero coverage in actual CI --
# only in the data-tier suite, which needs the gitignored cohort and does not run there.
#
# Per docs/SCIENTIFIC_CI_LAWS.md Law 1: every contract below gets both a positive control (the
# real, frozen formula passes) and a negative control (a plausible wrong variant fails, and
# fails for the stated reason) -- not just one half.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
sap <- read_sap(file.path(root, "SAP.lock"))

# ---------------------------------------------------------------- primary obtainment

test_that("gate_sap accepts the frozen primary obtainment model", {
  expect_equal(
    gate_sap(obtained ~ pe + svi_z + (1 | pair), "obtainment_primary",
            family = "binomial", sap = sap),
    "pe"
  )
})

test_that("adversarial: gate_sap rejects the secondary interaction reported as the primary", {
  # The primary obtainment estimand is the PE main effect on Medicaid calls alone -- no
  # interaction term is identifiable in that subset (see SAP.lock's own comment: each clinician
  # contributes exactly one Medicaid call). Substituting the secondary's pe*medicaid formula is
  # a real, plausible mix-up between the two obtainment models, not a contrived one.
  expect_error(
    gate_sap(obtained ~ pe * medicaid + svi_z + (1 | pair) + (1 | npi), "obtainment_primary",
            family = "binomial", sap = sap),
    "does not match the frozen"
  )
})

test_that("adversarial: gate_sap rejects the right primary-obtainment formula with the wrong family", {
  expect_error(
    gate_sap(obtained ~ pe + svi_z + (1 | pair), "obtainment_primary",
            family = "gaussian", sap = sap),
    "family"
  )
})

# ---------------------------------------------------------------- primary wait time
#
# Already exercised in test-analysis-gates.R (data tier); re-asserted here so the single most
# consequential contract in this study is not left dependent on the data tier ever running.

test_that("gate_sap accepts the frozen primary wait-time model", {
  expect_equal(
    gate_sap(business_days ~ pe * medicaid + svi_z + (1 | pair) + (1 | npi), "waittime_primary",
            family = "nbinom2", sap = sap),
    "pe:medicaid"
  )
})

test_that("adversarial: gate_sap rejects the 2-df joint-test substitution for wait time", {
  # The defect that actually shipped: dropping the ownership main effect AND the interaction,
  # then reporting the result as though it were the pe:medicaid interaction.
  expect_error(
    gate_sap(business_days ~ medicaid + svi_z + (1 | pair) + (1 | npi), "waittime_primary",
            sap = sap),
    "does not match the frozen"
  )
})

# ---------------------------------------------------------------- secondary obtainment

test_that("gate_sap accepts the frozen secondary obtainment model", {
  expect_equal(
    gate_sap(obtained ~ pe * medicaid + svi_z + (1 | pair) + (1 | npi), "obtainment_secondary",
            family = "binomial", sap = sap),
    "pe:medicaid"
  )
})

test_that("adversarial: gate_sap rejects the primary formula reported as the secondary", {
  # The reverse mix-up from the primary-obtainment negative control above: the secondary
  # estimand IS the interaction, so silently dropping it back to the primary's main-effect-only
  # formula is the same class of substitution SAP.lock's header warns about, one model over.
  expect_error(
    gate_sap(obtained ~ pe + svi_z + (1 | pair), "obtainment_secondary",
            family = "binomial", sap = sap),
    "does not match the frozen"
  )
})

test_that("adversarial: gate_sap rejects the right secondary-obtainment formula with the wrong family", {
  expect_error(
    gate_sap(obtained ~ pe * medicaid + svi_z + (1 | pair) + (1 | npi), "obtainment_secondary",
            family = "poisson", sap = sap),
    "family"
  )
})

# ---------------------------------------------------------------- sourced constants

test_that("adversarial: every assumed magnitude in the frozen plan carries a source", {
  expect_true(gate_sourced_constants(sap))
  stripped <- sap[setdiff(names(sap), "effect_primary_irr_source")]
  expect_error(gate_sourced_constants(stripped), "no recorded source")
})

test_that("semantic: the anchored effect size is attributed to the cited study, not asserted bare", {
  # gate_sourced_constants() only checks that *a* source string is present, not that it is a
  # real citation -- this pins the actual text so a future edit that blanks the citation but
  # leaves a placeholder non-empty string would still be caught, one level up from the gate.
  expect_match(sap[["effect_primary_irr_source"]], "Nie", fixed = TRUE)
  expect_match(sap[["effect_primary_irr_source"]], "doi", fixed = TRUE)
})
