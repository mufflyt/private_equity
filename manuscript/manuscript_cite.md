# Access to Generalist Obstetrics and Gynecology Care at Private Equity-Backed vs. Independent Practices: A Mystery Caller Audit Study

**Authors:** Tyler Muffly, MD¹; Lizeth [Last Name], [Credentials]²; Taylor Gatson, [Credentials]²

**Affiliations:**
¹ Department of Obstetrics and Gynecology, Denver Health and Hospital Authority, Denver, CO
² Department of Obstetrics and Gynecology, University of Colorado School of Medicine, Aurora, CO

**Corresponding Author:** Tyler Muffly, MD · Denver Health and Hospital Authority · 777 Bannock Street, Denver, CO 80204 · tyler.muffly@dhha.org

**Target Journal:** *Obstetrics & Gynecology* (The Green Journal)

**Word Count (Text Only):** [XXXX] · **Abstract Word Count:** [XXX] · **Tables:** 4 · **Figures:** 2
**Funding/Financial Support:** None.
**Conflict of Interest:** The authors have no conflicts of interest to disclose.
**IRB Approval:** Approved by the Colorado Multiple Institutional Review Board (COMIRB Protocol No. [XXXXX]) with a waiver of provider and patient consent.

## Précis

Private equity ownership of generalist OB-GYN practices is associated with a [31.5]-percentage-point reduction in Medicaid acceptance and a near-doubling of the insurance-based scheduling wait-time gap.

## Abstract

**Objective:** To compare new-patient scheduling access and wait times for Medicaid versus commercially insured patients at private equity (PE)-backed and independent obstetrics and gynecology (OB-GYN) practices.

**Methods:** We conducted a simulated-patient (mystery caller) crossover audit of [200] matched clinician pairs ([400] clinicians) across 26 states. Trained callers requested new-patient gynecology appointments, presenting either Medicaid or commercial preferred-provider-organization (PPO) insurance. Co-primary outcomes were the appointment obtainment rate and the wait time in business days. The primary obtainment comparison was PE vs. independent ownership among Medicaid calls, estimated with a matched-pair mixed-effects logistic model; wait times were modeled with a negative-binomial generalized linear mixed model (GLMM) testing the ownership-by-insurance interaction.

**Results:** Commercial insurance was accepted nearly universally, with no difference by ownership ([98.5]% independent vs. [99.0]% PE, [p = 0.68]). Medicaid acceptance was substantially lower at PE-backed than independent clinics ([41.0]% vs. [72.5]%; absolute difference [-31.5]%; OR [0.26], 95% CI [0.17 to 0.40], [p < 0.001]). Among clinics that scheduled an appointment, the insurance wait-time gap was wider at PE-backed clinics ([22.3] vs. [11.3] business days; interaction IRR [1.31], 95% CI [1.07 to 1.56], [p = 0.008]).

**Conclusion:** Private equity ownership of generalist OB-GYN practices is associated with lower Medicaid acceptance and a widened wait-time disparity between publicly and commercially insured patients.

## Introduction

Over the past decade, corporate consolidation and financialization have reshaped the delivery of health care in the United States. Private equity (PE) firms, which are investment partnerships that acquire companies, restructure operations, and aim to resell them at a profit within a short horizon (typically three to seven years), have expanded aggressively into outpatient physician practice, acquiring hundreds of groups across specialties.[@zhu2020specialties; @zhu2021ecosystem] Obstetrics and gynecology (OB-GYN) has become a prominent target of this activity, with multiple national women's-health "platforms" assembling large networks of acquired clinics.[@zhu2020specialties]

The returns underlying the PE model are typically pursued through administrative consolidation, expansion of ancillary services, intensified clinician productivity, and optimization of the "payer mix" toward higher-reimbursement commercial insurance and away from lower-reimbursement public programs such as Medicaid. A growing evidence base links PE ownership in health care to higher costs and mixed-to-worse quality across settings, including hospitals and physician specialties.[@borsa2023systematic; @bruch2020hospital; @kannan2023adverse] Parallel analyses in dermatology and ophthalmology have documented rapid PE penetration and downstream changes in utilization and spending, raising the question of whether similar dynamics affect access in women's health.[@tan2019dermatology; @braun2024ophthalmology]

Medicaid finances approximately 41% of births in the United States and is a cornerstone of reproductive health-care access.[@kff_births] Audit ("secret shopper") studies have repeatedly shown that Medicaid enrollees face higher appointment-denial rates and longer waits than commercially insured patients across specialties.[@bisgaier2011auditing; @asplin2005insurance] Yet no study has examined whether the *ownership structure* of OB-GYN practices, namely corporate PE ownership versus traditional independent private practice, shapes these disparities. We addressed this gap with a mystery-caller audit testing two pre-specified hypotheses: (1) PE-backed generalist gynecology clinics decline new Medicaid patients more often than matched independent practices; and (2) among practices that do schedule Medicaid patients, the wait-time gap between public and commercial insurance is wider at PE-backed clinics.

## Methods

### Study Design

We conducted a simulated-patient (mystery caller) crossover audit. Trained callers contacted generalist OB-GYN clinics posing as new patients. Each clinic was called twice: once presenting Medicaid and once presenting commercial Blue Cross Blue Shield (BCBS) PPO coverage. To minimize temporal and seasonal confounding, all calls were completed within a single week in July 2026. The Colorado Multiple Institutional Review Board (COMIRB) approved the protocol (No. [XXXXX]) under a waiver of patient and provider consent, consistent with established audit-study methodology.[@bisgaier2011auditing]

### Cohort Identification and Matching

PE-backed OB-GYN clinics were identified using the PitchBook financial database to track acquisitions by major women's-health platforms, and each platform's active clinician roster was compiled from its public consumer directory. To construct a clean counterfactual, control candidates were drawn from the CMS Doctors and Clinicians registry, restricted to independent private practices (excluding academic and hospital-system settings), and matched 1-to-1 to PE clinicians using a propensity-score matching pipeline.

Three eligibility rules were applied to the PE roster before matching. First, five platforms were excluded because their business model cannot supply the appointment the study requests: four fertility practices, which are subspecialty referral settings, and one obstetric hospitalist group, which has no outpatient clinic. This is a platform-level rule rather than a specialty-code filter, because a clinician at a fertility platform can carry a generalist OB-GYN taxonomy. Second, clinicians not observed practising within two years of the most recent year covered by the CMS activity file were excluded as likely to have left the practice. Third, clinicians identified as non-physicians on verification against the practice's own website were excluded. Clinicians removed from the treated arm by these rules remained ineligible as controls, so that an excluded PE clinician could not re-enter the study as an independent comparator.

Each PE clinician was then matched 1-to-1 to a control drawn from the same state, of the same gender, and within a 10-mile radius, requiring at least two eligible candidates inside that radius so that the selected control was chosen among alternatives rather than taken as the only option. Among those candidates, the control with the closest propensity score was selected. Propensity scores came from a logistic model of PE status on credential (MD vs. DO), gender, years in practice, and Open Payments activity as a proxy for industry engagement; state, gender, and the 10-mile radius were enforced as hard constraints on the candidate pool, while credential, years in practice, and Open Payments entered through the score rather than as separate calipers. To limit within-office clustering, exactly one clinician was randomly selected per physical office location, defined by a normalized street address. From a matched pool of 459 pairs across 26 U.S. states, we fielded 200 pairs (400 clinicians), and the 259 unfielded pairs were retained as a replacement pool. Address-level de-duplication does not guarantee independent scheduling: the 400 fielded clinicians are reached through 400 distinct registered telephone numbers but only 385 distinct practice lines, because 12 lines are centralized scheduling numbers serving 27 clinicians across multiple sites. In two matched pairs the PE clinician and the matched control share a practice line, and no fielded pair shares a street address. These relationships are recorded as analytic variables and addressed in prespecified sensitivity analyses (Supplementary Appendix S2). Because PE ownership was geographically concentrated, most heavily in Florida, the fielded sample was drawn to maximize representation across states rather than by simple random selection, so that no single market dominated the cohort.

### Contextual Covariates and Geographic Linkage

Neighborhood social vulnerability was measured with the Centers for Disease Control and Prevention/Agency for Toxic Substances and Disease Registry Social Vulnerability Index (CDC/ATSDR SVI), 2022 release, overall summary percentile ranking (`RPL_THEMES`). A pre-fielding audit of the covariate file established that the SVI values initially attached to the cohort could not be traced to any geographic linkage and were distributionally inconsistent with a percentile ranking; they were also absent for 94 of 200 control clinicians and no PE clinicians, so that missingness was almost perfectly associated with exposure (Fisher exact test, *P* = 5.1 × 10⁻³⁵). The variable was therefore reconstructed from source geography before any call was placed.

Reconstruction proceeded from each clinician's NPPES practice street address to a 2020 census tract using the U.S. Census Bureau batch geocoder, and from tract to `RPL_THEMES` using the CDC/ATSDR 2022 state files; the 2020 tract vintage is required because the 2022 SVI release is published on 2020 boundaries. Addresses the geocoder could not place were resolved, in order, by retrying with suite designators removed, by the stored practice coordinate, and by an area-weighted mean over the census tracts intersecting the ZIP Code Tabulation Area. The linkage method is retained as an analytic variable so that geographic precision can be modeled or used as an exclusion criterion.

Reconstruction recovered SVI for 197 of 200 PE clinicians and 197 of 200 controls across 312 census tracts, leaving 197 of 200 matched pairs complete. Missingness in the reconstructed variable is independent of exposure (Fisher exact test, *P* = 1.00), and the arms are balanced on the measure (standardized mean difference −0.03; Welch *P* = 0.79). The original values are retained unmodified for provenance and are not used in any analysis. Additional tract- and county-level variables present in the source file were determined by the same audit to be simulated rather than measured; they are excluded from all analyses reported here. The audit, the reconstruction, and its validation are documented in full in Supplementary Appendix S2.

### Call Protocol and Vignette

Callers followed a standardized script requesting a new-patient appointment for abnormal uterine bleeding (AUB), a common gynecologic complaint that warrants timely evaluation without constituting an emergency. Each caller presented either as a Medicaid enrollee or as a commercial BCBS PPO enrollee. Insurance-presentation order was randomized, with a minimum 48-hour interval between the two calls to a given office to reduce recognition. Outcomes were recorded in a customized, blinded REDCap database. To ensure data integrity, clinician phone numbers were cross-referenced against three independent sources (NPPES, CMS billing records, and platform websites); of the numbers checked, 73.3% matched across two or more sources and 100% matched at least one registry.

### Primary and Secondary Outcomes

The two co-primary outcomes were (1) the appointment obtainment rate, a binary indicator of whether a scheduling date was offered, and (2) the appointment wait time, measured in business days from the call date to the first available appointment. Secondary outcomes included administrative barriers to scheduling (for example, required upfront copayment, primary-care referral, or prior authorization).

### Statistical Analysis

Analyses follow a pre-specified hierarchy, fixed before any call was placed.

The primary obtainment estimand is the difference in appointment obtainment between PE-backed and independent clinicians among Medicaid calls only, estimated with a mixed-effects logistic model containing a random intercept for the matched pair. Because each clinician contributes exactly one Medicaid call, no clinician-level random effect is identifiable in this model. A McNemar test on discordant matched pairs is reported as a distribution-free confirmation, and the absolute risk difference is reported alongside the odds ratio.

The primary wait-time estimand is the ownership-by-insurance interaction, estimated with a negative-binomial GLMM using the *lme4*[@bates2015lme4] and *glmmTMB*[@brooks2017glmmtmb] packages in R. Fixed effects are clinic ownership (PE vs. independent), insurance type (Medicaid vs. commercial), their interaction, and the reconstructed CDC/ATSDR Social Vulnerability Index percentile; random intercepts for the matched pair and the individual clinician account for correlation within pairs and repeated measures.

The ownership-by-insurance interaction for obtainment is reported as a secondary analysis. Because commercial acceptance is nearly universal, that interaction is identified almost entirely from the Medicaid arm and is expected to be imprecise. In simulation under the anticipated cell proportions at 200 pairs, the primary Medicaid obtainment contrast reached essentially complete power, whereas the obtainment interaction reached approximately 40 percent and failed to return an estimable standard error in roughly one simulated dataset in eight.

Five sensitivity analyses were specified before fielding. First, the primary wait-time model is refitted excluding the two matched pairs in which the PE clinician and the matched control share a practice telephone line, for which a caller reaches the same scheduling system in both arms. Second, inference is recalculated treating the normalized practice line rather than the individual clinician as the clustering unit (385 units rather than 400). Third, the analysis is restricted to the 154 pairs in which both members carry an address-level census tract linkage, and repeated with the linkage method entered as a precision indicator. Fourth, the primary estimand is reported without the SVI covariate, so that the contribution of the geographic reconstruction to the result is visible. Fifth, the analysis is restricted to pairs with complete validated covariate information, to quantify the effect of residual missingness; this is not offered as a remedy for the arm-dependent missingness in the original covariate, which was repaired at source.

Wait time is defined conditional on obtaining an appointment. Because obtainment itself differs by insurance and by ownership, conditional wait-time comparisons are made within a selected subgroup, and the selection is heaviest in the PE Medicaid cell. We therefore pre-specify an unconditional access analysis among Medicaid calls in which failure to obtain an appointment is ranked as the worst access outcome rather than treated as missing data. Variance components and intraclass correlation coefficients are reported as exploratory: with two calls per clinician they are weakly identified. All tests were two-sided at α = 0.05.

### Sample Size and Power

The sample size was evaluated by simulation for the primary wait-time estimand, the ownership-by-insurance interaction, tested alone at a two-sided α of 0.05. Each replicate reproduced the fielded design — one Medicaid and one commercial call per clinician, two clinicians per matched pair — and was analyzed with the same negative-binomial GLMM specified above, with a clinician random intercept. Wait times were drawn negative-binomial with dispersion solved at a reference mean of 23 business days, under wait-time standard deviations of 10 and 20 days. Two hundred replicates were run per cell, and all fits converged.

Because no published estimate of a private-equity-by-insurance interaction in obstetric and gynecologic wait times exists, the assumed magnitude was anchored to the closest available simulated-patient study. Nie et al. reported a mean wait of 17.5 days at private equity-acquired urology practices versus 21.4 days at non-acquired practices (*P* = .017), a ratio of 1.22.[@nie2022urology] That study reported the ownership and insurance main effects separately and did not estimate their interaction for wait time; the figure is therefore used as the magnitude of the published private equity-associated wait-time difference in the closest mystery-caller study, not as a previously observed interaction. Its access outcome does exhibit the effect modification hypothesized here (Medicaid availability 52.1% at acquired versus 66.8% at non-acquired practices; adjusted odds ratio 0.55, 95% CI 0.37 to 0.83), which is why an interaction of this order is plausible. Conservative (1.10) and larger (1.35) scenarios were carried alongside.

If every call yielded a wait time, 200 matched pairs would give 87% power at the anchored magnitude and a standard deviation of 10 days. Wait times are observed only when a clinic offers a date, however, and under the anticipated obtainment proportions the 800 placed calls are expected to yield approximately 622 observed wait times, with the private equity-Medicaid cell that identifies the interaction falling from 200 calls to approximately 82. Repeating the simulation with calls retained at their cell-specific obtainment probability gives **69% power at 200 pairs**, which is the figure that describes the study as fielded: if the true interaction equals the anchored magnitude, the study has a 69% probability of detecting it at α = 0.05. Power reaches 81% at 244 pairs, the largest sample the matched pool can supply without dialing any office for two different pairs. Under the conservative scenario no attainable sample size exceeds 30% power, and under the larger scenario the design is saturated at both sizes; the anchored scenario is therefore the only one in which the sample size decision has consequence.

The minimum interaction detectable with 80% power at the fielded design, before censoring, is an incidence rate ratio of approximately 1.19, corresponding to a differential Medicaid wait-time penalty of roughly 5.7 business days. Dispersion is the binding constraint throughout: at a wait-time standard deviation of 20 days, power at the anchored magnitude falls to 41% at 200 pairs and reaches only 58% at 400. The full simulation grid, the censoring-aware results, and the derivation of the attainable ceiling are reported in Supplementary Appendix S1.

## Results

### Baseline Cohort Demographics (Table 1)

The propensity-score matching pipeline yielded well-balanced baseline characteristics across the [400] fielded clinicians (200 PE-employed, 200 independent controls); no matched covariate differed significantly between groups (Table 1).

### Appointment Obtainment (Medicaid Acceptance) (Table 2)

Across the [800] calls ([400] independent, [400] PE-backed), commercial BCBS PPO coverage was accepted nearly universally, with no difference by ownership: [98.5]% ([197]/[200]) at independent clinics vs. [99.0]% ([198]/[200]) at PE-backed clinics ([p = 0.68]). Medicaid acceptance, however, differed markedly: [72.5]% (145/[200]) at independent clinics vs. only [41.0]% (82/[200]) at PE-backed clinics, an absolute reduction of [-31.5]% (95% CI [-40.5]% to [-22.5]%, [p < 0.001]) under corporate ownership (Table 2).

### Scheduling Wait Times (Table 3)

Among clinics that scheduled new-patient gynecology appointments, Medicaid patients waited longer than commercially insured patients, and this disparity was amplified under PE ownership (Table 3). At independent practices, Medicaid patients waited on average [11.3] days longer than commercially insured patients; at PE-backed practices the gap was [22.3] days, a near-doubling. The negative-binomial GLMM confirmed a significant ownership-by-insurance interaction, indicating expansion of the wait-time gap at corporate offices (IRR [1.31], 95% CI [1.07 to 1.56], [p = 0.008]). These wait times are conditional on the clinic offering an appointment, and the conditioning is heaviest in the PE Medicaid cell, where only [82] of [200] calls yielded a scheduled date.

### Mixed-Effects Regression (Table 4)

Table 4 presents odds ratios for obtainment and incidence rate ratios for wait time from the adjusted regression models.

## Discussion

This mystery-caller audit provides among the first empirical evidence that corporate, private equity ownership of generalist OB-GYN practices is associated with restricted access for publicly insured patients. We observed a *dual-barrier* effect: PE-backed clinics were substantially less likely to accept Medicaid patients, and when they did, they imposed scheduling delays roughly twice as long as those at matched independent practices. The magnitude of the Medicaid access gap is consistent with prior secret-shopper work documenting large public-versus-private disparities in appointment availability and wait time across specialties.[@bisgaier2011auditing; @asplin2005insurance]

These findings align with the incentives embedded in the PE model and with a broadening literature linking PE ownership to higher costs and mixed-to-worse quality and outcomes across health-care settings.[@borsa2023systematic; @bruch2020hospital; @kannan2023adverse] Operating under substantial debt and compressed investment horizons, corporate managers are incentivized to pursue "payer-mix optimization," for example by capping monthly Medicaid slots or routing public-insurance scheduling through centralized call centers that add administrative friction, to prioritize higher-reimbursement commercial volume. While such strategies may improve corporate margins, they can exacerbate systemic inequities: Medicaid enrollees seeking evaluation for abnormal uterine bleeding may face delayed diagnosis of endometrial hyperplasia or malignancy, or be displaced to emergency and hospital-based settings that raise total system cost.

### Policy and Clinical Implications

Our results bear directly on intensifying federal and state scrutiny of health-care consolidation. As the Federal Trade Commission and state legislatures examine PE acquisitions, evidence that ownership structure degrades access for publicly insured populations may inform remedies such as Medicaid-acceptance conditions or transparency requirements for scheduling wait times as a condition of corporate acquisition.

### Limitations

This study has limitations. First, the audit used a single clinical vignette (AUB) and a single calling week, which may not capture seasonal variation or access for other presentations. Second, although controls were closely matched on geography and physician characteristics, unmeasured local-market factors could influence scheduling. Third, PE ownership is geographically concentrated: Florida contributed a disproportionate share of eligible pairs, so despite balancing efforts the cohort over-represents a small number of markets, and findings may not generalize to states without corporate consolidation. Fourth, wait time can only be measured at clinics that offered an appointment, and willingness to offer one differed by both insurance and ownership. The wait-time comparison is therefore made within a selected subgroup, and the selection is strongest exactly where the effect is largest: the PE Medicaid cell contributed the fewest scheduled appointments. If the clinics that decline Medicaid are also those that would have quoted the longest waits, the conditional analysis understates the true access gap. We report an unconditional access analysis among Medicaid calls, in which failure to obtain an appointment is ranked as the worst outcome, to keep this selection visible rather than implicit. Fifth, although each matched pair comprises clinicians at distinct street addresses, 12 centralized scheduling lines serve 27 fielded clinicians, and in two pairs both arms are reached through the same line; the clinician is therefore not everywhere the unit of independence, and we report sensitivity analyses excluding those pairs and clustering on the practice line. Sixth, the neighborhood social vulnerability covariate was reconstructed from practice addresses before fielding after a provenance audit; 32 of 400 clinicians, predominantly controls, carry a ZIP-approximate rather than an address-level census tract linkage, and 6 carry no value, so geographic precision is not uniform across arms even though missingness is. Seventh, the study is powered at approximately 69% for the primary wait-time interaction once obtainment censoring is accounted for, so a null wait-time interaction should not be read as evidence of no effect. Finally, mystery-caller designs capture scheduling behavior at the point of contact and cannot observe downstream care quality.

## References

::: {#refs}
:::

## Tables and Figures

**Table 1. Baseline Clinician and Practice Characteristics (Fielded Cohort)**

| Variable | Independent Private Practice (N = 200) | PE-Backed Corporate Practice (N = 200) | p-value |
|:--|:--:|:--:|:--:|
| **Credentials** | | | [0.99] |
| MD | 187 (93.5%) | 183 (91.5%) | |
| DO | 13 (6.5%) | 16 (8.0%) | |
| **Gender** | | | [0.99] |
| Female | 121 (60.5%) | 137 (68.5%) | |
| Male | 79 (39.5%) | 63 (31.5%) | |
| Years in Practice (mean ± SD) | 24.6 (±11.5) | 23.0 (±12.3) | [0.95] |
| Open Payments Years (mean ± SD) | 6.7 (±2.1) | 6.4 (±2.3) | [0.96] |

*Note:* All matching parameters show high balance between groups (p > 0.05).

**Table 2. Appointment Obtainment (Medicaid Acceptance) Rates (Dummy)**

| Payer Type | Independent (N = [200]) | PE-Backed (N = [200]) | Risk Difference (95% CI) | p-value |
|:--|:--:|:--:|:--:|:--:|
| Commercial BCBS PPO | [98.5]% ([197]/[200]) | [99.0]% ([198]/[200]) | [+0.5]% ([-1.8]% to [+2.8]%) | [0.68] |
| Medicaid | [72.5]% (145/[200]) | [41.0]% (82/[200]) | [-31.5]% ([-40.5]% to [-22.5]%) | [<0.001] |

**Table 3. New-Patient GYN Appointment Wait Times (Business Days) (Dummy)**

| Group / Payer | Commercial BCBS PPO (N = [395]) | Medicaid (N = [227]) | Wait-Time Gap (95% CI) |
|:--|:--:|:--:|:--:|
| Independent Practice | [12.1] days (SD [6.8]) | [23.4] days (SD [11.2]) | [11.3] days ([9.4] to [13.2]) |
| PE-Backed Practice | [14.5] days (SD [8.2]) | [36.8] days (SD [18.4]) | [22.3] days ([17.8] to [26.8]) |

**Table 4. Mixed-Effects Regression Outcomes for Obtainment and Wait Times (Dummy)**

| Outcome / Variable | OR (Obtainment) | 95% CI | p-value | IRR (Wait Time) | 95% CI | p-value |
|:--|:--:|:--:|:--:|:--:|:--:|:--:|
| **Primary obtainment:** PE vs. independent, Medicaid calls only | **[0.26]** | **[0.17] to [0.40]** | **[<0.001]** | not applicable | | |
| **Primary wait time:** payer × ownership interaction | not applicable | | | **[1.31]** | **[1.07] to [1.56]** | **[0.008]** |
| Payer (Medicaid vs. BCBS) | [0.04] | [0.01] to [0.13] | [<0.001] | [1.93] | [1.56] to [2.39] | [<0.001] |
| Ownership (PE vs. independent) | [1.51] | [0.25] to [9.12] | [0.65] | [1.20] | [0.94] to [1.53] | [0.14] |
| *Secondary obtainment:* payer × ownership interaction | [0.17] | [0.02] to [1.30] | [0.10] | not applicable | | |

*Note:* Models adjusted for clinician gender, credentials, state, and years in practice. Random intercepts for matched pair and individual clinician, except in the primary obtainment model, which contains a matched-pair intercept only because each clinician contributes a single Medicaid call. Placeholder effect sizes in this table are the quantities implied by the cell values in Tables 2 and 3, so that the dummy tables remain internally consistent; the secondary interaction is shown with the imprecision the design actually delivers.

**Supplemental Table 1. Intraclass Correlation Coefficients (ICC) for Wait-Time GLMM (Dummy, Exploratory)**

| Model Parameter | Variance Estimate | Residual Variance | ICC |
|:--|:--:|:--:|:--:|
| Clinician level (NPI) | [0.082] | [0.354] | [18.8]% |
| Matched-pair level | [0.054] | [0.354] | [12.4]% |

*Note:* ICC is computed as the level-specific variance divided by the sum of that variance and the residual variance. These components are reported as exploratory. Each clinician contributes at most two calls and each matched pair at most four, so the variance components are weakly identified; in simulation under the anticipated design the matched-pair variance was not reliably distinguishable from zero. They are presented to characterize the correlation structure, not as estimates the study is powered to support.

### Figure Legends

**Figure 1.** Appointment obtainment (Medicaid acceptance) rates by ownership group. Bar chart of the percentage of successful new-patient appointment offers for commercial BCBS PPO vs. Medicaid across independent private practices and PE-backed clinics (dummy placeholders).

**Figure 2.** Distribution of new-patient gynecology wait times (business days) by payer. Density curves for commercial BCBS PPO vs. Medicaid at independent vs. PE-backed clinics (dummy placeholders).

**Figure 3.** STROBE flow diagram of clinic inclusion and exclusion, showing the sampling and matching pathway for PE-backed clinics and independent matched controls.
