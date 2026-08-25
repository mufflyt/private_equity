# Survey of prior mystery-caller analyses, and what was taken from them

**Date:** 2026-08-24. **Scope:** every `.Rmd` on this machine and on `/Volumes/MufflySamsung`
that analyses a mystery-caller / simulated-patient study. **Prompted by:** an instruction to
find them and take the best parts.

---

## S1. What was found

Selection rule: at least two mentions of mystery-caller vocabulary and at least three model
calls, so that scripts merely *citing* an audit study do not qualify.

| Lines | Model calls | File |
|---:|---:|---|
| 2,690 | 33 | `~/Documents/mystery_shopper/ortho_sports_med/R/yusra_Reviewed-ortho_sport_med_Analysis_using_Marcos_approach.Rmd` |
| 2,612 | 83 | `~/Documents/mystery_shopper/ortho_sports_med/R/ortho_sport_med_Analysis_using_Marcos_approach.Rmd` |
| 1,884 | 83 | `~/Documents/mystery_shopper/final_ENT_results_of_Marcos_code1.Rmd` |
| 553 | 10 | `private_equity/primary_analysis.Rmd` (this study) |
| 388 | 8 | `MufflySamsung/…/isochrones/docs/mystery_caller_power_vignette.Rmd` |
| 306 | 3 | `~/mysterycall/vignettes/linear-mixed-models.Rmd` |
| 243 | 4 | `~/mysterycall/vignettes/audit-study-tools.Rmd` |

The three large ones are prior studies in the same design family — orthopaedic sports medicine
(two versions, one reviewed) and ENT. `~/mysterycall/vignettes/` holds seven further analysis
vignettes, but those are documentation of the package this study already depends on, not
independent analyses, so they are a source of *functions* rather than of *approach*.

The reviewed ortho file is the one that had been remembered as `usra*`. It is `yusra_*` — a
person's name.

## S2. Technique comparison

Counts are occurrences per file. `OURS` is `primary_analysis.Rmd` before this survey.

| Technique | ortho | ENT | yusra | OURS (before) |
|---|---:|---:|---:|---:|
| `emmeans` (marginal means) | 8 | 24 | 10 | **0** |
| `lmer` / `glmer` | 88 | 69 | 24 | 0 (`glmmTMB` instead) |
| `confint` (intervals) | 2 | 3 | 3 | **0** |
| convergence / singularity | 0 | 3 | 0 | **0** |
| `p.adjust` / multiplicity | 2 | 0 | 0 | **0** |
| `chisq` / `t.test` | 11 | 6 | 11 | 0 |
| ICC | 25 | 0 | 22 | 14 |
| pre-specified sensitivity analyses | 0 | 0 | 0 | **15** |

The comparison runs both ways. The prior studies are richer in *interpretation* — marginal
means, intervals, convergence scepticism. This study is far ahead of them in *pre-specification*
— a frozen plan, named estimands, sensitivity analyses fixed in advance. The gaps taken below
are the interpretation ones. The `chisq`/`t.test` counts were deliberately **not** closed: in
the prior files those are unadjusted bivariate tests run alongside the models, and adding
unplanned tests to a study with a frozen plan is a step backwards, not forwards.

## S3. What was taken

### 1. Adjusted cell means (from the ortho analyses)

The prior studies interpret interaction models through estimated marginal means. This study's
primary wait-time estimand *is* an interaction, and an interaction coefficient says how the
payer gap differs by ownership — not how long anybody waits. The Abstract nonetheless reports
four ownership-by-payer cells on each outcome, and nothing computed them.

Adopted through `mysterycall::mysterycall_marginal_effects()` rather than by adding an
`emmeans` dependency, on the response scale, persisted to `primary_analysis_cell_means.rds`.

### 2. Effect estimates on the reporting scale (from the `confint` usage)

`SAP.lock` names a reporting scale for each estimand; the Abstract reports each with a 95%
interval. The analysis previously did nothing with a fit but `summary()`, which prints the
**link** scale. Filling `OR [0.26], 95% CI [0.17 to 0.40]` from that means reading log-odds off
a screen and exponentiating by hand — an unrecorded transcription and an unrecorded
calculation, for numbers that go in an abstract.

Now extracted in code, estimand taken from the frozen plan rather than typed, Wald interval
formed on the link scale and then transformed, written to `primary_analysis_effects.rds`.

### 3. Convergence scepticism (from the ENT analysis)

The single most valuable thing in the trove is a comment:

> `#Mixed_effects_GLMM),  #GLMM did not fucking converge`

In a prior study of very nearly this design, the mixed model failed to converge, and the entire
detection mechanism was **a person noticing**. `summary()` on a non-converged fit prints a
coefficient table indistinguishable from a converged one — estimates, standard errors,
p-values, no warning at the point of use. Those standard errors are exactly what this study now
exponentiates into the Abstract's intervals. A false convergence does not produce a visibly
broken result; it produces a publishable one that is wrong.

Adopted as `gate_convergence()` in `R/analysis_gates.R`, applied to all three prespecified
fits, checking three things separately: optimiser code, positive-definite Hessian, and no
random-effect SD at the boundary (the singular fit that leaves the matched-pair clustering
absent while the model still "converges"). Blocking, in `test-model-convergence.R`.

## S4. What was deliberately not taken

| Not adopted | Why |
|---|---|
| Unadjusted `chisq.test` / `t.test` alongside the models | Unplanned tests in a study with a frozen plan. Would weaken pre-specification, not strengthen it |
| `lmer` / `glmer` | `SAP.lock` specifies `glmmTMB` with `nbinom2`; switching engines would change a frozen estimand |
| `emmeans` as a dependency | `mysterycall` already exports the marginal-means function; a second implementation of one name is the defect `docs/CANONICAL_SOURCES_AUDIT.md` records |
| Gamma / log-transform model shopping (ENT, ~line 1114) | Choosing a family after seeing which converges is a specification search. The family here is frozen |
| `mysterycall_validate_residuals_dharma` | Worth adding, but it needs a fitted model, and no model has been fitted in this environment yet |

## S5. One finding this survey raised, not fixed

**Multiplicity is not addressed.** The ortho analysis uses `p.adjust` twice. This study declares
**co-primary** outcomes in the Abstract — obtainment *and* wait time — and `SAP.lock` sets
`alpha = 0.05` with no multiplicity provision for testing two primary endpoints.

This is flagged, not corrected. Adding an adjustment now would change the decision rule of a
frozen plan, and the numbers it governs are not yet observed — which is the only circumstance
in which such a change *could* be made legitimately, and equally the reason it must be a
deliberate, recorded amendment rather than something a survey does on its way past. It belongs
in the `SAP.lock` amendments block or in an explicit decision to report both endpoints without
adjustment and say so.

## S6. Environment note

`glmmTMB` is not installed in this project's `renv` library, so no model in
`primary_analysis.Rmd` has ever been fitted here. That is consistent with the rest of the
record — no outcome export exists and `SAP.lock` has never been run. `gate_convergence()` is
therefore tested against fit objects built to glmmTMB's documented structure. That tests the
gate's logic rather than glmmTMB's; if the upstream structure changes, the gate's first check
(`fit carries no convergence code`) is what fires, which is the correct direction to fail.
