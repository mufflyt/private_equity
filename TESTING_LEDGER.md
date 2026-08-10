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

---

## Cycle 14 — 2026-08-10 03:3x — 3 BVA / 4 semantic / 3 adversarial

**Targets.** Table 1, the baseline balance table: the first thing a reviewer reads and the
evidence for the claim that propensity matching worked.

**Tests added** (`tests/testthat/test-table1-balance.R`)

| # | Category | Target | Assumption challenged |
|---|---|---|---|
| 1 | BVA | Table 1 counts | sum to the arm size |
| 2 | BVA | Table 1 percentages | agree with its own counts |
| 3 | BVA | dispersion | SDs positive, means plausible |
| 4 | semantic | credentials | match the fielded cohort |
| 5 | semantic | gender | matches the fielded cohort |
| 6 | semantic | years in practice | matches the fielded cohort |
| 7 | semantic | open payments | matches the fielded cohort |
| 8 | adversarial | missingness | disclosed, not silently averaged over |
| 9 | adversarial | imputation | a covariate imputed for matching is disclosed |
| 10 | adversarial | provenance | Table 1 is generated, not typed |

**11 failures. Table 1 does not describe the fielded cohort on any row.**

| Row | Table 1 states | Cohort actually has |
|---|---|---|
| Independent MD | 187 (93.5%) | **182** |
| Independent DO | 13 (6.5%) | **18** |
| PE MD | 183 (91.5%) | **170** |
| PE DO | 16 (8.0%) | **30** |
| Independent female | 121 (60.5%) | **126** |
| PE female | 137 (68.5%) | **138** |
| PE years in practice | 23.0 | **21.9** |
| Independent Open Payments | 6.7 | **6.2** |
| PE Open Payments | 6.4 | **5.7** |

Independent years in practice (24.6) is the only figure that matches. The credential rows
are the largest divergence: the PE arm has nearly twice the DOs Table 1 reports. Note also
that these cohort counts are computed from `MD vs. DO`, the derived column cycle 12 showed
stamps a CNM as MD, so even the "correct" figures inherit that defect.

**Undisclosed missingness.** 31 PE clinicians have no years in practice and 24 have no Open
Payments years. Table 1 reports means with no denominators and the manuscript never mentions
missingness, so a reader cannot tell the PE mean rests on 169 observations rather than 200.

**Undisclosed imputation.** `build_matched_control_group_psm.R` replaces missing years with
the cohort median before fitting the propensity model. Matching therefore used an imputed
covariate for 31 PE clinicians, roughly 15% of the arm, and the Methods does not say so.

**No script generates Table 1**, so its numbers cannot track the cohort and will drift again
after any redraw. This is the mechanism behind every row above.

**A TEST PREMISE OF MINE — corrected.** My parser looked for rows labelled `| - MD |`. The
real rows are `| MD |`. The hyphenated form came from `manuscript_content.txt`, the stale
scratch copy at the repo root that cycle 8 already flagged for deletion. I had read the wrong
file. Corrected to parse `manuscript/manuscript_cite.md`, the README's stated source of
truth.

**Not fixed.** Correcting Table 1 means regenerating it from the cohort, which is worth doing
only after the eligibility and redraw decisions land, since both change every number in it.

**Suite:** recorded from the run below.

**Suite: pass=333  fail=44  warn=0  skip=0**

---

## Cycle 15 — 2026-08-10 04:0x — 3 BVA / 3 semantic / 4 adversarial

**Targets.** The covariate defaults applied before matching, and the time zone the caller
uses to decide when to dial. Both are quiet: neither raises an error, and both change either
who is matched to whom or whether the phone is answered.

**Tests added** (`tests/testthat/test-covariate-imputation.R`)

| # | Category | Target | Assumption challenged |
|---|---|---|---|
| 1 | BVA | time zone | values are recognised US zones |
| 2 | BVA | gender | exactly two recorded categories, or absent |
| 3 | BVA | Open Payments | zero is a legitimate observed value |
| 4 | semantic | time zone | matches the clinic's state |
| 5 | semantic | imputation | missing covariates filled the same way in both arms |
| 6 | semantic | gender | a categorical covariate is not defaulted to one of its levels |
| 7 | adversarial | calling window | no clinic fielded without a time zone |
| 8 | adversarial | credential | not defaulted to MD when unknown |
| 9 | adversarial | provenance | imputed values distinguishable from observed |
| 10 | adversarial | leakage | median imputation computed within arm, not pooled |

**6 failures, all real.**

**(a) ASYMMETRIC IMPUTATION OF A MATCHING COVARIATE. The most serious of this cycle.**
`build_matched_control_group_psm.R` fills missing Open Payments years with **the PE median
for the PE arm and 0 for the control candidates** (lines 176 and 179). Open Payments is one
of the four covariates in the propensity model, so the two arms are not merely imputed
differently, they are imputed in opposite directions: PE clinicians with unknown industry
activity are treated as typical, controls with unknown activity are treated as having none.
This biases the propensity score systematically between arms, which is the one thing a
matching covariate must not do.

**(b) Gender is defaulted to "Female" when missing**, in both arms. Gender is an exact-match
covariate, so this does not add noise, it forces those clinicians into the female stratum
and matches them to women.

**(c) Credential is defaulted to "MD" when unknown.** Recorded in cycle 12 as the mechanism
that admitted a nurse midwife; here it is also a covariate defect, since MD/DO is matched on.

**(d) Six clinics carry a time zone their state does not use**: UT and PA marked Pacific, TX,
TN and IL marked Eastern, OH marked Central. PA marked Pacific is three hours out; a caller
following the sheet could dial at 5pm "Pacific", which is 8pm in Pennsylvania. A closed
office is recorded as a failure to contact, which enters the obtainment outcome.

**(e) Four clinics have no time zone at all**, so the protocol's 0800 to 1700 local
instruction cannot be followed for them.

**(f) Nothing marks which values were imputed**, so Table 1, the balance claim, and any
sensitivity analysis cannot exclude them, and an imputed zero is indistinguishable from an
observed zero.

**Passed and worth recording.** Year medians are computed within arm rather than pooled, so
there is no cross-arm leakage in that covariate. Gender values are exactly Female/Male. All
time zone values are recognised zones, the problem is only which state they are attached to.

**A THIRD FALSE NEGATIVE IN MY OWN SUITE — strengthened.** Test 8 asserted `grepl('"MD"\\)')`
and so missed `"MD",`, passing while the default it targeted was present. Rewritten to match
`"MD"` literally. Running tally of tests of mine that passed while their defect existed:
cycle 5 (lat/lon transposition), cycle 13 (207V classifier), cycle 15 (MD default). **The
final audit must treat this as a category, not three incidents.**

**Suite:** 345 pass, 50 fail, 0 warn, 0 skip.

---

## Cycle 16 — 2026-08-10 04:3x — 4 BVA / 3 semantic / 3 adversarial

**Targets.** The enrichment covariates (CDC SVI is a fixed effect in the SAP's wait-time
model; the tract and county measures are the contextual adjusters), plus the false-negative
pattern in my own suite that cycle 15 asked the audit to treat as a category.

**Tests added** (`tests/testthat/test-enrichment-covariates.R`)

| # | Category | Target | Assumption challenged |
|---|---|---|---|
| 1 | BVA | CDC SVI | lies within the percentile interval |
| 2 | BVA | tract shares | each is a percentage in [0,100] |
| 3 | BVA | county counts | positive; PE concentration admits a true zero |
| 4 | BVA | Medicaid fee index | plausible ratio range, not constant |
| 5 | semantic | tract shares | labelled for what they actually measure |
| 6 | semantic | CDC SVI | behaves like a percentile across the cohort |
| 7 | semantic | county enrollment | data, not a floor value |
| 8 | adversarial | adjusters | none is constant |
| 9 | adversarial | adjusters | no two are the same column renamed |
| 10 | adversarial | this suite | absence assertions are anchored |

**3 failures.**

**(a) The tract coverage shares are not shares.** Summed across Private, Medicaid, Medicare
and Uninsured, **289 of 400 rows exceed 100%**, median 105.7%, maximum 134.3%. ACS coverage
types are not mutually exclusive: dual eligibles and Medicare supplement holders are counted
in more than one category. The column names read as exclusive population shares, which is how
anyone building a model would treat them. Each column is individually valid as a coverage
rate; the set is not a partition. Worth a naming or documentation fix before they are used
as adjusters.

**(b) County enrollment carries a floor, not data.** `County_Medicare_Enrollment` has **5
rows at exactly 100** and `County_Medicaid_Enrollment` has **12 rows at exactly 100**, both
being the column minimum. No US county has exactly 100 Medicare enrollees, and twelve
counties do not share exactly 100 Medicaid enrollees. This is a placeholder indistinguishable
from an observation, the same class as the unflagged imputation found in cycle 15.

**(c) FALSE-NEGATIVE PATTERN CLOSED.** Test 10 scans this suite for
`expect_false(grepl(...))` on source text that is neither `fixed = TRUE` nor anchored, the
exact shape behind all three tests of mine that passed while their defect was present
(cycles 5, 13, 15). It found **seven** live instances:

| File | Assertion |
|---|---|
| `test-address-key-parity.R:26` | `set\.seed` inside the loop |
| `test-coordinate-integrity.R:132` | `TRUE_OR_MEDICAID <- 0.x` |
| `test-matching-invariants.R:21` | `dists <= 10` |
| `test-matching-invariants.R:29` | `length(close_indices) >= 1` |
| `test-matching-invariants.R:68` | `PE_or_Not\|Latitude\|Longitude` |
| `test-matching-invariants.R:121` | `set\.seed` after the loop |
| `test-matching-provenance.R:70` | `stop(\|warning(` |

All seven anchored with `fixed = TRUE` or `\b`. These are strictly **stronger**, not looser:
the `Latitude` alternation, for example, previously matched the `Matcher_Latitude` column
added in cycle 8 and would have begun failing spuriously. The test now fails if anyone adds
an unanchored absence assertion, so the category is closed rather than tracked.

**Passed and worth recording.** CDC SVI is within [0,1], near-continuous with 393 distinct
values and a median of 0.439, so it behaves like a genuine percentile. No adjuster is
constant, and no two are the same column under different names. PE concentration has 89 true
zeros, which is a real observation rather than missingness.

**Suite:** recorded from the run below.

**Suite: pass=401  fail=53  warn=0  skip=0**

---

## Cycle 17 — 2026-08-10 05:0x — 3 BVA / 4 semantic / 3 adversarial

**Targets.** The exposure variable itself. `PE_or_Not` is the study's independent variable
and nothing had tested how it is attributed: which platform owns a clinic, when it was
acquired, and whether that platform can supply the service the vignette requests.

**Tests added** (`tests/testthat/test-pe-exposure.R`)

| # | Category | Target | Assumption challenged |
|---|---|---|---|
| 1 | BVA | acquisition year | inside the observable window |
| 2 | BVA | acquisition year | stored as a year, not a float |
| 3 | BVA | platform count | the PE arm is not one platform |
| 4 | semantic | exposure timing | every PE clinician has a dated acquisition |
| 5 | semantic | platform names | canonical, not near-duplicates |
| 6 | semantic | platform capability | can supply the appointment the vignette requests |
| 7 | semantic | control arm | carries a sentinel, not platform metadata |
| 8 | adversarial | temporality | exposure precedes the outcome window |
| 9 | adversarial | clustering | platform-level clustering is in the analysis plan |
| 10 | adversarial | leakage | no control attributable to a PE platform |

**5 failures.**

**(a) 18 PE clinicians sit at platforms that cannot provide the appointment being requested.**
The single fielded vignette is abnormal uterine bleeding, a generalist outpatient GYN visit.

| Platform | n | Why it cannot supply the visit |
|---|---|---|
| US Fertility | 6 | fertility practice, subspecialty referral setting |
| Kindbody | 5 | fertility practice |
| IVI RMA Global | 5 | fertility practice |
| **OB Hospitalist Group** | **2** | **inpatient hospitalists, no outpatient clinic at all** |

A caller requesting a new-patient AUB appointment at an OB hospitalist group will be told
no such appointment exists. That is recorded as failure to obtain, and enters the primary
obtainment outcome as if it were a refusal. This is independent of the 56 non-OB-GYN
taxonomies found in cycle 13; the two overlap only partially.

**(b) Platform-level clustering is unmodelled.** The 200 PE clinicians belong to **12
corporate parents**, the largest (Axia Women's Health) holding **27%** of the arm, and the
top three holding 66%. Clinics under one parent share scheduling policy, call centres and
payer contracts, so they are not independent observations. The SAP declares random
intercepts for matched pair and individual clinician only. This inflates precision on the
PE side of every estimate.

**(c) 4 PE clinicians have no acquisition year**, so exposure timing is unknown for them.

**(d) Acquisition years are stored as floats** ("2020.0"), the same representation hazard as
the NPI column found in cycle 3.

**(e) `Unified Women's Healthcare` and `Unified Women's Healthcare / Genesis OBGYN`** are the
same parent under two spellings, splitting one platform into two.

**Passed and worth recording.** Acquisition years all precede the 2026 calling window, so
temporality holds. The control arm carries a clean `Control Group` sentinel with no
acquisition years, so there is no exposure leakage. No clinician appears in both arms.

**A FOURTH FALSE NEGATIVE — and the category is wider than cycle 16 assumed.** Test 9 first
accepted any occurrence of "platform" anywhere in the manuscript and **passed**, matching the
Introduction's descriptive use of the word. Cycle 16's guard only covers
`expect_false(grepl(...))`; this was a *presence* assertion with a permissive disjunction.
Strengthened to require "platform" inside a line that declares a random intercept. **The
final audit must widen the category from "unanchored absence assertions" to "any assertion
whose pattern can be satisfied by text adjacent to the thing being tested".**

**Suite:** 412 pass, 58 fail, 0 warn, 0 skip.

---

## Cycle 18 — 2026-08-10 05:3x — 3 BVA / 3 semantic / 4 adversarial

**Targets.** The comparator. Cycle 17 tested the exposure; the Methods claims controls were
"restricted to independent private practices (excluding academic and hospital-system
settings)", which is the counterfactual the study rests on.

**Tests added** (`tests/testthat/test-control-independence.R`)

| # | Category | Target | Assumption challenged |
|---|---|---|---|
| 1 | BVA | organisation size | positive count with a floor of one |
| 2 | BVA | provenance | every fielded control resolves in its source pool |
| 3 | BVA | classifier | practice-setting categories assigned exhaustively |
| 4 | semantic | independence | controls are independent private practices |
| 5 | semantic | classifier | positively confirms private practice rather than failing open |
| 6 | semantic | claim vs code | the exclusion the manuscript claims is the one implemented |
| 7 | adversarial | unnamed facilities | not silently called independent |
| 8 | adversarial | scale | no control inside a very large organisation |
| 9 | adversarial | bug class | fail-open classifiers inventoried repo-wide |
| 10 | adversarial | this suite | no assertion satisfiable by adjacent text |

**6 failures. The control arm is not what the manuscript describes.**

> **148 of the 172 fielded controls with a recorded organisation size (86%) belong to
> organisations larger than 10 clinicians. Median 252. Maximum 7,694.**

| Organisation size | Fielded controls |
|---|---|
| 1 to 10 | 24 |
| 11 to 50 | 25 |
| 51 to 500 | 72 |
| 501 to 1,000 | 28 |
| **over 1,000** | **23** |

A 7,694-member organisation is a health system. Twenty-three controls sit in organisations
with more than a thousand clinicians. "Independent private practice" does not describe this
arm, and the comparison is therefore not PE-backed versus independent but PE-backed versus
mostly-large-group.

**Root cause: a third fail-open classifier.** `get_practice_setting()` in
`export_control_candidates.py` returns `'Private Practice'` when the facility name is empty
**and** again when it matches none of the academic, government or community keyword lists.
Exclusion is by name keyword only; **organisation size is never tested**. **28 fielded
controls have no facility name at all** and were admitted as independent by that default.

*Bug class, now three sites:* subspecialty classifier (cycles 3 and 13, 56 victims),
MD-vs-DO default (cycle 15), practice setting (here, 148+ victims). Every one defaults to
the category that ADMITS a record. Test 9 keeps the inventory visible.

**Passed and worth recording.** Organisation sizes are well-formed positive counts, every
fielded control resolves in the candidate pool it was drawn from, and all four
practice-setting categories are assigned somewhere in the code.

**The widened false-negative guard works, and caught itself.** Test 10 extends cycle 16's
guard from absence assertions to presence assertions whose pattern can be satisfied by
adjacent text, the cycle-17 shape. On first run its only hit was the example
`grepl("platform", ms)` inside its own explanatory comment. Corrected to skip comment lines,
which is a scoping fix rather than a loosening: comments are prose, not assertions. No real
offenders remain.

**Suite:** 424 pass, 65 fail, 0 warn, 0 skip.

---

## Out-of-band — 2026-08-10 05:4x — PLATFORM-LEVEL ELIGIBILITY EXCLUSION AND FULL REDRAW

User authorised excluding five platforms from the treated cohort as an eligibility rule
upstream of the PSM, preserving an all-PE roster for control ineligibility, and redrawing
the sample end to end.

**Code changes to `build_matched_control_group_psm.R`**

1. `EXCLUDED_PLATFORMS` defined and applied immediately after NPI filtering, **before**
   office clustering, propensity estimation and matching.
2. Two cohorts now maintained: `pe_roster_all` (every PE-owned NPI, used only to keep PE
   clinicians out of the control pool) and `pe_matched_all` (the study-eligible treated
   cohort).
3. **`pe_full_df <- pe_df` changed to `pe_full_df <- pe_matched_all`.** This was the
   user's correction and it was decisive: the unified study database reset to the unfiltered
   roster, so filtering only `pe_matched_all` would have reintroduced all five platforms into
   every downstream artifact.
4. Control pool now explicitly filtered against the full PE roster. Nothing previously
   enforced this; the pools happened not to overlap (measured: 0 of 20,111 candidates), which
   is a property of the source data, not a guarantee.

**Removed by platform**

| Platform | Physicians | Distinct offices |
|---|---:|---:|
| CCRM Fertility | 56 | 39 |
| IVI RMA Global | 76 | 45 |
| US Fertility | 62 | 42 |
| Kindbody | 17 | 14 |
| OB Hospitalist Group | 4 | 4 |
| **Total** | **215** | **140** |

**New counts**

| Quantity | Before | After |
|---|---:|---:|
| PE roster (control-ineligible) | 1,279 | 1,279 |
| Study-eligible PE cohort | 1,279 | **1,064** |
| Eligible with phone + generalist | 1,033 | **1,003** |
| Eligible distinct offices | — | **603** |
| Matched pairs | 518 | **495** |
| 300-pair sample | 300 | **300** |
| Fielded 200-pair sample | 200 | **200** |
| States represented | 26 | **23** |
| Caliper geo matches | 345 | **318** |

**Pipeline rerun end to end**, with no pair IDs preserved and no in-place patching: PSM from
scratch, `pe_obgyn_matched_calling_list.csv` regenerated (990 records), 300-pair sample
redrawn, office de-duplication reapplied, geographically balanced 200 redrawn, and all three
REDCap artifacts regenerated (800 records, codes 1-400 Medicaid / 401-800 BCBS).

**The de-duplication had to be reapplied.** The redraw chain (subsample 300 -> balance 200)
does not de-duplicate offices, and the fresh 200 arrived with **129 of 400 rows sharing a
dialled number**. After reapplying `dedup_offices_and_backfill_200.R`: 124 pairs retained,
76 backfilled, **0 shared phones**, and the two-calls-per-office guarantee restored.

**Tests added** (`tests/testthat/test-platform-exclusion.R`, 17 assertions, all passing) —
the three the user specified plus two supporting contracts:
1. no excluded platform enters the treated cohort at any stage, and the exclusion precedes
   clustering in the source order;
2. no NPI from an excluded platform reaches the matched pool or the fielded sample;
3. no PE-owned clinician appears as a control anywhere, and the guard exists in the pipeline
   rather than merely holding in this data;
4. the two cohorts are distinct and the eligible one feeds the study database;
5. the redraw is a fresh draw of 200 pairs, not a patch.

**Honest limitations of this redraw**

- **Enrichment is 88% complete.** The 15 SVI, tract, county and churn columns are joined by
  NPI from the previous enriched database. All 300 PE clinicians resolve; **69 of 300 new
  controls do not**, because they were not in the old cohort. Those rows carry NA for those
  columns. Completing them requires rerunning `extract_demographic_covariates.R`,
  `apply_demographic_covariates.R` and `calculate_cohort_churn.R`, which need the ACS API,
  HRSA and CMS inputs and the 83.7 GB DuckDB. **The CDC SVI adjuster in the SAP is therefore
  missing for 69 controls until that chain is rerun.**
- **Taxonomy contamination is essentially unchanged: 53 non-OB-GYN clinicians in the fielded
  200, against 56 before.** The platform exclusion and the taxonomy problem are nearly
  independent, exactly as cycle 17 suspected. The 207V eligibility filter is still needed and
  is still not applied.
- **Geographic concentration worsened**: 26 states to 23, and Florida's share rose from 26%
  to 31%, because the excluded platforms were geographically dispersed.
- Table 1, the STROBE figure and every dummy table in the manuscript now describe a cohort
  that no longer exists and must be regenerated after the taxonomy decision.

**Suite:** 396 pass, 63 fail. The drop from 424 reflects the cohort change: data-level
assertions written against the previous fielded sample now describe a different one.

---

## Out-of-band — 2026-08-10 06:0x — MANUAL VERIFICATION OF NON-PHYSICIAN RECORDS

User challenged the cycle-13 framing that 13 fielded clinicians were trainees, noting that
clinicians often keep a student taxonomy long after training. **The challenge was correct
and the framing is withdrawn.**

**Evidence against the trainee reading.** After the redraw, 7 clinicians carry
`390200000X`, all of them in the CONTROL arm: median NPI enumeration year **2012**, median
**14 years in practice**, **6 of 7** enumerated at least ten years ago, and **7 of 7** with
Open Payments history. Industry payments are made to practising physicians. The wider
non-OB-GYN group is likewise indistinguishable from the OB-GYN group on every practice
indicator (median 28 vs 24 years in practice, 8 vs 8 Open Payments years, enumeration 2006
vs 2007).

**A structural limitation found while checking.** The pipeline retains **one taxonomy per
NPI**. NPPES permits several with one flagged primary, so a clinician whose OB-GYN taxonomy
is secondary appears non-OB-GYN here purely because the other rows were discarded upstream.
A 207V filter would therefore act on a single, self-reported, often decade-stale field.
**The 207V eligibility filter recommended in cycle 13 is withdrawn**, and a test now
prevents one being added.

**Two non-physician-taxonomy records verified individually against practice websites.**

| NPI | Name | Recorded | Verified | Outcome |
|---|---|---|---|---|
| 1144280553 | Cindy Joslyn | taxonomy Midwife, NPPES cred CNM, **roster name "Cindy Joslyn, MD"** | Women's Health of Central Massachusetts states she is "Certified by the American College of Nurse Midwives"; providing midwifery care since 1996 | **EXCLUDED** |
| 1932194743 | Claire Harraghy | taxonomy **363LW0102X (nurse practitioner)**, NPPES cred MD | A Woman's View, Hickory NC states she "is a board-certified OB/GYN"; UNC Health lists her under Obstetrics and Gynecology | **RETAINED** |

Exactly the split the user predicted: one genuine miscoding of a real OB-GYN, and one genuine
non-physician. Neither could have been resolved by a taxonomy rule, since the rule would have
removed both.

**Note on the roster name.** Joslyn is recorded as "Cindy Joslyn, **MD**" while both her
credential fields read CNM. That appended "MD" is a scrape error and is precisely how she
passed the MD/DO derivation found in cycle 15, which treats anything that is not DO as MD.
Two independent defects had to line up for a nurse midwife to reach a physician cohort.

**Change made.** `EXCLUDED_NPIS` added to `build_matched_control_group_psm.R`, containing the
one verified non-physician, applied alongside the platform exclusion. Two tests added: the
verified CNM must be named in the exclusion list, and no 207V taxonomy filter may gate
eligibility. `tests/testthat/test-platform-exclusion.R` now holds 21 passing assertions.

**Deliberately NOT re-run.** Joslyn is not in the current fielded 200; she sits in the matched
pool at pair_457 and in the 300-pair sheet, so she could only enter through a de-duplication
backfill. The guard prevents that on any future run. Re-running the whole pipeline to remove
one clinician who is not currently fielded would churn the cohort for no gain.

---

## Cycle 19 — 2026-08-10 06:2x — 4 BVA / 3 semantic / 3 adversarial

**Targets.** Provider-name and credential parsing, following the manual verification: the
roster name "Cindy Joslyn, MD" contradicted her own CNM credential, and that appended "MD"
is how she passed the MD/DO derivation. How far does that parsing failure extend?

**Tests added** (`tests/testthat/test-name-credential-parsing.R`)

| # | Category | Target | Assumption challenged |
|---|---|---|---|
| 1 | BVA | provider name | non-empty on every roster row |
| 2 | BVA | name credentials | a non-physician-only name credential never reaches the cohort |
| 3 | BVA | suffixes | a generational suffix is not absorbed into the credential token |
| 4 | BVA | parsed names | first and last populated wherever a name exists |
| 5 | semantic | credential conflict | a name claiming MD/DO never contradicts a mid-level credential |
| 6 | semantic | board suffixes | FACOG and friends are not treated as conflicts |
| 7 | semantic | parsing fidelity | the parsed surname appears in the source name |
| 8 | adversarial | NPI format | the roster stores NPI without a float suffix |
| 9 | adversarial | identity | no clinician appears twice under different NPIs |
| 10 | adversarial | auditability | credential conflicts are bounded and enumerable |

**4 failures, and the headline result is reassuring: the parsing failure is a singleton.**

Of 1,537 roster rows, 961 carry a credential appended to the name and 724 have both that
token and an NPPES credential. **216 look like conflicts, but almost all are board
memberships**: MDFACOG against NPPES MD, DOFACOG against DO. Once those are stripped:

> **Exactly one row claims a physician credential in the name against a non-physician
> credential in NPPES: Cindy Joslyn, already excluded.**

That bounds the defect the manual check uncovered. It is not a systemic parsing failure.

**Three non-physician records exist in the roster and none reached the cohort.** Carli
Chapman ELD (ABB) at Kindbody (embryology laboratory director), T.J. Maresca LCGC at Women's
Care Enterprises (genetic counsellor), and Alissa Hosein LD (dietitian). **All three carry no
NPI**, so the NPI-matching requirement excluded them before matching. Worth recording as a
place where the pipeline's own guard did its job.

**Real defects found:**

1. **Generational suffixes are absorbed into the credential token.** "Name, Jr, MD" collapses
   to `JRMD`, so the suffix and credential are no longer separable and the credential no
   longer compares equal to NPPES. Two rows.
2. **The roster stores NPI with a float suffix** (`1144280553.0`), a fresh instance of the
   representation hazard first found in cycle 3. This is the upstream source, so it seeds
   every consumer.

**Two test premises of mine — corrected.**
- Test 2 first enumerated a closed vocabulary of credential tokens and failed on legitimate
  extra degrees (MDJD, MDMIGS, MDFPMRS, DOESQ, MDIBCLC). Enumerating every valid degree is
  unbounded and was not the contract; rewritten to assert that a name claiming ONLY a
  non-physician credential never carries an NPI.
- Test 9 reported "3 names map to more than one NPI". They were a named clinician paired with
  their own NPI-less row, which is one person. Corrected to exclude blank NPIs; **zero true
  duplicates remain.**

**Passed and worth recording.** Every roster row has a name; parsed first and last names are
populated throughout; the parsed surname appears in the source name for more than 95% of
rows; board suffixes correctly reduce 216 apparent conflicts to a handful; and no clinician
appears under two NPIs.

**Suite:** 409 pass, 67 fail, 0 warn, 0 skip.

---

## Out-of-band — 2026-08-10 06:5x — FLOAT NPI FIXED AT SOURCE

The representation hazard first found in cycle 3 (`1003038688.0` vs `1003038688`) is
repaired at its origin rather than worked around downstream.

**Root cause.** `match_all_providers.py:528` did `int(float(x)) ... else None`. The value is
correct, but a pandas column of integers containing `None` is promoted to `float64`, so
`to_csv` writes `1003038688.0`. Every consumer then joins on a key that does not match the
integer NPIs in the calling sheets: cycle 3 measured a raw join of the fielded sheet against
the study database at **0 of 400 rows**.

**Fix.** `df['NPI'] = df['NPI'].astype('Int64')` after the cast. Int64 is pandas' nullable
integer type and writes the value with no decimal while preserving missingness.

**Existing artifacts normalised**, with backups in `backups/npi_normalize_20260810_065x/`:

| File | NPI values normalised |
|---|---:|
| pe_obgyn_providers_active.csv | 1,279 |
| pe_obgyn_providers_npi.csv | 1,279 |
| auto_not_in_gs_v2.csv | 749 |
| auto_not_in_gs.csv | 427 |
| gs_missing_with_npi.csv | 182 |
| optimal_coverage_sample_100.csv | 100 |
| new_physicians_with_npi.csv | 27 |
| optimal_coverage_sample_72.csv | 72 |
| strict_equal_sample_reduced.csv | 72 |

Verified cell by cell against the backups: shape unchanged in every file and **zero non-NPI
cells altered**.

**Pipeline rerun.** The roster is the matcher's input, so the whole chain was regenerated:
PSM, 300-pair sample, enrichment, office de-duplication, 200-pair sample and all REDCap
artifacts. The Joslyn NPI exclusion also took effect on this run, so the matched pool moved
from 495 to **494 pairs** and the fielded 200 was redrawn (134 retained, 66 backfilled,
0 shared phones, 23 states).

**Verification.** The raw join of the fielded sheet against the study database now matches
**400 of 400**, against 0 before. No CSV in the repository retains a decimal NPI.

**A test contract inverted, not weakened.** The cycle-3 test asserted
`sum(sheet$NPI %in% db$NPI) == 0`, pinning the hazard so nobody joined on the bare column.
That assertion described a defect that no longer exists, so it now asserts the opposite: the
raw join must match every fielded clinician, and neither artifact may contain a decimal NPI.
Pinning a defect is right while it stands; leaving the pin in place after the fix would be a
test asserting brokenness.

**Suite:** 413 pass, 65 fail, 0 warn, 0 skip.

---

## Cycle 20 — 2026-08-10 07:0x — 3 BVA / 4 semantic / 3 adversarial

**Targets.** The definition of the PE universe: the PitchBook keyword filter that decides
which companies count as private-equity-owned OB-GYN. It sits upstream of the roster, the
cohort, the exposure variable and every result, and had not been tested.

**Tests added** (`tests/testthat/test-pe-universe.R`)

| # | Category | Target | Assumption challenged |
|---|---|---|---|
| 1 | BVA | keyword patterns | word-anchored where ambiguity would bite |
| 2 | BVA | universe | non-empty subset of what it filtered |
| 3 | BVA | company records | every filtered company carries a name |
| 4 | semantic | traceability | every fielded platform traces to the PitchBook universe |
| 5 | semantic | coherence | the exposure universe and the eligibility rule do not contradict |
| 6 | semantic | filter scope | searches relevant fields, not every cell |
| 7 | semantic | exclusion | excluded platforms absent from the cohort but retained in the roster |
| 8 | adversarial | precision | no filtered company is a pure keyword coincidence |
| 9 | adversarial | deal records | carry a date and a type |
| 10 | adversarial | claim vs code | the manuscript's identification claim matches the implementation |

**4 failures.**

**(a) One fielded platform is not traceable to PitchBook.** **Advantia Health** appears in
neither the filtered company list nor the deal list, matched against both by normalised name.
It accounts for **19 clinicians in the eligible cohort and 6 in the fielded 200**. The Methods
states PE clinics "were identified using the PitchBook financial database to track
acquisitions by major women's-health platforms". Advantia's PE status therefore rests on a
source that is not documented and not in the repository. The other seven platforms trace
cleanly.

**(b) The exposure universe is defined around a segment the study excludes.** The keyword list
deliberately includes `\bfertility\b` and `\bivf\b`, and **42 of 72 companies (58%)** in the
resulting universe name fertility or IVF. Those platforms are then removed at the eligibility
step because they cannot supply a generalist GYN visit. Building the universe around
fertility and then discarding it is a contradiction that belongs in one place or the other:
either the keyword list should not target fertility, or the eligibility rule should be stated
as part of the universe definition.

**(c) The filter matches any cell in any column.** `df.map(matches_keywords).any(axis=1)`
admits a company if a keyword appears anywhere in the row, including the investor's name or a
free-text description. A generalist healthcare fund whose blurb mentions women's health
enters the OB-GYN universe. The precision test partly reassures here: **more than 90% of
filtered company names carry an OB-GYN term themselves**, so the loose scope has not done
much damage in practice, but nothing prevents it.

**(d) The Methods does not mention fertility** although fertility dominates the search
universe. "Acquisitions by major women's-health platforms" understates what was actually
searched.

**Passed and worth recording.** Keywords are word-anchored where it matters; the filtered
universe is a proper subset; every company carries a name; deal records carry dates and types;
excluded platforms are absent from the cohort while retained in the roster, which is both
halves of the eligibility contract holding simultaneously.

**Suite:** 429 pass, 69 fail, 0 warn, 0 skip.

---

## Cycle 21 — 2026-08-10 07:3x — 3 BVA / 3 semantic / 4 adversarial

**Targets.** Whether the cohort is still current. The Methods calls this an "active clinician
roster". Two independent signals bear on that and neither had been tested: when the platform
directories were scraped, and the last year each clinician was observed practising. A
clinician who has left is recorded as a failure to contact, which enters the primary
obtainment outcome as if it were a refusal.

**Tests added** (`tests/testthat/test-roster-currency.R`)

| # | Category | Target | Assumption challenged |
|---|---|---|---|
| 1 | BVA | scrape timestamp | recorded on every roster row |
| 2 | BVA | scrape window | timestamps fall in a plausible range |
| 3 | BVA | activity year | never post-dates its source |
| 4 | semantic | currency | the activity signal supports an "active roster" claim |
| 5 | semantic | provenance | every clinician traces to a named source |
| 6 | semantic | provenance form | recorded in one consistent form |
| 7 | adversarial | attrition risk | no fielded clinician last observed long ago |
| 8 | adversarial | coverage | activity known for every fielded clinician |
| 9 | adversarial | scrape coverage | every fielded platform appears in the scrape stats |
| 10 | adversarial | attrition mechanism | one exists given the roster's age |

**6 failures.**

**(a) The activity signal stops five years before the calling window.** `Last Active Year`
ranges 2013 to 2021 with **zero rows at 2022 or later**, so 2021 is the source's last year
rather than a property of these clinicians. **21 of 400 fielded clinicians were last observed
practising in 2019 or earlier**, and **40 of 400 have no activity year at all**. The Methods
describes an "active clinician roster"; the activity evidence cannot support that word on its
own. What does support it is the platform directory scrape, which is current.

**(b) 33 roster rows carry no scrape timestamp** (all from "Manual scrape (annotated
practices)"), so their currency is unknown.

**(c) 144 of 1,537 sources carry no resolvable domain**, being a platform name rather than a
page. Provenance for those rows cannot be re-checked.

**(d) Advantia Health is absent from `scraping_stats.json`**, matched by the documented slug
mapping. This is the second independent gap for the same platform: cycle 20 found it absent
from the PitchBook universe. **Advantia's PE status and its roster provenance are both
undocumented**, covering 19 clinicians in the eligible cohort and 6 in the fielded 200.

**(e) No attrition mechanism is stated.** The roster is roughly 7 weeks old at the calling
date and the backup-physician protocol was cut from the manuscript, leaving the replacement
pool as the only absorber, which the Methods does not describe as one.

**Two test premises of mine — corrected.** The provenance-format test required the domain to
end the string, so "togetherwomenshealth.com (Eastside)" counted as a non-URL; 658 false
positives reduced to 144 genuine ones. The scrape-coverage test matched platform display
names against stats keys that are slugs ("1_uwh_michigan" is Unified Women's Healthcare);
corrected to a documented mapping, which reduced four apparent gaps to one real one.

**Passed and worth recording.** Scrape timestamps are all within June 2026, activity years
never post-date their source, and every roster row carries a Source of Information field.

**Suite:** see the line below, read from the run.

**Suite: pass=438  fail=75  warn=0  skip=0**

---

## Out-of-band — 2026-08-10 08:0x — ACTIVITY RECENCY EXCLUSION

User asked to remove clinicians "not seen" in over two years, and specifically the 21 fielded
clinicians last observed in 2019 or earlier.

**The interpretation had to be settled first, because the obvious one destroys the study.**
`Last Active Year` maxes out at **2021**, so "within two years" measured against the 2026
calling year requires activity in 2024 or later and **keeps 0 of 1,032 clinicians**. The
threshold is therefore anchored to the newest activity year present in the data, which asks
the answerable question, "was this clinician still practising at the end of the observation
window", and self-calibrates if the source is ever refreshed.

```
MAX_INACTIVE_YEARS      <- 2
ACTIVITY_REFERENCE_YEAR <- max(Last Active Year)      # 2021, read from the data
cutoff                  <- reference - (MAX_INACTIVE_YEARS - 1)   # 2020
```

Applied before clustering, propensity estimation and matching, alongside the platform
exclusion. A guard aborts the run if the rule would remove more than half the cohort, so a
future empty or stale activity column fails loudly instead of silently emptying the study.

**Clinicians with no recorded activity year are RETAINED.** Absent evidence of activity is
not evidence of absence, and excluding them would drop 246 PE and 1,187 control candidates on
a missing value rather than an observation.

**A second defect found while verifying: the rule was asymmetric.** The first implementation
filtered only the treated arm. The fielded set still contained **10 controls last active
before 2020, and 0 such PE clinicians** — the arms had different eligibility criteria, so any
difference in reachability between them would partly reflect the filter rather than ownership.
This is the same shape as the asymmetric imputation found in cycle 15. The rule now applies
to `candidates_df` with the identical cutoff.

**Effect**

| | Before | After |
|---|---:|---:|
| Study-eligible PE cohort | 1,063 | **992** |
| PE excluded as inactive | — | **151** |
| Control candidates excluded as inactive | — | **2,036** |
| Matched pairs | 494 | **470** |
| Fielded clinicians last active before 2020 | 21 | **0** |
| Fielded states | 23 | 23 |

Full chain regenerated: PSM, 300-pair sample, enrichment, de-duplication, 200-pair sample and
all REDCap artifacts. De-duplication reapplied (131 retained, 69 backfilled, 0 shared phones).
Enrichment coverage 87%, the missing rows all new controls absent from the previous enriched
database.

**Tests added** (`tests/testthat/test-activity-recency.R`, 11 assertions, all passing): no
fielded clinician outside the window in either arm; the threshold is anchored to the data
rather than the calling year; a missing activity year is not treated as inactivity; the
runaway guard exists; and the exclusion precedes clustering.

**Suite:** 450 pass, 74 fail.
