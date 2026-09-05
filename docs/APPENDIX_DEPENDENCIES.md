# Appendix: dependency lockfile

## The gap

Nothing in this repository recorded what it was built against. `gates.yml` installs two GitHub
packages — `mysterycall` and `researchpaths` — from a **floating branch head**, so the code that
produced a number on one day and the code that produced it on another could differ with nothing
written down. The CRAN packages were unrecorded too.

For a study whose gates are its main defence against silent drift, that is a hole in the same
wall: `SAP.lock` freezes the model, `analysis_manifest.csv` freezes the provenance of every
column, and until now nothing froze the software.

## What was added

| File | Role |
|---|---|
| `config/dependencies.lock` | 39 records: 31 CRAN, 2 GitHub (with resolved 40-char SHAs), 6 PyPI, plus R and Python interpreter versions and a record date |
| `R/dependency_lock.R` | `read_lockfile()`, `scan_r_dependencies()`, `scan_py_dependencies()`, `lockfile_missing()`, `lockfile_drift()`. Sourcing has no side effects |
| `tests/testthat/test-dependency-lockfile.R` | 29 assertions, blocking |

```sh
Rscript R/dependency_lock.R           # packages the code loads but the lockfile omits
Rscript R/dependency_lock.R --drift   # lockfile vs. what is installed on this machine
```

## What is gated, and what deliberately is not

**Gated: completeness.** Every package the code actually loads must appear in the lockfile. This
compares the *code* against the *lockfile* and never reads the installed library, so it means the
same thing on a laptop and on a CI runner that installed different versions from RSPM.

**Not gated: version equality.** CI installs current CRAN; a developer has whatever they have. A
test demanding the two match would be red on every machine except the one that last regenerated
the file — a gate people learn to bypass, which is the exact failure `tests/BLOCKING` warns
about. `lockfile_drift()` reports that comparison for a human to act on instead.

## Open decision, not taken here: should `gates.yml` pin?

**This PR does not touch `gates.yml`.** The pin-versus-float question was already decided and
reverted in this repository:

- `79e1ced` pinned `gates.yml` to `mysterycall@42d66d92` and `researchpaths@26ec3f19`, arguing
  that a gate blocking every commit should not depend on a branch head someone else can move.
- `9844370` reverted it, with no stated reason.

Re-deciding it as a side effect of adding a lockfile would be relitigating someone else's call,
so the lockfile *records* the resolved SHAs and changes nothing about installation.

For whoever revisits it, the tradeoff and one new fact:

| | Float (current) | Pin |
|---|---|---|
| Upstream breaking change | Blocks every commit here, immediately | Cannot block; caught by `nightly.yml` instead |
| Upstream *fix* | Picked up automatically | Needs a deliberate SHA bump |
| Reproducibility | The gate's environment is unrecorded | The gate's environment is exact |

**New fact as of 2026-09-05:** `mysterycall`'s main has already moved from `42d66d92` (the SHA
the reverted pin named, and the one several source comments still cite) to
`36d72f1801f17ec3cf5c851b0bb0640f22e00cc2`. The floating install in `gates.yml` is therefore no
longer installing the build those comments describe. That is a fact, not an argument for either
option, and `nightly.yml` exists precisely to surface it.

A middle option, if the reason for the revert was the maintenance cost of bumping SHAs by hand:
pin `gates.yml` and let `nightly.yml` keep floating, which is what `79e1ced` actually proposed —
the nightly job's whole purpose is catching upstream drift on a schedule and reporting it through
a tracking issue rather than blocking day-to-day work.

## Regenerating

Versions are updated **by hand, deliberately, in their own commit** — the same discipline
`SAP.lock` uses. Run the two reports above, then edit `config/dependencies.lock`. Re-resolve a
GitHub SHA with:

```sh
gh api repos/mufflyt/mysterycall/commits/main --jq '.sha'
gh api repos/mufflyt/researchpaths/commits/master --jq '.sha'   # note: master, not main
```
