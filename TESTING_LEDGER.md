# Adversarial testing ledger

24 cycles, 10 new tests each, 30-minute intervals. Rotation: cycle n mod 3 = 1 -> 4 BVA /
3 semantic / 3 adversarial; = 2 -> 3/4/3; = 0 -> 3/3/4.

Rules in force: no test may be weakened, skipped, or deleted to obtain a green suite. A
failure that reflects a genuine scientific ambiguity is preserved and escalated rather
than resolved by picking an estimand. When a defect is found, the same bug class is
searched for across the repository before the defect is considered closed.

Run the suite with `Rscript tests/run_tests.R`.

---

## Cycle 1 — 2026-08-09 21:4x — 4 BVA / 3 semantic / 3 adversarial

**Foundation.** No test harness existed (no `tests/`, not an R package). Created
`tests/testthat/`, `tests/run_tests.R`, and `R/pe_helpers.R`, the last holding the pure
key-building helpers extracted verbatim from `dedup_offices_and_backfill_200.R` so they
can be tested without executing a pipeline. The extraction was verified
behaviour-preserving: the de-dup output before and after is byte-identical, and identical
to the live fielded sheet (md5 `4afe625a541b227aecf0acdad6fa634b`).

**Tests added** (`tests/testthat/test-pe_helpers.R`)

| # | Category | Target | Assumption challenged |
|---|---|---|---|
| 1 | BVA | `phone_key` | boundary sits exactly at 10 digits; 9 rejected, 11 truncated to last 10 |
| 2 | BVA | `address_key` | ZIP must be exactly 5 digits; ZIP+4 and pandas float ZIPs normalise correctly |
| 3 | BVA | `npi_key` | strips a float suffix but never a trailing digit that belongs to the NPI |
| 4 | BVA | all three | zero-row input returns zero-length, not an error |
| 5 | semantic | `address_key` | distinct streets sharing a suite-token prefix must not share an office key |
| 6 | semantic | `address_key` | suite/floor designators are stripped so one building is one office |
| 7 | semantic | `npi_key` | idempotent under repeated normalisation |
| 8 | adversarial | `address_key`, `phone_key` | unusable values return NA and never collide with each other |
| 9 | adversarial | `address_key` | an absent optional column behaves identically to a blank one |
| 10 | adversarial | `npi_key`, `phone_key` | factor input yields labels, not integer level codes |

**Failures discovered:** 4, all from test 5, all one defect.

**Root cause.** `address_key()` stripped punctuation *before* removing suite designators.
With the word gaps gone, the alternation `(...|FL|...|NO|...|STE|...)` matched the start of
ordinary street names and the greedy `[0-9A-Z]*` consumed the remainder. `100 FLAGLER ST`,
`100 FLAMINGO AVE` and `100 FLORIDA BLVD` all collapsed to `100_MIAMI_FL_33130`; likewise
`NOLAN`/`NORTH` via `NO` and `STERLING` via `STE`. Distinct offices were therefore treated
as one, which over-blocks the de-duplication and wrongly discards eligible matched pairs.
Florida is worst affected, which is also where the cohort is most concentrated.

**Fix.** Strip designators while the word boundaries still exist: collapse separators to
single spaces, remove `\b(SUITE|STE|...)\b *[0-9A-Z]*`, then remove remaining punctuation.
Smallest change that satisfies the intended contract; no test was altered.

**Same bug class elsewhere** (the important part)

| Location | Status |
|---|---|
| `R/pe_helpers.R` | FIXED this cycle |
| `build_matched_control_group_psm.R:113` | **same defect, not yet fixed** — this is the original `office_id` assignment |
| `add_symmetric_backups.py:34` | **same defect, not yet fixed** |
| `match_all_providers.py:1265` | already correct: uses `\b...\b.*$`. The R path drifted from the Python one. |

**Measured impact on the study cohort.** Recomputing over
`pe_obgyn_study_database.csv` (2,048 rows): **433 rows (21.1%) change office key**, and the
count of distinct offices rises **916 -> 939**, meaning 23 offices were previously merged
that are not the same office.

**UNRESOLVED DECISION — requires sign-off, deliberately not actioned.**
Correcting `build_matched_control_group_psm.R` changes `office_id`, which changes which
pairs collide, which changes the fielded 200 and therefore the REDCap load files. That is a
change to the study sample, not a refactor. Per the loop's own rules the estimand was not
changed silently: the live `pe_obgyn_final_calling_sheet_200.csv`, the REDCap files and the
manuscript were left untouched pending a decision on whether to re-draw the sample before
calling begins.

**Suite status after fix:** 33 pass, 0 fail, 0 warn, 0 skip.

---

## Cycle 2 — 2026-08-09 21:5x — 3 BVA / 4 semantic / 3 adversarial

**Targets.** The shipped REDCap artifacts and the protocol guarantee they encode. Cycle 1
tested the key builders in isolation; this cycle tests the artifacts those keys produced.

**Tests added** (`tests/testthat/test-redcap-structure.R`)

| # | Category | Target | Assumption challenged |
|---|---|---|---|
| 1 | BVA | choices file | codes span exactly 1..800, no gap or duplicate |
| 2 | BVA | arm split | boundary falls exactly between code 400 and 401 |
| 3 | BVA | matched pairs | every pair has exactly two clinicians, never one or three |
| 4 | semantic | choices file | code i and i+400 are the same physician, not merely the same position |
| 5 | semantic | sheet + choices | every office receives exactly two calls (the COMIRB promise) |
| 6 | semantic | import file | 800 records, contiguous ids, `physician_name` carries the code not a label |
| 7 | semantic | sheet + choices | the ownership-by-payer 2x2 is exactly 200 calls per cell |
| 8 | adversarial | all artifacts | REDCap files are not stale relative to the calling sheet |
| 9 | adversarial | call schedule | all 800 records scheduled exactly once, arms differ, >=48h gap |
| 10 | adversarial | key builders | row order does not determine office identity |

**Failures discovered:** none. **Fixes:** none.

**Honest note.** A clean cycle here is weak evidence: these artifacts were generated and
independently verified earlier the same day, so the tests largely re-confirm known-good
output. Their value is as regression guards, not as discovery. Cycles 3+ should move into
code not written today: `build_matched_control_group_psm.R` (propensity fitting, the
10-mile radius, the reseeded sampling loop), `calculate_cohort_churn.R`,
`run_geographic_sensitivity_analysis.R`, `match_all_providers.py`,
`extract_demographic_covariates.R`, and the power/calibration constants.

**Suite status:** 64 pass, 0 fail, 0 warn, 0 skip.

**Carried forward (unresolved):** the cycle-1 suite-regex defect remains unfixed in
`build_matched_control_group_psm.R:113` and `add_symmetric_backups.py:34`, pending a
decision on re-drawing the fielded sample.
