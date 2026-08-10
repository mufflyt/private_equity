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

---

## Out-of-band — 2026-08-09 21:3x — authorized redraw attempt (BLOCKED)

User authorized fixing `build_matched_control_group_psm.R` and re-drawing the fielded
sample, resolving the cycle-1 escalation.

**Fixes applied to the PSM script (both retained, both test-guarded):**

1. Suite regex corrected to the word-anchored form, matching `R/pe_helpers.R`.
2. `set.seed(42)` moved out of the per-office loop. Re-seeding inside the loop restarted
   the same stream at every office, so `sample(seq_len(n))` returned the identical
   permutation each time and always began at index 1: the "random" selection of one
   physician per office was deterministically the first-listed physician.

Two tests added (`tests/testthat/test-address-key-parity.R`) pinning the PSM script's
suite regex to the word-anchored form and asserting the office loop is seeded once,
outside the loop. Suite: 70 pass, 0 fail.

**The redraw itself FAILED and was rolled back.**

Re-running the PSM script produced **2 matched pairs instead of 511**. The unmodified
script, restored from git, produces the same 2 pairs. The regression is therefore NOT
caused by the fixes: **the committed pipeline cannot reproduce its own fielded cohort.**

Diagnosis:

- PE cohort loads fine: 1,033 NPI-matched generalists with valid phones.
- Control pool loads fine: 29,882 candidates.
- Matching collapses: `City matches: 2, Caliper Geo Matches: 0`.
- `control_candidates_raw.csv` contains **no coordinates at all** (columns are npi,
  gender, cred, city, state, zip_code, facility_name, ...). The script derives coordinates
  from a hand-maintained gazetteer (`manual_coords`, ~17 entries, plus
  `lat_long_ref <- city_state_to_lat_long`), so the 10-mile geographic caliper can never
  fire on this input. Zero geo matches is the expected behaviour of the committed code.

**Consequence.** The 511-pair matched calling list on disk was produced from inputs or a
geocoding step that are not recoverable from the repository. The manuscript's Methods
claim of "1-to-1 propensity-score matching within a strict 10-mile, same-state radius"
cannot currently be reproduced or verified, and the sample cannot be re-drawn with the
corrected office key until the geocoding path is restored.

**State after rollback.** All six live artifacts verified byte-identical to the pre-redraw
backup in `backups/pre_redraw_20260809_213418/`: fielded sheet, all three REDCap files,
matched calling list, study database.

**Casualty.** `pe_obgyn_control_providers.csv` (354,683 bytes) was overwritten by the
failed runs and was omitted from the backup set. It is a regenerable intermediate and
nothing live depends on it, but it cannot be regenerated until matching works.

**BLOCKING QUESTION for the user:** where did the geocoded control candidates come from?
Until that is answered the sample cannot be re-drawn, and the fielded 200 remains the
one produced by the old, over-merging office key.

---

## Cycle 3 — 2026-08-09 22:0x — 3 BVA / 3 semantic / 4 adversarial

**Targets.** Off today's code and into the matching/provenance layer, as cycle 2 directed.

**Tests added** (`tests/testthat/test-matching-provenance.R`)

| # | Category | Target | Assumption challenged |
|---|---|---|---|
| 1 | BVA | `address_key` | an address that is only a designator must yield NA, not a shared empty key |
| 2 | BVA | `address_key` | ZIP must be five *digits*; non-numeric rejected, leading zero preserved |
| 3 | BVA | geocoding | within-city coordinate multiplicity has a real floor of 1 (the zero-distance case) |
| 4 | semantic | geocoding vs Methods | a 10-mile caliper cannot discriminate when a city has one coordinate |
| 5 | semantic | `get_subspecialty_from_tax` | unknown taxonomies fail open into the generalist cohort |
| 6 | semantic | cohort integrity | no clinician appears in both ownership arms |
| 7 | adversarial | pipeline determinism | results must not depend on the wall-clock year |
| 8 | adversarial | input contract | control candidates must carry the coordinates matching requires |
| 9 | adversarial | vintage | every fielded clinician resolves in the study database |
| 10 | adversarial | manuscript | Table 4 stays consistent with Tables 2 and 3 |

**Failures: 3.**

**(a) REAL DEFECT — wall-clock dependence. FIXED.**
`build_matched_control_group_psm.R:157` computed `study_year` from `Sys.Date()`. The cohort
would therefore change on 1 January: years-in-practice imputation, and any matching that
depends on it, drift with the calendar, so a re-run in a later year cannot reproduce the
fielded sample. Pinned to `STUDY_YEAR <- 2026`, the year the cohort was built, which
preserves current behaviour exactly while making future runs reproducible.
*Same bug class search:* `Sys.Date()` appears in exactly one place repo-wide. The
`Sys.time()` at line 452 records when a run happened and is legitimate provenance; the
test was narrowed to that distinction rather than banning both.

**(b) TEST PREMISE WRONG — corrected.**
Test 9 asserted `sheet$NPI` appears in `db$NPI` raw. It does not: **0 of 400 match.** The
study database was written by pandas with float NPIs (`1003038688.0`) while the calling
sheets carry integers. Under `npi_key()` the match is **400 of 400**. The contract is
clinician identity, so the test now normalises, and additionally pins the raw-join hazard
(`expect_equal(sum(sheet$NPI %in% db$NPI), 0)`) so nobody joins on the bare column and
silently gets an empty frame. This is the cycle-1 float-vs-int hazard surfacing in a
second location.

**(c) KNOWN BLOCKER — preserved failing, not weakened.**
Test 8 fails: `control_candidates_raw.csv` has no latitude column, so the 10-mile caliper
cannot fire. This is the reproducibility blocker from the out-of-band entry. Fixing it
requires input data the repository does not contain, so the test is left red and clearly
named rather than loosened. **This is the suite's only red test and is expected.**

**Unresolved scientific findings (no code changed, decisions needed):**

1. **Geocoding is city-centroid, not address-level.** Of 378 city/state groups in the study
   database, **273 (72%) have every clinician at one identical coordinate** (Worcester MA:
   all 34). For those, the "strict 10-mile radius" is arithmetically equivalent to
   same-city matching. The Methods claim overstates the geographic precision actually
   achieved. Wording should be corrected before submission.
2. **The subspecialty filter fails open.** `get_subspecialty_from_tax()` returns
   "Generalist" for any taxonomy it does not recognise, with no warning. Any new or
   mistyped CMS subspecialty code enters the generalist cohort silently.

**Suite status:** 98 pass, 1 fail (the preserved blocker), 0 warn, 0 skip.
