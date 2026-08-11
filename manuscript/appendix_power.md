# Appendix S1. Statistical power for the primary wait-time estimand

*Private equity ownership and appointment access in obstetrics and gynecology: a simulated-patient audit*

Prepared 2026-08-10. Source: `run_new_power_analysis.R` at commit `43fd2bd`. All simulation
code, seeds and results files referenced here are in the study repository.

---

## S1.1 Purpose

This appendix documents the power calculation supporting the fielded sample of 200 matched
clinician pairs (400 clinicians, 800 scheduled calls). It states the estimand, the generative
model, the analysis model, the source of the assumed effect size, the simulation results, and —
at greater length than is usual — the conditions under which the reported power does not hold.
Three of those conditions are consequential enough to change the design conclusion, and they are
set out in §S1.8 rather than buried.

An earlier version of this calculation is superseded. It is described in §S1.7 so that readers
comparing drafts can see what changed and why.

## S1.2 The estimand

The primary wait-time hypothesis is that private-equity ownership widens the gap in
new-patient wait times between Medicaid and commercially insured callers. On the log scale of a
negative-binomial model this is the ownership-by-insurance interaction:

$$\log E[\text{wait}] = \beta_0 + \beta_{\text{PE}}\,\text{PE} + \beta_{\text{Mcd}}\,\text{Medicaid} + \beta_{\text{int}}\,(\text{PE}\times\text{Medicaid}) + u_j$$

with $u_j$ a clinician random intercept. The quantity of interest is $\exp(\beta_{\text{int}})$,
the ratio of the Medicaid-to-commercial wait ratio at PE-owned practices to the same ratio at
independent practices. Power is reported for a two-sided Wald test of $\beta_{\text{int}} = 0$
at $\alpha = 0.05$ — **one degree of freedom, the interaction term alone**.

This matters because the interaction is a *within-clinician* contrast. Ownership varies between
clinicians; insurance varies within, because each clinician receives one Medicaid call and one
commercial call. A clinician random intercept therefore absorbs between-clinician variance and
*sharpens* this contrast. Accounting for clustering makes this particular test more powerful,
not less — the opposite of the usual design-effect intuition, and the reason an earlier
independence-assuming fit understated rather than overstated power here (§S1.7).

## S1.3 Generative model

Each simulated replicate builds the fielded design exactly: $n$ matched pairs, $2n$ clinicians
(half PE, half independent), two calls per clinician.

**Cell means (business days).** Commercial waits are set equal across ownership, so the entire
effect is loaded onto the Medicaid cell:

| | Commercial | Medicaid |
|---|---:|---:|
| Independent | 15.0 | 30.0 |
| PE | 15.0 | $30.0 \times \text{IRR}$ |

Setting $\beta_{\text{PE}} = 0$ is deliberate. The test is on the interaction, and leaving the
ownership main effect at zero avoids importing an assumption the study has no basis for.

**Dispersion.** Counts are drawn negative-binomial with $\mathrm{Var} = \mu + \mu^2/\theta$,
with $\theta$ solved at a reference mean of 23 days (the average of the four cells):
$\theta = 23^2/(\mathrm{SD}^2 - 23)$. This gives $\theta = 6.87$ at SD 10 days and
$\theta = 1.40$ at SD 20 days. Both are carried through the whole grid because the wait-time
distribution is the least-known input in the design.

**Between-clinician variance.** $u_j \sim N(0, 0.2^2)$, on the **log** scale, not in days — a
roughly 20% coefficient of variation in each clinician's baseline wait.

## S1.4 Analysis model

Each replicate is fitted with

```r
glmmTMB(wait_time ~ pe * insurance + (1 | physician), family = nbinom2)
```

matching the statistical analysis plan. A replicate counts toward the denominator only if the
fit converges and returns a standard error for the interaction; convergence was 200/200 in every
cell reported below, so no cell is affected by selective retention.

## S1.5 Choice of effect size

There is no published estimate of a private-equity-by-insurance interaction in wait time for
obstetrics and gynecology, so the assumed magnitude is anchored to the closest available
mystery-caller study.

**Anchor.** Nie et al., *Urology* 2022 [@nie2022urology], 815 simulated-patient calls to 445
urology offices, comparing private-equity-acquired with non-acquired practices under commercial
and Medicaid insurance. Mean wait was 17.5 days at PE-affiliated practices versus 21.4 days at
non-PE practices ($P = .017$) — a ratio of $17.5/21.4 = 0.818$, or **1.22** expressed in the
opposite direction.

**How 1.22 is and is not being used.** Nie et al. reported the ownership and insurance main
effects separately and did **not** estimate their interaction for wait time; their
Medicaid-versus-commercial wait ratio was 1.047 ($P = .59$). The figure 1.22 is therefore used
here as *the magnitude of the published PE-associated wait-time difference in the closest
mystery-caller study*, and must not be described as a previously observed
private-equity-by-insurance interaction. It is a plausible order of magnitude for an
appointment-access effect attributable to ownership, not an estimate of the parameter this study
will test.

**Why an interaction of that order is plausible.** Nie et al.'s *access* outcome does show the
effect modification hypothesised here: Medicaid appointment availability was 52.1% at PE-acquired
practices versus 66.8% at non-acquired practices (adjusted OR 0.55, 95% CI 0.37 to 0.83). An
ownership effect that large on whether a Medicaid patient is seen at all makes an ownership
effect of similar order on how long they wait credible.

**Direction.** Nie et al. found *shorter* average waits at PE practices. The present design
assumes PE practices differentially lengthen the Medicaid wait. Only the magnitude is borrowed;
the sign follows from this study's hypothesis, and the test is two-sided.

**Scenarios.** Conservative 1.10; primary 1.22; larger plausible 1.35. At IRR 1.22 the implied
PE Medicaid wait is 36.6 days against 30.0 at independent practices, a 6.6-day differential
penalty.

## S1.6 Results

200 simulations per cell, seed 42, `glmmTMB` 1.1.14 / TMB 1.9.21 under R 4.4.2. Monte Carlo
standard error at an estimated power of 0.87 is 0.024 (95% CI 0.82 to 0.92); at 0.29 it is 0.032.
Differences smaller than about 0.05 between adjacent cells should not be interpreted.

**Table S1.1. Power for the ownership-by-insurance interaction, wait-time SD 10 days.**

| Matched pairs | Calls | IRR 1.10 (conservative) | **IRR 1.22 (primary)** | IRR 1.35 (larger) |
|---:|---:|---:|---:|---:|
| 100 | 400 | 0.205 | 0.575 | — |
| 150 | 600 | 0.250 | **0.840** | — |
| **200 (fielded)** | **800** | 0.290 | **0.870** | — |
| 250 | 1000 | 0.420 | 0.945 | — |
| 300 | 1200 | 0.515 | 0.950 | — |
| 400 | 1600 | 0.560 | 0.990 | — |

The IRR 1.35 column is monotonically above the 1.22 column by construction; it was still
computing when this appendix was prepared and the cells are left blank rather than asserted.

**Table S1.2. Power under high dispersion, wait-time SD 20 days, IRR 1.22.**

| Matched pairs | 100 | 150 | **200** | 250 | 300 |
|---|---:|---:|---:|---:|---:|
| Power | 0.180 | 0.260 | **0.410** | 0.455 | 0.530 |

**Reading.** Under the primary anchored effect and a wait-time SD of 10 days, the fielded design
of 200 pairs gives 0.870 power for the interaction, and 150 pairs would already clear 0.80.
Under the conservative 1.10 the design is underpowered at every feasible size — 0.29 at 200 pairs
and only 0.56 at 400 — so no achievable sample rescues that scenario. Under high dispersion the
primary scenario reaches only 0.41 at the fielded size.

**Dispersion, not sample size, is the binding constraint.** Doubling the wait-time SD costs more
power than halving the sample. This is the input the study has least information about, and the
first thing that should be re-examined once real wait times accumulate.

**Table S1.3. Minimum detectable interaction at the fielded design** (200 pairs, SD 10 days).

> **PENDING SIMULATION.** Grid of IRR 1.14 / 1.17 / 1.20 / 1.26 at 200 pairs, SD 10, running in
> `scratch/mde_200_pairs.R`. Interpolating Table S1.1 between IRR 1.10 (0.290) and IRR 1.22
> (0.870) places the 80%-power threshold near IRR 1.19, but that is an interpolation across a
> steep region and the simulated values supersede it. Do not circulate this appendix with this
> box still present.

## S1.7 What changed from the earlier calculation

Three figures for wait-time power appear in earlier drafts. They differ for identifiable reasons,
none of which is a difference in the data.

| Reported | Model | Hypothesis tested | Assumed IRR | Status |
|---|---|---|---:|---|
| 0.83 | `glm.nb`, independence | 2-df joint test | 1.167 | superseded |
| 0.82 | `glmmTMB` mixed | 2-df joint test | 1.167 | correct for that question |
| 0.66 | `glmmTMB` mixed | interaction alone | 1.167 | correct model, unsupported effect size |
| ~0.77 | dry-run | interaction alone | 1.31 | effect size from the dummy tables |
| **0.870** | `glmmTMB` mixed | interaction alone | **1.22** | **current** |

Two distinct errors were corrected. First, the original simulation drew a per-clinician random
intercept and then fitted `glm.nb`, which assumes independent observations — it analysed data
whose correlation structure it had itself created. Second, and larger, the reported number came
from comparing `~ pe * insurance` against `~ insurance`, which drops the ownership main effect
**and** the interaction: a two-degree-of-freedom joint test of "any ownership effect anywhere".
That is an easier question than the one the analysis plan asks, and rejecting it would not
establish the hypothesis. Both are fixed; power is now reported for the single interaction
parameter.

The remaining movement, from 0.66 to 0.870, is entirely the effect size. The 1.167 used
previously was invented rather than derived. Note that the manuscript's own dummy tables imply
1.31, above the primary anchor used here, so the anchored calculation is the more conservative
of the two.

**Not yet corrected.** `run_maineffect_power.R`, `run_interaction_75_power.R` and
`run_obtainment_power.R` still fit marginal models. For the main-effect script this matters in
the usual direction: the ownership term is a *between*-clinician contrast, so ignoring clustering
there does inflate reported power. Those figures should not be cited until the scripts are
rerun.

## S1.8 Conditions under which the reported power does not hold

Table S1.1 describes an idealised design: 800 calls, every call yielding a wait time, 400
mutually independent clinicians, and no covariate missingness. The fielded study departs from
that in four ways. The first two are large enough to change the conclusion.

### (a) Wait time is observed only when an appointment is offered

The simulation gives all 800 calls a wait time. The study cannot: a wait time exists only if the
clinic offered a date. Under the anticipated obtainment proportions in Table 2 of the main
manuscript, the expected analytic sample is

| Cell | Calls | Anticipated obtainment | Expected wait times |
|---|---:|---:|---:|
| Independent, commercial | 200 | 98.5% | 197 |
| Independent, Medicaid | 200 | 72.5% | 145 |
| PE, commercial | 200 | 99.0% | 198 |
| **PE, Medicaid** | 200 | **41.0%** | **82** |
| **Total** | **800** | | **622** |

The interaction's precision is governed by the smallest cell, and the smallest cell is the one
that identifies it. Roughly 82 observed PE-Medicaid waits, not 200, will carry the estimate.

> **PENDING SIMULATION.** `scratch/power_with_obtainment_censoring.R` reruns the primary
> scenario (IRR 1.22, SD 10) with each call retained at its cell's anticipated obtainment
> probability, at 200, 250, 300, 400 and 500 pairs. This gives the power the study will actually
> have for the wait-time interaction, as distinct from the 0.870 of Table S1.1. It is expected to
> be materially lower. Do not circulate this appendix with this box still present.

This is a selection problem as well as a precision problem: the PE-Medicaid waits that *are*
observed come from the minority of PE practices willing to schedule a Medicaid patient, which is
plausibly a favourable subset. The interaction is therefore conditioned on a post-treatment
variable, and the main manuscript already flags the conditioning. The power consequence had not
previously been quantified.

### (b) The social-vulnerability covariate is missing only in the control arm

The analysis plan specifies the CDC Social Vulnerability Index percentile as a fixed effect. In
the fielded sheet:

| Arm | Has CDC_SVI | Missing |
|---|---:|---:|
| PE | 200 | 0 |
| Independent | 106 | 94 |

Missingness is **perfectly confounded with exposure**: it is zero in the PE arm and 47% in the
control arm, because the controls added in the most recent redraw were never geocoded to a census
tract. A complete-case fit of the model as specified would retain 106 complete pairs of 200 —
approximately the 100-pair row of Table S1.1, or power near 0.60 — and would do so by discarding
control clinicians on a basis related to how they entered the sample.

This is fixable and should be fixed rather than modelled around. The 94 values are absent because
the tract-level geocoding step was not rerun after the most recent redraw — none of the 94 appear
in `pe_obgyn_study_database_with_churn.csv`, so no join recovers them — but all 94 carry a
complete street address and ZIP in `pe_obgyn_study_database.csv` (NPPES, CMS DAC and scraped
address fields are all populated, as is a latitude). They are therefore geocodable to a census
tract and joinable to the CDC SVI release with the same procedure already used for the PE arm.
Until that is done, the SAP-specified model and this power calculation describe different
studies.

If the geocoding cannot be completed before fielding, the defensible fallbacks are to drop SVI
from the primary model and report it only in a sensitivity analysis, or to replace it with a
county-level or ZIP-level deprivation measure available for all 400 clinicians. What should not
happen is a complete-case fit of the model as written, which would silently delete 47% of the
control arm on a basis correlated with exposure.

### (c) The fielded sample does not contain 400 independent clinics

Resolving each fielded clinician to a dialable office key (phone where available, normalised
address otherwise), the 400 fielded clinicians occupy **385 distinct numbers**. Twelve numbers
are shared by 27 clinicians, several across different cities — central scheduling lines for
multi-site groups rather than genuine single offices. One number covers four fielded clinicians
across Edina, Minneapolis and Saint Paul; it will be dialed eight times.

Two fielded pairs place the PE clinician and their matched control on the **same number**
(pair_321 and pair_437). For those pairs the caller reaches the same scheduler for both arms, and
the within-pair ownership contrast is not a contrast at all. Sixteen such pairs exist in the
459-pair pool; two were drawn into the fielded 200.

The analysis treats the clinician as the clustering unit. Where a shared central line means a
shared scheduler, the clinician intercept is misspecified and the true number of independent
units is below 400. This does not have a clean power multiplier attached to it, but it moves in
the anticonservative direction and both fielded same-number pairs should be replaced.

### (d) The pool cannot supply a much larger design

If more pairs were wanted, the pool cannot supply them at the rate the pair count suggests. The
459 matched pairs occupy only 614 distinct offices. Requiring that no office be dialed for two
different pairs — the two-calls-per-clinic guarantee — the largest fieldable set found by
randomised greedy search over 2,000 restarts is **244 pairs**, against a counting upper bound of
307. So the practical ceiling is roughly 244 pairs, not 459.

At IRR 1.22 and SD 10, 244 pairs would give about 0.94 power — but under (a) and (b) above, the
extra 44 pairs do not close the gap that censoring and covariate missingness open. **Expanding
the sample is the wrong lever.** Restoring SVI for the 94 control clinicians is worth more than
44 additional pairs and costs a geocoding rerun.

*(A previously circulated figure of 224 office-disjoint pairs was computed with a weaker greedy
ordering; 244 is the best packing found and supersedes it.)*

### (e) The simulation omits the pair-level random intercept

The analysis plan specifies random intercepts for **both** the matched pair and the clinician;
the simulation generates and fits only the clinician intercept. The effect on the interaction is
expected to be small, because the interaction is identified within clinician, and the main
manuscript already reports that the matched-pair variance was not reliably distinguishable from
zero in simulation. It is noted for completeness rather than as a live threat.

## S1.9 Conclusion

Under the literature-anchored effect of IRR 1.22 and a wait-time SD of 10 days, the fielded
design of 200 matched pairs is adequately powered for the primary wait-time interaction (0.870).
That statement is conditional on three things that are not currently true of the fielded
dataset:

1. **Obtainment censoring** reduces the analytic sample from 800 calls to roughly 622, with the
   identifying PE-Medicaid cell falling to about 82. Quantified in §S1.8(a).
2. **SVI is missing for 94 of 200 control clinicians and none of the PE clinicians.** Fitting the
   model as specified on complete cases would leave 106 pairs and power near 0.60. All 94 carry
   complete addresses and are geocodable; this is a data preparation gap, not a design
   limitation, and should be closed before fielding.
3. **Dispersion is the binding constraint.** At SD 20 the same design gives 0.41. This should be
   re-examined against real wait times as soon as they accumulate.

Under the conservative IRR 1.10 no feasible sample size reaches 0.80, and the manuscript should
say so rather than report only the favourable scenario.

## S1.10 Reproducibility

| Item | Value |
|---|---|
| Primary script | `run_new_power_analysis.R` |
| Results | `power_analysis_new_results.csv` |
| Seed | `set.seed(42)`, set once before the grid |
| Replicates | 200 per cell |
| Software | R 4.4.2; glmmTMB 1.1.14; TMB 1.9.21; MASS 7.3.65 |
| Supporting scripts | `scratch/mde_200_pairs.R`, `scratch/power_with_obtainment_censoring.R`, `scratch/office_disjoint_ceiling.R` |
| Tests | `tests/testthat/test-power-and-calibration.R` |

## References
