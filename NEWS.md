# News

Highlights of recent work on the PE OB/GYN mystery-caller study. See `CHANGELOG.md`
for the detailed log.

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
