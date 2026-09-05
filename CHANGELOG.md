# Changelog

All notable changes to this project. Dates are absolute. This is a research repo,
so entries are grouped by date rather than semantic version.

## 2026-09-05

### Added

- **Row-level data contract** (`config/row_contract.yml`, `R/row_contract.R`). `analysis_manifest.csv`
  governs columns; nothing governed rows. Ten rule types over five artifacts plus two
  cross-artifact key agreements: row counts, uniqueness, value domains, matched-pair size AND
  balance, record-id coverage of 1..800, and that three artifacts describe the same 400
  clinicians. Runs in CI, because the calling artifacts are committed.
- **Manuscript claims registry** (`manuscript/manuscript_claims.csv`). The 2026-08-24 provenance
  audit made machine-readable: 31 claims with artifact, locator, value, provenance status, source
  and verification date. Checked in both directions on every commit.
- **Estimand drift report** (`R/estimand_drift.R`, `docs/ESTIMAND_DRIFT_REPORT.md`,
  `config/derived_estimands.csv`). Compares what `SAP.lock` names against what
  `primary_analysis.Rmd` reports and what the manuscript prints. Reads declarations only, so it
  runs where the analysis cannot.
- **Dependency lockfile** (`config/dependencies.lock`, `R/dependency_lock.R`). 39 records: 31
  CRAN, 2 GitHub with resolved SHAs, 6 PyPI, plus both interpreter versions. Completeness is
  gated; version equality deliberately is not.
- **CI contract** (`config/ci_contract.yml`). What CI must enforce, in a form a non-R-reader can
  audit: triggers, the command it must run, a step-timeout ceiling, and which test files may
  never leave `tests/BLOCKING`.
- **Manuscript rendering in CI** (`.github/workflows/manuscript.yml`). Renders
  `manuscript_cite.md` completely through pandoc and fails on an unresolved citation, which
  pandoc itself renders as `**key?**` and exits 0 on.
- **REDCap API pull** (`redcap_pull.R`). Produces `redcap/redcap_raw_export_800.csv`, the input
  `build_study_database_from_redcap.R` names and nothing produced. Checks the payload, not just
  the HTTP status.
- **Study-staff deidentification guard** (`config/staff_name_hashes.txt`,
  `tests/testthat/test-staff-deidentification.R`). Salted hashes, so the repository can detect a
  real name without containing one.
- Two README figures built from repository state (`make_contract_figures.py`), stdlib-only SVG.
- Appendices: `docs/APPENDIX_REPOSITORY_CONTRACTS.md`, `docs/APPENDIX_DEIDENTIFICATION.md`,
  `docs/APPENDIX_DEPENDENCIES.md`.

### Fixed

- **Real study-staff given names removed from a test fixture.** They sat in
  `test-pipeline-output-regression.R` as the `initials` input and again in the expected `caller`
  output. REDCap labels that field "Name of person completing form", so caller identity is data
  the study collected about a person.
- **Wrong REDCap form name in the record load.** `redcap_import_ready_200.csv` and
  `build_200_redcap_import.R` named `acost_three_dx_urogyn_2_complete`, the form of a different
  study. REDCap silently ignores a completion column for a form it does not have, so all 800
  records would have imported with none marked complete. Found by the row contract on its first
  run; project 40415 held zero records, so nothing had been loaded under the wrong name.
- **Six unregistered Abstract placeholders** declared (`MC026`-`MC031`). The audit named five in
  prose; four were registered.
- **A real REDCap export was committable.** `.gitignore` un-ignores `redcap/` wholesale, so an
  export carrying `initials` could have been committed. Re-ignored by name.
- `config/derived_estimands.csv` was silently excluded by the blanket `*.csv` rule; `config/*.csv`
  is now excepted as a class. Caught by CI.
- `matplotlib` declared in `requirements.txt`. `make_readme_figures.py` has always needed it.
- Two scanner defects in `R/dependency_lock.R`: `sprintf("%s::%s")` read as a package named `s`,
  and the scanner reading its own test fixtures back as dependencies.
- `write_drift_report()` joined an absolute path to root, writing a `tmp/` directory inside the
  repository.

### Changed

- `test-staff-deidentification.R` scans **tracked** files rather than the working tree. Once a
  legitimate gitignored REDCap export exists locally, a working-tree scan would have turned the
  gate red on every machine holding one.

### Notes

- Blocking suite grew from 283 to 545 expectations across 22 files, all runnable without cohort
  data.
- The committed REDCap data dictionary was verified field-by-field against a live API pull of
  project 40415 on 2026-09-04: 18 fields, zero differences. The project holds zero records.

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
