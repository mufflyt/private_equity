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

**Methods:** We conducted a simulated-patient (mystery caller) crossover audit of [200] matched clinician pairs ([400] clinicians) across 26 states. Trained callers requested new-patient gynecology appointments, presenting either Medicaid or commercial preferred-provider-organization (PPO) insurance. Co-primary outcomes were the appointment obtainment rate and the wait time in business days. Wait times were modeled with a negative-binomial generalized linear mixed model (GLMM).

**Results:** Commercial insurance was accepted nearly universally, with no difference by ownership ([98.5]% independent vs. [99.0]% PE, [p = 0.68]). Medicaid acceptance was substantially lower at PE-backed than independent clinics ([41.0]% vs. [72.5]%; absolute difference [-31.5]%, [p < 0.001]). Among clinics that scheduled Medicaid patients, the insurance wait-time gap was significantly wider at PE-backed clinics ([22.3] vs. [11.3] business days; interaction IRR [1.62], 95% CI [1.28 to 2.05], [p < 0.001]).

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

Clinicians were matched within a strict 10-mile radius in the same state on provider gender (exact match), credential (MD vs. DO), years in practice (within a five-year band), and Open Payments activity as a proxy for industry engagement. To prevent within-office clustering, exactly one physician was randomly selected per physical office location. From a matched pool of 511 pairs across 26 U.S. states, we fielded 200 pairs (400 clinicians), reserving the remaining 311 pairs as an attrition pool. Because PE ownership was geographically concentrated, most heavily in Florida, the fielded sample was drawn to maximize representation across states rather than by simple random selection, so that no single market dominated the cohort.

### Call Protocol and Vignette

Callers followed a standardized script requesting a new-patient appointment for abnormal uterine bleeding (AUB), a common gynecologic complaint that warrants timely evaluation without constituting an emergency. Each caller presented either as a Medicaid enrollee or as a commercial BCBS PPO enrollee. Insurance-presentation order was randomized, with a minimum 48-hour interval between the two calls to a given office to reduce recognition. Outcomes were recorded in a customized, blinded REDCap database. To ensure data integrity, clinician phone numbers were cross-referenced against three independent sources (NPPES, CMS billing records, and platform websites); of the numbers checked, 73.3% matched across two or more sources and 100% matched at least one registry.

### Cohort-Compliant Backup Protocol

To protect the matched-pair structure against call-time attrition (for example, a relocated or retired physician), we pre-identified cohort-compliant backup physicians at the same office location (101 PE clinics and 243 control clinics). Callers substituted a pre-assigned backup only when the primary was unreachable and recorded the deviation in REDCap.

### Primary and Secondary Outcomes

The two co-primary outcomes were (1) the appointment obtainment rate, a binary indicator of whether a scheduling date was offered, and (2) the appointment wait time, measured in business days from the call date to the first available appointment. Secondary outcomes included administrative barriers to scheduling (for example, required upfront copayment, primary-care referral, or prior authorization).

### Statistical Analysis

Obtainment rates were compared between PE-backed and independent clinics with two-sample proportion Z-tests. Wait times were analyzed with a negative-binomial GLMM using the *lme4*[@bates2015lme4] and *glmmTMB*[@brooks2017glmmtmb] packages in R. Fixed effects included clinic ownership (PE vs. independent), insurance type (Medicaid vs. commercial), and their interaction; random intercepts for the matched pair and the individual clinician accounted for correlation within pairs and repeated measures. All tests were two-sided at α = 0.05.

## Results

### Baseline Cohort Demographics (Table 1)

The propensity-score matching pipeline yielded well-balanced baseline characteristics across the [400] fielded clinicians (200 PE-employed, 200 independent controls); no matched covariate differed significantly between groups (Table 1).

### Appointment Obtainment (Medicaid Acceptance) (Table 2)

Across the [800] calls ([400] independent, [400] PE-backed), commercial BCBS PPO coverage was accepted nearly universally, with no difference by ownership: [98.5]% ([197]/[200]) at independent clinics vs. [99.0]% ([198]/[200]) at PE-backed clinics ([p = 0.68]). Medicaid acceptance, however, differed markedly: [72.5]% (145/[200]) at independent clinics vs. only [41.0]% (82/[200]) at PE-backed clinics, an absolute reduction of [-31.5]% (95% CI [-40.5]% to [-22.5]%, [p < 0.001]) under corporate ownership (Table 2).

### Scheduling Wait Times (Table 3)

Among clinics that scheduled new-patient gynecology appointments, Medicaid patients waited longer than commercially insured patients, and this disparity was amplified under PE ownership (Table 3). At independent practices, Medicaid patients waited on average [11.3] days longer than commercially insured patients; at PE-backed practices the gap was [22.3] days, a near-doubling. The negative-binomial GLMM confirmed a significant ownership-by-insurance interaction, indicating substantial expansion of the wait-time gap at corporate offices (IRR [1.62], 95% CI [1.28 to 2.05], [p < 0.001]).

### Mixed-Effects Regression (Table 4)

Table 4 presents odds ratios for obtainment and incidence rate ratios for wait time from the adjusted regression models.

## Discussion

This mystery-caller audit provides among the first empirical evidence that corporate, private equity ownership of generalist OB-GYN practices is associated with restricted access for publicly insured patients. We observed a *dual-barrier* effect: PE-backed clinics were substantially less likely to accept Medicaid patients, and when they did, they imposed scheduling delays roughly twice as long as those at matched independent practices. The magnitude of the Medicaid access gap is consistent with prior secret-shopper work documenting large public-versus-private disparities in appointment availability and wait time across specialties.[@bisgaier2011auditing; @asplin2005insurance]

These findings align with the incentives embedded in the PE model and with a broadening literature linking PE ownership to higher costs and mixed-to-worse quality and outcomes across health-care settings.[@borsa2023systematic; @bruch2020hospital; @kannan2023adverse] Operating under substantial debt and compressed investment horizons, corporate managers are incentivized to pursue "payer-mix optimization," for example by capping monthly Medicaid slots or routing public-insurance scheduling through centralized call centers that add administrative friction, to prioritize higher-reimbursement commercial volume. While such strategies may improve corporate margins, they can exacerbate systemic inequities: Medicaid enrollees seeking evaluation for abnormal uterine bleeding may face delayed diagnosis of endometrial hyperplasia or malignancy, or be displaced to emergency and hospital-based settings that raise total system cost.

### Policy and Clinical Implications

Our results bear directly on intensifying federal and state scrutiny of health-care consolidation. As the Federal Trade Commission and state legislatures examine PE acquisitions, evidence that ownership structure degrades access for publicly insured populations may inform remedies such as Medicaid-acceptance conditions or transparency requirements for scheduling wait times as a condition of corporate acquisition.

### Limitations

This study has limitations. First, the audit used a single clinical vignette (AUB) and a single calling week, which may not capture seasonal variation or access for other presentations. Second, although controls were closely matched on geography and physician characteristics, unmeasured local-market factors could influence scheduling. Third, PE ownership is geographically concentrated: Florida contributed a disproportionate share of eligible pairs, so despite balancing efforts the cohort over-represents a small number of markets, and findings may not generalize to states without corporate consolidation. Finally, mystery-caller designs capture scheduling behavior at the point of contact and cannot observe downstream care quality.

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
| Payer (Medicaid vs. BCBS) | [0.15] | [0.08] to [0.28] | [<0.001] | [1.93] | [1.56] to [2.39] | [<0.001] |
| Ownership (PE vs. Control) | [1.02] | [0.55] to [1.89] | [0.94] | [1.20] | [0.94] to [1.53] | [0.14] |
| Payer × Ownership Interaction | [0.28] | [0.12] to [0.65] | [0.003] | [1.62] | [1.28] to [2.05] | [<0.001] |

*Note:* Models adjusted for clinician gender, credentials, state, and years in practice. Random intercepts for matched pair and individual clinician.

**Supplemental Table 1. Intraclass Correlation Coefficients (ICC) for Wait-Time GLMM (Dummy)**

| Model Parameter | Variance Estimate | Residual Variance | ICC |
|:--|:--:|:--:|:--:|
| Clinician level (NPI) | [0.082] | [0.354] | [18.8]% |
| Matched-pair level | [0.054] | [0.354] | [12.4]% |

*Note:* The clinician-level ICC indicates that [18.8]% of residual wait-time variance is attributable to within-physician factors, supporting repeated-measures random intercepts.

### Figure Legends

**Figure 1.** Appointment obtainment (Medicaid acceptance) rates by ownership group. Bar chart of the percentage of successful new-patient appointment offers for commercial BCBS PPO vs. Medicaid across independent private practices and PE-backed clinics (dummy placeholders).

**Figure 2.** Distribution of new-patient gynecology wait times (business days) by payer. Density curves for commercial BCBS PPO vs. Medicaid at independent vs. PE-backed clinics (dummy placeholders).

**Figure 3.** STROBE flow diagram of clinic inclusion and exclusion, showing the sampling and matching pathway for PE-backed clinics and independent matched controls.
