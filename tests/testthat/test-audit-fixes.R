# Audit-fix cycle -- adversarial tests for the round-1/round-2 bug fixes.
#
# MUTATION EVIDENCE (docs/SCIENTIFIC_CI_LAWS.md). Every contract here carries a negative
# control -- a demonstration that the ORIGINAL bug fails the test -- so a pass cannot come
# from a test that would green-light anything. The bugs these pin:
#   1. merge() multiplying rows on duplicated NPI keys (PSM study-database build)
#   2. churn: shared offices double-counted across arms; single-year offices written as
#      zero-churn when no turnover could have been observed
#   3. formatC space-padding character FIPS/GEOID input in the SVI zero-padding chain
#   4. timezone: silent Eastern default, no territories, no minority-zone cities
#   5. phone verification: dtype-fragile join and first-row-by-accident dedup

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)

# ---------------------------------------------------------------- timezone (4)

test_that("BVA: assign_time_zone covers territories and minority-zone cities", {
  expect_equal(assign_time_zone("PR"), "Atlantic",
               info = "Puerto Rico is Atlantic; the silent Eastern default must never return")
  expect_equal(assign_time_zone("GU"), "Chamorro")
  expect_equal(assign_time_zone("TX", "El Paso"), "Mountain",
               info = "El Paso is the minority zone of a split-timezone state")
  expect_equal(assign_time_zone("TX", "Dallas"), "Central")
  expect_equal(assign_time_zone("TN", "Memphis"), "Central")
  expect_equal(assign_time_zone("TN", "Knoxville"), "Eastern")
  expect_equal(assign_time_zone("FL", "Pensacola"), "Central")
  expect_equal(assign_time_zone("fl", "  pensacola "), "Central",
               info = "case and whitespace must not escape the minority-city match")
})

test_that("BVA: assign_time_zone stops on an unmapped state rather than defaulting", {
  expect_error(assign_time_zone("XX"), "No time zone mapping",
               info = "a silent default is how PR was mis-timed; the stop is the fix")
  expect_error(assign_time_zone(NA), "No time zone mapping")
  expect_error(assign_time_zone(""), "No time zone mapping")
})

test_that("adversarial: timezone_reference.csv cannot drift from assign_time_zone", {
  expect_true(file.exists(p("timezone_reference.csv")),
              info = "artifact missing -- regenerate with Rscript export_timezone_reference.R")
  ref <- utils::read.csv(p("timezone_reference.csv"), colClasses = "character")
  for (i in seq_len(nrow(ref))) {
    expect_equal(unname(assign_time_zone(ref$state[i], ref$city[i])), ref$timezone[i],
                 info = sprintf("artifact row %s/%s disagrees with the canonical function",
                                ref$state[i], ref$city[i]))
  }
  # Negative control: mutate one row of a copy and the same comparison MUST fail.
  mutant <- ref
  mutant$timezone[mutant$state == "PR" & mutant$city == ""] <- "Eastern"
  disagrees <- any(vapply(seq_len(nrow(mutant)),
                          function(i) assign_time_zone(mutant$state[i], mutant$city[i]) != mutant$timezone[i],
                          logical(1)))
  expect_true(disagrees,
              info = "negative control: if a tampered artifact passes, the comparison is vacuous")
})

test_that("adversarial: match_all_providers.py has no timezone table of its own", {
  src <- readLines(p("match_all_providers.py"), warn = FALSE)
  expect_false(any(grepl("STATE_TIMEZONES\\s*=", src)),
               info = "the third copy of the table must not come back; read timezone_reference.csv")
  expect_true(any(grepl("timezone_reference\\.csv", src)),
              info = "the Python pipeline must read the canonical artifact")
})

# ---------------------------------------------------------------- zero-padding (3)

zero_pad <- function(x, width) sprintf(paste0("%0", width, ".0f"), as.numeric(x))

test_that("BVA: the canonical zero-padding formulation pads short digit strings", {
  expect_equal(zero_pad("1001", 5), "01001")
  expect_equal(zero_pad("48201000100", 11), "48201000100",
               info = "11-digit GEOIDs survive exactly -- they overflow 32-bit integer")
  expect_equal(zero_pad("100100", 11), "00000100100",
               info = "short GEOIDs zero-pad on the left")
})

test_that("adversarial: the original formatC approach demonstrably fails this contract", {
  # Negative control: the bug being pinned is that formatC space-pads CHARACTER input
  # regardless of flag. If R ever 'fixes' formatC, this control goes red and the contract
  # above can be re-litigated deliberately; until then it proves the test discriminates.
  expect_false(identical(formatC("1001", width = 5, flag = "0"), "01001"),
               info = "formatC on character input is the bug; it must not satisfy the contract")
})

test_that("adversarial: zero_padding of digit strings never emits a leading space", {
  x <- c("1", "12", "123", "1234", "12345")
  expect_true(all(!grepl(" ", zero_pad(x, 5))),
              info = "a leading space fails every downstream FIPS match silently")
})

# ---------------------------------------------------------------- phone verification (3)

test_that("BVA: phone_verification counts agreeing sources, never NA dialed numbers", {
  v <- phone_verification(c("(561) 998-2001", NA, "5550001111"),
                          c("5619982001",      "5550001111", "5550001111"),
                          c(NA,                "5550001111", NA),
                          c("(561) 998-2001",  "5550001111", "0000000000"))
  expect_equal(v$Phone_Database_Matches, c(2L, 0L, 1L),
               info = "NA dialed cannot agree with anything, even a database unanimous about the office")
  expect_equal(v$Phone_Verification_Status[1], "Verified (2+ DBs)")
  expect_equal(v$Phone_Verification_Status[2], "Unverified")
  expect_match(v$Phone_Verification_Status[3], "Verified \\(1 DB: NPPES\\)")
})

test_that("adversarial: float-suffixed NPIs and punctuated phones cannot empty the join", {
  # The Python original compared raw values: a float-parsed NPI column matched nothing and
  # every row fell silently to Unverified. npi_key is the pinned contract for the join.
  expect_equal(npi_key("1003038688.0"), npi_key("1003038688"))
  expect_equal(npi_key(1003038688), npi_key("1003038688.0"),
               info = "numeric and float-suffixed spellings must produce one key")
  expect_equal(phone_key("(305) 273-4641"), phone_key("3052734641"),
               info = "punctuation variants of one number must produce one key")
})

test_that("adversarial: cross_reference_phones.R normalises keys and surfaces duplicates", {
  src <- readLines(p("cross_reference_phones.R"))
  expect_true(any(grepl("npi_key", src)),
              info = "the dtype-fragile pandas index lookup must not be reimplemented")
  expect_true(any(grepl("duplicated", src)),
              info = "duplicated NPIs must be detected, not collapsed by accident of row order")
})

# ---------------------------------------------------------------- merge dedupe + churn (4)

test_that("BVA: dedupe_first keeps the first row per key and reports the collapse", {
  df <- data.frame(NPI = c("a", "a", "b"), val = 1:3, stringsAsFactors = FALSE)
  expect_message(out <- dedupe_first(df, "NPI", "test"), "duplicated")
  expect_equal(out$val, c(1L, 3L),
               info = "first occurrence is the documented rule; match() semantics agree")
  expect_silent(dedupe_first(df[!duplicated(df$NPI), ], "NPI", "test"))
})

test_that("adversarial: a merge after dedupe_first cannot multiply rows", {
  # Both sides duplicated is the PSM case: pe_full_df and its mapping table derive from the
  # same frame, so each duplicated-NPI row matches EVERY mapping row -- quadratic growth.
  left  <- data.frame(NPI = c("a", "a", "b"), x = 1:3, stringsAsFactors = FALSE)
  right <- data.frame(NPI = c("a", "a", "b"), y = c(10, 11, 20), stringsAsFactors = FALSE)
  # Negative control first: the unguarded merge DOES multiply -- this is the bug being pinned.
  expect_true(nrow(merge(left, right, by = "NPI", all.x = TRUE)) > nrow(left),
              info = "negative control: if this ever fails, merge() semantics changed and re-litigate")
  guarded <- merge(dedupe_first(left, "NPI"), dedupe_first(right, "NPI"), by = "NPI", all.x = TRUE)
  expect_equal(nrow(guarded), 2L,
               info = "after first-occurrence dedupe on both sides the merge is row-preserving")
})

test_that("BVA: office_churn writes NA, never zero, for a single observed year", {
  one <- office_churn(2016, c("a", "b"))
  expect_true(is.na(one$Mean_Annual_Churn),
              info = "a single year is unmeasurable; 0.0 asserted turnover that could not be observed")
  expect_equal(one$Max_Staff_Count, 2L)
  multi <- office_churn(c(2015, 2016, 2016, 2017, 2017), c("a", "a", "b", "a", "c"))
  expect_equal(multi$Mean_Annual_Churn, 1,
               info = "steps: joined 1/1 then (1+1)/2 = 1.0 mean")
  expect_equal(multi$Total_Exits, 1)
  expect_equal(multi$Total_Entries, 2)
})

test_that("adversarial: within-year duplicate registry rows cannot inflate staff counts", {
  # The warehouse can carry two rows for one NPI in one year (multiple taxonomy records).
  # The original loop counted length(npi) -- treating one person as two staff -- and
  # double-counted their joins and exits.
  dup <- office_churn(c(2015, 2015, 2016), c("a", "a", "a"))
  expect_equal(dup$Max_Staff_Count, 1L,
               info = "one clinician listed twice is one member of staff")
  expect_equal(dup$Total_Entries, 0)
  expect_equal(dup$Total_Exits, 0)
})
