# Appendix: the repository's frozen contracts

**Date:** 2026-09-05. **Scope:** every machine-checked contract in this repository.
**Enforced by:** `tests/BLOCKING`, run by `hooks/pre-commit` locally and
`.github/workflows/gates.yml` on every push and pull request.

---

## S1. Why contracts rather than tests

This repository already had a habit worth naming: when something went wrong, the fix was not
only to correct the value but to write down what the value was allowed to be, in a file a person
can read, and have code re-read it. `SAP.lock` came from a power analysis silently substituting
a 2-degree-of-freedom joint test for the 1-degree-of-freedom interaction the plan named.
`analysis_manifest.csv` came from eight `rnorm()` columns presented as measurements.

The pattern generalises. A test asserts a fact; a contract *states* it, in a place a
non-programmer can audit, and the test only enforces it. When a contract and the world disagree,
the diff says which guarantee moved.

Four gaps in that coverage were closed on 2026-09-05.

## S2. The six contracts

| Contract | Governs | Enforced by |
|---|---|---|
| `SAP.lock` | The model: formula, family, subset, estimand, reporting scale | `gate_sap()`, `test-sap-contract-gates.R`, `test-estimand-drift.R` |
| `analysis_manifest.csv` | Every column: provenance, status, distributional family | `gate_provenance()`, `test-manifest-sources-populated.R` |
| `config/row_contract.yml` | Every **row**: counts, keys, pair balance, id coverage, cross-artifact agreement | `test-row-contract.R` |
| `config/dependencies.lock` | The **software** the analysis ran on | `test-dependency-lockfile.R` |
| `config/ci_contract.yml` | **CI itself**: triggers, commands, timeouts, which gates may never leave | `test-ci-contract.R` |
| `manuscript/manuscript_claims.csv` | Every **published number**: artifact, locator, provenance status, source | `test-manuscript-claims.R` |

Plus two guards that are contracts about *exposure* rather than about values:
`config/staff_name_hashes.txt` (`test-staff-deidentification.R`) and the pull-output ignore rules
(`test-redcap-pull-contract.R`).

## S3. What each new contract found on its first run

A contract that finds nothing on the day it is written is usually describing what someone
already believed. Four of these did not.

| Contract | Found |
|---|---|
| Row contract | `redcap/redcap_import_ready_200.csv` named the completion column `acost_three_dx_urogyn_2_complete` — the form of a **different study**, the IC vs POP vs SUI urogynecology project this repository was seeded from. REDCap silently ignores a completion column for a form it does not have: all 800 records would have imported with none marked complete. Fixed at both places the name lived. |
| Manuscript claims | The Abstract carries **ten** bracketed placeholder values. The 2026-08-24 provenance audit named five in prose; four were registered. The reverse-direction check found the other six. |
| CI contract | Nothing wrong with CI — but writing it exposed that `yaml::read_yaml()` returns a workflow's `on:` block under the name `"TRUE"`, so every trigger assertion written the obvious way passes **vacuously**. |
| REDCap pull contract | `.gitignore` un-ignores `redcap/` wholesale, so a real outcome export — which carries `initials`, REDCap's *"Name of person completing form"* — would have been **committable**. Found before any export existed. |

The deidentification guard is the fifth: it was written because three real study-staff given names
were sitting in a test fixture, and nothing was asking whose name was in the input.

## S4. Two lessons that generalise

**A membership check is not an agreement check.** The estimand drift report asks whether a scale
the manuscript prints is one the plan uses *anywhere*. "Odds ratio" is such a scale, so
relabelling the wait-time interaction from IRR to OR **passes** that test while saying something
false. The assertion that holds is each label against *its own* estimand's planned scale.

**Existence is not universality.** The bracket guard first asked "does `[41.0]` still appear?"
It appears three times in `manuscript_cite.md`. The check passed with one of the three
unbracketed — which is precisely how two publication-shaped figures came to render placeholder
values with the brackets stripped. Counting appearances *outside* brackets and requiring zero is
the only form that catches it.

Both are the same error: a check that can be satisfied by part of the data when the claim is
about all of it. Both were caught by mutation testing, not by review.

## S5. Verification recorded 2026-09-04

`redcap/PrivateVsPublicDoesEquityOwner_DataDictionary_2026-08-24_blinded.csv` was compared
field-by-field against a live API pull of REDCap project 40415. **18 fields, zero differences**,
including the 800-option `physician_name` dropdown. The committed dictionary is current, which is
what makes the row contract's `complete_form` rule meaningful — it checks against a dictionary
known to match the live instrument.

The project held **zero records** at that time. No call outcome has been collected yet.

## S6. Where the contracts do not reach

Stated so it is known rather than assumed:

- **Version equality is not gated.** `config/dependencies.lock` records versions; nothing fails
  when the installed set differs. CI installs current CRAN, and a test demanding a match would be
  red on every machine except the one that last regenerated the file.
- **Two Quarto documents cannot be rendered in CI.** `private_equity_manuscript.qmd` and
  `private_equity_title_page.qmd` read gitignored analysis output. `--no-execute` does not help:
  it skips chunks but still evaluates inline R.
- **Free-text cells inside committed CSVs are not scanned for staff names.** The column-level
  vector is guarded; a name in a `notes` cell is not.
- **Git history still contains the staff names.** See
  [`APPENDIX_DEIDENTIFICATION.md`](APPENDIX_DEIDENTIFICATION.md) — that is an owner decision.
- **`gates.yml` still installs two GitHub packages from a floating branch head.** See
  [`APPENDIX_DEPENDENCIES.md`](APPENDIX_DEPENDENCIES.md) — pinning was decided and reverted
  already, so this work did not re-decide it.

## S7. Decisions still open

Neither is a code change, and neither was taken here.

1. **Purge the staff names from git history?** Three options, with consequences, in
   `APPENDIX_DEIDENTIFICATION.md`. Repository owner, plausibly COMIRB.
2. **Should `gates.yml` pin its GitHub dependencies?** Tradeoff table in
   `APPENDIX_DEPENDENCIES.md`. One new fact: `mysterycall`'s main has already moved past the SHA
   several source comments still cite.

And one that belongs to the PI rather than the repository: the exclusion-code-to-outcome mapping
and the index-call rule are still absent from `SAP.lock`, so the obtainment endpoint is not yet
fully pre-specified. That matters before calling starts, not after.
