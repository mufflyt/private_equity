# Manuscript provenance audit

**Date:** 2026-08-24. **Scope:** every publication-facing artifact in this repository.
**Prompted by:** two figures in `manuscript/` that depicted the study's primary outcomes from
numbers typed into the script, before any call was placed.
**Enforced by:** `tests/testthat/test-manuscript-provenance.R` (blocking).

---

## S1. Why this exists

A figure named `figure1.png`, titled "Appointment Obtainment Rates by Practice Ownership",
showing PE Medicaid acceptance of 41.0% against 72.5% for independent practices with
confidence intervals, is indistinguishable from a result. It was not one. The rates were
literals in `manuscript/generate_figures.R`; the wait-time distribution beside it was
`rlnorm()` draws around typed medians. No call has been placed, no REDCap outcome export
exists, and `SAP.lock` has never been run.

That is not a stale artifact. It is a plausible, publication-shaped object with no measurement
behind it, and no unit test would ever have found it — nothing was broken. This audit exists
because if two of them were sitting in `manuscript/`, the question is what else is.

## S2. Status vocabulary

| Status | Meaning |
|---|---|
| `verified` | Value recomputed from a committed artifact and matches |
| `stale` | Value was computed correctly once, from a superseded cohort |
| `simulated` | Value comes from simulated or random data |
| `hard-coded` | Value typed into a script rather than derived |
| `external` | Published quantity from a cited source; correctly hard-coded |
| `design` | Pre-specified design parameter; correctly hard-coded |
| `unresolved` | Cannot be produced by the current pipeline; must not be inferred |

## S3. Audit table

### Outcome claims — none are measured

| Artifact | Reported | Source of value | Current | Status | Action taken |
|---|---|---|---|---|---|
| `manuscript/figure1.png` | PE Medicaid 41.0% vs independent 72.5%, with CIs | literals in `generate_figures.R` | none exists | `simulated` | Renamed `SIMULATED_figure1_obtainment.png`; title and subtitle declare it; blocking test |
| `manuscript/figure2.png` | PE Medicaid 36.8 d vs 23.4 d | `rlnorm()` around typed medians | none exists | `simulated` | Renamed `SIMULATED_figure2_wait_times.png`; same treatment |
| `manuscript_cite.md` Abstract | `[41.0]%`, `[72.5]%`, `OR [0.26]`, `IRR [1.31]`, `[p < 0.001]` | bracketed placeholders | none exists | `unresolved` | Left bracketed. Blocking test requires the brackets to remain while no outcome export exists |
| `figures/fig6_wait_distributions.png`, `fig8_forest_plot.png`, `fig9_interaction.png` | outcome-shaped | `figures/SIMULATED_wait_times.csv` | none exists | `simulated` | Source file already carries the prefix; figures are in `figures/`, not a publication directory |

The bracket convention in the Abstract is the reason the prose did **not** become a fabricated
result while the figures did: the figures rendered the same placeholder values with the
brackets stripped.

### Cohort-flow claims

| Artifact | Reported | Source | Current | Status | Action |
|---|---|---|---|---|---|
| `strobe_diagram.R` Initial scraped roster | 1537 | typed | 1537 | `verified` | none |
| `strobe_diagram.R` Unique NPI verified | 1279 | typed | 1279 | `verified` | none |
| `strobe_diagram.R` OB-GYN generalist only | 1021 | typed | not reproducible | `unresolved` | Left as found; flagged |
| `strobe_diagram.R` De-clustered (1/office) | 544 | typed | not reproducible | `unresolved` | Set `NA`; **script now stops** rather than draw the figure |
| `strobe_diagram.R` Geographically matched | 544 | typed | 918 clinicians / 459 pairs | `stale` | Corrected to 918 |
| `strobe_diagram.R` Fielded cohort | 200 | typed | 400 clinicians / 200 pairs | `stale` | Corrected to 400; the figure had switched units mid-flow |

### Cohort-descriptive claims

| Artifact | Reported | Current | Status | Action |
|---|---|---|---|---|
| `manuscript_cite.md` states | 23 | 26 | `stale` | Corrected |
| `appendix_data_provenance.md` states | 23 | 26 | `stale` | Corrected |
| `manuscript_cite.md` SVI recovered, controls | 197 of 200 | 198 of 200 | `stale` | Corrected |
| `manuscript_cite.md` census tracts | 312 | 319 | `stale` | Corrected |
| `manuscript_cite.md` clustering units | 385 | 387 | `stale` | Corrected |
| `appendix_data_provenance.md` clustering units | 385 | 387 | `stale` | Corrected |
| `manuscript_cite.md` pairs sharing a phone line | two | three | `stale` | Corrected |
| `manuscript_cite.md` address-level linkage pairs | 154 | 195 | `stale` | Corrected |
| `appendix_data_provenance.md` address-level linkage | 154 | 195 | `stale` | Corrected |
| `manuscript_cite.md` phones in 2+ sources | 73.3% | 69.0% | `stale` | Corrected |
| `manuscript_cite.md` phones in ≥1 source | 100% | 100% | `verified` | none |
| `manuscript_cite.md` fielded pairs / clinicians | 200 / 400 | 200 / 400 | `verified` | none |
| `manuscript_cite.md` matched pool | 459 pairs | 459 pairs | `verified` | none |
| `manuscript_cite.md` pairs with SVI complete | 197 | 197 | `verified` | none |

### Correctly hard-coded

| Artifact | Value | Status | Why permitted |
|---|---|---|---|
| `manuscript_cite.md`, `appendix_power.md` | Nie et al. 17.5 d, 21.4 d, *P* = .017, 52.1%, 66.8%, OR 0.55 | `external` | Published, cited `@nie2022urology` |
| `SAP.lock`, `appendix_power.md` | IRR 1.10 / 1.22 / 1.35 | `design` | Pre-specified scenarios; `gate_sourced_constants` requires each to carry a source |
| `appendix_power.md` | 69% power at 200 pairs, 81% at 244 | `design` | Simulation output under the pre-specified design |

## S4. What remains unresolved

Two STROBE stages cannot be reproduced from any committed artifact: `OB-GYN Generalist Only`
(1021) and `De-clustered (1/Office)` (544). They are **not** filled by deduction. Subtracting
one stage from another to recover a missing count produces a number that looks derived, is
unfalsifiable, and belongs to the same class of error as the simulated figures. The figure now
refuses to generate until the de-clustering step supplies the number it actually produced.

The four analysis result artifacts and both dry-run outputs predate the current cohort and are
pinned as known-stale in `test-artifact-vintage.R`. Re-running them is separate work.

## S4b. Appendix S3, added 2026-08-25

`manuscript/appendix_comparator_validation.md` is the first publication-facing document in this
repository whose every reported count is enforced against the artifact it came from. Fifteen
figures are recomputed from `data/comparator/comparator_adjudication.csv` at test time, and the
appendix is required to state the two vintage limits that would otherwise let a 2019 relation
be presented as a 2026 comparator. Six deliberate drifts were injected and all six were caught.

This is the pattern §S5 argues for, applied to prose rather than to figures: the appendix may
format the artifact, and it may not hold a number the artifact cannot produce.

## S5. The architectural gap

Publication-facing artifacts can still be created from typed numbers. The contract in
`test-manuscript-provenance.R` closes the dangerous case — an unlabelled outcome artifact
cannot exist while no outcome export does — but it cannot make typing impossible.

The durable fix is for the manuscript to consume a small set of frozen, hashed, machine-written
result artifacts and to format them only: `cohort_flow.csv`, `table1.csv`,
`primary_outcomes.csv`, `secondary_outcomes.csv`, `figure_data/*.csv`. A manuscript that
formats artifacts cannot invent a result; a manuscript that computes them can. That work is not
done here.
