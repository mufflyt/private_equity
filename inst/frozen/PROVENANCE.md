# Frozen geographic reference for the fielded cohort

## Status: the upstream gazetteer artifact could NOT be reconstructed

`build_matched_control_group_psm.R` resolves city+state to coordinates through
`mysterycall::city_state_to_lat_long`. The build of that dataset used to construct the fielded
200-pair cohort no longer exists:

* `mysterycall` git history contains exactly two commits touching the gazetteer blob —
  `f4eb8135` (2023-12-01) and `22d07772` (2026-06-02, a rename only). Both trees carry the
  **same** 31,909 x 4 table with full state names and `latitude`/`longitude` columns.
* No other installed copy, tarball, `.Rcheck` directory or cache exists on this machine.
* The installed build that the cohort was matched against was overwritten on 2026-08-10 when
  `mysterycall` was reinstalled from source during this audit. That was my error.

The historical artifact therefore cannot be preserved. Per instruction, the new gazetteer has
**not** been substituted into the primary analysis and the cohort has **not** been regenerated.

## The drift is material, not cosmetic

Re-resolving the 918 matched clinicians' city+state through the **current** gazetteer, using the
matcher's own 53-entry state map:

| Quantity | Value |
|---|---:|
| Matched clinicians | 918 |
| Resolvable in the current gazetteer | 860 (93.7%) |
| Coordinates identical to the frozen ones | **707 / 860 (82.2%)** |
| Maximum discrepancy | **54.18 degrees** |

A 54-degree discrepancy is continental. Roughly one matched clinician in six would resolve to a
different location, which changes who falls inside the 10-mile caliper and therefore which
controls were eligible. Substituting the current gazetteer is a new matching specification.

## What is frozen instead

The reference **as applied** survives, because the matcher persists the coordinates its caliper
actually used. `geo_reference_fielded_cohort.csv` is those coordinates, extracted from
`pe_obgyn_study_database.csv` (`Matcher_Latitude`, `Matcher_Longitude`) for all 918 matched
clinicians, keyed by NPI with the city and state that produced them.

This is the stronger artifact for the purpose. The `.rda` was only a container; what the
estimand depends on is the coordinate each clinician was assigned.

| Field | Value |
|---|---|
| Artifact | `inst/frozen/geo_reference_fielded_cohort.csv` |
| SHA-256 | `4e825fc798c034944a00a7d11fd15f71f830ff528b8f024cc00493d0d1bb01bc` |
| Rows | 918 (one per matched clinician) |
| Distinct city+state | 276 |
| Columns | `npi`, `city`, `state`, `lat`, `long` — the pipeline contract |
| Source | `pe_obgyn_study_database.csv`, columns `Matcher_Latitude` / `Matcher_Longitude` |
| Extracted | 2026-08-11 |

## Current mysterycall, recorded but NOT used for the primary analysis

| Field | Value |
|---|---|
| Commit | `f3c001a8d0f4fe5f68630cfca3b95c592947764d` |
| Version | 1.6.0 |
| `data/city_state_to_lat_long.rda` SHA-256 | `f2506de4b15cbfa151e386b852ad5748e942c185ea1a700ef4b6ef5896a664b1` |
| Dimensions | 31,909 x 4 |
| Columns | `state`, `city`, `latitude`, `longitude` |
| State vocabulary | full names ("Alabama") |

Recorded so that a future compatibility check has something to compare against. **It is not the
reference the fielded cohort was built on and must not be substituted for it.**

## Correction to an earlier claim

An earlier commit message and `tests/BLOCKING` note stated the gazetteer "went from 6,211 rows
with two-letter states to 31,909 rows with full state names". That was wrong. 6,211 was the
number of rows a **seven-state stub map inside the test** could resolve, misread from a
test-failure diff as a row count. The historical gazetteer's dimensions were never observed and
are now unrecoverable. What is established is that its contents differed materially — 82.2%
agreement, 54-degree maximum discrepancy — and that `names()` on it included `lat` and `long`,
since the original test asserted exactly that and passed.

## The open decision

Pinning `mysterycall` to the build the cohort used is not possible; that build is gone. The
options that remain:

1. **Treat `geo_reference_fielded_cohort.csv` as the frozen dependency** (implemented here).
   Any reconstruction of the matched cohort must join coordinates from this file rather than
   from a package dataset. The primary cohort is unchanged and unchanging.
2. Re-derive the historical gazetteer from its upstream source if `data-raw/` can rebuild it
   reproducibly, then compare against the frozen coordinates.
3. Accept the current gazetteer and regenerate — explicitly declined for this repair.

Option 1 is in force. Running the current gazetteer as a **sensitivity analysis** is a separate,
worthwhile exercise: if it reproduces the same matched controls the drift was inconsequential,
and if it does not, that is a robustness result rather than an undocumented mutation. The 82.2%
figure above suggests it will not, which is precisely why it must not touch the primary cohort.
