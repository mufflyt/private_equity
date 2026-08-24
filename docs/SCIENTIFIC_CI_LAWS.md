# Scientific CI laws

Two rules learned from defects this repository actually produced. They are laws rather than
guidance because in both cases the failure mode was a green check that meant nothing.

## Law 1 — No scientific assertion without a positive and a negative control

A test that has never been shown to fail is not evidence. Before any scientific contract is
promoted to blocking, plant the defect it claims to detect, confirm it fails **and fails for the
stated reason**, then revert and confirm it passes.

Both halves are required. The negative control proves the test can fail; the positive control
proves it is not passing vacuously.

**Why.** `test-manuscript-provenance.R` shipped with a placeholder check whose regex used a
POSIX bracket class that never matched. It executed zero expectations, testthat reported it as
an *empty test*, and CI showed green. It was caught by unbracketing a value and watching
nothing fail.

**And why the positive half.** In `test-control-independence.R` the first draft asserted that
the matcher references `num_org_mem`. It does not — organisation size never enters control
eligibility. Without that positive control, the adjacent negative check would have been
satisfied by a matcher that read nothing at all.

A green result is not evidence when the test executes zero expectations, tests an empty vector,
tests simulated placeholders instead of analytic data, or succeeds because a pattern never
matched.

## Law 2 — Any audit result that could change the frozen cohort requires independent confirmation first

Reimplement the computation a second time, in a different language or by a different route,
before reporting it and before changing anything. If the two disagree, neither is a finding
until the disagreement is explained.

**Why.** Two audit results during the matching-lineage pass would have been catastrophic if
acted on:

| Claimed | Actual | Cause |
|---|---|---|
| 142 of 200 pairs beyond the 10-mile caliper, max 1,611 miles | 2 of 88 testable, max 34.4 | Read `Latitude`, not the matcher's `Matcher_Latitude`. Three coordinate columns exist; one decided the caliper |
| 215 excluded-platform clinicians matched | 23 | A row filter silently failed and scanned all 2,048 rows instead of the 1,022 grouped ones |

Neither reached a conclusion, because both were checked against a second implementation before
being written down. That was procedure in the second case and luck in the first; this law makes
it procedure in both.

A corollary: when two implementations disagree, the disagreement is itself a finding. The
2-record gap between the R and Python counts of control organisation size was caused by
`match()` taking the first row and a Python dict taking the last — which exposed 6,943
duplicated NPIs in the control candidate pool, 110 of them among the fielded controls, with
conflicting organisation sizes and facility names. Nothing else had noticed.

## Applying them

Every blocking scientific test records its mutation evidence in a comment at the head of the
section it governs: the planted defect, the observed failure, and the revert. Where a contract
cannot be mutation-tested, it says so and why.
