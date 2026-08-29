# Supplementary Appendix S4. Analytic Output Provenance and Model Diagnostics

*Private equity ownership and appointment access in obstetrics and gynecology: a simulated-patient audit*

Prepared 2026-08-29. Companion to Supplementary Appendix S1 (statistical power), S2 (covariate
provenance and independence), and S3 (comparator validation). No outcome data exist; nothing
described here was fitted to observed results.

---

## S4.1 Purpose

Supplementary Appendix S2 documents an audit of the covariates entering the models. This
appendix documents the corresponding audit of what comes *out* of them: whether every quantity
the manuscript reports is produced by the analysis, on the scale in which it is reported, and
whether the models producing those quantities are checked for the conditions under which their
standard errors are interpretable.

The audit was prompted by a general finding recorded in the study repository: two
publication-shaped figures had been generated from values typed into a plotting script rather
than estimated from data. Those figures were relabeled and quarantined. The question this
appendix answers is whether the same class of defect could arise in the prose.

## S4.2 The gap between what was promised and what was computed

The Abstract reports its principal results in three forms: cell-level percentages and wait
times for the four ownership-by-payer combinations; effect estimates as an odds ratio and an
incidence rate ratio with 95% confidence intervals; and an absolute difference in percentage
points.

The frozen analysis plan prespecifies three models—primary obtainment among Medicaid calls,
primary wait time as an ownership-by-insurance interaction, and secondary obtainment across
both payers—and names a reporting scale for each estimand. At the time of the audit the
analysis document fitted all three models correctly and then applied only `summary()` to each.

That is a printed coefficient table on the **link** scale. Nothing in the analysis produced an
adjusted cell mean, an exponentiated effect estimate, a confidence interval on the reporting
scale, or the absolute difference. Populating the Abstract would therefore have required a
person to read log-odds from a console, exponentiate by hand, and transcribe the result: two
unrecorded operations on numbers destined for an abstract, with no artifact retaining what was
done. An odds ratio reported as its log-odds is not an imprecise number but a different one.

## S4.3 Adjusted cell means

The primary wait-time estimand is an interaction. An interaction coefficient describes how the
payer gap differs by ownership; it does not describe how long anyone waits. Both quantities are
needed—the interaction to test the hypothesis, the cell means to interpret it.

Adjusted marginal means for the four ownership-by-payer cells are now computed for both
outcomes on the response scale, using the marginal-effects function exported by the study's
analysis package rather than a locally written predictor, and are written to a serialized
artifact that the manuscript formats.

The approach was adopted from prior simulated-patient analyses conducted by this group in
orthopaedic sports medicine and otolaryngology, which interpret models of this shape through
estimated marginal means. A survey of those analyses is retained in the repository. Their use
of unadjusted bivariate tests alongside the models was deliberately **not** adopted, as
unplanned comparisons would weaken rather than strengthen a study with a frozen plan.

## S4.4 Effect estimates on the prespecified scale

Each prespecified estimand is now extracted from its fitted model in code. The estimand is read
from the frozen plan rather than named in the analysis document, so a mismatch between the plan
and the analysis is an error rather than a silent substitution. Wald intervals are formed on
the link scale and then transformed; forming them on the ratio scale can place the lower bound
of an odds ratio at or below zero. Results are written to a serialized artifact and a
comma-separated file.

## S4.5 The commercial-arm comparison

The Abstract reports a comparison of commercial-payer acceptance by ownership. The frozen plan
names no commercial-arm analysis, and the natural way to populate that sentence—fitting a model
to the commercial subset—would introduce an unplanned comparison into an abstract.

It is not necessary. The prespecified secondary obtainment model is fitted across both payers
as an ownership-by-insurance interaction, so the ownership main effect in that model is exactly
the ownership contrast among commercial calls. The reported quantity is therefore a component
of a prespecified model, and the analysis document now states which component it is. A separate
model fitted to the commercial subset alone is prohibited by an automated contract.

## S4.6 Convergence and singularity

No model in this repository had been checked for convergence.

This matters more than it may appear. Applying `summary()` to a model that failed to converge
prints a coefficient table indistinguishable from one that converged: estimates, standard
errors, and p-values, with no warning at the point of use. Those standard errors are precisely
what §S4.4 exponentiates into the reported confidence intervals. A false convergence does not
produce a visibly broken result; it produces a publishable one that is wrong.

The precedent is direct. In a prior simulated-patient study by this group of very nearly this
design, a mixed model failed to converge, and the sole detection mechanism was an investigator
noticing and commenting the model out. That is not a mechanism that scales to a frozen plan.

Every fitted model is now gated before any quantity is read from it, on three conditions
checked separately so that a failure identifies itself:

1. the optimizer reported successful convergence;
2. the Hessian is positive-definite, without which the printed standard errors are not
   trustworthy even though they are printed;
3. no random-effect standard deviation has collapsed to the boundary — the singular fit in
   which a grouping term estimates nothing while the model still reports convergence, so that
   the matched-pair clustering on which the design depends is silently absent from the model.

The gate stops the analysis rather than issuing a warning.

## S4.7 A prespecification gap, reported and not corrected

The Abstract declares **co-primary** outcomes—appointment obtainment and wait time—and the
frozen plan sets a single alpha of 0.05 with no provision for multiplicity across two primary
endpoints.

This is recorded here rather than corrected. Introducing a multiplicity adjustment would change
the decision rule of a frozen analysis plan. Outcomes are not yet observed, which is the only
circumstance in which such a change could be made legitimately, and equally the reason it must
be a deliberate, documented amendment rather than an incidental repair. The available options
are a recorded amendment to the plan, or an explicit decision to report both endpoints without
adjustment and to state that in the manuscript.

## S4.8 Verification

Each rule above is enforced by an automated contract that blocks the analysis if violated:
every quantity the Abstract reports at cell level must be computed on the response scale for
both outcomes; every prespecified estimand must be extracted on the scale the plan names, using
the plan's own term, with the interval formed on the link scale; results must be persisted
rather than left in a rendered console; the commercial-arm claim must derive from the
prespecified secondary model, and no model may be fitted to the commercial subset alone; and
every fitted model must pass the convergence gate before any quantity is read from it.

Each contract was verified by deliberate defect injection rather than by inspection. Two
contracts failed that verification when first written—each tested for the presence of a name
anywhere in the analysis document, a condition satisfied by an unrelated line—and were
rewritten to inspect the call sites themselves. Neither was found by reading.

## S4.9 Artifact availability

A related deficiency was identified in 2026-08 and is recorded for completeness. Several inputs
read by the automated contracts were present in the working directory but excluded from version
control by a repository-wide rule on data files, so that the contract suite could pass on the
originating machine while failing on a fresh copy. The comparator artifacts underlying
Supplementary Appendix S3 were among them and have been committed. An advisory contract now
enumerates the remaining files in that state and prevents the list from growing; several are
provider rosters whose versioning is a data-governance decision rather than a technical one.
