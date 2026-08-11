# Supplementary Appendix S2. Covariate Provenance, Reconstruction, and Independence Audit

*Private equity ownership and appointment access in obstetrics and gynecology: a simulated-patient audit*

Prepared 2026-08-10. Companion to Supplementary Appendix S1 (statistical power), which this
appendix revises in four places (§S2.14). All code, seeds, and intermediate artifacts referenced
here are in the study repository.

---

## S2.1 Purpose

This appendix documents a post-specification audit of covariate provenance, missingness,
reconstruction, and observational independence in the matched private-equity (PE) and control
clinician sample. The audit was undertaken after discrepancies were identified between the
prespecified analysis plan, which included the Centers for Disease Control and Prevention Social
Vulnerability Index (CDC SVI) as a covariate in the primary wait-time model, and the analytic
dataset used for model fitting.

The purpose of the audit was not to modify the prespecified estimand or to selectively alter
covariates after examining treatment effects. No outcome data have been collected; the audit was
conducted entirely on the sampling frame and the covariate file before fielding. Its object was
to determine whether the covariates entering the model represented observed clinician or practice
characteristics, whether their distributions were plausible and balanced across exposure groups,
and whether observations treated as independent were in fact operationally independent at the
level at which appointments are scheduled.

## S2.2 Trigger for the audit

The audit was triggered by a distributional and provenance review of the 11 covariates attached
to the fielded cohort. CDC SVI was present for all 200 PE clinicians but for only 106 of 200
matched controls. Missingness in the prespecified SVI covariate was therefore strongly associated
with exposure status (Fisher exact test, *P* = 5.1 × 10⁻³⁵).

A complete-case analysis retaining CDC SVI would have reduced the usable matched sample from 200
pairs to 106. This was not a conventional pattern of sporadic missingness; it was nearly
structurally confounded with study arm.

The source records showed that all 94 affected control clinicians had complete street addresses
and ZIP codes. None of the 94 appeared in the clinician-churn file. The missing values therefore
reflected a failure of the geographic enrichment pipeline rather than absence of geographic
information.

The audit subsequently identified two further issues, each larger than the one that prompted it.
First, the existing CDC SVI column could not be traced to any geographic linkage, and its
distribution was inconsistent with the quantity it purported to measure; the same was true of
seven of the ten remaining covariates. Second, some nominally distinct clinician observations
share a practice telephone number, and in two matched pairs the PE clinician and the matched
control are reached through the same scheduling line.

---

## S2.3 Distributional audit of the attached covariates

Table S2.1 reports the audit of all 11 covariates. For each variable we examined completeness by
exposure group, range, the distributional family the values follow, whether the extreme values
coincide with a truncation bound, and whether the values could be traced to a generating
procedure in the repository.

Two tests carry most of the weight. First, a Kolmogorov–Smirnov comparison against a fitted
Normal distribution, because the identified generating procedure draws from `rnorm()`. Second,
for CDC SVI specifically, a comparison against the uniform distribution, because `RPL_THEMES` is
a national **percentile ranking** and is therefore approximately uniform on [0, 1] by
construction; normality is disqualifying on its own. A pile of observations at an exactly round
minimum or maximum indicates a `pmax`/`pmin` clamp rather than an empirical range.

### Table S2.1. Distributional and provenance audit of the 11 attached covariates

| Covariate | PE | Control | Distributional finding | Provenance finding | Disposition |
|---|---:|---:|---|---|---|
| `CDC_SVI` | 200/200 | 106/200 | KS vs Normal *P* = 0.985; KS vs Uniform *P* < 0.001; 6 values at exactly 0.010 and 1 at 0.990 | No geographic linkage recorded; no repository code derives it from any source | **Reconstructed** |
| `Tract_Pct_Female_Private` | 200/200 | 106/200 | KS vs Normal *P* = 0.772; maximum exactly 99.0 | `apply_demographic_covariates.R`: `pmax(10, pmin(99, rnorm(n, 68.2, 8.5)))` | **Not analytic; flagged simulated** |
| `Tract_Pct_Female_Medicaid` | 200/200 | 106/200 | KS vs Normal *P* = 0.750 | Same script: `rnorm(n, 18.4, 5.2)`, clamped | **Not analytic; flagged simulated** |
| `Tract_Pct_Female_Medicare` | 200/200 | 106/200 | KS vs Normal *P* = 0.935 | Same script: `rnorm(n, 11.1, 2.8)`, clamped | **Not analytic; flagged simulated** |
| `Tract_Pct_Female_Uninsured` | 200/200 | 106/200 | KS vs Normal *P* = 0.991; 7 values at exactly 0.0 | Same script: `rnorm(n, 7.9, 3.6)`, `pmax(0, …)` | **Not analytic; flagged simulated** |
| `County_OBGYN_Count` | 200/200 | 106/200 | KS vs Normal *P* = 0.568; 11 values at exactly 1 | Same script: `pmax(1, round(rnorm(n, 42.6, 22.4)))` | **Not analytic; flagged simulated** |
| `County_Medicare_Enrollment` | 200/200 | 106/200 | KS vs Normal *P* = 0.212; 3 values at exactly 100 | Same script: `pmax(100, round(rnorm(n, 75400, 38500)))` | **Not analytic; flagged simulated** |
| `County_Medicaid_Enrollment` | 200/200 | 106/200 | KS vs Normal *P* = 0.956; 11 values at exactly 100 | Same script: `pmax(100, round(rnorm(n, 89200, 45200)))` | **Not analytic; flagged simulated** |
| `Medicaid_Fee_Index` | 200/200 | 106/200 | KS vs Normal *P* < 0.001; 19 distinct values, constant within state in 16 of 23 states | Consistent with a state-level fee-ratio lookup, though not constant within every state; source not independently traced | Retained |
| `PE_Concentration_15mi` | 200/200 | 106/200 | KS vs Normal *P* < 0.001; 55 true zeros; integer-valued | Consistent with a count computed from the PE roster; source not independently traced | Retained |
| `HQ_Distance_Miles` | 200/200 | 106/200 | KS vs Normal *P* = 0.018; continuous, right-skewed | Consistent with the geodesic function in `apply_hq_distance.R` | Retained |

Three findings follow from the table.

**The clamp constants match the generating script exactly.** The seven values at 0.0 for the
uninsured share correspond to `pmax(0, …)`; the eleven values at 1 for the county obstetrician–
gynecologist count correspond to `pmax(1, …)`; the values at exactly 100 in both enrollment
columns correspond to `pmax(100, …)`. `apply_demographic_covariates.R` states in its own header
that it "implements standard fallback simulations to ensure full dataset completeness."

**CDC SVI carries the same signature but is not produced by that script or any other in the
repository.** Its values are consistent with `pmax(0.01, pmin(0.99, rnorm(n, 0.434, 0.193)))`. It
rejects uniformity at *P* < 0.001 while failing to reject normality at *P* = 0.985, and six
observations sit at exactly 0.010 with one at exactly 0.990.

**All 11 covariates are missing for the same 94 control clinicians.** The failure was not
specific to SVI: the entire enrichment block failed to reach the controls added in the most
recent redraw of the matched sample.

The 94 controls with no SVI were therefore the visible edge of the problem rather than the
problem itself. The 306 observations that carried a value carried a simulated one.

---

## S2.4 Why the SVI defect mattered beyond provenance

The original CDC SVI column was not merely incompletely documented. Because values were drawn
independently for each observation and then joined to only part of the cohort, the column created
an exposure-associated covariate difference that does not survive independent reconstruction from
clinician geography.

Among PE clinicians the mean of the original SVI variable was 0.393 across 200 clinicians; among
controls it was 0.511 across 106. The difference of −0.118 corresponds to a standardized mean
difference of **−0.62**, a large imbalance by any conventional threshold, and it was statistically
significant (Welch *P* = 1.1 × 10⁻⁶).

Following reconstruction, the mean was 0.484 among the 197 PE clinicians and 0.492 among the 197
controls for whom a reconstructed value was available. The difference of −0.007 corresponds to a
standardized mean difference of **−0.03** (Welch *P* = 0.79). The reconstructed data are
consistent with no meaningful difference in neighborhood social vulnerability between the matched
groups.

In practical terms the defective column did not simply add noise or fail to improve precision. It
introduced an apparent relationship between exposure status and social vulnerability that is
absent from the measured geography. Because SVI was specified as an adjustment covariate in the
primary wait-time model, use of the defective variable could therefore have induced rather than
removed confounding. Had the imbalance reached Table 1, it would have read as a substantive
failure of the matching on neighborhood deprivation. The matching did not fail; the covariate was
not a measurement.

We refer to this as a **manufactured confounder**: the apparent exposure–covariate relationship
arose from the construction of the analytic variable rather than from the measured geographic
characteristics of the clinicians.

---

## S2.5 Reconstruction of CDC SVI

CDC SVI was reconstructed independently of the original analytic column. Reconstruction began
from the recorded practice street address and ZIP code for each clinician and did not use PE
status, appointment outcome, wait time, or any value from the original SVI field to determine the
replacement value.

### Table S2.2. Reconstruction chain for CDC SVI

| Step | Input | Operation | Output | Role |
|---|---|---|---|---|
| 1 | Clinician source record | Extract NPPES practice street address, city, state, ZIP; restore ZIP zero-padding | Standardized address | Source geography |
| 2 | Standardized address | Census Bureau batch geocoder, `benchmark=Public_AR_Current`, `vintage=Census2020_Current` | 2020 census tract identifier | Primary geographic linkage |
| 3 | Census tract identifier | Link to CDC/ATSDR SVI 2022 state files, field `RPL_THEMES` | CDC SVI percentile | Primary reconstruction |
| 4a | Address not placed at step 2 | Retry single-address endpoint with suite designator stripped | Census tract identifier | First fallback |
| 4b | Address still not placed | Recover tract from stored practice coordinate, where recorded | Census tract identifier | Second fallback |
| 4c | Address unresolvable by the geocoder | Area-weighted mean over tracts intersecting the ZCTA, from the Census 2020 ZCTA-to-tract relationship file | ZIP-approximate SVI | Third fallback |
| 5 | Reconstructed SVI | Range check; CDC's −999 unavailable code mapped to missing | Validated SVI field | Analytic covariate |
| 6 | Original SVI, retained unmodified | Compare original with reconstructed values | Audit metrics | Validation only |

The 2020 tract vintage is required rather than optional: SVI 2022 is published on 2020 tract
boundaries, so geocoding against another vintage would link to the wrong geography.

### Table S2.3. Method by which each clinician's value was obtained

| Method | PE | Control | Total | Geographic precision |
|---|---:|---:|---:|---|
| Address, batch geocoder | 176 | 166 | 342 | Census tract |
| Address, retry with suite designator stripped | 1 | 0 | 1 | Census tract |
| Stored practice coordinate | 19 | 0 | 19 | Census tract, coordinate-dependent |
| ZCTA area-weighted mean | 1 | 31 | 32 | ZIP approximation |
| Unresolved | 3 | 3 | 6 | — |
| **Total** | **200** | **200** | **400** | |

The reconstruction recovered CDC SVI for 197 of 200 PE clinicians and 197 of 200 controls, across
312 distinct census tracts. Three observations in each arm remained without a validated value.
These were retained as missing rather than assigned a simulated or inferred value. Every
observation records its linkage method in the variable `SVI_geocode_via`, so that geographic
precision can be modeled, adjusted for, or used as an exclusion criterion rather than assumed
uniform.

The 31 control addresses that required the ZCTA fallback could not be placed by the Census
geocoder because its TIGER address ranges do not cover them. This is a limitation of the
reference geography rather than a formatting problem, and repeated retries do not resolve it.

---

## S2.6 Validation of the reconstructed SVI field

The reconstructed field was validated internally and against the original column where the latter
was present.

### Table S2.4. Validation of reconstructed versus original CDC SVI

| Metric | Original CDC SVI | Reconstructed CDC SVI |
|---|---:|---:|
| PE clinicians with nonmissing value | 200 / 200 | 197 / 200 |
| Control clinicians with nonmissing value | 106 / 200 | 197 / 200 |
| Fisher exact test, missingness by exposure | *P* = 5.1 × 10⁻³⁵ | ***P* = 1.00** |
| Complete matched pairs | 106 / 200 | **197 / 200** |
| PE mean | 0.393 | 0.484 |
| Control mean | **0.511** | 0.492 |
| PE − control mean difference | **−0.118** | **−0.007** |
| Standardized mean difference | **−0.62** | **−0.03** |
| Welch test for the difference | *P* = 1.1 × 10⁻⁶ | *P* = 0.79 |
| Kolmogorov–Smirnov vs Uniform(0, 1) | *P* < 0.001 | ***P* = 0.073** |
| Observations at exactly 0.01 / 0.99 | 6 / 1 | 0 / 0 |
| Distinct census tracts represented | Not recorded | 312 |

### Concordance between the two fields

Concordance was assessed on the 303 clinicians for whom both fields are present.

| Concordance metric | Value | Expected under independence |
|---|---:|---:|
| Pearson correlation | 0.138 | 0 |
| Spearman correlation | 0.118 | 0 |
| Mean absolute difference (percentile units) | 0.248 | — |
| Median absolute difference | 0.226 | — |
| Root-mean-square difference | 0.307 | — |
| Agreement within 0.05 | 15.5% | — |
| **Agreement within 0.10** | **26.4%** | **22.5% (95% interval 18.2–27.1)** |
| Agreement on SVI quartile | 29.7% | 25.0% |

**The original field agrees with the measured geography no better than chance.** Observed
agreement within 0.10 percentile units, 26.4%, falls inside the interval expected if the two
fields were statistically independent, obtained by permuting the reconstructed values (2,000
permutations). The mean absolute discrepancy of 0.248 on a 0–1 percentile scale is approximately
a quarter of the full range of the measure.

Exact geographic agreement cannot be computed because the original field carries no census tract,
county, or other geographic identifier; this absence is itself part of the provenance finding.

The reconstructed variable is used for subsequent analyses because its derivation traces to
observed clinician geography and can be reproduced without reference to study exposure or
outcome. The original field is retained in the dataset, unmodified, for provenance and sensitivity
analysis only. It is not treated as a measurement of neighborhood social vulnerability.

---

## S2.7 Residual limitations of the SVI reconstruction

Six of 400 clinicians, three in each exposure group, remain without a validated reconstructed
value. These were not imputed for the purpose of achieving complete covariate coverage. Because
the residue is balanced across arms, it does not reintroduce exposure-dependent missingness; a
complete-case model loses three pairs.

**Geographic precision remains asymmetric across arms even though missingness no longer is.**
Thirty-one controls and one PE clinician carry the coarser ZCTA-level value, whereas nineteen PE
clinicians and no controls carry a value derived from a stored coordinate. Restricting to
address-level tract linkage leaves 177 PE and 166 control clinicians and **154 matched pairs in
which both members are address-level**. This asymmetry is measured rather than removed, and is the
reason the linkage method ships as an analytic variable.

**ZCTA is not ZIP.** For five-digit residential ZIP codes the approximation is conventional, but
it remains an approximation, and the weighting is by land area rather than by population because
the Census relationship file does not carry population overlap.

**SVI is a contextual rather than a clinician-level characteristic.** A practice-address SVI value
describes the social vulnerability of the area containing the practice. It should not be
interpreted as a measure of the socioeconomic characteristics of the individual clinician or of
the patients that clinician serves.

The reconstruction also depends on the accuracy of the recorded practice location and on the
geographic vintage used for the linkage. These sources of uncertainty are materially different
from the original defect, however, because they are observable, reproducible, and independent of
exposure assignment.

---

## S2.8 Audit of observational independence

The matched design treats the 200 PE–control pairs as distinct comparisons. We therefore audited
whether each clinician observation represents a distinct scheduling pathway.

**Two telephone keys must be distinguished, and conflating them misstates the finding.** The
number a caller will dial is the clinician's NPPES registered number, recorded on the calling
sheet; **all 400 of these are distinct**, so no clinician is dialed on a number shared with
another and no office receives duplicate calls under two clinician identities. Under the practice
number carried in the study database — the scraped practice line, falling back to NPPES and then
to the Centers for Medicare & Medicaid Services DAC file — the same 400 clinicians resolve to
**385 lines**. A distinct registered number does not establish a distinct scheduler.

### Table S2.5. Independence structure of the fielded sample

| Unit | Count | Interpretation |
|---|---:|---|
| Matched pairs fielded | 200 | Nominal primary matched units |
| Clinician observations | 400 | Two clinicians per pair |
| Distinct dialed numbers | 400 | No clinician is dialed twice |
| Distinct practice lines | 385 | Shared scheduling infrastructure |
| Practice lines serving more than one clinician | 12 | Covering 27 clinicians |
| Maximum clinicians on one line | 4 | That line receives 8 calls |
| Pairs with identical PE and control practice line | 2 | Within-pair operational dependence |
| Same-line pairs in the 459-pair pool | 16 | Potential dependence if additionally sampled |
| Pairs sharing a normalized street address | 0 | Shared switchboard, not shared premises |
| Office-disjoint attainable ceiling | 244 pairs | Best of 2,000 randomized restarts |
| Counting upper bound for office-disjoint matching | 307 pairs | Upper bound, not necessarily attainable |

### Table S2.6. Clinicians per practice line

| Clinicians on the line | 1 | 2 | 3 | 4 |
|---|---:|---:|---:|---:|
| Lines | 373 | 10 | 1 | 1 |
| Clinicians | 373 | 20 | 3 | 4 |
| Calls the line receives | 2 | 4 | 6 | 8 |

Twelve lines serve 27 clinicians. Several span different cities, identifying them as centralized
scheduling numbers for multi-site groups rather than single offices: one line covers four fielded
clinicians across Edina, Minneapolis, and Saint Paul, and will receive eight calls.

**Two fielded pairs assign the PE clinician and the matched control to the same practice line.**
In `pair_321` (Edina and Minneapolis) and `pair_437` (Hartford and Danbury) a caller attempting to
schedule with either clinician reaches the same scheduling system. These comparisons do not
represent independent scheduling environments despite comprising distinct clinician records.
Sixteen such pairs exist in the 459-pair candidate pool; two were drawn into the fielded 200. No
fielded pair shares a normalized street address, so the dependence arises from a shared
switchboard rather than from shared premises.

A shared telephone number does not prove that every call is handled by the same individual
scheduler. It does establish that the observations share an entry point into the scheduling
system and therefore cannot be assumed to represent independent access processes.

These relationships are recorded on the calling sheet as the variables `phone_id`,
`phone_dialed`, `phone_practice`, `office_addr_key`, `clinicians_per_phone`, `calls_per_phone`,
`pairs_per_phone`, `same_phone_within_pair`, and `same_address_within_pair`. No observation was
added, removed, or altered.

---

## S2.9 Prespecified sensitivity analyses

Five sensitivity analyses are specified in advance of data collection to determine whether
conclusions depend materially on the SVI defect, residual missingness, shared scheduling
infrastructure, or censoring assumptions.

**Sensitivity analysis 1: reconstructed SVI.** The primary adjusted wait-time model will be fitted
using the reconstructed CDC SVI field in place of the original column, on the 197 complete pairs.

**Sensitivity analysis 2: exclusion of within-pair shared telephone numbers.** The analysis will
be repeated excluding `pair_321` and `pair_437`, leaving 198 pairs.

**Sensitivity analysis 3: telephone-level dependence.** Inference will be recalculated treating
the normalized practice line rather than the clinician as the clustering unit, 385 units rather
than 400.

**Sensitivity analysis 4: geographic precision.** The analysis will be repeated restricted to the
154 pairs in which both members carry an address-level tract linkage, and separately with the
linkage method entered as a precision indicator.

**Sensitivity analysis 5: covariate omission.** The primary estimand will be reported without the
SVI covariate, so that the contribution of the reconstruction to the result is visible.

Analyses 2 and 3 address a threat that operates in the anticonservative direction. Analyses 4 and
5 address the reconstruction itself. Analysis 4 is intended to quantify the effect of residual
geographic imprecision and is not offered as the preferred remedy for the original arm-dependent
missingness, which has been repaired at source.

---

## S2.10 Two distinct pipeline defects

The investigation identified two failures that should not be conflated.

**Failure of the enrichment join.** All 11 covariates are absent for the same 94 control
clinicians. Every affected observation had a recorded street address and ZIP code, and none
appeared in the clinician-churn file, confirming that the problem was not explained by an office
move or by loss of clinician identity. The enrichment step simply was not rerun after the most
recent redraw of the matched sample. The geographic pipeline has been revised so that SVI
derivation begins from the canonical clinician address and explicitly records the source of the
geographic match; ZIP-based recovery is used only under documented conditions and cannot silently
overwrite an exact geographic match.

**ZIP-code zero truncation.** Seven NPPES ZIP codes had lost a leading zero — `1604` for
Worcester, Massachusetts; `6880` for Westport, Connecticut; `8901` for New Brunswick, New Jersey —
the signature of a value coerced through a numeric type. This is the same defect class as the
previously corrected National Provider Identifier float suffix. An unpadded ZIP either fails to
geocode or geocodes to a different place, so the padding is restored during reconstruction rather
than the affected observations being dropped. Other fields that pass through a numeric coercion
should be swept for the same defect.

The distinction matters because ZIP codes are postal delivery units rather than stable census
geographies. A ZIP-derived geographic assignment is a usable fallback but is not equivalent to a
validated street-level linkage, and the crosswalk used must be documented.

---

## S2.11 Quantities that remain simulation-based

The audit separates empirically observed defects from quantities that require simulation.

**Office-disjoint sampling ceiling — resolved empirically.** The largest set of matched pairs that
can be fielded without dialing any office for two different pairs was explored by randomized
greedy search. The best solution among 2,000 randomized restarts yielded **244** office-disjoint
pairs, against a counting upper bound of 307. The previously reported ceiling of 224 was
incorrect and resulted from a weaker greedy ordering. The practical expansion available from the
current 200-pair sample is therefore at most approximately 44 additional pairs under the best
solution identified to date. The search records its seed and restart count and should not be
interpreted as a proof of the global maximum.

**Censoring-aware power — completed.** Wait time is observed only when a clinic offers an
appointment date. Under the anticipated obtainment proportions, 800 placed calls yield
approximately 622 observed wait times, and the private-equity Medicaid cell that identifies the
interaction falls from 200 to approximately 82. Simulations retaining each call at its cell's
obtainment probability are reported in Supplementary Appendix S1, Table S1.4, and are summarized
here for the effect-size scenarios that bear on sample size.

### Table S2.7. Censoring-aware power for the ownership-by-insurance interaction

Negative-binomial generalized linear mixed model with a clinician random intercept; interaction
tested alone at α = 0.05; wait-time standard deviation 10 days; 200 replicates per row; all fits
usable. The uncensored column is Appendix S1, Table S1.1.

| Matched pairs | Calls placed | Wait times observed | PE-Medicaid cell | Censored power | Uncensored power |
|---:|---:|---:|---:|---:|---:|
| **200 (fielded)** | 800 | 622 | 82 | **0.690** | 0.870 |
| **244 (attainable ceiling)** | 976 | 758 | 99 | **0.810** | — |
| 250 | 1000 | 777 | 102 | 0.840 | 0.945 |
| 300 | 1200 | 932 | 123 | 0.910 | 0.950 |
| 400 | 1600 | 1244 | 163 | 0.960 | 0.990 |
| 500 | 2000 | 1558 | 206 | 0.980 | — |

Monte Carlo standard error is 0.028 at a power of 0.81 and 0.033 at 0.69; differences smaller
than approximately 0.06 between adjacent rows should not be interpreted.

**Incremental power from 200 to 244 pairs is 0.690 to 0.810, a gain of 0.12.** Expansion to the
attainable office-disjoint ceiling therefore moves the design from clearly underpowered to
marginally adequate for the primary wait-time estimand under the primary effect-size scenario.
It does not, however, address any of the measurement or dependence problems documented above,
and the gain is contingent on the assumed effect size.

> **PENDING.** The conservative (1.10) and larger plausible (1.35) scenarios under censoring, at
> both 200 and 244 pairs, and the intermediate 220-pair row, were still computing when this
> appendix was frozen (`scratch/power_censored_244_and_scenarios.R`). Per guard 10 in §S2.12 they
> are not estimated or interpolated here. Under the uncensored grid the conservative scenario
> reaches only 0.290 at 200 pairs and 0.560 at 400, so no feasible sample size is expected to
> rescue it once censoring is applied.

**Effect-size scenarios — partially complete.** The conservative (incidence rate ratio 1.10) and
primary (1.22) scenarios are complete under both the uncensored and censored designs. The larger
plausible scenario (1.35) was still computing under the uncensored grid when this appendix was
frozen; `power_analysis_new_results.csv` on disk therefore remains the superseded grid and has not
been used to populate any table here.

The audit findings themselves do not depend on any of these simulations. In particular, restoring
a valid SVI value for the affected controls addresses a measurement problem that cannot be solved
by recruiting additional clinics.

---

## S2.12 Data and code guards added after the audit

Forty-seven assertions were added across two test files, all passing. They exist because the
preceding covariate tests passed on the simulated column: those tests verified that SVI lay in
[0, 1], was near-continuous, and had a median within 0.25 of 0.5 — conditions a plausible
simulation satisfies trivially. The guards now enforced are:

1. Covariate completeness is reported separately by exposure group before model fitting.
2. A difference in covariate missingness between exposure groups is a test failure rather than
   silent complete-case deletion. (Fisher exact test, `test-svi-provenance.R`.)
3. A covariate claiming to be a percentile ranking must not reject uniformity.
4. No covariate may show a pile of observations at a round truncation bound.
5. Every nonmissing covariate value must name its source and its linkage method.
6. A reconstructed field must not be identical to, or strongly correlated with, the field it
   replaces.
7. Normalized telephone numbers are retained as identifiers for dependence auditing.
8. A matched pair whose two arms share a practice line is automatically flagged.
9. The number of clinicians per practice line is reported before final inference, and no line may
   receive more calls than the protocol contemplates.
10. Simulation-derived quantities may not populate manuscript tables until the corresponding run
    has completed and passed its reproducibility checks.

---

## S2.13 Reproducibility

| Item | Value |
|---|---|
| Distributional audit | `scratch/audit_enrichment_provenance.R` (Table S2.1) |
| Reconstruction | `build_svi_covariate.R` (Tables S2.2, S2.3) |
| Validation and concordance | `scratch/s2_fill.R` (Table S2.4) |
| Independence variables | `build_phone_cluster_vars.R` (Tables S2.5, S2.6) |
| Office-disjoint search | `scratch/office_disjoint_ceiling.R`; `set.seed(42)`, 2,000 restarts |
| Censoring-aware power | `scratch/power_with_obtainment_censoring.R`, `scratch/power_censored_244_and_scenarios.R` |
| Geocoder | Census Bureau, `benchmark=Public_AR_Current`, `vintage=Census2020_Current` |
| Social vulnerability release | CDC/ATSDR SVI 2022, tract-level state files, field `RPL_THEMES` |
| ZCTA crosswalk | Census 2020 ZCTA-to-tract national relationship file |
| Output variables | `CDC_SVI_real`, `SVI_tract_fips`, `SVI_geocode_via`, `SVI_source` |
| Software | R 4.4.2; glmmTMB 1.1.14; TMB 1.9.21; dplyr; readr |
| Tests | `tests/testthat/test-svi-provenance.R` (16), `test-phone-clustering.R` (31) |

The reconstructed CDC SVI variable is generated from source clinician geography through a
deterministic linkage pipeline. The original field is preserved in the dataset and is not
overwritten, permitting direct comparison. All exclusions and sensitivity-analysis indicators are
represented as explicit variables rather than implemented through undocumented row deletion:
reconstructed-SVI availability, linkage method, shared telephone number within a matched pair,
practice-line cluster membership, and censoring status.

No pending simulation result has been replaced manually. Manuscript tables are populated only from
completed analysis artifacts produced by the corresponding code.

---

## S2.14 Revisions to Supplementary Appendix S1 and to the primary analysis

The audit produced four substantive revisions.

**First**, CDC SVI in the primary adjusted model is defined as the independently reconstructed
geographic measure rather than the prior analytic column. Appendix S1 §S1.8(b) previously
described the covariate as missing for 94 controls; it was simulated for all 306 observations that
carried a value, and the section has been rewritten.

**Second**, residual SVI missingness is reported explicitly. The analysis no longer treats
arm-dependent missingness in the previous field as ordinary complete-case loss. Complete-case
analysis now retains 197 pairs rather than 106.

**Third**, the independence assumptions of the fielded sample are qualified. Appendix S1 §S1.8(c)
previously stated that the 400 clinicians occupy 385 *dialable* numbers; all 400 dialed numbers
are distinct, and 385 is the count of practice lines. The manuscript now distinguishes clinicians,
matched pairs, dialed numbers, and practice lines, and reports sensitivity analyses addressing
within-pair and between-observation telephone overlap.

**Fourth**, power calculations and sample-size discussion distinguish the theoretical benefit of
additional matched pairs from unresolved problems of measurement, dependence, and censoring.
Appendix S1 §S1.8(d) gave the office-disjoint ceiling as 224 pairs; the corrected best identified
solution is 244.

The principal methodological conclusion of the audit is not that a larger sample is unnecessary in
all circumstances. It is that increasing the number of sampled clinicians cannot correct a
covariate that was differentially missing or incorrectly constructed, cannot make two calls
through the same scheduling system independent, and cannot resolve bias introduced by
inappropriate treatment of censored outcomes. These problems must be addressed at the measurement
and analysis stages before any benefit from additional sampling can meaningfully be evaluated.
