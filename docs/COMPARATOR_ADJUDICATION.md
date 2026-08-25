# Comparator validation against PECOS and CMS Doctors and Clinicians

**Date:** 2026-08-25. **Scope:** does the control arm satisfy the prespecified comparator?
**Standing constraint:** nothing was changed — not the cohort, pairs, REDCap, caller materials,
`SAP.lock`, or the manuscript. This document and its artifacts exist to support a decision.

`SAP.lock` names the contrast **"PE vs independent"**. The COMIRB protocol restricts controls to
**"independent private practices"**. No step in the pipeline ever tested that.

---

## S1. The archive, frozen

`/Volumes/MufflySamsung/pecos_data/` and `/Volumes/MufflySamsung/PPEF_Data/`. All 23 files are
inventoried with sha256 and row counts in `data/comparator/pecos_source_manifest.csv`.

**The `pecos_data/` directory is not a current snapshot.** Its zip members are dated
`2019-04-15`; the Nov 2025 file timestamps are extraction dates. Quote-normalised sha256 proves
it byte-identical to the 2019 vintage:

| File | vs `PPEF_Data/*_2019.csv` |
|---|---|
| `ppefenrol` / `ppefreassign` / `ppefaddr` / `ppefspec` | **identical** |

| Snapshot type | Vintages held |
|---|---|
| PPEF enrolment | 2016, 2017, 2019, 2023Q3, 2024Q3, 2025 |
| **PPEF reassignment** | **2016, 2017, 2019 only** |
| DAC National Downloadable File | 2014 → **05/2024** |
| DAC Facility Affiliation | plus **06/2026** |

**The affiliation chain requires reassignment, so PECOS alone stops at 2019** — seven years
before fielding. The latest vintage carrying organisation identity *and* practice location
*and* predating fielding is therefore **DAC 05/2024**, which is itself PECOS-derived. It is the
primary measurement; PECOS 2019 corroborates and supplies the temporal view.

## S2. Linkage, dually verified

The chain, with **PAC ID** as the entity key, not organisation NPI:

`NPI → individual ENRLMT_ID → REASGN_BNFT_ENRLMT_ID → RCV_BNFT_ENRLMT_ID → organisation PAC ID`

Two implementations sharing no code: Python dictionaries and row-wise accumulation, against
Unix external **sort-merge** joins over the raw files.

| Compared | impl 1 | impl 2 | Disagreements |
|---|---:|---:|---:|
| (NPI, receiving enrolment) pairs | 472 | 472 | **0** |
| (NPI, organisation PAC ID) pairs | 463 | 463 | **0** |
| PAC-level member counts | 311 orgs | 311 orgs | **0** |
| DAC (NPI, org PAC) pairs | 345 | 345 | **0** |

The DAC pass was re-verified a third way, in Perl with an independent regex CSV parser; record
counts matched exactly (2,563,744), confirming no embedded newlines.

`I → I` reassignments (3,898) are excluded: the receiving party is a person, not an organisation.

## S3. Two findings that prevent misclassification

**Hospital affiliation is not employment.** 244 of 400 clinicians carry a CMS facility
affiliation, almost all "Hospital". An OB/GYN needs admitting privileges to deliver. Using this
as evidence of employment would have condemned most of the cohort. It is recorded and never
used to classify.

**PECOS provider type does not discriminate.** 461 of 463 receiving organisations are
`PART B SUPPLIER - CLINIC/GROUP PRACTICE` — what a health-system employed medical group enrols
as, and what an independent group enrols as.

## S4. THE PRINCIPAL FINDING — control-arm exposure contamination

This is not the independence question, and it is more serious.

The study's own roster (`pe_obgyn_providers_active.csv`, 1,279 NPIs across 13 PE platforms)
defines the exposure. Testing control NPIs against it directly:

| Test | Result |
|---|---:|
| Control NPIs appearing in the PE roster | **0 / 200** |
| PE-arm NPIs appearing in the PE roster (positive control) | **200 / 200** |

Exposure assignment is internally consistent *at the level of the individual*. But that only
shows the roster is **incomplete**, not that controls are independent. Testing at the level of
the **organisation** — do controls bill through a CMS organisation that contains a roster
clinician?

| Frame | Controls in a PE-platform organisation | Pairs affected |
|---|---:|---:|
| **Fielded (200 controls)** | **61 (30.5%)** | **61** |
| Eligible universe (459 controls) | 223 (48.6%) | 209 |

Platforms involved, fielded frame: Axia Women's Health (16), Unified Women's Healthcare (15),
Women's Care Enterprises (15), Femwell Group Health (7), Nova Women's Health Partners (4),
Advantia Health (4), CCRM Fertility (1).

Independently confirmed: 21 organisations, 46 controls sharing an organisation with a *fielded*
PE-arm clinician, reproduced exactly by both implementations. External verification confirms the
largest are private-equity platforms: Women's Care (BC Partners → Lindsay Goldberg), Axia
(Audax → Partners Group), Unified Women's Healthcare.

**A redraw does not fix this.** The eligible universe is proportionally worse (48.6% vs 30.5%).
Only **236 of 459** universe controls are free of a PE-platform link.

## S5. Adjudicated comparator status

`data/comparator/comparator_adjudication.csv`, 1,845 rows covering the fielded frame, the
eligible universe, and the full roster. Three states; ambiguity is never forced.

| | Fielded controls (200) | Eligible universe (459) |
|---|---:|---:|
| `not_independent_supported` | **91** | 271 |
| `independence_unresolved` | 87 | 165 |
| `independent_supported` | **22** | 23 |

Location resolution: 198/200 fielded controls resolved to a single organisation; 2 ambiguous.

Affirmative evidence of independent private practice exists for **22 of 200** fielded controls.

## S6. Size, kept as measurement — never as definition

The protocol says "independent private practice"; it prespecifies no headcount. A 30-physician
physician-owned group can be independent; a 4-physician hospital-owned clinic is not.

| Measure | min | median | max |
|---|---:|---:|---:|
| Existing `num_org_mem` | 2 | 252 | 7,694 |
| DAC national clinicians | 0 | 230 | 7,694 |
| **DAC local (sampled office)** | 0 | **8** | 1,606 |

The gap between national and local is the whole point: the median control sits in an
**8-clinician office belonging to a 230-clinician organisation**. Descriptive thresholds, for
sensitivity only:

| ≤ | 1 | 5 | 10 | 25 | 50 | 100 |
|---|---:|---:|---:|---:|---:|---:|
| national | 2 | 18 | 25 | 36 | 51 | 61 |
| local | 15 | 73 | 105 | 131 | 142 | 148 |

Recommended covariates for Table 1 and sensitivity: `log1p(dac_local_clinicians)` and
`log1p(dac_national_clinicians)`, **separately**.

## S7. Reconciliation with the existing `num_org_mem`

| Comparison | Result |
|---|---:|
| Controls with both measures | 173 / 200 |
| `num_org_mem` == DAC national clinicians | **168 / 173** |
| DAC national more than 2× existing | 0 |

The two agree because they are the same quantity: `control_candidates_raw.csv` is a DAC extract.
The earlier disagreement was mine — my first probe used **PECOS 2019 PAC-level reassignment
counts**, a different vintage and a different entity resolution, and took `max()` across all
affiliations. That probe's "53 at ≤10, 11 solo" is superseded by "25 at ≤10 national, 105 at ≤10
local". The old measure tracked **national** size, and reported 23 controls at ≤10 — consistent
with the 25 found here.

## S8. Evidence category

**C — comparator materially violated.** Not on the independence definition, which remains
partly unresolvable from administrative data, but on the finding above it: 61 of 200 controls
bill through organisations containing clinicians the study itself classifies as PE-owned, and
only 22 of 200 have affirmative evidence of independent private practice.

Because a redraw from the eligible universe is proportionally worse, the available options are
restriction and re-matching against a comparator definition fixed in advance — not a redraw.

## S9. What is NOT established

PECOS and DAC record **where Medicare benefits are reassigned and billed**, not ownership. A
shared organisation is strong evidence of a shared corporate practice platform; it is not a
title search. The 87 unresolved controls are unresolved, and the manual adjudication columns
(`external_source`, `evidence_date`, `adjudicator`, `adjudication_confidence`,
`adjudication_note`) are present and empty by design, awaiting human adjudication.

Enforced by `tests/testthat/test-comparator-adjudication.R` (blocking): missing evidence cannot
imply independence; admitting affiliation cannot imply employment; size alone cannot decide
ownership; classification is order-invariant and deterministic; any definitive classification
must retain affirmative evidence; and the contamination count cannot be zeroed out. Ten
mutations, all caught.
