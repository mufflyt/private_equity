# The comparator estimand.
#
# The COMIRB protocol (v2, 2026-07-05) prespecifies the comparator as INDEPENDENT PRIVATE
# PRACTICES, in its title, its design, its objectives, its inclusion criteria and explicitly:
# "control candidates were drawn from the CMS Doctors and Clinicians registry, restricted to
# independent private practices". SAP.lock says "PE vs independent".
#
# The fielded controls do not demonstrably satisfy that. Organisation size was never enforced --
# the matcher never reads num_org_mem -- and the facility-name classifier admits on both its
# empty branch and its fall-through. Under the resolved classification, 0 of 200 controls are
# solo practitioners and 23 sit at or below ten clinicians.
#
# These contracts do not resolve that deviation. They stop it from being lost, stop the
# terminology from drifting away from what the code enforces, and make the measurement
# reproducible. The cohort is unchanged.

# MUTATION EVIDENCE, all reverted:
#   order-invariance   plant: switch 343 NPIs to a first-row value
#                      result: recomputation contract failed, and 23 -> a different count
#   conflict flagging  plant: un-flag one NPI whose rows straddle the threshold
#                      result: the ambiguity contract failed
#   terminology law    plant: make the matcher reference num_org_mem
#                      result: enforces_size became TRUE and the law failed, which is the
#                              behaviour wanted -- closing the deviation must force a recount
#
# The order-invariance law also carries its own positive control: it demonstrates that a
# first-row rule is NOT order-invariant, so the law is not vacuously satisfied by any rule.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p    <- function(...) file.path(root, ...)
rd   <- function(f) utils::read.csv(f, colClasses = "character", check.names = FALSE)

sheet <- rd(p("pe_obgyn_final_calling_sheet_200_dedup.csv"))
cls   <- rd(p("data", "covariates", "control_org_classification.csv"))
cand  <- rd(p("control_candidates_raw.csv"))
expo  <- readLines(p("export_control_candidates.py"), warn = FALSE)
psm   <- readLines(p("build_matched_control_group_psm.R"), warn = FALSE)
ms    <- paste(readLines(p("manuscript", "manuscript_cite.md"), warn = FALSE), collapse = "\n")

ctl <- npi_key(sheet$NPI[sheet$PE_or_Not == "Non-PE"])
i   <- match(ctl, npi_key(cls$npi))
res <- suppressWarnings(as.numeric(cls$org_size_resolved[i]))

# --------------------------------------------- law 1: classification cannot depend on row order

test_that("LAW: one NPI's organisation classification cannot depend on row order", {
  # NEGATIVE CONTROL: the resolved value must be invariant to the order of the source rows.
  # Recomputing from a reversed and from a randomly permuted candidate file must agree.
  org <- suppressWarnings(as.numeric(cand$num_org_mem)); k <- npi_key(cand$npi)
  resolve <- function(idx) {
    v <- tapply(org[idx], k[idx], function(x) if (all(is.na(x))) NA_real_ else max(x, na.rm = TRUE))
    v[order(names(v))]
  }
  fwd <- resolve(seq_along(k))
  rev <- resolve(rev(seq_along(k)))
  set.seed(7); shuf <- resolve(sample(seq_along(k)))
  expect_equal(fwd, rev)
  expect_equal(fwd, shuf)
  # POSITIVE CONTROL: a first-row rule is NOT order-invariant, which is why max() was chosen.
  first_of <- function(idx) {
    o <- org[idx]; kk <- k[idx]
    v <- o[match(sort(unique(kk)), kk)]
    stats::setNames(v, sort(unique(kk)))
  }
  expect_false(isTRUE(all.equal(first_of(seq_along(k)), first_of(rev(seq_along(k))))),
               info = "if first-row were order-invariant this law would be untestable here")
})

test_that("the shipped classification matches an order-invariant recomputation", {
  org <- suppressWarnings(as.numeric(cand$num_org_mem)); k <- npi_key(cand$npi)
  v <- tapply(org, k, function(x) if (all(is.na(x))) NA_real_ else max(x, na.rm = TRUE))
  # as.numeric() on both sides: tapply returns an array, so comparing it to a plain vector
  # fails on attributes while every value is identical.
  expect_equal(as.numeric(suppressWarnings(as.numeric(cls$org_size_resolved))[order(npi_key(cls$npi))]),
               as.numeric(v[order(names(v))]))
})

# --------------------------------------------- law 2: conflicts resolved or flagged

test_that("LAW: conflicting organisation records are resolved or explicitly flagged", {
  expect_true(all(c("n_source_rows", "org_size_min", "org_size_max", "facilities",
                    "ambiguous", "resolution_rule", "org_size_unknown") %in% names(cls)))
  expect_true(all(nzchar(trimws(cls$resolution_rule))),
              info = "a resolved value with no stated rule is a choice disguised as a fact")
  multi <- suppressWarnings(as.integer(cls$n_source_rows)) > 1L
  expect_equal(sum(multi), 6943L)
  # Every NPI whose rows straddle the threshold must be flagged, none silently resolved.
  mn <- suppressWarnings(as.numeric(cls$org_size_min))
  mx <- suppressWarnings(as.numeric(cls$org_size_max))
  should <- !is.na(mn) & !is.na(mx) & mn <= 10 & mx > 10
  expect_equal(toupper(cls$ambiguous) == "TRUE", should)
  expect_gt(sum(should), 0L)
  # Nothing is discarded: an NPI with several facilities keeps all of them.
  expect_true(any(grepl(" | ", cls$facilities, fixed = TRUE)))
})

# --------------------------------------------- law 3: terminology equals what the code enforces

test_that("LAW: no field may be called independent unless the code tests the criterion", {
  # The criterion the protocol names is independent PRACTICE. Organisation size is the
  # measurable form of it, and nothing enforces it.
  enforces_size <- any(grepl("num_org_mem", psm, fixed = TRUE)) ||
                   any(grepl("num_org_mem *[<>]", expo))
  expect_false(enforces_size,
               info = "if size is now enforced, this deviation may be closed; recount and update")
  # So a column or label asserting independence would be asserting an untested property.
  expect_false(any(grepl("^Independent", names(sheet))),
               info = "a column named Independent must not exist while nothing tests independence")
})

test_that("LAW: manuscript comparator terminology equals the operational definition", {
  # The Methods currently claims an exclusion the code does not perform. Until the deviation is
  # resolved, the claim and the code must be visibly inconsistent HERE rather than invisibly
  # inconsistent in the manuscript, so this pins the claim's presence and its falsity together.
  claims <- grepl("excluding academic and hospital-system", ms, fixed = TRUE)
  expect_true(claims, info = "if the claim was removed, update this contract and the audit")
  n_indep <- sum(res <= 10, na.rm = TRUE)
  expect_equal(n_indep, 23L,
               info = sprintf("%d of 200 fielded controls are at or below ten clinicians", n_indep))
  expect_equal(sum(res <= 1, na.rm = TRUE), 0L,
               info = "no fielded control is a solo practitioner")
})

test_that("the affected pair count is pinned at each defensible threshold", {
  # Reported so any cohort decision starts from numbers rather than impressions. Affected =
  # pairs that would be lost if controls above the threshold were excluded pairwise.
  for (t in c(5L, 10L, 25L, 50L, 100L)) {
    ok <- sum(res <= t, na.rm = TRUE)
    expect_equal(ok, c(`5` = 16L, `10` = 23L, `25` = 33L, `50` = 47L, `100` = 58L)[[as.character(t)]],
                 info = sprintf("threshold %d: %d controls qualify, %d pairs affected", t, ok, 200 - ok))
  }
})
