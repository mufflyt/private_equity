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

---

## Cycle 4 — 2026-08-09 22:3x — 4 BVA / 3 semantic / 3 adversarial

**Targets.** The power/calibration layer that justified the 200-pair sample size, plus the
derived truth constants in the dry-run analysis.

**Tests added** (`tests/testthat/test-power-and-calibration.R`)

| # | Category | Target | Assumption challenged |
|---|---|---|---|
| 1 | BVA | NB dispersion | theta explodes as variance approaches the mean, and goes negative below it |
| 2 | BVA | power constants | hardcoded 6.87 / 1.40 match their stated derivation |
| 3 | BVA | power grid | the grid covers the sample size actually fielded (200 pairs) |
| 4 | BVA | `coalesce_cols` | first non-blank in priority order wins; absent column skipped |
| 5 | semantic | power simulation | the analysis model must match the correlation the simulation generates |
| 6 | semantic | power constants | every declared effect actually enters the linear predictor |
| 7 | semantic | dry-run truths | truth constants are derived from cells, never typed separately |
| 8 | adversarial | shipped artifacts | no consumed artifact stores NPI in lossy float form |
| 9 | adversarial | docs vs code | documented random-intercept magnitude matches the code |
| 10 | adversarial | results artifact | the power CSV matches the grid the script declares |

**Failures: 5.** Two were my own test bugs, three were real.

**(a) TEST BUGS — corrected.** `expect_lt`/`expect_gt` do not accept an `info` argument.
Separately, `is.infinite(theta(10, sqrt(10)))` is FALSE: `sqrt(10)^2 - 10` is 1.78e-15, not
zero, so theta is a finite 5.6e16. The hazard is the explosion, not the infinity, and a
float-exact equality was the wrong contract. Both corrected; neither loosened.

**(b) REAL DEFECT — dead declared effect. FIXED (behaviour-preserving).**
`beta_scenario <- log(13/15)` was computed and documented as a GYN scenario main effect but
never entered `eta`. The header comment therefore described a design the simulation did not
implement. Removed the constant and corrected the comment to state that scenario is not
simulated, since only the AUB vignette is fielded. No numeric behaviour changed.

**(c) REAL DEFECT — documentation on the wrong scale. FIXED (behaviour-preserving).**
The header said "Random intercept SD (physician-level correlation): 3 days" while the code
uses `sd = 0.2` on the log scale. A days-scale figure under a log link is a different
quantity. Comment corrected to match the code. No numeric behaviour changed.

**(d) REAL DEFECT — the power analysis is anticonservative. ESCALATED, NOT SILENTLY FIXED.**
The simulation draws one random intercept per physician and gives each physician two calls,
then fits `glm.nb`, which assumes independent observations. Ignoring within-physician
correlation understates the standard errors and therefore **overstates power**. `library(lme4)`
is loaded but never used.

*Same bug class search — this is in FOUR scripts, not one:*

| Script | Simulates clustering | Fits mixed model | Fits independence model |
|---|---|---|---|
| `run_new_power_analysis.R` | yes | no | yes |
| `run_maineffect_power.R` | yes | no | yes |
| `run_interaction_75_power.R` | yes | no | yes |
| `run_obtainment_power.R` | yes | no | yes |
| `fig3_simr.R` | yes | **yes** | no |

Only `fig3_simr.R` analyses as it simulates.

**Why this matters.** `power_analysis_new_results.csv` reports **0.83 power at the fielded
200 pairs** (SD = 10), and that is the number justifying the sample size. It is an
overstatement. Independent corroboration: cycle-0 dry-run work fitted a correctly specified
negative-binomial GLMM to the same design and obtained **76.5%** for the wait-time
interaction, below the 0.83 claimed here and below the conventional 80% threshold.

Not fixed silently because correcting the model changes the reported power and therefore
the sample-size justification, which is a scientific conclusion. The failing test is
preserved. **Decision needed:** re-run all four power analyses with `glmer.nb`/`glmmTMB` (or
cluster-robust standard errors) and restate the power figures in the manuscript.

**Suite status:** 125 pass, 2 fail, 0 warn, 0 skip. Both failures are deliberately
preserved escalations, not regressions:
1. control-candidate coordinates missing (reproducibility blocker, cycle 3)
2. power simulation fits an independence model (this cycle)

---

## Cycle 5 — 2026-08-09 23:0x — 3 BVA / 4 semantic / 3 adversarial

**Targets.** The geographic matching constraint, the sensitivity analysis built on it, and
the churn accounting.

**Tests added** (`tests/testthat/test-geography-and-churn.R`)

| # | Category | Target | Assumption challenged |
|---|---|---|---|
| 1 | BVA | haversine | zero at zero separation, symmetric, plausible magnitude |
| 2 | BVA | churn loop | accounting starts at year two; denominator is prior-year staff |
| 3 | BVA | calipers | membership is monotone in the radius |
| 4 | semantic | fielded pairs | pairs satisfy the 10-mile radius the Methods asserts |
| 5 | semantic | sensitivity | the 3/5/10-mile calipers are not degenerate |
| 6 | semantic | churn labels | exits are departures, entries are arrivals, mean is of per-year rates |
| 7 | semantic | manuscript | vignette and payer arms match the fielded design |
| 8 | adversarial | coordinates | latitude/longitude are not transposed |
| 9 | adversarial | sensitivity artifact | reproducible from the cohort coordinates |
| 10 | adversarial | churn | a one-year office yields no fabricated churn; no-history is NA, not 0 |

**Failures: 6** (4 new, 2 carried).

**(a) TEST BUG — corrected.** My New York to Los Angeles reference was 2,451 mi; with
r = 3959 and those coordinates it is 2,446. The contract is that the formula returns a
plausible great-circle distance with arguments in the right order, so the assertion is now
a band around the true value. Not a loosening: the original figure was simply wrong.

**(b) ROOT-CAUSE DEFECT — the cohort coordinates are wrong. ESCALATED.**

This is the most consequential finding so far and it explains cycle 3 as well.

- **142 of 200 fielded pairs are more than 10 miles apart**, against a Methods claim of
  matching "within a strict 10-mile radius". Maximum separation: **1,611 miles**.
- Every pair that *is* within 10 miles sits at **exactly 0 miles**. There are no
  intermediate distances at all: 58 pairs at 0, 142 above 10, nothing between.
- The same-state constraint **did** hold: 200 of 200 pairs share a state.
- Inspecting the extremes shows the coordinates are not merely coarse, they are wrong:

  | Pair state | Coordinate A | Coordinate B | Separation |
  |---|---|---|---|
  | PA | (37.867, -104.920) = Colorado | (30.421, -78.102) = Atlantic Ocean | 1,611 mi |
  | MN | (35.998, -75.117) = North Carolina | (31.949, -102.617) = West Texas | 1,595 mi |
  | NJ | (34.043, -102.576) = Texas panhandle | (40.594, -74.622) = New Jersey | 1,594 mi |

  A Pennsylvania clinician geocoded into Colorado is a lookup resolving on city name
  without honouring the state.

**What this invalidates.** Every distance-derived quantity: the 10-mile caliper, the
geographic sensitivity analysis, `HQ_Distance_Miles`, and plausibly
`PE_Concentration_15mi`. The matching was in practice same-state plus same-city-name, not
a distance caliper, which is consistent with the re-run reporting `Caliper Geo Matches: 0`.

**(c) REAL — the sensitivity analysis is vacuous. ESCALATED.**
The same 58 pairs qualify at 3, 5 and 10 miles, so the analysis reports robustness to a
radius it never varied. `geographic_sensitivity_results.csv` claims **200** pairs within 10
miles where the cohort coordinates give **58**, and its 5-mile and 3-mile rows are
byte-identical to each other. The artifact is not reproducible from the cohort.

**Passed, and worth noting.** Churn accounting is sound: it starts at year two, uses
prior-year staff as the denominator, computes `(joined + left) / baseline_staff`, averages
per-year rates rather than summed counts, and distinguishes an observed zero from NA.
Ownership arms, vignette and payer arms in the manuscript are consistent.

**Weak test identified for cycle 6.** Test 8 (lat/lon not transposed) PASSED while the
coordinates were badly wrong, because it only checked value ranges. The real contract is
coordinate-to-state consistency. Cycle 6 should assert that each clinician's coordinate
falls within its stated state.

**Suite status:** 144 pass, 5 fail, 0 warn, 0 skip. All five are preserved escalations:
1. control-candidate coordinates missing (cycle 3)
2. power simulation fits an independence model (cycle 4)
3. 142/200 fielded pairs exceed the 10-mile radius (this cycle)
4. 3/5/10-mile calipers are degenerate (this cycle)
5. sensitivity artifact not reproducible from coordinates (this cycle)

---

## Cycle 6 — 2026-08-09 23:3x — 3 BVA / 3 semantic / 4 adversarial

**Targets.** The contract cycle 5 identified as missing: coordinate-to-state consistency.

**Tests added** (`tests/testthat/test-coordinate-integrity.R`)

| # | Category | Target | Assumption challenged |
|---|---|---|---|
| 1 | BVA | bounding boxes | a border point is accepted; a clearly-outside point is rejected |
| 2 | BVA | coordinate granularity | coordinates are shared, so precision has a floor well above address level |
| 3 | BVA | haversine | resolves separations below one mile |
| 4 | semantic | cohort coordinates | every fielded clinician's coordinate lies inside their stated state |
| 5 | semantic | state lookup | the abbreviation map is correct and has no shadowed duplicates |
| 6 | semantic | `HQ_Distance_Miles` | non-negative and within CONUS scale |
| 7 | adversarial | coordinates | one point is never shared across different states |
| 8 | adversarial | `PE_Concentration_15mi` | count-like, never negative |
| 9 | adversarial | SAP-revision truths | derived from cell constants, never typed literals |
| 10 | adversarial | artifact agreement | fielded sheet and study database agree on state |

**Failures: 3 new** (plus 4 carried).

**(a) MY TEST BUG, THIRD OCCURRENCE — corrected.** `expect_lt` does not take an `info`
argument, the same slip made in cycle 4 with `expect_lt`/`expect_gt`. Recording it as a
pattern in my own test writing rather than a one-off: testthat's comparison expectations
(`expect_lt`, `expect_gt`, `expect_lte`, `expect_gte`) accept no `info`; only
`expect_true`/`expect_equal`-family do. Future cycles should use `expect_true(x < y, info=)`
when a message is wanted.

**(b) DECISIVE ROOT CAUSE — the geocoding is broken, not merely coarse. ESCALATED.**

Cycle 5 inferred this from three extreme pairs. Measured directly against padded state
bounding boxes for all 26 cohort states:

> **380 of 400 fielded clinicians (95%) are geocoded outside the state they practise in.**

Only 20 of 400 land in the right state. Example: a Michigan clinician at (39.147, -93.208),
which is Missouri. Two coordinates are shared by clinicians in *different* states, the
signature of a city-name lookup that is not honouring state.

The 400 fielded clinicians resolve to 235 distinct points, so the data is city-level at
best even where it is not simply wrong.

**Consequence, restated with the measurement behind it.** Every distance-derived quantity in
the study is unusable: the 10-mile caliper (cycle 5: 142/200 pairs exceed it), the
geographic sensitivity analysis (cycle 5: vacuous, and its artifact reports 200 pairs where
coordinates give 58), `HQ_Distance_Miles`, and `PE_Concentration_15mi`. The Methods sentence
"matched within a strict 10-mile radius in the same state" is supported only in its
same-state half, which cycle 5 verified holds at 200/200.

**Passed and worth recording.** The state abbreviation lookup in
`build_matched_control_group_psm.R` is correct: full-name to abbreviation, no duplicates,
Pennsylvania to PA, Colorado to CO. So the defect is not in that mapping. `HQ_Distance_Miles`
and `PE_Concentration_15mi` are within plausible ranges and non-negative, and the fielded
sheet and study database agree on state for every clinician, which is why the same-state
constraint survived while the distances did not. The defect therefore lies in the
`city_state_to_lat_long` lookup from the `mysterycall` package or in how rows are joined to
it, not in the abbreviation table or the state columns.

**Suite status:** 168 pass, 6 fail, 0 warn, 0 skip. All six are preserved escalations:
1. control-candidate coordinates missing (cycle 3)
2. power simulation fits an independence model (cycle 4)
3. 142/200 fielded pairs exceed the 10-mile radius (cycle 5)
4. 3/5/10-mile calipers are degenerate (cycle 5)
5. sensitivity artifact not reproducible from coordinates (cycle 5)
6. 380/400 clinicians geocoded outside their state (this cycle)

Items 3 to 6 are one defect with four symptoms. **Next cycle should test the
`mysterycall::city_state_to_lat_long` join directly** to isolate whether the lookup data or
the join key is at fault.

**CORRECTION to the cycle 6 record above.** The suite line was written before the final
run completed. Actual status is **167 pass, 7 fail**, not 168/6. The list of preserved
escalations omitted one test from this cycle. The complete list of seven is:

1. control-candidate coordinates missing (cycle 3)
2. power simulation fits an independence model (cycle 4)
3. 142/200 fielded pairs exceed the 10-mile radius (cycle 5)
4. 3/5/10-mile calipers are degenerate (cycle 5)
5. sensitivity artifact not reproducible from coordinates (cycle 5)
6. 380/400 clinicians geocoded outside their state (cycle 6)
7. **2 coordinates shared by clinicians in different states (cycle 6)** — omitted above

Items 3 to 7 are one defect with five symptoms.

---

## Cycle 7 — 2026-08-10 00:0x — 4 BVA / 3 semantic / 3 adversarial

**Targets.** The geocoding lookup itself, as cycle 6 directed. Cycles 3, 5 and 6 measured
symptoms; this cycle tested the join that causes them, and **found and fixed the root cause**.

**Tests added** (`tests/testthat/test-geocode-lookup.R`)

| # | Category | Target | Assumption challenged |
|---|---|---|---|
| 1 | BVA | gazetteer | rows survive state normalisation; the boundary is zero |
| 2 | BVA | state tokens | classified at the two-character boundary |
| 3 | BVA | join key | city+state is essentially unique; city alone is not |
| 4 | BVA | lookup miss | an unknown city returns nothing, never row 1 |
| 5 | semantic | vocabulary | gazetteer and mapping table use the same state vocabulary |
| 6 | semantic | join key | joining on city alone is ambiguous and must not be used |
| 7 | semantic | resolved coords | a coordinate lies inside the state requested |
| 8 | adversarial | silent emptying | an emptied reference table must not pass silently |
| 9 | adversarial | fallback | the 17-entry manual list cannot stand in for a 31,909-row gazetteer |
| 10 | adversarial | package contract | gazetteer columns and types are stable |

**All 10 pass. Three defects fixed, two of them the root cause of five prior escalations.**

**(a) ROOT CAUSE — state vocabulary mismatch. FIXED.**
`city_state_to_lat_long$state` holds two-letter abbreviations (`AL`, `AZ`). The script mapped
it through `full_to_abbrev`, which is keyed by full names (`Alabama`). The lookup returned NA
for **all 31,909 rows**, and the `!is.na(state_upper)` filter on the next line then deleted
the entire gazetteer. `get_coords()` fell through to a 17-entry manual list and returned NA
for every other city. Fixed by accepting either vocabulary.

**(b) MASKED SECOND DEFECT — wrong column names. FIXED.**
With the gazetteer restored, the run failed at `candidates_df$latitude[i] <- coords[1]`,
"replacement has length zero". `get_coords()` read `match_row$latitude` / `$longitude`, but
the gazetteer names its columns `lat` / `long`, so the expression was NULL and `c(NULL, NULL)`
was zero-length. **This bug was invisible while defect (a) was present**, because the branch
that reads those columns never executed. Fixing one exposed the other.

**(c) SILENT FAILURE — no guard. FIXED.**
The filter that emptied the gazetteer was followed by nothing. The script continued,
geocoded everything to NA, and reported a successful matching run. Added a `stop()` on an
empty gazetteer plus a row count, so this class of failure announces itself.

**VERIFIED END TO END.** With all three fixed, matching runs clean:

| | Before | After |
|---|---|---|
| Gazetteer rows | 0 | **31,909** |
| Controls matched | 2 | **518** |
| Caliper Geo Matches | **0** | **345** |
| City matches | 2 | 173 |

The 10-mile geographic caliper now actually fires, for the first time in this pipeline's
recorded history. **The reproducibility blocker from cycle 3 is resolved**, and the redraw
the user authorised is now technically possible.

**Live artifacts deliberately NOT replaced.** The verification run overwrote the calling
list and study database; both were restored from `backups/pre_redraw_20260809_213418/` and
verified identical, along with the fielded sheet and REDCap files. The new output is
preserved at `backups/redraw_candidate_20260810/` for inspection. Replacing the fielded
sample is not a step to take unattended: it changes which clinics Taylor calls, and it
additionally requires re-running enrichment, de-duplication and the REDCap load files.

**Suite status:** 201 pass, 7 fail, 0 warn, 0 skip. The seven remaining failures are all
data-level assertions about the *current* fielded cohort, which was built with the broken
geocoder. They are expected to clear once the redraw is adopted; they are not code defects
any more.

**My own recurring test bug, 4th and 5th occurrence.** `expect_gt(..., info=)` again, in the
same cycle where cycle 6 recorded the pattern. Swept all test files programmatically rather
than fixing case by case; none remain.

---

## Cycle 8 — 2026-08-10 00:3x — 3 BVA / 4 semantic / 3 adversarial

**Targets.** Coordinate provenance: *which* coordinates were being measured.

**Tests added** (`tests/testthat/test-coordinate-provenance.R`)

| # | Category | Target | Assumption challenged |
|---|---|---|---|
| 1 | BVA | years in practice | inside a plausible career span |
| 2 | BVA | open payments years | cannot exceed the programme's lifetime |
| 3 | BVA | calling list | two arms per pair at both cohort sizes |
| 4 | semantic | matcher | persists the coordinates its caliper relied on |
| 5 | semantic | provenance | persisted coordinates come from the matcher, not a later step |
| 6 | semantic | redraw | carries the columns downstream expects |
| 7 | semantic | Python/R parity | both address normalisers strip suites with word boundaries |
| 8 | adversarial | redraw | does not silently change cohort scale |
| 9 | adversarial | pairs | no clinician matched to themselves or duplicated |
| 10 | adversarial | redraw | controls drawn from the control pool, not the PE cohort |

**CORRECTION TO CYCLES 5 AND 6.** Those cycles measured `Latitude`/`Longitude` from the
study database and concluded the matching ignored its 10-mile radius. That conclusion was
right, but the evidence was not: **the matcher never wrote those columns.** It computed
coordinates, used them for the caliper, and discarded them; the persisted columns were added
later by `apply_hq_distance.R` / `calculate_pair_distances.R`. So cycles 5 and 6 audited a
*different coordinate source* than matching used. The conclusion survives by a stronger route
established in cycle 7: the matcher's gazetteer was empty, so its caliper reported
`Caliper Geo Matches: 0` and could not have been enforced at all. The specific figures
(142/200 over 10 miles, 380/400 outside their state) describe the downstream enrichment
coordinates, not the matcher's.

**(a) REAL DEFECT — the geographic claim was unauditable. FIXED.**
The matcher now writes `Matcher_Latitude` / `Matcher_Longitude` alongside the cohort, so the
coordinates used for matching and the coordinates available for audit are the same by
construction. Purely additive; matching behaviour unchanged. Coverage is **1,384 of 2,055
records (67%)** — the remainder are full-PE-cohort rows absent from the matched subsets.
*Follow-up for a later cycle: close the remaining 33%.*

**(b) VALIDATED — the redraw now satisfies the geography, mostly.** Measured on the
matcher's own coordinates for the first time:

| | Old cohort | Redraw candidate |
|---|---|---|
| Caliper Geo Matches | 0 | **345** |
| Pairs within 10 mi | caliper never fired | **402 / 497 (81%)** |
| Median pair distance | n/a (all 0 or >10) | **4.5 mi** |
| Calipers discriminate | no (58/58/58) | **yes (230 / 260 / 402)** |

The 3, 5 and 10-mile calipers now select genuinely different sets, so the sensitivity
analysis would become meaningful rather than vacuous.

**(c) RESIDUAL — the city-match fallback bypasses the caliper. ESCALATED.**
95 of 497 redrawn pairs (19%) still exceed 10 miles, max 1,281 mi. The matcher has two
paths: a geographic caliper (345 matches) and a city-name fallback (173 matches). The
fallback does not enforce the distance constraint. If the Methods is to claim a strict
10-mile radius, either the fallback must apply the caliper or the claim must acknowledge it.

**(d) OPEN — `add_symmetric_backups.py:34`** still strips suites without word boundaries,
the cycle-1 defect. One-line fix, held per standing instruction because it was not named in
the user's authorisation. It cannot affect the fielded sample: the script is not run and the
manuscript's backup section was cut.

**(e) OPEN — a redraw lacks five enrichment columns**: `CDC_SVI`, `Medicaid_Fee_Index`,
`Latitude`, `Longitude`, `PE_Concentration_15mi`. Adopting the redraw requires re-running the
enrichment chain, not just the matcher.

**Suite status:** 224 pass, 7 fail. Cycle 8 added 10 tests; four failed and three of those
are now fixed or reclassified, leaving the standing escalations.

**CORRECTION to the cycle 8 record above.** The suite line said 224 pass / 7 fail; it was
written before the run finished. This is the **second** time (cycle 6 was the first), so it
is a process fault, not a slip: *run the suite, then write the ledger line from its output.*
Adopted for all remaining cycles.

Actual cycle 8 outcome after correcting one test: **222 pass, 9 fail.**

One further test of mine was wrong and is corrected here. The provenance test asserted the
literal source text `$Latitude <-`, an implementation detail, and so kept failing after the
fix simply because the new columns are named `Matcher_Latitude`/`Matcher_Longitude`. Per the
rule against asserting implementation details where a behavioural contract exists, it now
checks the produced artifact for matcher coordinate columns with non-empty values. Not a
loosening: the new assertion is strictly about observable output.

The nine standing failures are:

1. control-candidate coordinates missing (cycle 3) — now a stale artifact question, since
   cycle 7 showed the matcher geocodes candidates itself
2. power simulation fits an independence model (cycle 4)
3. 142/200 fielded pairs exceed 10 miles (cycle 5, on downstream coordinates)
4. 3/5/10-mile calipers degenerate on the current cohort (cycle 5)
5. sensitivity artifact not reproducible (cycle 5)
6. 380/400 clinicians outside their state (cycle 6, on downstream coordinates)
7. 2 coordinates shared across states (cycle 6)
8. redraw lacks five enrichment columns (cycle 8)
9. `add_symmetric_backups.py:34` unanchored suite regex (cycle 1, held)

Items 3 to 7 describe the **current fielded cohort**, which cycle 7 showed was built with a
non-functioning geocoder. They are evidence for adopting the redraw, not open code defects.

---

## Cycle 9 — 2026-08-10 01:0x — 3 BVA / 3 semantic / 4 adversarial

**Targets.** The matcher's own guarantees: propensity model, caliper boundary, control reuse,
determinism. Suite status below was read from the run output, per the cycle-8 process fix.

**Tests added** (`tests/testthat/test-matching-invariants.R`)

| # | Category | Target | Assumption challenged |
|---|---|---|---|
| 1 | BVA | caliper | strict `< 10`; a pair at exactly 10.0 is excluded |
| 2 | BVA | candidate pool | a match needs at least two nearby candidates, never one |
| 3 | BVA | propensity | scores are probabilities (binomial family, response scale) |
| 4 | semantic | matching paths | there is ONE path and it enforces the caliper |
| 5 | semantic | propensity model | uses the covariates the Methods claims, and no outcome-adjacent terms |
| 6 | semantic | pair invariant | every matched pair honours the caliper on the matcher's coordinates |
| 7 | adversarial | control reuse | a control is never reused across pairs |
| 8 | adversarial | pool separation | the control pool cannot contain PE clinicians |
| 9 | adversarial | RNG | matching is seeded once, so a rerun is reproducible |
| 10 | adversarial | environment | no dependence on the caller's working directory |

**CORRECTION TO CYCLE 8.** Cycle 8 recorded a "city-name fallback that bypasses the caliper",
holding it responsible for 95 pairs beyond 10 miles. **There is no such path.** Line 411
computes `close_indices <- which(dists < 10)` and everything downstream sits inside that
branch; `city_match_count` and `caliper_geo_match_count` merely label whether the selected
control happened to share the PE clinic's city. Both are within the caliper. The escalation
is withdrawn.

**(a) REAL DEFECT, INTRODUCED BY ME IN CYCLE 8. FIXED.**
The 95 over-caliper pairs were an artefact of my own coordinate export. It recovered control
coordinates by looking up NPI in `candidates_df` after `!duplicated()`. **NPI is not unique
in the candidate pool** (one clinician appears at several addresses), so the lookup returned
an arbitrary row's coordinates. Measured: PE coordinates agreed with the gazetteer for their
own city **100%** of the time, controls only **81%** — exactly the 19% that appeared to
violate the caliper.

Fixed by recording `Matcher_Latitude`/`Matcher_Longitude` from `crow`, the candidate row the
matcher actually selected, at the point of selection, and attaching the PE side before column
alignment. Coverage improved from 1,384/2,055 to **1,405/2,055, including all 518 controls**
(was 497). The pair invariant now **passes: every matched pair is within 10 miles on the
matcher's own coordinates.**

*Lesson recorded:* recovering a value by key after the fact is not equivalent to recording it
at the point of use when the key is not unique. Worth checking elsewhere in this pipeline.

**(b) TWO TEST PREMISES OF MINE — corrected.** One asserted that no `matched_control <- `
assignment precedes the caliper, which caught the loop's `NULL` initialisation; narrowed to
non-NULL assignments. The other, for the second time in this file, asserted source text
(`Latitude *=`) and broke when the implementation moved. Both now assert observable output.
Standing lesson: prefer artifact assertions to source-text assertions wherever an artifact
exists.

**Passed and worth recording.** The propensity model uses exactly the four covariates the
Methods claims (MD/DO, gender, years in practice, Open Payments) with no outcome-adjacent or
geographic terms; it is binomial on the response scale; controls are never reused; the
control pool contains no PE clinicians; matching is seeded once before the office loop; and
no path depends on the working directory.

**Suite status:** 250 pass, 9 fail, 0 warn, 0 skip.

---

## Cycle 10 — 2026-08-10 01:3x — 4 BVA / 3 semantic / 3 adversarial

**Targets.** Cycle 9's lesson as a bug-class hunt: every site that recovers a value by NPI
after the fact rather than recording it at the point of use.

**Tests added** (`tests/testthat/test-key-joins.R`)

| # | Category | Target | Assumption challenged |
|---|---|---|---|
| 1 | BVA | NPI form | exactly ten digits or absent, never partial |
| 2 | BVA | empty key | the blank key is not equal to any real key |
| 3 | BVA | enrichment | reaches every fielded clinician, not merely most |
| 4 | BVA | `HQ_Distance_Miles` | zero is a real value, not a converted NA |
| 5 | semantic | NPI-less rows | are not treated as one clinician by a keyed join |
| 6 | semantic | fielded artifacts | contain no NPI-less clinician |
| 7 | semantic | `distinct(NPI)` | safe only because real NPIs are unique; state the precondition |
| 8 | adversarial | site inventory | every by-key recovery site stays inventoried |
| 9 | adversarial | order independence | enrichment does not depend on source row order |
| 10 | adversarial | `cross_reference_phones.py` | first-row-on-duplicate is detected, not silent |

**All 10 pass. No new failures.**

**Bug-class sweep result.** Seven sites recover a value by NPI after the fact:
`apply_hq_distance.R:48`, `apply_demographic_covariates.R:55`,
`calculate_cohort_churn.R:139`, `dedup_offices_and_backfill_200.R:75,77`,
`cross_reference_phones.py:17,35`, plus the `iloc[0]` reads in `add_symmetric_backups.py`
and `add_backup_physicians.py`.

**Measured verdict: the pattern is currently safe, and the reason is worth recording.**
Of 2,048 rows in the enriched study database, **1,790 carry a well-formed ten-digit NPI and
none is duplicated**. The `distinct(NPI, .keep_all = TRUE)` pattern therefore has nothing to
choose between. This is a precondition none of those seven sites states or checks; test 7
now states it, so a future source with genuine duplicates fails loudly here instead of
silently picking a row, which is exactly how the cycle-9 defect behaved.

**CORRECTION TO MY OWN INTERIM CLAIM.** While inventorying I reported "257 duplicated NPIs".
That was wrong. `sum(duplicated(k))` counted **258 rows that share a blank key**, not
duplicated real NPIs. The distinct-duplicated-key count is 1, and it is the empty string.
Real NPIs have zero duplication. Recorded because the erroneous figure briefly made a safe
pattern look like an active defect.

**LATENT DEFECT — the blank key joins to itself. Documented, not fixed.**
258 PE-arm rows carry a provider name but no NPI, having failed NPPES matching. They all
share the empty key, so any by-NPI join collapses them onto whichever blank-keyed row
survives a `distinct()` step: 258 clinicians would receive one clinician's enrichment. That
is 25% of the 1,033 PE generalists.

It is latent rather than active because **nothing NPI-less is fielded** — all 400 fielded
clinicians have well-formed distinct NPIs, asserted by test 6. Any future analysis over the
full PE cohort rather than the fielded subset would hit it. Not fixed because the correct
remedy is to exclude blank keys from these joins at each of seven sites, which touches
enrichment values the current cohort depends on.

**Suite status:** 272 pass, 9 fail, 0 warn, 0 skip. No change to the nine standing
escalations; cycle 10 added no new ones.

---

## Cycle 11 — 2026-08-10 02:0x — 3 BVA / 4 semantic / 3 adversarial

**Targets.** The REDCap instrument itself. Cycle 2 tested the load files; nothing had tested
the form that will actually collect the primary outcomes. A field that cannot hold the value
the analysis needs is a defect upstream of every model in the SAP.

**Tests added** (`tests/testthat/test-redcap-instrument.R`)

| # | Category | Target | Assumption challenged |
|---|---|---|---|
| 1 | BVA | `calltime`/`holdtime` | admit realistic upper values |
| 2 | BVA | date fields | bounded at both ends |
| 3 | BVA | coded answers | start at 1, contiguous, no duplicates |
| 4 | semantic | `appdate` | the primary outcome cannot be left silently blank |
| 5 | semantic | date fields | can record the time their labels promise |
| 6 | semantic | arm identity | the instrument records which insurance arm a call belongs to |
| 7 | semantic | dropdown | matches the fielded cohort |
| 8 | adversarial | branching logic | contradictory records are not enterable unchallenged |
| 9 | adversarial | required set | every field the analysis consumes is required |
| 10 | adversarial | numeric bounds | no value admitted that would corrupt an outcome |

**11 failures across 9 of the 10 tests. Every one is a genuine instrument defect; none is a
test bug. None fixed — see the note on drift below.**

1. **The primary wait-time outcome can be saved blank.** `appdate` is not required and has
   no branching logic. A record can be marked complete with the study's primary endpoint
   empty and REDCap will not prompt.
2. **Date fields cannot store a time.** `calldate1` and `calldate2` validate as `date_mdy`
   while their labels read "Date and Time of FIRST/SECOND Phone Call" and instruct calling
   between 0800 and 1700 local. Neither the business-hours instruction nor the >=48 hour
   spacing between insurance arms can be verified from the collected data.
3. **Date fields have no maximum** (`calldate1`, `calldate2`, `appdate`), so a mistyped year
   is accepted and would produce an enormous wait time.
4. **`holdtime` and `calltime` cap at 1000 seconds** (16 min 40 s). The `reminders` field
   explicitly anticipates holds beyond five minutes, and a long hold is precisely the access
   barrier the study is trying to detect. A 20-minute hold cannot be recorded.
5. **`physician_name` is not required**, yet it carries the *only* identifier of which
   insurance arm a record belongs to (`medicaid_status` option 3 is "NA as this was a Blue
   Cross/Blue Shield call"). A record without it has an unknown arm and is unusable.
6. **The dictionary's dropdown is stale**: 600 choices, from the 300-pair era, against the
   800 the fielded set needs.
7. **No branching logic exists anywhere in the instrument.** A caller can record
   `contacted1 = No` and still enter an appointment date, or mark an exclusion and still
   record a wait time. Nothing prevents internally contradictory records.

**Why nothing was fixed.** The user's own email states the mystery-caller database "is built
in REDCap", so this CSV is plausibly a snapshot of a live project rather than its source of
truth. Editing it here would create drift between the file and the live instrument without
changing what Taylor actually sees. The fix also is not simply "mark appdate required":
where a clinic declines Medicaid there is no appointment date, so the correct remedy is
branching logic conditional on obtainment, which is an instrument-design decision.

**Recommended, in priority order:** add branching logic so `appdate` is shown and required
only when an appointment was obtained; make `physician_name` required; switch the two call
dates to a datetime validation; add date maxima; raise the duration caps to at least 3600 s;
and paste the current 800-line choices file into the Online Designer.

**Suite status:** 292 pass, 20 fail, 0 warn, 0 skip. Nine standing escalations plus the
eleven instrument findings above.

---

## Cycle 12 — 2026-08-10 02:3x — 3 BVA / 3 semantic / 4 adversarial

**Targets.** Who is actually in the cohort, and the public-facing STROBE figure describing
how they got there.

**Tests added** (`tests/testthat/test-cohort-definition.R`)

| # | Category | Target | Assumption challenged |
|---|---|---|---|
| 1 | BVA | STROBE funnel | never widens between stages |
| 2 | BVA | STROBE annotations | equal the gaps they describe |
| 3 | BVA | credentials | fall in the allowed physician set |
| 4 | semantic | STROBE counts | match the artifacts they describe |
| 5 | semantic | text vs figure | manuscript and Figure 1 agree on the matched pool |
| 6 | semantic | cohort definition | no mid-level provider in a physician cohort |
| 7 | adversarial | credentials | every fielded clinician has one recorded |
| 8 | adversarial | subspecialty | fielded cohort is generalist OB-GYN only |
| 9 | adversarial | matcher | the exclusion list is applied, not merely declared |
| 10 | adversarial | caller sheet | export cannot mangle NPIs or phone numbers |

**5 failures after correcting two of my own test premises.**

**(a) A MID-LEVEL PROVIDER IS IN THE FIELDED COHORT. ESCALATED.**
**Dr. Cindy Joslyn, CNM, Worcester MA, PE arm, pair_472** is scheduled to be called. The
study is defined as OB-GYN physicians, matched on "MD vs. DO". Her record:

| Field | Value |
|---|---|
| Provider Name | Cindy Joslyn, **MD** |
| Input Credentials | **CNM** |
| NPPES Credentials | **CNM** |
| **MD vs. DO** | **MD** |
| NPPES Taxonomy | **Midwife** |
| Subspecialty | OB-GYN |

Two independent defects let her through, and **both were already on the ledger as
abstract risks**:

1. *The fail-open subspecialty mapper* (cycle 3, finding 2). `get_subspecialty_from_tax()`
   returns "Generalist" for any taxonomy it does not recognise. Taxonomy "Midwife" is not
   one of the four subspecialty codes, so a midwife is classified a generalist OB-GYN.
2. *The MD/DO derivation treats anything that is not DO as MD*
   (`build_matched_control_group_psm.R:155`: `ifelse(grepl("DO", cred), "DO", "MD")`). A CNM
   is therefore stamped MD and passes every physician filter downstream.

`EXCLUDED_CREDENTIALS` in `match_all_providers.py` does list CNM and is referenced in four
places, so the exclusion is implemented upstream; it is these two downstream derivations
that readmit her. **Not fixed: removing a clinician changes the fielded sample.**

**(b) 41 of 400 fielded clinicians have no credential recorded**, so MD/DO cannot be
verified for 10% of the cohort, and Table 1's credential row cannot be complete.

**(c) FIGURE 1 CONTRADICTS THE MANUSCRIPT TEXT. ESCALATED.**
`strobe_diagram.R` states **544** matched pairs; the calling list holds **511** and the
Methods now says 511. It also states 1,021 OB-GYN generalists where the matcher reports
1,033. The figure is internally consistent (its exclusion annotations equal its own gaps)
but describes a cohort that no longer exists. This is the 544-pair figure the user already
flagged to the co-investigator as outdated; it is still in the figure source.

**(d) TWO TEST PREMISES OF MINE — corrected.** The STROBE stage parser used the stage name
as a regex, and "De-clustered (1/Office)" contains metacharacters, yielding NA; now matched
with `fixed = TRUE`. And test 9 grepped for `MIDLEVEL` when the identifier is
`EXCLUDED_CREDENTIALS`; corrected, and it passes.

**Passed and worth recording.** The fielded cohort is Generalist-only by the Subspecialty
column, the caller sheet export reads everything as character so NPIs and phones cannot be
mangled, and the STROBE annotations are internally consistent.

**Suite status:** see the line recorded from the run below.

**Suite: pass=304  fail=25  warn=0  skip=0**

---

## Cycle 13 — 2026-08-10 03:0x — 4 BVA / 3 semantic / 3 adversarial

**Targets.** Cycle 12's CNM traced to its source: the taxonomy behind the Subspecialty label.

**Tests added** (`tests/testthat/test-taxonomy-eligibility.R`)

| # | Category | Target | Assumption challenged |
|---|---|---|---|
| 1 | BVA | taxonomy values | every one is a well-formed CMS code |
| 2 | BVA | prefix | the OB-GYN boundary is 207V, not 207 |
| 3 | BVA | completeness | taxonomy present for every fielded clinician |
| 4 | BVA | arms | exactly 200 per arm |
| 5 | semantic | eligibility | every fielded clinician practises obstetrics and gynecology |
| 6 | semantic | Subspecialty column | reflects the taxonomy it claims to summarise |
| 7 | semantic | classifier | positively confirms OB-GYN rather than failing open |
| 8 | adversarial | trainees | no student is fielded as a practising physician |
| 9 | adversarial | non-physicians | no NP or midwife taxonomy is fielded |
| 10 | adversarial | differential bias | contamination is not concentrated in one arm |

**THE MOST CONSEQUENTIAL FINDING OF THE RUN. 8 failures, all real.**

> **56 of 400 fielded clinicians (14%) do not have an OB-GYN taxonomy.**

What is actually in the cohort Taylor is about to call:

| Taxonomy | n | What it is |
|---|---|---|
| 390200000X | **13** | **Student in an organised health care training program** |
| 174400000X | 10 | Specialist (unspecified) |
| 208800000X | 5 | Urology |
| 208000000X | 4 | Pediatrics |
| 207P00000X | 3 | Emergency medicine |
| "Obstetrics & Gynecology" | 3 | free text, not a code |
| 207Q00000X | 2 | Family medicine |
| 208600000X | 2 | Surgery |
| 12 further codes | 1 each | dermatology, internal medicine, allergy, haematology-oncology, infectious disease, genetics, adolescent medicine, neurology, diagnostic radiology, colon and rectal surgery, **thoracic surgery**, obesity medicine |
| 363LW0102X | 1 | **Nurse practitioner, women's health** |
| Midwife | 1 | the CNM found in cycle 12 |

A thoracic surgeon cannot offer a new-patient gynaecology appointment for abnormal uterine
bleeding. Thirteen of the cohort are trainees. Two are non-physicians.

**Root cause, and it was already on the ledger.** `get_subspecialty_from_tax()` tests for
exactly four subspecialty codes and returns `"Generalist"` for everything else. There is no
positive test that the taxonomy belongs to the 207V OB-GYN family. This is the fail-open
classifier recorded as an abstract risk in cycle 3, finding 2. It has 56 victims, not the
one found in cycle 12. The `Subspecialty` column consequently reads "Generalist" for all
400, which is why no earlier check caught it: **cycle 12's test 8 asserted exactly that
column and passed.**

*Same bug class:* `build_matched_control_group_psm.R:10,16` and again at `:470,476`, and
`add_backup_physicians.py:14,24`. Four sites, same fail-open shape.

**Differential by arm: PE 32, control 24.** Contamination that differs between arms biases
the comparison rather than merely adding noise.

**A WEAK TEST OF MY OWN — strengthened.** Test 7 initially asserted `grepl("207V", blk)` and
**passed**, because the four subspecialty codes in the function body begin with 207V. It
would have certified a fail-open classifier as safe. Rewritten to require an explicit prefix
test (`substr(...,1,4) == "207V"`, `grepl("^207V")`, or `startsWith`). This is the second
time a test of mine passed while the defect it targeted was present (cycle 5's transposition
test was the first); both are recorded so the final audit can look for more.

**Not fixed.** Adding a positive 207V test removes 56 clinicians from the cohort and changes
the fielded sample, the matched pairs, and every downstream artifact. That is the user's
call, and it compounds with the redraw decision already pending.

**Suite:** 313 pass, 33 fail, 0 warn, 0 skip.
