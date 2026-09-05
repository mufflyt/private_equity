# Appendix: study-staff deidentification

## What happened

On 2026-09-05 an audit of the repository found three real study-staff given names committed in
`tests/testthat/test-pipeline-output-regression.R`. They appeared twice: once as the `initials`
fixture handed to `mysterycall_prepare_calls()`, and again in the expected `caller` output the
test asserts against.

Nothing flagged them. Every test in the suite asked whether the pipeline computed the right
answer; none asked whose name was in the input. The names entered in commit `9e98029`
("Add 10 CI regression tests pinning exact outputs..."), where they were almost certainly copied
from a real REDCap export while building a golden-value fixture.

REDCap's `initials` field is labelled *"Name of person completing form"*. Caller identity is
therefore data the study collected about a person, not incidental metadata.

## What was fixed

| Change | File |
|---|---|
| Fixture names replaced with synthetic ones (`avery`, `BRIAR`, `Avery`, `carson`, `briar`) | `tests/testthat/test-pipeline-output-regression.R` |
| Expected `caller` output updated to match | same |
| Salted hashes of the real names, so the repo can detect without containing | `config/staff_name_hashes.txt` |
| Regression guard, promoted to blocking | `tests/testthat/test-staff-deidentification.R` |

The mixed-case shape of the fixture was preserved exactly (`"x"`, `"Y"`, `"X"`, other, `"y"`),
because that casing is what exercises the normalisation the test asserts. The test still passes
19 assertions, unchanged in number.

## What the guard does and does not cover

**Covered.** No hashed staff name may appear anywhere under `tests/`. No committed `.csv` may
carry a caller-identity column (`initials`, `caller`, `caller_name`, `rater`, `interviewer`,
`staff`). Both are enforced on every push through `tests/BLOCKING`.

**Deliberately out of scope**, each for a reason stated in the test itself:

- **Author bylines in `manuscript/`.** That is attribution, governed by authorship. Removing a
  co-author's name from a byline is not a privacy fix.
- **Sibling-repository provenance references** (comments naming the repo a helper was ported
  from). Same character as a byline: it credits a source, it is not study data.
- **Free-text cells inside a committed `.csv`.** The column-level vector is guarded; a name
  buried in a `notes` cell is not. The upstream mitigation is that no REDCap free-text export is
  ever committed: `.gitignore` blanket-ignores `*.csv`, and the tracked ones are generated
  calling artifacts with fixed schemas.

## Open decision, not taken here

**The names remain in git history** — commits `9e98029`, `5cb7cb5`, `7c96199`, `b439b51`,
`2d277ed`. Removing them requires rewriting published history and force-pushing across every
clone, which invalidates outstanding branches and any external reference to a rewritten SHA.

That is a repository-owner decision with consequences outside this codebase, so it was **not**
taken as part of the code fix. The options, for whoever decides:

1. **Leave history as is.** The guard stops reintroduction; the exposure is three given names,
   without surnames, in a research-methods repository. Lowest operational risk.
2. **Rewrite history** (`git filter-repo`), force-push, and have every collaborator re-clone.
   Removes the names from the default branch's history but not from forks, existing clones, or
   any GitHub cache of the old objects.
3. **Make the repository private**, which removes the public exposure without a rewrite.

If the repository is or becomes public and the staff have not consented to being named, option 2
or 3 is the conservative reading. That judgement belongs to the PI and, if the staff are study
personnel under the COMIRB protocol, plausibly to COMIRB.

## Adding a name to the guard

Do **not** paste the name into any tracked file. Generate its hash and append only the digest:

```sh
Rscript -e 'cat(digest::digest(paste0("pe-obgyn-staff-deid-v1", tolower("NAME")),
                               algo = "sha256", serialize = FALSE), "\n")'
```

## Limits of the hash trick, stated plainly

The salt is committed and the space of given names is small, so these digests are brute-forceable
by anyone motivated. This is a **regression guard against reintroduction**, not a confidentiality
mechanism, and `config/staff_name_hashes.txt` says so at the top of the file.
