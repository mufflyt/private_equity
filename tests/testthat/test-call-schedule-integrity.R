# redcap_call_schedule_800.csv -- which of a clinician's two calls goes first, and how far
# apart -- had no test coverage at all until this file. It is generated independently of
# redcap_slot_crosswalk_400.csv (a different transmute() block in build_200_redcap_import.R,
# not derived from the crosswalk's own output), so the two files agreeing is not guaranteed by
# construction; it is exactly the kind of cross-artifact consistency a future edit to either
# generator could silently break without either file's own internal checks noticing.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)
sched <- utils::read.csv(p("redcap", "redcap_call_schedule_800.csv"),
                         colClasses = "character", check.names = FALSE)
xwalk <- utils::read.csv(p("redcap", "redcap_slot_crosswalk_400.csv"),
                         colClasses = "character", check.names = FALSE)

test_that("BVA: the schedule has the shape the calling protocol assumes", {
  expect_true(file.exists(p("redcap", "redcap_call_schedule_800.csv")))
  expect_true(all(c("PE_or_Not", "pair", "first_arm", "second_arm", "first_record_id",
                    "second_record_id", "min_hours_between_calls") %in% names(sched)))
  expect_equal(nrow(sched), 400L, info = "one row per clinician (both of a pair's calls)")
})

test_that("semantic: the two arms in every row are Medicaid and Blue Cross/Blue Shield, never the same twice", {
  expect_true(all(sched$first_arm != sched$second_arm))
  expect_true(all(sort(unique(c(sched$first_arm, sched$second_arm))) ==
                 c("Blue Cross/Blue Shield", "Medicaid")))
})

test_that("semantic: min_hours_between_calls matches the protocol's stated 48-hour minimum", {
  expect_true(all(as.numeric(sched$min_hours_between_calls) >= 48))
})

test_that("cross-artifact: the schedule and the crosswalk reference the exact same 800 record ids", {
  # Independently generated (see file header) -- this is not guaranteed by construction.
  sched_ids <- sort(as.integer(c(sched$first_record_id, sched$second_record_id)))
  xwalk_ids <- sort(as.integer(c(xwalk$medicaid_record_id, xwalk$bcbs_record_id)))
  expect_equal(sched_ids, xwalk_ids,
              info = "the schedule's 800 record ids must be exactly the crosswalk's 800, no more, no fewer")
  expect_equal(sched_ids, 1:800, info = "and together they must cover 1:800 with no gaps or duplicates")
})

test_that("semantic: first_arm correctly predicts which record-id range first_record_id falls in", {
  # Medicaid calls are record ids 1-400, BCBS calls 401-800 (SAP.lock; build_200_redcap_import.R).
  # A mismatch here would mean a caller's first dial routes to the wrong insurance arm's slot.
  first_id  <- as.integer(sched$first_record_id)
  second_id <- as.integer(sched$second_record_id)
  med_first <- sched$first_arm == "Medicaid"
  expect_true(all(first_id[med_first] <= 400L))
  expect_true(all(first_id[!med_first] > 400L))
  expect_true(all(second_id[med_first] > 400L))
  expect_true(all(second_id[!med_first] <= 400L))
})

test_that("adversarial: a schedule referencing a record id outside the crosswalk's universe is caught", {
  broken <- sched
  broken$first_record_id[1] <- "9001"
  sched_ids <- sort(as.integer(c(broken$first_record_id, broken$second_record_id)))
  xwalk_ids <- sort(as.integer(c(xwalk$medicaid_record_id, xwalk$bcbs_record_id)))
  expect_false(isTRUE(all.equal(sched_ids, xwalk_ids)),
              info = "the cross-artifact check above must actually be capable of failing")
})

# ---------------------------------------------------------------------------- regression: hash pin
test_that("regression: the committed call schedule's content has not changed", {
  expect_equal(
    artifact_sha256(p("redcap", "redcap_call_schedule_800.csv")),
    "6a59caf2368124589b57b96b23c9fc43ab7f3ca5ebdbd4444f015b8f2d4a526d",
    info = paste("redcap_call_schedule_800.csv changed. If this is a deliberate re-fielding or",
                "correction, update this hash deliberately and say so in the commit message --",
                "do not update it to silence a failure you have not investigated.")
  )
})
