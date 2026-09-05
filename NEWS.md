# News

Highlights of recent work on the PE OB/GYN mystery-caller study. See `CHANGELOG.md`
for the detailed log.

## 2026-09-05

- **The repository's contracts now cover rows, software, CI and every published number.**
  `SAP.lock` froze the model and `analysis_manifest.csv` froze every column; four more contracts
  close the gaps around them. Each is a file a person can audit, re-read by code on every commit.
- **Four of them found something real on their first run.** The record load named a REDCap form
  belonging to a different study, so all 800 records would have imported unmarked. The Abstract
  had six placeholder values nobody had registered. A real outcome export, which carries the
  caller's name, was committable. And writing the CI contract exposed that a YAML quirk had made
  every trigger assertion pass vacuously.
- **Real study-staff names removed from a test fixture**, with a hashed regression guard so they
  cannot return. The names remain in git history; removing them is an owner decision, documented
  rather than taken.
- **The REDCap outcome pipeline is now end to end.** `redcap_pull.R` fetches the export that
  `build_study_database_from_redcap.R` had always named and nothing produced.
- **The manuscript is rendered in CI**, and an unresolved citation now fails the build rather
  than rendering as `**key?**` behind a green check.
- Blocking gates grew from 283 to 545 expectations, all runnable without cohort data.

## 2026-07-05

- **Fielded sample locked.** A geographically balanced 200 matched pairs (400 clinicians,
  26 states, 800 planned calls) drawn from the 511-pair matched pool, with Florida capped
  so no single market dominates.
- **REDCap ready.** Physician dropdown choices and record load files generated, including
  the 800 physician-by-insurance options (Medicaid 1-400, Blue Cross/Blue Shield 401-800).
- **Figures.** Sampling flow, geographic map, and power curves (negative-binomial GLMM and
  `simr`), plus illustrative results templates, all in the Green Journal style.
- **Manuscript drafted.** Reproducible pandoc build: 12 verified references (auto-numbered
  AMA), 12-point Times New Roman, and dash-free prose.
- **Upstream contribution.** The Google Sheets caller-list exporter was submitted to the
  `mysterycall` R package as a documented, tested function.
- **Geographic matching sensitivity analysis.** Restricting regression and obtainment models to tighter 3-mile and 5-mile micro-market boundaries verifies that private equity wait-time disparities remain robust.
- **Payer-mix and concentration controls.** Incorporated the state-level Kaiser Family Foundation Medicaid-to-Medicare fee index and local corporate clinic density (PE offices within 15 miles) as covariates in statistical models.
- **Longitudinal clinician churn.** Added DuckDB historical NPI tracking showing that corporate PE clinics exhibit an average annual clinician churn rate of 15.5% compared to 17.6% for independent controls under normalized address matching.
