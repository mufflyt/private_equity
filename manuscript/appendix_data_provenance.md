# Appendix S2. Provenance and integrity of the analysis covariates

*Private equity ownership and appointment access in obstetrics and gynecology: a simulated-patient audit*

Prepared 2026-08-10. Companion to Appendix S1 (statistical power), which this appendix revises
in two places. All code, seeds and intermediate files referenced here are in the study
repository.

---

## S2.1 Purpose

This appendix documents an audit of the contextual covariates attached to the fielded cohort,
the discovery that several of them were simulated rather than measured, the reconstruction of
the one that enters the primary model, and a second structural finding about which observations
in the sample are independent of one another.

It is written at this length because the defect was invisible to inspection. Every value was in
range, plausibly distributed, and populated for most of the cohort. Nothing about looking at the
column would have revealed the problem, and the existing test suite passed on it.

## S2.2 What triggered the audit

Appendix S1 reported that the CDC Social Vulnerability Index (SVI), a fixed effect in the
primary wait-time model, was present for 200 of 200 private-equity clinicians and 106 of 200
controls. Missingness perfectly confounded with exposure is a first-order threat to a
complete-case analysis, so the intended repair was to geocode the 94 controls and complete the
column.

Establishing where the existing 306 values came from was the first step of that repair. No
script in the repository produced them from any external source.

## S2.3 The audit

`apply_demographic_covariates.R` generates the tract- and county-level covariates with `rnorm()`
and clamps them to plausible ranges with `pmax`/`pmin`. Its own header describes this as
implementing "standard fallback simulations to ensure full dataset completeness". That accounts
for the `Tract_*` and `County_*` columns explicitly. It does not mention SVI, so each covariate
was tested against the signature that generator leaves: a Normal shape, plus a pile of rows at a
round clamp bound that real data would not reproduce exactly.

**Table S2.1. Distributional audit of the fielded covariates** (n = 306, the rows carrying any
enrichment at all; `scratch/audit_enrichment_provenance.R`).

| Column | Distinct | Min | Max | KS vs Normal | KS vs Uniform | Rows at min | Rows at max | Verdict |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| `CDC_SVI` | 301 | 0.010 | 0.990 | **0.985** | <0.001 | **6** | 1 | **simulated** |
| `Tract_Pct_Female_Private` | 203 | 45.0 | 99.0 | **0.772** | <0.001 | 1 | 1 | **simulated** |
| `Tract_Pct_Female_Medicaid` | 153 | 3.6 | 34.8 | **0.750** | <0.001 | 1 | 1 | **simulated** |
| `Tract_Pct_Female_Medicare` | 103 | 3.4 | 19.0 | **0.935** | <0.001 | 1 | 1 | **simulated** |
| `Tract_Pct_Female_Uninsured` | 126 | 0.0 | 18.9 | **0.991** | <0.001 | **7** | 1 | **simulated** |
| `County_OBGYN_Count` | 85 | 1 | 108 | **0.568** | <0.001 | **11** | 2 | **simulated** |
| `County_Medicare_Enrollment` | 304 | 100 | 220,941 | 0.212 | <0.001 | **3** | 1 | **simulated** |
| `County_Medicaid_Enrollment` | 295 | 100 | 225,112 | **0.956** | <0.001 | **11** | 1 | **simulated** |
| `Medicaid_Fee_Index` | 19 | 0.48 | 0.90 | <0.001 | <0.001 | 36 | 2 | derived (state lookup) |
| `PE_Concentration_15mi` | 31 | 0 | 258 | <0.001 | <0.001 | 55 | 1 | derived (roster count) |
| `HQ_Distance_Miles` | 197 | 18.6 | 1801.5 | 0.018 | <0.001 | 1 | 1 | derived (geodesic) |

The clamp bounds in the simulated rows correspond exactly to the constants in
`apply_demographic_covariates.R`: `pmax(0, pmin(50, ...))` for the uninsured share, whose seven
rows sit at 0; `pmax(1, ...)` for the county OB-GYN count, whose eleven rows sit at 1;
`pmax(100, ...)` for both enrollment counts.

**CDC_SVI carries the same signature and is not produced by that script or any other in the
repository.** The decisive test is the one specific to what SVI claims to be. `RPL_THEMES` is an
overall summary *percentile ranking*, so across a national sample it is approximately uniform on
[0,1] by construction. The shipped column rejects uniformity at p < 0.001 while failing to reject
normality at p = 0.985, with six rows at exactly 0.010 and one at exactly 0.990 — the floor and
ceiling of a `pmax(0.01, pmin(0.99, rnorm(n, 0.434, 0.193)))`.

**The 94 controls with no SVI were therefore the visible edge of the problem, not the problem.**
The 306 rows that carried a value carried a simulated one. All eleven columns above are missing
for the same 94 controls, so the entire enrichment block — not SVI alone — failed to reach the
clinicians added in the most recent redraw.

## S2.4 Why this mattered beyond provenance

A simulated covariate is not merely uninformative. Because it was drawn independently for every
row and then joined to only part of the cohort, it manufactured an apparent imbalance between
the study arms that does not exist in the data.

| | Simulated `CDC_SVI` | Reconstructed `CDC_SVI_real` |
|---|---:|---:|
| PE mean (n) | 0.393 (200) | 0.484 (197) |
| Control mean (n) | 0.511 (106) | 0.492 (197) |
| Standardized mean difference | **−0.621** | **−0.027** |
| Welch *p* | — | 0.785 |

A standardized mean difference of −0.62 is a large imbalance by any conventional threshold. Had
it reached Table 1, it would have read as a substantive failure of the matching on
neighbourhood deprivation, and adjusting for it in the outcome model would have been an
adjustment for an artifact. On the real data the arms are balanced to an SMD of −0.03. The
matching did not fail; the covariate was not real.

Correlation between the simulated and reconstructed columns, on rows where both exist, is 0.138.

## S2.5 Reconstruction

`build_svi_covariate.R` rebuilds the covariate for all 400 fielded clinicians from public
sources only. It writes new columns and leaves `CDC_SVI` in place untouched, so that no
downstream script changes meaning without a visible edit.

**Chain.** NPPES practice address → 2020 census tract, via the Census Bureau batch geocoder
(`benchmark=Public_AR_Current`, `vintage=Census2020_Current`) → `RPL_THEMES`, via the CDC/ATSDR
SVI 2022 state files. The 2020 vintage is required rather than optional: SVI 2022 is published on
2020 tract boundaries, so geocoding against another vintage would join to the wrong geography.
CDC codes unavailable tracts as −999; those become `NA` rather than entering a model as a
numeric −999.

**Fallbacks, in order.** Addresses the batch endpoint cannot place are retried individually with
suite designators stripped. Those still unplaced fall back to a stored coordinate where one
exists. The remainder — addresses the Census geocoder genuinely cannot resolve, because its TIGER
address ranges do not cover them, so retrying does not help — receive an area-weighted mean over
the tracts intersecting their ZCTA, computed from the Census 2020 ZCTA-to-tract relationship
file.

**Table S2.2. How each fielded clinician's value was obtained.**

| Method | PE | Control | Total | Precision |
|---|---:|---:|---:|---|
| Address, batch geocoder | 176 | 166 | 342 | tract |
| Address, retry with suite stripped | 1 | 0 | 1 | tract |
| Stored coordinate | 19 | 0 | 19 | tract, coordinate-dependent |
| ZCTA area-weighted mean | 1 | 31 | 32 | ZIP approximation |
| Unresolved | 3 | 3 | 6 | — |
| **Total** | **200** | **200** | **400** | |

Every row records its method in `SVI_geocode_via`, so precision can be modelled, adjusted for,
or excluded rather than assumed uniform.

## S2.6 Validation

**Table S2.3. The reconstructed column against the one it replaces.**

| Check | Simulated | Reconstructed | Contract |
|---|---:|---:|---|
| PE clinicians with a value | 200 / 200 | 197 / 200 | — |
| Control clinicians with a value | 106 / 200 | 197 / 200 | — |
| Fisher test, missingness by arm | *p* = 5.1 × 10⁻³⁵ | ***p* = 1.00** | must not reject |
| Complete matched pairs | 106 / 200 | **197 / 200** | — |
| KS vs Uniform(0,1) | *p* < 0.001 | ***p* = 0.073** | must not reject |
| Rows at exactly 0.01 / 0.99 | 6 / 1 | 0 / 0 | no clamp pile |
| Distinct census tracts | not applicable | 312 | — |

Missingness is now independent of exposure, and a complete-case fit of the model as specified
retains 197 pairs rather than 106. Appendix S1 §S1.8(b) previously listed this as a live threat
to the power calculation; it is resolved, and the residual sample-size threat there is
obtainment censoring alone.

103 of the 394 clinicians with a value share a census tract with at least one other clinician,
which is why tied SVI values are expected and are not evidence of a defect.

## S2.7 Residual limitations of the reconstructed covariate

**Six clinicians, three per arm, remain without a value.** The residue is balanced, so it poses
no exposure-dependent missingness problem; a complete-case model loses three pairs.

**Measurement precision is not balanced, although missingness now is.** Thirty-one controls and
one PE clinician carry the coarser ZCTA-level value, while nineteen PE clinicians and no controls
carry a value derived from a stored coordinate. Restricting to address-level tract values leaves
177 PE and 166 control clinicians, and **154 pairs in which both members are address-level**.
This asymmetry is measured rather than removed, and is the reason `SVI_geocode_via` ships as a
column.

**ZCTA is not ZIP.** For five-digit residential ZIPs the approximation is standard, but it is an
approximation, and the weighting is by land area rather than population because the relationship
file does not carry population overlap.

## S2.8 Which observations are independent

A second structural question is not about covariates but about the unit of analysis. The design
treats the clinician as independent. That is not true everywhere.

**The number dialed and the number that answers are different keys.** The `Phone` column on the
calling sheet — what a caller enters — is the NPPES registered number, and all 400 are distinct.
No clinician is dialed on a number shared with another. Under the practice number carried in the
study database (scraped practice line, falling back to NPPES then CMS DAC), the same 400
clinicians collapse onto **385 lines**.

**Table S2.4. Clinicians per practice line among the fielded 400.**

| Clinicians on the line | 1 | 2 | 3 | 4 |
|---|---:|---:|---:|---:|
| Lines | 373 | 10 | 1 | 1 |
| Clinicians | 373 | 20 | 3 | 4 |
| Calls the line receives | 2 | 4 | 6 | 8 |

Twelve lines serve 27 clinicians. Several span different cities, which identifies them as central
scheduling numbers for multi-site groups rather than as single offices: one covers four fielded
clinicians across Edina, Minneapolis and Saint Paul and will receive eight calls. Where a shared
line means a shared scheduler, calls to those clinicians are not independent observations,
whatever their registered numbers say.

**Two fielded pairs place both arms on one line.** In `pair_321` (Edina and Minneapolis) and
`pair_437` (Hartford and Danbury) the PE clinician and their matched control route through the
same number, so a caller reaches one scheduler for both arms and the within-pair ownership
contrast is not a contrast. Sixteen such pairs exist in the 459-pair matched pool; two were drawn
into the fielded 200. **No fielded pair shares a normalised street address**, so this is a shared
switchboard rather than a shared physical office.

`build_phone_cluster_vars.R` writes this structure onto the calling sheet as `phone_id`,
`phone_dialed`, `phone_practice`, `office_addr_key`, `clinicians_per_phone`, `calls_per_phone`,
`pairs_per_phone`, `same_phone_within_pair` and `same_address_within_pair`. It changes no rows.

## S2.9 Prespecified analyses these variables support

Stated here so that they are prespecified rather than reconstructed after the results are known.

1. **Primary analysis** as written in the statistical analysis plan, with `CDC_SVI_real` in place
   of `CDC_SVI`, on the 197 complete pairs.
2. **Same-line exclusion.** Repeat the primary analysis excluding pairs with
   `same_phone_within_pair == TRUE` (198 pairs remain).
3. **Line-level clustering.** Refit with the practice line rather than the clinician as the
   clustering unit, 385 units rather than 400, to test whether shared schedulers materially
   change the interaction.
4. **SVI precision.** Repeat restricted to the 154 pairs in which both members carry an
   address-level tract value, and separately with `SVI_geocode_via` entered as a precision
   indicator.
5. **SVI omitted.** Report the primary estimand without the covariate, so that the contribution
   of the reconstruction to the result is visible.

Analyses 2 and 3 address a threat that moves in the anticonservative direction; analyses 4 and 5
address the reconstruction itself.

## S2.10 A data defect found along the way

Seven NPPES ZIP codes had lost a leading zero — `1604` for Worcester MA, `6880` for Westport CT,
`8901` for New Brunswick NJ — the signature of a value coerced through a numeric type. This is
the same defect class as the NPI float suffix corrected earlier. An unpadded ZIP either fails to
geocode or, worse, geocodes to a different place, so it is repaired in
`build_svi_covariate.R` rather than dropped. The repository should be swept for other fields that
pass through a numeric coercion.

## S2.11 What remains simulated

**The `Tract_Pct_Female_*`, `County_OBGYN_Count`, `County_Medicare_Enrollment` and
`County_Medicaid_Enrollment` columns are simulated and have not been reconstructed.** They do not
enter the primary model, but they are named in the repository as though they were measurements
and would be reported as such by anyone who used them. They should either be sourced from the
ACS, HRSA AHRF and CMS releases their names refer to, or renamed and removed from any analytic
role.

`Medicaid_Fee_Index`, `PE_Concentration_15mi` and `HQ_Distance_Miles` do not carry the simulation
signature and appear to be genuinely derived, but their provenance was not independently traced
in this audit and should not be assumed.

## S2.12 Guards added

Two test files were added, 47 assertions, all passing. They exist because the previous enrichment
tests passed on the simulated column: those tests checked that SVI lay in [0,1], was
near-continuous, and had a median within 0.25 of 0.5 — all of which a plausible simulation
satisfies trivially.

- **`tests/testthat/test-svi-provenance.R`** (16). Distributional shape against the uniform a
  percentile rank implies; absence of a clamp pile at a round bound; every value naming its
  source and geocoding method; independence of missingness from exposure by Fisher test;
  coverage and complete-pair floors; and a guard that the reconstructed column is never the
  simulated one copied forward. Each of these fails on the shipped column.
- **`tests/testthat/test-phone-clustering.R`** (31). Every dialed number distinct; cluster sizes
  agreeing with the groups they count; unresolvable numbers never merged into one cluster;
  `same_phone_within_pair` a property of the pair; exactly the two known contaminated pairs
  flagged; and no line receiving more calls than the protocol contemplates.

## S2.13 Reproducibility

| Item | Value |
|---|---|
| Audit | `scratch/audit_enrichment_provenance.R` (Table S2.1) |
| Reconstruction | `build_svi_covariate.R` |
| Clustering variables | `build_phone_cluster_vars.R` |
| Geocoder | Census Bureau, `benchmark=Public_AR_Current`, `vintage=Census2020_Current` |
| SVI release | CDC/ATSDR SVI 2022, tract-level state files, `RPL_THEMES` |
| ZCTA crosswalk | Census 2020 ZCTA-to-tract national relationship file |
| Output columns | `CDC_SVI_real`, `SVI_tract_fips`, `SVI_geocode_via`, `SVI_source` |
| Software | R 4.4.2; dplyr; readr |
| Tests | `tests/testthat/test-svi-provenance.R`, `test-phone-clustering.R` |

## S2.14 Revisions to Appendix S1

- **§S1.8(b)** described SVI as missing for 94 controls. The column was simulated for all 306
  rows that had it. The section is rewritten and the threat is resolved.
- **§S1.8(c)** stated that the 400 clinicians occupy 385 *dialable* numbers. All 400 dialed
  numbers are distinct; 385 is the count of practice lines. The section is corrected.
- **§S1.8(d)** gave the office-disjoint ceiling as 224 pairs, from a weaker greedy ordering. The
  best packing found over 2,000 randomised restarts is **244**, against a counting upper bound of
  307.
