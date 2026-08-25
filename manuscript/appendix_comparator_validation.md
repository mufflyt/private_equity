# Supplementary Appendix S3. Comparator Validation Against Medicare Enrollment Records

*Private equity ownership and appointment access in obstetrics and gynecology: a simulated-patient audit*

Prepared 2026-08-25. Companion to Supplementary Appendix S1 (statistical power) and Supplementary
Appendix S2 (covariate provenance and independence). All code, inputs, cryptographic hashes, and
intermediate artifacts referenced here are in the study repository.

---

## S3.1 Purpose

The prespecified statistical analysis plan defines the exposure contrast as private equity (PE)
ownership versus **independent** ownership, and the approved human-subjects protocol restricts the
control arm to **independent private practices**. No step in the study pipeline had ever verified
that the sampled controls satisfied that definition. This appendix reports a validation of the
comparator against Medicare provider enrollment records, undertaken before any call was placed.

No outcome data exist. Nothing in the fielded cohort, the matched pairs, the record numbering, the
caller materials, the study database, the frozen analysis plan, or the manuscript was altered as a
result of this work. The appendix reports evidence; it does not enact a change of design.

## S3.2 Data sources and their vintages

Two Centers for Medicare & Medicaid Services (CMS) sources were used. The Provider Enrollment,
Chain, and Ownership System (PECOS) public enrollment files supply the relational structure that
links an individual clinician to the organization receiving their reassigned Medicare benefits. The
Doctors and Clinicians (DAC) National Downloadable File, itself derived from PECOS, supplies
organizational identity together with practice-location detail and specialty.

Twenty-three archive files were inventoried, and each was recorded with its byte count, row count,
and SHA-256 digest. One file was an empty 10-byte stub and is recorded as not used.

An initial reading of the archive treated its enrollment extract as a contemporaneous snapshot. It
is not. The compressed members carry an internal date of April 15, 2019, and the uncompressed files
are byte-identical to the 2019 vintage after normalization for quoting; the later file-system
timestamps reflect extraction rather than content. This was corrected before any analysis.

A second constraint proved more consequential. Enrollment files are available through 2025, but the
**reassignment** files—which carry the individual-to-organization relation on which affiliation
depends—exist only for 2016, 2017, and 2019. PECOS alone therefore cannot describe affiliation
closer than seven years before fielding. The most recent source containing organizational identity,
practice location, and a date preceding cohort construction is the DAC National Downloadable File of
May 2024, and it was adopted as the primary measurement. PECOS 2019 was retained for corroboration
and for the temporal view. Facility affiliations were read from the June 2026 DAC release.

## S3.3 Reconstruction of organizational affiliation

Affiliation was reconstructed along the relation CMS defines:

> individual NPI → individual enrollment identifier → reassignment of benefits → receiving
> enrollment identifier → receiving organization

The **PECOS Associate Control (PAC) identifier** was used as the organizational entity key rather
than the organizational National Provider Identifier, because a single organizational enrollment may
carry more than one NPI. Reassignments in which the receiving party was an individual rather than an
organization (n = 3,898 nationally) were excluded, as the receiving party in those records is a
person and not a practice entity.

Because a clinician may hold several affiliations, the organization relevant to each sampled office
was resolved rather than aggregated. Candidate records were matched to the office actually sampled
by telephone number, then by normalized street address within state, then by city and state. Taking
the maximum organization size across all of a clinician's affiliations was considered and rejected:
it conflates a clinician's largest employer with the practice a caller reached.

Records carrying no organizational identifier denote the absence of an organizational affiliation on
that row rather than an organization of size zero. An earlier implementation selected such records
when they matched the sampled office, which suppressed the organization-bearing records at the same
address for 29 fielded controls. The rule was corrected to prefer organization-bearing records, and
office matches consisting solely of records without an organization are reported in their own
category rather than as resolved.

## S3.4 Independent verification of the linkage

Because an error in the linkage would propagate to every downstream statement, the reconstruction
was implemented twice, by methods sharing no code: once using in-memory hash structures with
row-wise accumulation, and once using external sort-merge relational joins over the raw files. The
two were compared exactly.

| Quantity compared | Implementation 1 | Implementation 2 | Disagreements |
|---|---:|---:|---:|
| Clinician-to-receiving-enrollment relations | 472 | 472 | **0** |
| Clinician-to-organization (PAC) relations | 463 | 463 | **0** |
| Organization-level member counts | 311 organizations | 311 organizations | **0** |
| DAC clinician-to-organization relations | 345 | 345 | **0** |

The DAC file was additionally parsed a third time with an independent regular-expression parser;
record counts agreed exactly (2,563,744), confirming the absence of embedded record separators that
would have shifted field positions.

## S3.5 Two measures that do not discriminate, and were not used

**Hospital affiliation does not indicate employment.** Of the clinicians examined, 244 carry a CMS
facility affiliation, nearly all to hospitals. Obstetrician–gynecologists require admitting
privileges in order to deliver, so this relation is close to universal in the specialty and is
recorded by CMS as a service relation rather than an ownership or employment relation. Treating it
as evidence of employment would have misclassified most of the cohort. It is retained as a
descriptor and is excluded from classification by an explicit rule.

**Enrollment provider type does not distinguish practice ownership.** Of 463 receiving
organizations, 461 are enrolled as "Part B Supplier — Clinic/Group Practice." A health system's
employed medical group and an independent physician-owned group enroll identically. This field was
therefore also excluded from classification.

## S3.6 Principal finding: exposure misclassification in the control arm

The most consequential result of this validation does not concern independence.

Exposure in this study is assigned from a roster of clinicians at 13 named PE platforms (1,279
NPIs). Tested directly against that roster, the control arm is clean, and the corresponding
positive control behaves as expected:

| Test | Result |
|---|---:|
| Control NPIs appearing in the PE roster | **0 of 200** |
| PE-arm NPIs appearing in the PE roster (positive control) | **200 of 200** |

Exposure assignment is thus internally consistent at the level of the individual clinician. That
consistency, however, establishes only that no rostered clinician was placed in the control arm; it
does not establish that controls are independent, because the roster is a sample of platform
clinicians rather than a census of platform practices.

Testing instead at the level of the organization—whether a control bills through a CMS organization
that also contains a rostered PE clinician—yields a different picture:

| Frame | Controls whose sampled office is in a PE-platform organization | Matched pairs affected |
|---|---:|---:|
| **Fielded cohort (200 controls)** | **59 (29.5%)** | **59** |
| Eligible matched universe (459 controls) | 220 (47.9%) | 206 |

Under a broader definition counting any affiliation rather than only the office sampled, the
corresponding figures are 61 and 223. The narrower, office-resolved figure is reported as primary
because it describes the practice a caller actually reached.

Platforms involved in the fielded frame were Axia Women's Health (16 controls), Women's Care
Enterprises (15), Unified Women's Healthcare (12), Femwell Group Health (7), Advantia Health (4),
Nova Women's Health Partners (4), and CCRM Fertility (1). External corroboration confirms the
private-equity status of the largest: Women's Care Enterprises (BC Partners, subsequently Lindsay
Goldberg), Axia Women's Health (Audax Private Equity, subsequently Partners Group), and Unified
Women's Healthcare.

The direction of the resulting bias is toward the null. If a substantial fraction of the comparator
arm is drawn from private-equity-owned practices, the estimated contrast between PE and independent
ownership is attenuated, and a null or small effect could not be distinguished from a true absence
of effect.

**This defect is not remediable by redrawing the cohort.** In the eligible matched universe from
which replacements would be drawn, the proportion affected is higher (47.9% versus 29.5%), and only
239 of 459 universe controls are free of a sampled-office PE-platform link.

## S3.7 Adjudicated comparator status

Each clinician was assigned to one of three states. Ambiguous cases were not forced into a
definitive category, and no definitive classification was permitted without recorded evidence.

| Classification | Fielded controls (n = 200) | Eligible universe (n = 459) |
|---|---:|---:|
| Not independent, affirmatively supported | **91** | 271 |
| Independence unresolved | 86 | 165 |
| Independent, affirmatively supported | **23** | 23 |

Office resolution among fielded controls: 170 resolved to a single organization, 29 matched only
records carrying no organizational affiliation, and 1 matched several organizations.

Affirmative evidence of independent private practice therefore exists for **23 of 200** fielded
controls. The 86 unresolved controls are unresolved: administrative enrollment data record where
Medicare benefits are reassigned and billed, not who owns a practice, and the absence of evidence of
non-independence is not evidence of independence.

## S3.8 Practice size as a measurement rather than a definition

The protocol specifies independent private practice and prespecifies no organizational size
threshold. A 30-physician physician-owned group may be independent; a 4-physician hospital-owned
clinic is not. Size was therefore measured and reported, and was excluded from the definition of
independence by an explicit rule.

System-wide and local practice size were preserved separately, because a national organization of
several thousand clinicians is not the same object as a large local practice.

| Measure (fielded controls) | n | Minimum | Median | Maximum |
|---|---:|---:|---:|---:|
| Organization members, existing measure | 173 | 2 | 252 | 7,694 |
| Organization clinicians, national | 171 | 2 | 248 | 7,694 |
| **Clinicians at the sampled office** | 171 | 1 | **8** | 1,606 |

The separation is substantial: the median control practices in an office of 8 clinicians belonging
to an organization of 248. Counts below descriptive thresholds are reported for sensitivity
analysis only and do not define the comparator:

| Threshold (≤) | 1 | 5 | 10 | 25 | 50 | 100 |
|---|---:|---:|---:|---:|---:|---:|
| National organization | 0 | 16 | 23 | 34 | 49 | 59 |
| Sampled office | 13 | 71 | 103 | 129 | 140 | 146 |

Where practice scale is used in later analyses it should enter as a continuous covariate, with the
local and national measures modeled separately.

## S3.9 Reconciliation with the previously used organization-size measure

An earlier characterization of the control arm used the organization-member count carried in the
control sampling frame. That measure and the national organization size derived here agree for **168
of 171** controls for which both are available, because the sampling frame is itself a DAC extract;
the two are substantially the same quantity.

A preliminary reading during this work suggested a materially different distribution, including 11
apparently solo practitioners. That reading was in error: it used PECOS 2019 reassignment counts, a
different vintage and a different entity resolution, and took the maximum across all of a
clinician's affiliations. It is superseded by the figures in §S3.8, and no conclusion rests on it.

## S3.10 Limitations

PECOS and DAC record the reassignment and billing of Medicare benefits. A shared organization is
strong evidence of a shared corporate practice platform; it is not a determination of ownership, and
these sources cannot establish who holds equity in a practice. Clinicians may maintain several
simultaneous organizational relationships, and CMS permits a reassignment to end while others
continue, so a single record does not fully describe a clinician's arrangements.

The affiliation relation could not be measured closer than May 2024, and the PECOS reassignment
relation no closer than 2019. Practices acquired subsequently would not be visible.

The classification reported here is a screening instrument supported by external corroboration of
the largest organizations. It is not a completed human adjudication. Fields for external source,
evidence date, adjudicator, confidence, and note are present in the released table and are
deliberately empty pending that work, which should include a second independent adjudication of
every non-independent and unresolved case and of a random sample of those classified independent.

## S3.11 Reproducibility and enforcement

The adjudication table covers 1,845 clinicians spanning the fielded frame, the eligible matched
universe, and the full PE roster. Source files are recorded with SHA-256 digests, and the
classification is deterministic and invariant to input row order.

Nine automated contracts enforce the rules stated above and block the analysis if violated: missing
enrollment evidence cannot imply independence; hospital admitting affiliation cannot imply
employment; organization size alone cannot decide ownership; a record without an organizational
identifier is never treated as a resolved organization; classification depends only on its inputs;
any definitive classification must retain affirmative evidence; and neither contamination measure
may be removed from the released table. Each contract was verified by deliberate defect injection;
fifteen injected defects were detected, each for its intended reason.
