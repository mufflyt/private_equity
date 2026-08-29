# News

Highlights of recent work on the PE OB/GYN mystery-caller study. See `CHANGELOG.md`
for the detailed log.

## 2026-08-29

- **The control arm contains private-equity practices.** Validated against Medicare enrollment
  records: 59 of 200 fielded controls (29.5%) bill through a CMS organisation that also
  contains a clinician from this study's own PE roster — Axia, Women's Care Enterprises,
  Unified Women's Healthcare, Femwell, Advantia, Nova, CCRM. No control NPI is in the roster
  itself (0 of 200, against 200 of 200 for the PE arm), so exposure assignment is internally
  consistent per clinician; the roster is simply not a census of platform practices. The bias
  runs toward the null, and **redrawing makes it worse** (47.9% in the eligible universe).
  Nothing has been changed pending a decision.
- **Affirmative evidence of independent private practice exists for 23 of 200 controls.** The
  protocol restricts controls to independent private practices. 91 are affirmatively not
  independent; 86 are unresolved and are left unresolved, because enrollment records show where
  benefits are billed, not who owns a practice.
- **Two appendices.** S3 documents the comparator validation; S4 documents analytic output
  provenance and model diagnostics. S3 is the first publication-facing document here whose
  every count is recomputed from its artifact at test time.
- **Models are now checked for convergence.** `summary()` on a non-converged fit prints a table
  indistinguishable from a converged one, and those standard errors are what become the
  Abstract's confidence intervals. In a prior study of this design the mixed model failed to
  converge and the only detection mechanism was a person noticing.
- **Every number the Abstract reports is now computed.** Adjusted cell means for the four
  ownership-by-payer cells, and each prespecified estimand extracted on the scale `SAP.lock`
  names, persisted rather than transcribed.
- **Two reproducibility defects found and fixed:** the comparator artifacts were silently never
  committed, and the installed `mysterycall` was too old to provide a function `main` delegates
  to — which had left `origin/main` red on its own.

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
