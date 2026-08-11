# Contracts for the shared-scheduler variables on the fielded sheet.
#
# The design assumes the clinician is the unit of independence. It is not, everywhere: 27 of
# the 400 fielded clinicians route through 12 shared practice lines, and two matched pairs put
# the PE clinician and their control on the same line, where a caller reaches one scheduler for
# both arms. build_phone_cluster_vars.R makes that structure explicit so it can be excluded or
# adjusted for rather than assumed away. These tests pin the structure it must describe.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)

sheet <- utils::read.csv(p("pe_obgyn_final_calling_sheet_200.csv"),
                         colClasses = "character", check.names = FALSE)
n_clin <- as.integer(sheet$clinicians_per_phone)
n_call <- as.integer(sheet$calls_per_phone)
pair   <- sheet[["Matched Pair ID"]]
same   <- toupper(trimws(sheet$same_phone_within_pair)) == "TRUE"

test_that("BVA: every clustering column is present and populated", {
  for (cn in c("phone_id", "phone_dialed", "clinicians_per_phone", "calls_per_phone",
               "pairs_per_phone", "same_phone_within_pair")) {
    expect_true(cn %in% names(sheet), info = sprintf("%s is missing", cn))
    expect_true(all(nzchar(trimws(ifelse(is.na(sheet[[cn]]), "", sheet[[cn]])))),
                info = sprintf("%s has blank rows", cn))
  }
})

test_that("BVA: no clinician is dialed on a number another clinician is also dialed on", {
  # The operational guarantee. phone_dialed is what the caller enters; a duplicate would mean
  # one office fielding four calls under two clinician identities without anyone noticing.
  d <- sheet$phone_dialed
  expect_equal(length(unique(d)), nrow(sheet),
               info = sprintf("%d duplicate dialed numbers", nrow(sheet) - length(unique(d))))
  expect_true(all(nchar(d) == 10L), info = "a dialed number must be ten digits")
})

test_that("BVA: cluster sizes agree with the groups they claim to count", {
  tb <- table(sheet$phone_id)
  expect_equal(n_clin, as.integer(tb[sheet$phone_id]),
               info = "clinicians_per_phone disagrees with the phone_id grouping")
  expect_equal(n_call, 2L * n_clin,
               info = "each clinician receives exactly two calls, one per insurance arm")
  expect_equal(sum(n_clin > 1L), 27L)
  expect_equal(length(unique(sheet$phone_id)), 385L)
})

test_that("semantic: an unresolvable practice number never collides with another", {
  # Rows with no usable practice phone and no usable address fall back to a per-NPI singleton
  # key. If they shared one key instead, they would be reported as a single large clinic.
  noph <- is.na(sheet$phone_practice) | !nzchar(trimws(ifelse(is.na(sheet$phone_practice), "", sheet$phone_practice)))
  if (any(noph)) {
    expect_true(all(n_clin[noph] == 1L),
                info = "clinicians with no resolvable practice line were merged into one cluster")
  } else {
    succeed()
  }
})

test_that("semantic: same_phone_within_pair is a property of the pair, not of the row", {
  by_pair <- tapply(same, pair, function(x) length(unique(x)) == 1L)
  expect_true(all(by_pair),
              info = "the two members of a pair disagree about whether they share a line")
})

test_that("adversarial: exactly the known contaminated pairs are flagged", {
  # pair_321 (P:9529207001, Edina/Minneapolis) and pair_437 (P:2037308789, Hartford/Danbury)
  # place both arms on one line. If a redraw changes this set the flag must move with it, so
  # this asserts the count and the identity together rather than hard-coding only the ids.
  flagged <- sort(unique(pair[same]))
  expect_equal(length(flagged), 2L,
               info = sprintf("flagged pairs: %s", paste(flagged, collapse = ", ")))
  expect_setequal(flagged, c("pair_321", "pair_437"))
  for (b in flagged) {
    ids <- unique(sheet$phone_id[pair == b])
    expect_equal(length(ids), 1L, info = sprintf("%s is flagged but spans %d lines", b, length(ids)))
    expect_setequal(sheet$PE_or_Not[pair == b], c("PE", "Non-PE"))
  }
})

test_that("adversarial: the clustering variables do not silently alter the sample", {
  expect_equal(nrow(sheet), 400L)
  expect_equal(length(unique(pair)), 200L)
  expect_equal(as.integer(table(sheet$PE_or_Not)[c("PE", "Non-PE")]), c(200L, 200L))
})

test_that("adversarial: no line carries more calls than the protocol contemplates", {
  # The two-calls-per-clinic guarantee is stated for offices. A line serving four clinicians
  # receives eight calls, which is a protocol departure whether or not it is acceptable, and
  # must be visible rather than inferred.
  worst <- max(n_call)
  expect_true(worst <= 8L,
              info = sprintf("one line receives %d calls", worst))
  expect_true(sum(n_call > 2L) == 27L,
              info = sprintf("%d clinicians sit on a line receiving more than two calls",
                             sum(n_call > 2L)))
})
