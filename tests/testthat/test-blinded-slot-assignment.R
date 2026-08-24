# Record numbering must not encode the exposure.
#
# The defect these tests exist to stop is not hypothetical: it shipped. The fielded REDCap
# dictionary was numbered by sorting on (Matched Pair ID, PE_or_Not). "Non-PE" sorts before
# "PE", so every one of the 200 pairs landed control-then-PE. Record parity predicted
# ownership perfectly -- odd = control, even = PE, 400 for 400 -- and the two members of a
# pair sat next to each other in the caller's dropdown. Blinding was defeated by the record
# id, which no @HIDDEN on an ownership field can fix.
#
# Every test below constructs that defect and asserts the new allocator does not reproduce it.
# This file needs no cohort CSV, so it runs in CI.

source(testthat::test_path("..", "..", "R", "pe_helpers.R"))

n     <- 400L
pair  <- rep(seq_len(n / 2L), each = 2L)
group <- rep(c("PE", "Non-PE"), n / 2L)

parity_split <- function(slot, group) {
  odd <- slot %% 2L == 1L
  c(pe_odd  = sum(group == "PE"     &  odd), pe_even  = sum(group == "PE"     & !odd),
    ctl_odd = sum(group == "Non-PE" &  odd), ctl_even = sum(group == "Non-PE" & !odd))
}
adjacent_pairs <- function(slot, pair) {
  by_slot <- as.character(pair)[order(slot)]
  sum(by_slot[-1L] == by_slot[-length(by_slot)])
}

test_that("adversarial: the shipped ordering is reproduced and shown to leak", {
  # arrange(pair, PE_or_Not) then row_number(), which is what build_200_redcap_import.R did.
  ord    <- order(pair, group)
  leaked <- integer(n); leaked[ord] <- seq_len(n)
  split  <- parity_split(leaked, group)
  # Parity is a perfect predictor: every control odd, every PE even.
  expect_equal(unname(split[["ctl_odd"]]), n / 2L)
  expect_equal(unname(split[["pe_odd"]]),  0L)
  # And every pair is adjacent.
  expect_equal(adjacent_pairs(leaked, pair), n / 2L)
})

test_that("the allocator returns a permutation of the slots", {
  expect_equal(sort(assign_blinded_slots(pair, group)), seq_len(n))
})

test_that("parity carries exactly zero information about the arm", {
  split <- parity_split(assign_blinded_slots(pair, group), group)
  expect_equal(unname(split[["pe_odd"]]),  n / 4L)
  expect_equal(unname(split[["pe_even"]]), n / 4L)
  expect_equal(unname(split[["ctl_odd"]]),  n / 4L)
  expect_equal(unname(split[["ctl_even"]]), n / 4L)
})

test_that("no matched pair lands on consecutive slots", {
  expect_equal(adjacent_pairs(assign_blinded_slots(pair, group), pair), 0L)
})

test_that("the arms are not blocked into low and high slots either", {
  # A parity-balanced allocation could still put every PE clinician in the first half.
  slot <- assign_blinded_slots(pair, group)
  pe_first_half <- sum(group == "PE" & slot <= n / 2L)
  expect_gt(pe_first_half, 70L)
  expect_lt(pe_first_half, 130L)
})

test_that("the allocation is reproducible from its seed and varies without it", {
  expect_identical(assign_blinded_slots(pair, group, seed = 1L),
                   assign_blinded_slots(pair, group, seed = 1L))
  expect_false(identical(assign_blinded_slots(pair, group, seed = 1L),
                         assign_blinded_slots(pair, group, seed = 2L)))
})

test_that("the invariants hold across many seeds, not just the one that was chosen", {
  for (s in 1:40) {
    slot  <- assign_blinded_slots(pair, group, seed = s)
    split <- parity_split(slot, group)
    expect_equal(unname(split[["pe_odd"]]), n / 4L, info = sprintf("seed %d", s))
    expect_equal(adjacent_pairs(slot, pair), 0L,    info = sprintf("seed %d", s))
  }
})

test_that("BVA: the allocator refuses inputs it cannot balance", {
  expect_error(assign_blinded_slots(pair[-1L], group), "same length")
  # Dropping two whole pairs keeps both arms even, so this must still succeed.
  expect_error(assign_blinded_slots(pair[-(1:4)], group[-(1:4)], seed = 1L), NA)
  # An odd number of records cannot split into equal parity halves.
  expect_error(assign_blinded_slots(pair[-1L], group[-1L]), "even number")
  # Nor can an arm of odd size.
  g <- group; g[1L] <- "Non-PE"
  expect_error(assign_blinded_slots(pair, g), "even size")
  # One arm is not a comparison.
  expect_error(assign_blinded_slots(pair, rep("PE", n)), "exactly 2 arms")
})

test_that("semantic: pair members stay together in the study, just not in the numbering", {
  slot <- assign_blinded_slots(pair, group)
  # Every pair still has exactly two members and one of each arm; only their slots moved.
  by_pair <- split(group, pair)
  expect_true(all(vapply(by_pair, length, integer(1)) == 2L))
  expect_true(all(vapply(by_pair, function(g) length(unique(g)) == 2L, logical(1))))
  expect_equal(length(unique(slot)), n)
})
