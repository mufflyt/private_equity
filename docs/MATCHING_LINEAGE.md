# Matching lineage of the fielded cohort

**Date:** 2026-08-24. **Scope:** a bounded lineage-recovery pass, run without altering the
400-person frame, the 200 pair assignments, blinded numbering, caller materials or REDCap.

Two findings were kept separate throughout: **missing provenance is not evidence of incorrect
matching, and it cannot be silently converted into verified provenance either.**

---

## S1. Finding A — the 137 "missing provenance" clinicians: RESOLVED

137 of the 400 fielded clinicians had no row in `pe_obgyn_study_database.csv`. They were being
looked for in the wrong artifact.

**The matching run that produced the fielded cohort is preserved in
`pe_obgyn_study_database_with_churn.csv`.** All 200 fielded pairs match it by label *and by
membership*, 200/200, and all 400 clinicians are present. `pe_obgyn_matched_calling_list.csv`
is a **different matching run**:

| Candidate lineage | Label + membership identical | Same two clinicians under any label |
|---|---:|---:|
| `pe_obgyn_study_database_with_churn.csv` (511 pair groups, 1,022 rows) | **200 / 200** | **200 / 200** |
| `pe_obgyn_matched_calling_list.csv` (459 pairs) | 6 / 200 | 53 / 200 |

The two runs share a label vocabulary and mean different things by it. `pair_101` is Bunting +
Grenitz (Davie / Plantation FL) in the fielded cohort and Pezzullo-Burgs + Johnson (Miami FL)
in the 459-pair file. **`Matched Pair ID` is not a stable identifier across artifacts** and must
never be used as a join key between them.

This corrects an earlier characterisation in this repository, including in `README.md` and in
the commit for PR #12, that "173 of the 400 fielded clinicians are not in the matched pool" and
"bypassed the stage that applies the exclusion". They did not bypass matching. They came from a
different run of it.

## S2. Finding B — the geographic input: State 2, explained but not reproducible

`control_candidates_raw.csv` was never the coordinate source and its lack of latitude is not a
defect in it. `build_matched_control_group_psm.R` resolves city + state to coordinates through
`mysterycall::city_state_to_lat_long`, a gazetteer, and applies a haversine caliper of
`dists < 10` miles requiring at least two candidates inside the radius.

The gazetteer build the cohort was matched against was overwritten on 2026-08-10 and cannot be
recovered; `inst/frozen/PROVENANCE.md` documents this and records that re-resolving through the
current build reproduces 82.2% of coordinates with a 54-degree maximum discrepancy. What
survives is the reference **as applied**: `Matcher_Latitude` / `Matcher_Longitude`, frozen into
`inst/frozen/geo_reference_fielded_cohort.csv` (918 rows, sha256 recorded there).

### The caliper was applied in the 459-pair run

Using the coordinates that run's caliper actually used:

| Quantity | Value |
|---|---:|
| Pairs tested | 459 / 459 |
| Pairs at or beyond 10 miles | **0** |
| Maximum within-pair distance | **9.976 miles** |
| Median | 0.000 miles |
| Pairs at exactly zero distance | 260 (56.6%) |

A maximum of 9.976 against a threshold of 10 is the signature of an enforced caliper. The
median of zero is the city-level geocoding, which is a separate limitation recorded in
`test-matching-provenance.R`.

## S3. Finding C — NEW, and this one is State 3

**The matching run that produced the fielded cohort did not apply the platform exclusion.**

| Run | Rows carrying a pair group | Pairs | From a protocol-excluded platform |
|---|---:|---:|---:|
| Fielded cohort's run (`_with_churn`) | 1,022 | 511 | **23** |
| 459-pair run (`matched_calling_list`) | 918 | 459 | **0** |

The 511 pair groups are exactly the "511-pair matched pool" that
`dedup_offices_and_backfill_200.R` names in its own header, which independently confirms this
artifact as the pool the fielded set was drawn from.

The five excluded platforms are fertility practices and an inpatient hospitalist group, which
`test-platform-exclusion.R` documents as unable to supply the appointment the study requests.
The 459-pair run excluded them completely. The run the cohort came from matched 23 of them
into pairs, and 18 of those reached the fielded frame.

### The caliper in that run is partially violated, and mostly untestable

Only 88 of the 200 fielded pairs have matcher coordinates for both members; the other 112
contain at least one clinician who appears in no artifact carrying `Matcher_*` columns.

| Quantity | Value |
|---|---:|
| Fielded pairs testable | 88 / 200 |
| Pairs at or beyond 10 miles | **2** (`pair_116` at 34.39 mi, `pair_24` at 10.76 mi) |
| Maximum | 34.386 miles |
| Median | 3.825 miles |

Two violations in 88 is not the clean enforcement the 459-pair run shows, and 112 pairs cannot
be checked at all. This is evidence of partial or absent caliper enforcement in the fielded
run, not proof of its scale.

## S4. Classification

| Finding | State | Grounds to reopen the cohort? |
|---|---|---|
| A — 137 missing provenance | **Resolved.** Lineage recovered; wrong artifact | No |
| B — geographic input, 459-pair run | **2. Explained but not reproducible** | No |
| C — platform exclusion, fielded run | **3. Scientifically unsupported** — a documented protocol rule was demonstrably not applied | **Yes** |
| C′ — caliper, fielded run | Partially violated where testable; 56% untestable | Contributes to C |

Per the standing rule, only state 3 is grounds to reconsider the pair assignments. **Finding C
reaches it.** Nothing has been changed. The frame, the pairs, the numbering, the caller
materials and REDCap are untouched pending that decision.

## S5. Two near-misses worth recording

**The wrong coordinate column.** The first caliper test on the fielded run reported 142 of 200
pairs beyond 10 miles, a median of 382 miles and a maximum of 1,611 — a catastrophic-looking
result, and wrong. It used `_with_churn`'s `Latitude`, which is **not** the matcher's
coordinate: for NPI 1003038688 the matcher used 41.960637 and that column holds 33.234. Three
coordinate columns exist across these artifacts (`latitude`, `Matcher_Latitude`, `Latitude`)
and only one decided the caliper. Caught because `inst/frozen/PROVENANCE.md` names it.

**The broken row filter.** The exclusion count was first computed as 215 by a Python filter
that failed to select grouped rows and silently scanned all 2,048 instead. The R
implementation returned 23. R is right: 1,022 grouped rows is 511 pairs, which matches the
pool size the backfill script documents. The corrected figure is **23**.

Both are recorded because they are the same class of error this audit exists to find, made
while performing the audit, and because a wrong catastrophic finding is more damaging than a
missed one. Neither reached a conclusion, because both were checked against a second
implementation before being written down.

## S6. CI taxonomy

Three levels, distinguished because they mean different things:

| Level | Meaning | Example |
|---|---|---|
| **Blocking execution** | Must be true to run the current pipeline | `test-analysis-gates.R`, `test-blinded-slot-assignment.R` |
| **Advisory historical provenance** | Cannot be made green because a historical input is genuinely gone | `test-matching-provenance.R` control-candidate contract |
| **Publication readiness** | Does not stop data collection, but must block any claim that the cohort is fully reproducible, and must block final manuscript release unless resolved or disclosed | Findings B and C above |

Finding C belongs to publication readiness and to the cohort decision. Finding B belongs to
publication readiness alone: it does not invalidate the 459-pair run, but it does mean the
phrase "fully reproducible" cannot be used of this cohort without disclosure.
