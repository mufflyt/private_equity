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

| Assumed IRR | 1.10 | 1.14 | 1.17 | **1.20** | 1.22 | 1.26 |
|---|---:|---:|---:|---:|---:|---:|
| Power | 0.290 | 0.520 | 0.725 | **0.840** | 0.870 | 0.960 |

The design as fielded detects an interaction of about **IRR 1.19** with 80% power, equivalent to
a Medicaid wait of 35.7 days at PE practices against 30.0 at independent ones — a differential
penalty of roughly **5.7 business days**. Anything smaller than that is likely to be missed.
This is the number to quote when a reviewer asks what the study can rule out, and it assumes
every call yields a wait time; §S1.8(a) shows what happens when that assumption is dropped.

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
that in five ways. The first is large enough to change the conclusion; the second was large
enough and has been repaired.

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

**Table S1.4. Power for the interaction when calls are retained at their cell's obtainment
probability** (IRR 1.22, SD 10 days, 200 replicates per row).

| Matched pairs | Calls placed | Wait times observed | PE-Medicaid cell | Power | Table S1.1 power |
|---:|---:|---:|---:|---:|---:|
| **200 (fielded)** | 800 | 622 | 82 | **0.690** | 0.870 |
| 250 | 1000 | 777 | 102 | 0.840 | 0.945 |
| 300 | 1200 | 932 | 123 | 0.910 | 0.950 |
| 400 | 1600 | 1244 | 163 | 0.960 | 0.990 |
| 500 | 2000 | 1558 | 206 | 0.980 | — |

**Censoring costs 0.18 of power at the fielded size and takes the design below the conventional
threshold: 0.690, not 0.870.** Power at 200 pairs with censoring is roughly what Table S1.1
reports at 150 pairs without it. Recovering 80% requires about 250 pairs.

This materially changes the sample-size conclusion and is the strongest argument in this
appendix for moving toward the attainable ceiling — see §S1.8(d), which puts that ceiling at 244
pairs, just short of the 250 needed. At 244 pairs the interpolated censored power is
approximately 0.83.

This is a selection problem as well as a precision problem: the PE-Medicaid waits that *are*
observed come from the minority of PE practices willing to schedule a Medicaid patient, which is
plausibly a favourable subset. The interaction is therefore conditioned on a post-treatment
variable, and the main manuscript already flags the conditioning. The power consequence had not
previously been quantified.

### (b) The social-vulnerability covariate was simulated, and has been reconstructed

**RESOLVED. This section records a defect that has been repaired; the repair is described so
that the covariate's provenance is on the record.**

The analysis plan specifies the CDC Social Vulnerability Index percentile as a fixed effect in
the primary wait-time model. The `CDC_SVI` column shipped in the fielded sheet was not a
measurement. It was a Normal(0.434, 0.193) draw truncated to [0.01, 0.99]:

| Check | Simulated `CDC_SVI` | What a real percentile rank gives |
|---|---:|---|
| Kolmogorov-Smirnov vs Normal | p = 0.985 | should reject |
| Kolmogorov-Smirnov vs Uniform(0,1) | p < 0.001 | should not reject |
| Rows at exactly 0.010 | 6 | none — a clamp floor |
| Rows at exactly 0.990 | 1 | none — a clamp ceiling |

An SVI overall summary ranking is a percentile, so it is approximately uniform on [0,1] by
construction; normality is disqualifying on its own. The generator is `apply_demographic_
covariates.R`, whose own header states that it "implements standard fallback simulations to
ensure full dataset completeness". The sibling `Tract_Pct_Female_*`, `County_OBGYN_Count`,
`County_Medicare_Enrollment` and `County_Medicaid_Enrollment` columns carry the same
signature — Normal shape with a visible pile at a `pmax`/`pmin` bound — and **should be treated
as simulated until independently sourced.** `Medicaid_Fee_Index`, `PE_Concentration_15mi` and
`HQ_Distance_Miles` do not show it and appear to be genuinely derived.

The 94 controls with no SVI at all were therefore the visible edge of the problem, not the
problem: the 306 rows that *had* a value had a simulated one.

**Reconstruction.** `build_svi_covariate.R` rebuilds the covariate for all 400 fielded
clinicians from public sources only: NPPES practice address to 2020 census tract via the Census
Bureau batch geocoder, then tract to `RPL_THEMES` via the CDC/ATSDR SVI 2022 state files.
Addresses the geocoder cannot place — 31 of 400, whose TIGER address ranges simply do not cover
them — fall back to a stored coordinate where one exists, then to an area-weighted mean over the
tracts intersecting the ZCTA. Each row records which method produced it in `SVI_geocode_via`.

| | Simulated `CDC_SVI` | Reconstructed `CDC_SVI_real` |
|---|---:|---:|
| PE with a value | 200 / 200 | 197 / 200 |
| Control with a value | 106 / 200 | 197 / 200 |
| Fisher test, missingness by arm | p = 5.1 × 10⁻³⁵ | **p = 1.00** |
| Complete pairs | 106 / 200 | **197 / 200** |
| KS vs Uniform(0,1) | p < 0.001 | p = 0.073 |

Missingness is now independent of exposure, and a complete-case fit retains 197 pairs rather
than 106. The old column is deliberately left in place, untouched, so that no downstream script
changes meaning without a visible edit.

**One residual asymmetry, measured rather than removed.** Missingness is balanced, but
*precision* is not: 31 control clinicians and 1 PE clinician carry the coarser ZCTA-level value,
while 19 PE clinicians and no controls carry a value from a stored coordinate. Address-level
tract values are 166 control and 176 PE. `SVI_geocode_via` makes this analysable — the natural
sensitivity analysis restricts to address-level rows, and the natural robustness check adds a
precision indicator to the model.

### (c) The fielded sample does not contain 400 independent schedulers

**Correction to an earlier statement.** A previous version of this appendix said the 400
clinicians occupy 385 "dialable" numbers. That was wrong about what will be dialed. The sheet's
`Phone` column, which is what a caller enters, is the NPPES registered number, and **all 400 are
distinct** — no clinician is dialed on a number shared with another.

Independence is a different question from dialing. Under the practice number carried in the
study database (scraped practice line, falling back to NPPES then CMS DAC), the same 400
clinicians collapse onto **385 lines**:

| Clinicians on the line | 1 | 2 | 3 | 4 |
|---|---:|---:|---:|---:|
| Clinicians | 373 | 20 | 3 | 4 |

Twelve lines serve 27 clinicians, several across different cities — central scheduling numbers
for multi-site groups rather than single offices. One line covers four fielded clinicians across
Edina, Minneapolis and Saint Paul and will receive eight calls.

**Two fielded pairs place both arms on the same practice line.** In `pair_321` (Edina and
Minneapolis) and `pair_437` (Hartford and Danbury) the PE clinician and their matched control
route through one number, so a caller reaches the same scheduler for both arms and the
within-pair ownership contrast is not a contrast. Sixteen such pairs exist in the 459-pair pool;
two were drawn into the fielded 200. No fielded pair shares a normalised street address, so this
is a shared-switchboard problem rather than a same-office problem.

`build_phone_cluster_vars.R` writes this structure onto the sheet as `phone_id`, `phone_dialed`,
`phone_practice`, `office_addr_key`, `clinicians_per_phone`, `calls_per_phone`,
`pairs_per_phone`, `same_phone_within_pair` and `same_address_within_pair`, so that the
prespecified sensitivity analyses — excluding same-line pairs, and treating the practice line
rather than the clinician as a clustering unit — can be run as written rather than reconstructed
after the fact. Treating the line as the cluster gives **385 independent units, not 400**.

### (d) The pool cannot supply a much larger design

If more pairs were wanted, the pool cannot supply them at the rate the pair count suggests. The
459 matched pairs occupy only 614 distinct offices. Requiring that no office be dialed for two
different pairs — the two-calls-per-clinic guarantee — the largest fieldable set found by
randomised greedy search over 2,000 restarts is **244 pairs**, against a counting upper bound of
307. So the practical ceiling is roughly 244 pairs, not 459.

**Revised reading.** An earlier version of this section concluded that expanding the sample was
the wrong lever. That was written before the censoring-aware simulation existed, and it no
longer holds. Table S1.4 puts censored power at 0.690 at 200 pairs and 0.840 at 250, so the
extra pairs now buy about 0.15 of power in the range that matters, not the 0.04 the uncensored
grid suggested. The ceiling of 244 pairs sits just below the 250 that restores 80%; interpolating
Table S1.4 gives approximately **0.83 at 244 pairs**.

Expansion is therefore worth considering on its merits, alongside two cheaper levers that act on
the same shortfall: anything that raises PE-Medicaid obtainment measurement (for example
recording a wait time for calls that offer a date beyond the audit window rather than treating
them as non-obtained) directly enlarges the identifying cell, and the SVI repair in (b) has
already restored 91 complete pairs at no fieldwork cost.

*(A previously circulated figure of 224 office-disjoint pairs was computed with a weaker greedy
ordering; 244 is the best packing found and supersedes it.)*

### (e) The simulation omits the pair-level random intercept

The analysis plan specifies random intercepts for **both** the matched pair and the clinician;
the simulation generates and fits only the clinician intercept. The effect on the interaction is
expected to be small, because the interaction is identified within clinician, and the main
manuscript already reports that the matched-pair variance was not reliably distinguishable from
zero in simulation. It is noted for completeness rather than as a live threat.

## S1.9 Conclusion

**The headline number for the manuscript is 0.69, not 0.87.**

Under the literature-anchored effect of IRR 1.22 and a wait-time SD of 10 days, the fielded
design of 200 matched pairs reaches 0.870 for the primary wait-time interaction *if every call
yields a wait time*. It will not. Once calls are retained at their cell's anticipated obtainment
probability, power at 200 pairs is **0.690** (§S1.8(a), Table S1.4). The study as fielded is
underpowered for its primary wait-time estimand.

Where that leaves the design:

1. **Obtainment censoring is the dominant threat.** It costs 0.18 of power by shrinking the
   identifying PE-Medicaid cell from 200 to about 82. Roughly 250 pairs restores 80%; the
   attainable ceiling of 244 pairs (§S1.8(d)) gives approximately 0.83.
2. **The SVI defect is repaired.** The covariate was simulated, not measured, and has been
   reconstructed from the published CDC release for 394 of 400 clinicians with missingness now
   independent of exposure (Fisher p = 1.00) and 197 of 200 pairs complete. This removes what
   would otherwise have been a second, larger reduction to 106 pairs. §S1.8(b).
3. **Shared schedulers are measured, not assumed away.** Two fielded pairs put both arms on one
   practice line; 385 lines serve 400 clinicians. Sensitivity analyses excluding same-line pairs
   and clustering on the line are prespecified and the variables to run them are on the sheet.
   §S1.8(c).
4. **Dispersion remains the binding constraint on the uncensored figures.** At SD 20 the same
   design gives 0.41, and no feasible sample size rescues it. Re-examine against real wait times
   as soon as they accumulate.

Under the conservative IRR 1.10 no feasible sample size reaches 0.80, and the manuscript should
say so rather than report only the favourable scenario. The minimum detectable interaction at
the fielded design, before censoring, is about IRR 1.19 — a differential Medicaid penalty of
roughly 5.7 business days.

## S1.10 Reproducibility

| Item | Value |
|---|---|
| Primary script | `run_new_power_analysis.R` |
| Results | `power_analysis_new_results.csv` |
| Seed | `set.seed(42)`, set once before the grid |
| Replicates | 200 per cell |
| Software | R 4.4.2; glmmTMB 1.1.14; TMB 1.9.21; MASS 7.3.65 |
| Censoring-aware run | `scratch/power_with_obtainment_censoring.R` (Table S1.4) |
| Minimum detectable effect | `scratch/mde_200_pairs.R` (Table S1.3) |
| Office packing bounds | `scratch/office_disjoint_ceiling.R` (§S1.8(d)) |
| SVI reconstruction | `build_svi_covariate.R`; audit in `scratch/audit_enrichment_provenance.R` |
| Shared-line variables | `build_phone_cluster_vars.R` |
| Tests | `tests/testthat/test-power-and-calibration.R`, `test-svi-provenance.R`, `test-phone-clustering.R` |

## References
