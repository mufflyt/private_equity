# Does the REAL, committed record-blinding crosswalk actually blind, right now?
#
# test-blinded-slot-assignment.R already proves assign_blinded_slots() -- the function -- is
# correct on synthetic input. That is not the same claim as "the artifact currently loaded into
# REDCap is correct": build_200_redcap_import.R asserts both invariants once, at generation
# time, on whatever it just built (see its own stopifnot() block), but nothing re-checks the
# committed file afterward. A hand edit, a stale regeneration, or a future build that silently
# drops that stopifnot() would all be invisible to CI. This file closes that gap by testing
# redcap/redcap_slot_crosswalk_400.csv itself -- the actual deployed mapping -- independently of
# how it was produced.
#
# redcap_slot_crosswalk_400.csv is committed (redcap/ is force-tracked in .gitignore) and needs
# no gitignored cohort data, so this runs anywhere, including CI.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)
xwalk <- utils::read.csv(p("redcap", "redcap_slot_crosswalk_400.csv"),
                         colClasses = "character", check.names = FALSE)

test_that("BVA: the crosswalk has the shape the blinding contract assumes", {
  expect_true(file.exists(p("redcap", "redcap_slot_crosswalk_400.csv")))
  expect_true(all(c("medicaid_record_id", "bcbs_record_id", "NPI", "pair_id", "ownership") %in%
                 names(xwalk)))
  expect_equal(nrow(xwalk), 400L,
              info = "one row per fielded clinician; 200 pairs x 2 clinicians")
  expect_equal(length(unique(xwalk$NPI)), 400L, info = "no clinician appears twice")
})

test_that("semantic: bcbs_record_id is medicaid_record_id + 400, the documented affine shift", {
  med <- as.integer(xwalk$medicaid_record_id)
  bcbs <- as.integer(xwalk$bcbs_record_id)
  expect_true(all(!is.na(med)) && all(!is.na(bcbs)))
  expect_equal(bcbs, med + 400L,
              info = paste("build_200_redcap_import.R defines bcbs_record_id = slot + n;",
                           "a constant shift preserves parity and adjacency from",
                           "medicaid_record_id, which is why checking medicaid_record_id alone",
                           "is sufficient below -- verified here rather than assumed"))
  expect_equal(sort(med), 1:400, info = "medicaid_record_id is a permutation of 1:400")
})

test_that("semantic: record parity does not predict ownership -- the exact defect this replaced", {
  med <- as.integer(xwalk$medicaid_record_id)
  odd <- med %% 2L == 1L
  pe_odd  <- sum(xwalk$ownership == "PE" & odd)
  pe_even <- sum(xwalk$ownership == "PE" & !odd)
  ctl_odd  <- sum(xwalk$ownership == "Non-PE" & odd)
  ctl_even <- sum(xwalk$ownership == "Non-PE" & !odd)
  expect_equal(pe_odd, 100L,
              info = sprintf("PE: %d odd / %d even (want 100/100) -- the shipped defect had",
                             pe_odd, pe_even))
  expect_equal(pe_even, 100L)
  expect_equal(ctl_odd, 100L)
  expect_equal(ctl_even, 100L)
})

test_that("semantic: no matched pair sits on consecutive record ids", {
  ordered <- xwalk[order(as.integer(xwalk$medicaid_record_id)), , drop = FALSE]
  adjacent <- sum(ordered$pair_id[-1L] == ordered$pair_id[-nrow(ordered)])
  expect_equal(adjacent, 0L,
              info = "the shipped defect put both members of every pair on consecutive ids")
})

test_that("semantic: every pair appears exactly twice, once per arm", {
  by_pair <- split(xwalk$ownership, xwalk$pair_id)
  expect_true(all(vapply(by_pair, length, integer(1)) == 2L),
             info = "every pair_id must have exactly 2 rows")
  expect_true(all(vapply(by_pair, function(g) setequal(g, c("PE", "Non-PE")), logical(1))),
             info = "every pair must be exactly one PE and one Non-PE clinician")
})

test_that("adversarial: reverts to the shipped defect are caught, not just novel ones", {
  # Reconstruct the leaked ordering (sort by pair, then PE_or_Not; "Non-PE" sorts first) on this
  # crosswalk's own clinicians, and confirm THAT ordering -- not the real one -- is what fails.
  # This is the regression test for the specific defect, not a generic randomness check.
  leaked_order <- xwalk[order(xwalk$pair_id, xwalk$ownership), , drop = FALSE]
  leaked_slot <- seq_len(nrow(leaked_order))
  # "Non-PE" sorts before "PE" alphabetically, so within each pair's 2 consecutive rows the
  # control lands first (odd position) and PE second (even) -- odd = control, even = PE, the
  # documented historical pattern, not the other way around.
  leaked_even_pe <- sum(leaked_order$ownership == "PE" & leaked_slot %% 2L == 0L)
  expect_equal(leaked_even_pe, sum(leaked_order$ownership == "PE"),
              info = "sanity check on the reconstruction: the leaked ordering must itself leak")
  leaked_adjacent <- sum(leaked_order$pair_id[-1L] == leaked_order$pair_id[-nrow(leaked_order)])
  expect_equal(leaked_adjacent, nrow(leaked_order) / 2L,
              info = "sanity check: the leaked ordering must put every pair adjacent")
})

# ---------------------------------------------------------------------------- regression: hash pin
#
# The invariant checks above (parity balance, no adjacency) would still pass if this file were
# silently regenerated with a different seed, or hand-edited, as long as the new version also
# happened to be blinded -- they check the CONTRACT, not that the specific, already-deployed
# mapping is unchanged. This file is "the only record of which id is which clinician" (see
# docs/APPENDIX_RECORD_BLINDING.md): if it silently changes, this repo's local copy stops
# agreeing with whatever is actually loaded into the live REDCap project, even though every
# invariant above would still be green. Pin the exact byte content so any change -- accidental
# regeneration, a hand edit, a bad merge -- is caught as a regression, not just a contract check.
test_that("regression: the committed crosswalk's content has not changed", {
  expect_equal(
    artifact_sha256(p("redcap", "redcap_slot_crosswalk_400.csv")),
    "4b937c1354d3a2fa03fcc76ed4ac9cdffdaf6d9bcf0293ada8def7d6673f4d57",
    info = paste("redcap_slot_crosswalk_400.csv changed. If this is a deliberate re-fielding or",
                "correction, update this hash deliberately and say so in the commit message --",
                "do not update it to silence a failure you have not investigated.")
  )
})
