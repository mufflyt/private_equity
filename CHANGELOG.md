# Changelog

All notable changes to this project. Dates are absolute. This is a research repo,
so entries are grouped by date rather than semantic version.

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
