# Changelog

All notable changes to this project. Dates are absolute. This is a research repo,
so entries are grouped by date rather than semantic version.

## 2026-08-29

### Added

- **Comparator validation against Medicare enrollment records** (`pecos/`,
  `data/comparator/`, `docs/COMPARATOR_ADJUDICATION.md`). Reconstructs each clinician's
  organisational affiliation from PECOS reassignment and the CMS Doctors and Clinicians
  National Downloadable File, using PAC ID as the entity key and resolving the organisation at
  the *sampled office* rather than aggregating across affiliations. Adjudication table covers
  1,845 clinicians across the fielded frame, the 459-pair eligible universe, and the full PE
  roster.
- **Supplementary Appendix S3** (`manuscript/appendix_comparator_validation.md`) — the
  comparator validation, written for publication. First document here whose every reported
  count is recomputed from its artifact at test time.
- **Supplementary Appendix S4** (`manuscript/appendix_analytic_provenance.md`) — analytic
  output provenance and model diagnostics: adjusted cell means, effect estimates on the
  prespecified reporting scale, the commercial-arm derivation, and convergence gating.
- **`gate_convergence()`** (`R/analysis_gates.R`) — blocks the analysis unless every fitted
  model converged, has a positive-definite Hessian, and carries no boundary random-effect
  variance. Applied to all three prespecified fits before any quantity is read from them.
- Adjusted cell means and prespecified effect estimates in `primary_analysis.Rmd`, computed on
  the reporting scale `SAP.lock` names and persisted rather than transcribed.
- **Independent verification implementations** (`pecos/verify/`) — the PECOS chain resolved a
  second time by external sort-merge relational joins, and the DAC file parsed a third time in
  Perl, with an exact comparison tool that exits non-zero on any disagreement.
- **`docs/PRIOR_ANALYSIS_SURVEY.md`** — survey of every mystery-caller analysis on this machine
  and the external drive, what was taken from each, and what was deliberately not taken.
- README figures 4 and 5: comparator status, and sampled-office against owning-organisation
  practice size. `test-readme-figures.R` requires every referenced figure to exist, to be no
  older than the artifact it plots, and to match the README's headline counts.

### Fixed

- **Blank-organisation selection defect.** A DAC row with an empty `org_pac_id` records *no*
  organisational affiliation; the first builder selected such rows when they matched the
  sampled office, discarding the organisation-bearing rows at the same address for 74
  clinicians (29 fielded controls), one of whose only organisation was a PE platform. The
  contamination count was understated as a result.
- **Comparator artifacts were never committed.** `git add -A data/comparator` added nothing:
  `.gitignore` blankets `*.csv` and `*.json` and `git add` skips ignored paths silently. The
  scripts, the appendix, and a blocking test reading the data all shipped without the data.
- **Stale `mysterycall` install.** `assign_blinded_slots()` delegates to
  `mysterycall_assign_blinded_slots()`, added upstream in 42d66d92, but the installed build was
  from af004a1 and lacked it — 5 failures and 8 errors on `origin/main`, independent of any
  local change. Resolved by updating the installed package, not by forking the function back.
- Two provenance contracts that were satisfied by an unrelated line rather than by the thing
  they guard, and an unanchored absence assertion, all found by mutation rather than reading.

### Changed

- `manuscript/PROVENANCE.csv` now admits non-figure publication outputs and a `verified`
  status. The invariant that every figure must be registered is unchanged and asserted first;
  only the reverse direction was relaxed, and a registered output missing from disk now fails.
- `pecos/classify.py` removed in favour of `pecos/build_comparator_adjudication.py`: it carried
  the blank-organisation defect, and two live implementations of one classification is the race
  `docs/CANONICAL_SOURCES_AUDIT.md` exists to prevent.

### Known issues

- **59 of 200 fielded controls (29.5%)** bill through a CMS organisation that also contains a
  clinician from this study's own PE roster. Affirmative evidence of independent private
  practice exists for **23 of 200**. Redrawing from the eligible universe is worse (47.9%).
  Undecided; the cohort, pairs, REDCap, caller materials, `SAP.lock` and manuscript are
  unchanged.
- **18 inputs read by blocking tests are untracked**, so the suite can pass on the machine that
  built them and fail on a fresh clone — confirmed by running `origin/main` in a clean
  worktree. Enumerated by the advisory `test-blocking-inputs-tracked.R`, which prevents the
  list from growing. Several are provider rosters whose versioning is a data-governance
  decision.
- The Abstract declares co-primary outcomes; `SAP.lock` sets a single alpha with no
  multiplicity provision. Reported, not corrected.

## 2026-07-05

### Added

- Matched control pipeline: independent private-practice controls drawn from the CMS
  Doctors and Clinicians registry and 1-to-1 propensity-score matched to PE clinicians
  within a 10-mile, same-state radius (`build_matched_control_group_psm.R`,
  `export_control_candidates.py`).
- Fielded-sample selection: geographically balanced 200-pair draw via round-robin across
  states, capping Florida's over-representation (`build_200_redcap_import.R`,
  `subsample_300_pairs.R`).
- REDCap load files: `redcap_import_ready_200.csv` (records) and
  `redcap_physician_name_choices.txt` (800 physician-by-insurance dropdown choices;
  ids 1-400 Medicaid, 401-800 Blue Cross/Blue Shield, contiguous, no gaps).
- Google Sheets caller-list exporter, byte-identical R port of the earlier Python
  (`build_balanced_google_sheet.R`); contributed upstream to `mysterycall`.
- Study figures with `mysterycall` Green Journal styling: sampling/matching flow,
  geographic tile-map, negative-binomial power curves, a `simr` power curve, and
  illustrative results templates (`make_figures*.R`, `make_polish.R`, `fig3_simr.R`).
- Manuscript in `manuscript/`: reproducible pandoc source (`manuscript_cite.md`),
  verified bibliography (`references.bib`), AMA style (`ama.csl`), and a 12-point
  Times New Roman reference doc (`pandoc-reference.docx`).
- Geographic Sensitivity Analysis: added `run_geographic_sensitivity_analysis.R` script which calculates matching distances for the 200 fielded pairs and runs regression sensitivity at 10-mile, 5-mile, and 3-mile calipers.
- Longitudinal Churn Analysis: added `calculate_cohort_churn.R` script which queries the 83.7 GB NPPES DuckDB database on the external hard drive to compute historical clinician churn (entries, exits, and annual retention rates) for the 1,130 unique clinic locations in the study cohort.
- Additional Covariates: incorporated the CDC Social Vulnerability Index (SVI), state-level Medicaid-to-Medicare fee index ratios (from Kaiser Family Foundation), and local corporate practice density (within a 15-mile radius) into the statistical models, study database, and final calling sheets.
- Updated Documents: regenerated the Green Journal Word manuscript (`Manuscript_PE_OBGYN_GreenJournal_2026-07-05_19-07.docx`) and COMIRB protocol doc (`COMIRB_Protocol_PE_OBGYN_2026-07-05.docx`) to adjust the methods, tables, and regression results for the new covariates.

### Changed

- `physician_name` REDCap choices reformatted to a readable calling string
  (`Dr. Name, City, State, Phone: ..., NPI: ...`) with `id: N` shown at both ends,
  contiguous numeric codes, and one option per physician-by-insurance combination.
- Manuscript: expanded to 12 primary-source-verified references with an auto-numbered
  AMA list; set to 12-point Times New Roman throughout; prose written without en or
  em dashes (dashes retained only in references and citation ranges).

### Fixed

- Reconciled cohort counts across the manuscript (26 states, 511-pair pool, 200 fielded).
- Replaced a misattributed ophthalmology citation with the verified Braun et al.,
  *Ophthalmology* 2024 Medicare-spending study (found by code review).
- Made the manuscript reproducible from the repo by committing the pandoc source and CSL
  (previously only in an ephemeral scratchpad).
