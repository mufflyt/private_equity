# Canonical sources audit

**Date:** 2026-08-10
**Scope:** `private_equity` against the seven Muffly R repositories
**Method:** full namespace enumeration and intersection (`scratch/namespace_audit.R`, `scratch/dupes.R`)

---

## S0. Summary

The study repository reimplements functionality that already exists, tested and exported, in
packages the author maintains. Three findings matter more than the rest:

1. **`extract_demographic_covariates.R` is a verbatim local copy of `mysterycall/R/demographic_covariates.R`.** All four fetchers — ACS female insurance, HRSA AHRF, CMS enrollment, NPPES clinician churn — exist and are exported by `mysterycall`. The study defined its own copies, then `apply_demographic_covariates.R` never called any of them and substituted `rnorm()` draws instead. **This is the provenance of the simulated covariates documented in Appendix S2.** The real-data path existed and was bypassed.
2. **`mysterycall` already exports safe joins.** `mysterycall_safe_left_join()`, `_inner_join()`, `_semi_join()`, `_anti_join()` and `mysterycall_assert_unique_keys()` do what `assert_join()` in `R/analysis_gates.R` does, with more coverage. The local version should be deleted.
3. **`mysterycall_nb_power()` is the canonical negative-binomial power simulator** and `run_new_power_analysis.R` re-derives most of it. It is not a drop-in replacement — it tests a two-group main effect and has no censoring — but the duplicated machinery belongs in the package, not in a study script.

Beyond the study, the packages duplicate **28 exported names among themselves** (excluding
`isochrones`), which means canonical ownership is already ambiguous in places. That is listed in
S5.

---

## S1. Repositories enumerated

All seven local checkouts were clean and on `main` with GitHub remotes at the time of the audit,
so the local trees are identical to what `remotes::install_github("mufflyt/<pkg>")` would fetch.
Enumeration was done from `NAMESPACE` rather than from an installed namespace, so packages that
are not currently installed are still covered.

| Repository | Version | Exports | R files | Test files | Installed | Nature |
|---|---|---:|---:|---:|---|---|
| `isochrones` | 4.6.1 | (see note) | 1,311 | 4,855 | no | **Project, not a library.** Its `NAMESPACE` is `exportPattern` with a header stating the project is executed by *sourcing* `R/`. 5,618 top-level function definitions, many dot-prefixed internals. |
| `twostep` | 0.1.0 | 53 | 12 | 26 | yes | Package |
| `mysterycall` | 1.6.0 | 239 | 199 | 393 | yes | Package, CRAN-bound |
| `mysterymaps` | 0.2.0 | 27 | 20 | 3 | yes | Package |
| `cliff` | 0.1.0 | 18 | 22 | 86 | yes | Package |
| `mufflyaccess` | 0.10.0 | 114 | 32 | 42 | yes | Package |
| `simulation` (= `urpssim`) | 0.5.0 | 475 | 93 | 112 | yes, as `urpssim` | Package |
| `Lizeth` / `lizeth` | — | — | 2 in `R/`, 22 top-level | — | no | Analysis project, not a package |

**Installable export surface: 890 unique names across the six libraries.**

> **`isochrones` is not a dependency.** It is designed to be sourced, not attached, and it is not
> installed. Its functions are listed below as *precedent* — a place where the correct
> implementation already exists and can be lifted or promoted — not as something `private_equity`
> can call with `isochrones::`. Promoting a needed function into `mysterycall` or `mufflyaccess`
> is the way to consume it.

---

## S2. Direct hits: functions this repository wrote that already exist

### S2.1 Shadowed canonical names — highest severity

`extract_demographic_covariates.R` defines four functions **under the exact names `mysterycall`
exports**, with the same signatures:

| Local definition | Canonical | Defined at |
|---|---|---|
| `mysterycall_track_clinician_churn()` | `mysterycall::mysterycall_track_clinician_churn` | `mysterycall/R/demographic_covariates.R:12` |
| `mysterycall_get_acs_female_insurance()` | `mysterycall::mysterycall_get_acs_female_insurance` | `…:97` |
| `mysterycall_get_hrsa_ahrf()` | `mysterycall::mysterycall_get_hrsa_ahrf` | `…:142` |
| `mysterycall_get_cms_enrollment()` | `mysterycall::mysterycall_get_cms_enrollment` | `…:170` |

Shadowing an exported name is worse than writing a differently named duplicate: whichever is
sourced last wins, silently, and the choice depends on script order.

**The consequence is already documented.** `apply_demographic_covariates.R` calls none of these.
It generates `Tract_Pct_Female_*`, `County_OBGYN_Count` and both `County_*_Enrollment` columns
with `rnorm()` and clamps, describing this in its own header as "standard fallback simulations to
ensure full dataset completeness." The canonical functions that would have fetched the real ACS,
AHRF and CMS values were present in the author's own package the entire time.

**Action:** delete the local copies, `library(mysterycall)`, and either call the fetchers or
delete the simulated columns. Tracked as **A1**.

### S2.2 Utility functions with canonical equivalents

| `private_equity` | Where | Canonical | Notes |
|---|---|---|---|
| `assert_join()` | `R/analysis_gates.R` | `mysterycall::mysterycall_safe_left_join`, `_inner_join`, `_semi_join`, `_anti_join`, `mysterycall_assert_unique_keys`; also `simulation::safe_left_join` | Canonical is broader. **Delete local.** |
| `npi_key()` | `R/pe_helpers.R` | `mufflyaccess::canon_npi`; `mysterycall::mysterycall_validate_npi`; `isochrones::canon_npi` | Two packages both export `canon_npi` — see S5. |
| `phone_key()` | `R/pe_helpers.R` | `mysterycall::mysterycall_validate_phone`; `isochrones::normalize_phone`, `fix_phone_digits`, `validate_phone` | |
| `address_key()` | `R/pe_helpers.R` | `isochrones::canonical_address_key`, `create_address_key`, `canonicalize_address`; `mysterycall::mysterycall_normalize_address_df` | The suite-regex defect this project fixed twice is already solved in `isochrones`. |
| `strip_suite()` | `build_svi_covariate.R` | `isochrones::strip_suite` | Same name, same purpose, written independently. |
| `zip5()` | `build_svi_covariate.R` | `isochrones::normalize_zip5`, `fix_zip5`, `clean_zip` | The leading-zero defect is already handled upstream. |
| `haversine_distance()` | `build_matched_control_group_psm.R`, `calculate_pair_distances.R` | `simulation::haversine_km`; `isochrones::haversine`, `haversine_distance`, `calculate_haversine_distance_km` | Defined twice locally. |
| `blank()` | `R/pe_helpers.R` | `isochrones::has_blank` | |
| `coalesce_cols()` | `R/pe_helpers.R` | `isochrones::coalesce` | |
| `TitleCase()` | `build_matched_control_group_psm.R` | `mysterymaps::mysterymaps_place_title_case` | |
| Census geocoding block | `build_svi_covariate.R` | `mysterymaps::mysterymaps_geocode` | Not verified as address→tract capable; see A4. |
| STROBE figure | `manuscript/strobe_diagram.R` | `mysterycall::mysterycall_strobe_flow`, `mysterycall_flow_diagram`, `mysterycall_strobe_checklist` | The hand-written figure is the one still reporting a superseded cohort of 544. |
| DHARMa residual figure | `figures/dharma_diagnostics.png` | `mysterycall::mysterycall_validate_residuals_dharma` | |

### S2.3 Power analysis

| `private_equity` | Canonical |
|---|---|
| `run_new_power_analysis.R` | `mysterycall::mysterycall_nb_power` |
| `scratch/mde_200_pairs.R` | `isochrones::mc_ru_find_mde` |
| `run_maineffect_power.R`, `run_interaction_75_power.R`, `run_obtainment_power.R` | `mysterycall::mysterycall_power_curve`, `mysterycall_power_calc`, `mysterycall_poisson_power` |
| Sample-size prose in Methods | `mysterycall::mysterycall_sample_size_text` |

`mysterycall_nb_power(n_physicians, calls_per_physician, irr, theta, baseline_mean, sigma_u,
alpha, n_sim, seed)` fits `y ~ ins + (1 | phys)` with `glmmTMB::nbinom2`. That is the same
machinery this repository rebuilt — negative binomial, physician random intercept, Monte Carlo
loop, fixed seed — around a **different estimand**.

**It is not a drop-in replacement, and this audit does not claim it is.** Two gaps:

- It compares two independent groups of physicians on a main effect. The study's primary
  estimand is an ownership-by-insurance **interaction**, where insurance varies *within*
  physician in a crossover.
- It has no obtainment censoring, which is the factor that moves this study's power from 0.87 to
  0.69.

**Action:** add a crossover/interaction variant and an optional censoring argument to
`mysterycall`, then call it. Do not keep a private fork of a power simulator. Tracked as **A5**.

### S2.4 Concepts where canonical coverage exists but was not consulted

| Concept | Canonical surface |
|---|---|
| Missing data | `mysterycall::build_missingness_mcar_table`, `mysterycall_missing_data_analysis`, `mysterycall_impute_age`, `mysterycall_impute_calls`; `isochrones::analyze_missing_data_patterns`, `check_missingness_step5`, `assert_no_missing_keys` |
| REDCap | `mysterycall::mysterycall_parse_redcap_labels` |
| NPI enrichment | `mysterycall::mysterycall_enrich_npi`, `mysterycall_search_and_process_npi` |
| Assertions / gates | `simulation` exports ~40 `assert_*` functions; `mufflyaccess::validate_urps_*`, `urps_provenance`; `mysterymaps::mysterymaps_gate_provider_coverage`; `twostep::assert_access_language`, `assert_matching_geography` |
| Coordinate sanity | `isochrones::assert_coordinates_plausible`, `assert_no_poison_coordinates` |

The assertion surface in `simulation` and `mufflyaccess` is a closer precedent for `SAP.lock` and
the preflight than anything written here; `simulation::assert_spec_matches_prereg` and
`assert_estimands_independent` are the same idea applied to a different study.

---

## S3. Where the local implementation should be kept

Not everything here is duplication. The following have no canonical equivalent and are correctly
local, though several belong upstream eventually:

| Local | Why it stays |
|---|---|
| `R/analysis_gates.R` — `gate_provenance`, `gate_family`, `gate_missingness`, `gate_sap`, `gate_clustering`, `gate_analytic_n` | No package exports a distributional-provenance gate, a missingness-by-exposure gate, or a frozen-SAP formula check. `gate_missingness` is being promoted to `mysterycall` (see A2). |
| `analysis_manifest.csv`, `SAP.lock` | Study-specific configuration by definition. |
| `build_svi_covariate.R` — the tract→`RPL_THEMES` chain | No package links CDC/ATSDR SVI. Candidate for `mufflyaccess`, which already owns tract-level vintage helpers. |
| `build_phone_cluster_vars.R` | Study-specific; the shared-scheduler concept would generalise to `mysterycall`. |
| `dedup_offices_and_backfill_200.R`, `build_200_redcap_import.R` | Study-specific protocol logic. |

---

## S4. Defect found in a canonical source

`mysterycall::build_missingness_mcar_table()` emits this sentence into manuscript prose whenever
there is at least one item-level variable — the only guard is `if (!is.null(worst_item))`, at
`R/missingness_mcar.R:245`:

> "Item-level missingness … **reflects source non-linkage that is independent of the subgroup
> structure**, rather than missingness conditioned on a unit's subgroup or observation status."

Nothing tests that claim. The signature is
`build_missingness_mcar_table(data, item_vars, structural_vars, var_labels, unknown_tokens,
mcar_vars, run_mcar, make_gt, gt_title)` — there is **no exposure or grouping argument at all**.
Little's MCAR test runs on the numeric item-level block, which asks whether missingness depends
on *observed values*, not whether it depends on the arm; a categorical exposure such as
`PE_or_Not` would not be in that block.

Run against this study's original covariate file, the function would have printed that sentence
over SVI missingness that was 200/200 in the PE arm and 106/200 in the control arm — Fisher
exact *P* = 5.1 × 10⁻³⁵.

Because `mysterycall` is CRAN-bound, every study using it inherits the sentence. Tracked as
**A2**; branch `missingness-exposure-gate` is open in `mysterycall`.

---

## S5. Canonical ownership is ambiguous between the packages

Twenty-eight exported names are defined in more than one installable package. Sixty-nine are
duplicated once `isochrones` is included. This is a canonical-source problem independent of
`private_equity`: a caller attaching two of these packages gets whichever masks the other.

| Name | Packages |
|---|---|
| `calculate_proportion_ci`, `calculate_replacement_gap`, `calculate_rural_metro_comparison`, `calculate_state_vulnerability`, `calculate_two_prop_test` | `cliff`, `mufflyaccess`, `simulation` |
| `annual_trend`, `weighted_mean_all`, `zero_access_share` | `twostep`, `mufflyaccess`, `simulation` |
| `acs_year_of`, `CANONICAL_BANDS`, `DENOMINATOR_CATEGORY`, `get_canonical_bands`, `get_primary_access_band`, `mc_weighted_ci`, `PRIMARY_ACCESS_BAND_MIN`, `PRIMARY_ACCESS_BAND_SEC`, `RACE_FEMALE_VARS`, `RUCA_NONMETRO_MIN`, `rurality_from_ruca`, `TOTAL_FEMALE_VAR`, `TRACT_REACHED_COVERAGE_PCT`, `tract_vintage_of` | `twostep`, `mufflyaccess` |
| `cesarean_rate_for_year`, `cohort_vaginal_exposure`, `completed_parity_for_cohort` | `mufflyaccess`, `simulation` |
| `e2sfca_incremental_weights`, `gaussian_band_weights` | `twostep`, `simulation` |
| `canon_npi` | `mufflyaccess`, `isochrones` |
| `haversine_km` | `simulation`, `isochrones` |

The `twostep` / `mufflyaccess` cluster looks like a shared constants module that was copied
rather than depended on. Designating one owner per name and having the other `Depends`/`Imports`
it would remove the masking risk.

---

## S6. Actions

| # | Action | Repo | Status |
|---|---|---|---|
| **A1** | Delete the four shadowed `mysterycall_*` definitions from `extract_demographic_covariates.R`; `library(mysterycall)` instead. Then either call the fetchers to obtain real ACS/AHRF/CMS values or delete the simulated columns outright. | `private_equity` | open |
| **A2** | Add an `exposure` argument to `build_missingness_mcar_table()`; test each item-level variable's missingness against it; make the independence sentence conditional on the result, and drop the claim entirely when no exposure is supplied. | `mysterycall` | in progress |
| **A3** | Export `mysterycall_gate_missingness()` — the hard-failing form of the same test — so studies inherit the gate. | `mysterycall` | in progress |
| **A4** | ~~Replace `assert_join()` with `mysterycall_safe_*_join()` / `mysterycall_assert_unique_keys()`.~~ **Done (re-verified 2026-08-24):** `assert_join()` no longer exists anywhere in the repo; `key_join_index()` in `R/analysis_gates.R` delegates to `mysterycall::mysterycall_safe_left_join()`, and `test-analysis-gates.R` asserts both that the delegation is present and that `assert_join <- function` cannot reappear. | `private_equity` | resolved |
| **A5** | Add a crossover/interaction variant and an optional obtainment-censoring argument to `mysterycall_nb_power()`; retire `run_new_power_analysis.R` in favour of it. | `mysterycall` | open |
| **A6** | Replace `npi_key`, `phone_key`, `address_key`, `strip_suite`, `zip5`, `haversine_distance`, `blank`, `coalesce_cols`, `TitleCase` with canonical calls. Where the canonical lives only in `isochrones`, promote it into `mysterycall` or `mufflyaccess` first. | both | open |
| **A7** | ~~Regenerate the STROBE figure with a canonical mysterycall plotter instead of hand-written diagram code.~~ **Done, 2026-08-24 (re-verified during this audit's follow-up):** `strobe_diagram.R` calls `mysterycall_plot_inclexcl()` (the `counts`/`exclusions`/`title` signature this script needs; `mysterycall_strobe_flow()` also exists but isn't the one wired in). Four of six stage counts are now verified against committed artifacts by inline comment. What remains is not a canonical-function gap: "De-clustered (1/Office)" has no verifiable source (the old value, 544, "matches nothing in the current pipeline") and the script deliberately sets it `NA` and `stop()`s rather than guess -- same class of fix as the frozen-geo-reference and `pe_obgyn_study_database.csv` gaps elsewhere in this repo. That gap needs the real de-clustering step's output restored, not a code change. | `private_equity` | **resolved (canonical function); one real data gap remains, tracked separately, not a duplication issue** |
| **A8** | Assign one owning package for each of the 28 duplicated exports; have the others import. | all | open |
| **A9** | Add a repository gate that fails when a script defines a function whose name is exported by an attached canonical package — the shadowing in A1 would have been caught at the moment it was written. | `private_equity` | open |

---

## S7. Reproducing this audit

```
Rscript scratch/namespace_audit.R > scratch/namespace_audit.out   # enumeration + intersection
Rscript scratch/dupes.R                                           # cross-package duplication
```

Both read `NAMESPACE` from the local checkouts. Re-run after any `git pull` in the package
repositories, since the audit's claims about what is canonical are only as current as those
trees.
