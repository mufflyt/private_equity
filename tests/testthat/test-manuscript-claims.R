# Manuscript claims registry: 3 BVA, 3 semantic, 4 adversarial.
#
# WHAT THIS GOVERNS. docs/MANUSCRIPT_PROVENANCE_AUDIT.md established, on 2026-08-24, what every
# publication-facing number in this repository actually is. That audit is prose: a human read
# it once, corrected nine stale values, and nothing has re-read it since. A number edited
# tomorrow silently leaves the audit describing a manuscript that no longer exists.
#
# manuscript/manuscript_claims.csv is that audit made machine-readable, and this file is the
# thing that re-reads it on every commit. The registry carries the audit's own status
# vocabulary, so the two cannot drift into different taxonomies.
#
# THE CONTRACT THAT MATTERS is bidirectional and is the reason a registry beats prose:
#   registry -> manuscript   every match_string must still be findable in its artifact, so
#                            editing a number without updating the registry fails.
#   manuscript -> registry   every bracketed placeholder in the Abstract must be registered as
#                            `unresolved`, so adding a new fabricated-looking value without
#                            declaring it fails.
# Checking only the first direction would let new unregistered claims accumulate freely.
#
# WHY `unresolved` IS THE STATUS THAT CARRIES THE MOST WEIGHT. Two figures in manuscript/ once
# showed PE Medicaid obtainment of 41.0% against 72.5% with confidence intervals, before a
# single call had been placed. The prose survived only because it kept the values in brackets;
# the figures rendered the same numbers with the brackets stripped. MC011 and MC012 are those
# two numbers. If they ever lose their brackets, this file fails.
#
# MUTATION EVIDENCE (Law 1, docs/SCIENTIFIC_CI_LAWS.md):
#   negative control  a registry row whose match_string is absent from its artifact must be
#                     reported (test 7). Runs live against a synthetic registry.
#   positive control  the same check where it IS present must report nothing (test 7).
#   end-to-end        2026-09-05, three mutations, each producing exactly one failure and
#                     exactly the right one:
#                       "across 26 states" -> "across 27 states"
#                         -> "adversarial: every registered claim is still present in its
#                            artifact" (MC003)
#                       one of the three "[41.0]" occurrences unbracketed
#                         -> "adversarial: no unresolved claim has lost its brackets" (MC011)
#                       a new bracketed "[77.7]" added to the Abstract
#                         -> "adversarial: every Abstract placeholder in the manuscript is
#                            registered"
#                     All reverted clean to 35 passed / 0 failed.
#
# THE SECOND MUTATION IS WHY THE BRACKET CHECK COUNTS RATHER THAN GREPS. Written the obvious
# way -- does "[41.0]" still appear? -- it PASSED with one of three occurrences unbracketed,
# because two remained. [41.0] appears in the Abstract, the Results prose and Table 2. The
# check now counts appearances of the bare number outside brackets and requires zero, which is
# the only form that catches the defect that actually happened to the figures.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
REG <- file.path(root, "manuscript", "manuscript_claims.csv")

# na.strings = character(0) is load-bearing. MC020's value and match_string are the literal
# string "NA" -- the de-clustering count that is deliberately not reproducible -- and read.csv
# converts "NA" to a missing value even under colClasses = "character". That turned the one row
# whose whole point is being explicitly unavailable into a row the locator could not evaluate.
claims <- utils::read.csv(REG, colClasses = "character", check.names = FALSE,
                          na.strings = character(0))

# The vocabulary is the audit's, verbatim. A status outside it means the registry and the audit
# have grown apart, which is the drift this file exists to prevent.
STATUSES <- c("verified", "stale", "simulated", "hard-coded", "external", "design", "unresolved")

artifact_path <- function(a) {
  p1 <- file.path(root, a); p2 <- file.path(root, "manuscript", a)
  if (file.exists(p1)) p1 else p2
}
artifact_text <- function(a) paste(readLines(artifact_path(a), warn = FALSE), collapse = "\n")

# Which registered rows cannot be found where they say they are.
missing_claims <- function(cl, reader = artifact_text) {
  out <- character(0)
  for (i in seq_len(nrow(cl))) {
    txt <- tryCatch(reader(cl$artifact[i]), error = function(e) NA_character_)
    if (is.na(txt)) { out <- c(out, sprintf("%s (artifact unreadable)", cl$claim_id[i])); next }
    if (!grepl(cl$match_string[i], txt, fixed = TRUE)) {
      out <- c(out, sprintf("%s (%s: '%s')", cl$claim_id[i], cl$artifact[i], cl$match_string[i]))
    }
  }
  out
}

# ---------------------------------------------------------------- BVA (3)

test_that("BVA: the registry parses, is non-empty, and has the declared columns", {
  need <- c("claim_id", "artifact", "claim", "value", "match_string", "status", "source",
            "verified_on", "notes")
  expect_equal(setdiff(need, names(claims)), character(0))
  expect_true(nrow(claims) > 0L)
  expect_false(any(duplicated(claims$claim_id)),
               info = "a duplicated claim_id makes a row unaddressable in a review")
  expect_true(all(grepl("^MC[0-9]{3}$", claims$claim_id)))
})

test_that("BVA: every status is in the audit's vocabulary and every date is a date", {
  bad <- setdiff(unique(claims$status), STATUSES)
  expect_equal(bad, character(0),
               info = paste("status(es) outside docs/MANUSCRIPT_PROVENANCE_AUDIT.md S2:",
                            paste(bad, collapse = ", ")))
  expect_true(all(grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", claims$verified_on)))
})

test_that("BVA: every artifact named in the registry exists", {
  for (a in unique(claims$artifact)) {
    expect_true(file.exists(artifact_path(a)),
                info = sprintf("registry names artifact '%s', which does not exist", a))
  }
})

# ---------------------------------------------------------------- semantic (3)

test_that("semantic: no claim is registered without a source", {
  expect_true(all(nzchar(trimws(claims$source))),
              info = "a claim with no source cannot be distinguished from a number someone typed")
  # An unresolved claim must say so in its source rather than name a file that would imply the
  # value was computed from something.
  unres <- claims[claims$status == "unresolved", , drop = FALSE]
  expect_true(nrow(unres) > 0L, info = "no unresolved claims registered; expected at least the Abstract placeholders")
  expect_true(all(grepl("NONE|NOT REPRODUCIBLE", unres$source)),
              info = "an unresolved claim names a source, which implies it was computed")
})

test_that("semantic: values corrected by the 2026-08-24 audit carry the corrected number", {
  # Nine values were stale and were corrected. Pinning three of them here means a revert to the
  # pre-audit number is caught, not just an arbitrary edit.
  corrected <- c(MC003 = "26", MC008 = "387", MC009 = "195")
  for (id in names(corrected)) {
    row <- claims[claims$claim_id == id, , drop = FALSE]
    expect_equal(nrow(row), 1L, info = sprintf("%s has left the registry", id))
    expect_equal(row$value, unname(corrected[id]),
                 info = sprintf("%s reverted to a pre-audit value", id))
  }
})

test_that("semantic: claims duplicated across artifacts agree with each other", {
  # The audit found manuscript_cite.md and appendix_data_provenance.md disagreeing on three
  # values. Same quantity, two documents, and nothing compared them.
  pairs <- list(c("MC003", "MC013"), c("MC008", "MC014"), c("MC009", "MC015"))
  for (p in pairs) {
    v <- claims$value[match(p, claims$claim_id)]
    expect_equal(v[1], v[2],
                 info = sprintf("%s and %s describe the same quantity and disagree: %s vs %s",
                                p[1], p[2], v[1], v[2]))
  }
})

# ---------------------------------------------------------------- adversarial (4)

test_that("adversarial: NEGATIVE and POSITIVE control on the locator", {
  fake <- data.frame(claim_id = c("MC900", "MC901"), artifact = "x.md",
                     match_string = c("present here", "absent entirely"),
                     stringsAsFactors = FALSE)
  reader <- function(a) "a line that is present here and nothing else"
  got <- missing_claims(fake, reader = reader)
  expect_length(got, 1L)
  expect_true(grepl("MC901", got), info = "the locator missed a claim that is not in the text")
  expect_length(missing_claims(fake[1, , drop = FALSE], reader = reader), 0L)
})

test_that("adversarial: every registered claim is still present in its artifact", {
  miss <- missing_claims(claims)
  expect_true(length(miss) == 0L,
              info = paste("claim(s) no longer findable ->", paste(miss, collapse = " | ")))
})

test_that("adversarial: no unresolved claim has lost its brackets", {
  # This is the specific defect that produced two publication-shaped figures with no
  # measurement behind them. The brackets are the only thing marking these as placeholders.
  unres <- claims[claims$status == "unresolved" & grepl("^\\[", claims$match_string), ,
                  drop = FALSE]
  expect_true(nrow(unres) >= 2L,
              info = "the Abstract placeholders have left the registry")
  for (i in seq_len(nrow(unres))) {
    txt <- artifact_text(unres$artifact[i])
    expect_true(grepl(unres$match_string[i], txt, fixed = TRUE),
                info = sprintf("%s: %s is no longer bracketed in %s",
                               unres$claim_id[i], unres$match_string[i], unres$artifact[i]))

    # EVERY occurrence must stay bracketed, not merely one. [41.0] appears three times in
    # manuscript_cite.md -- Abstract, Results prose, and Table 2 -- so a check that only asks
    # "does [41.0] still appear somewhere" passes while two of the three have been unbracketed.
    # That is precisely how the two simulated figures happened: the same placeholder values,
    # rendered with the brackets stripped. Count the bare number instead.
    bare <- sub("^\\[(.*)\\]$", "\\1", unres$match_string[i])
    if (identical(bare, unres$match_string[i])) next   # not a purely bracketed placeholder
    loose <- gregexpr(sprintf("(?<![\\[0-9.])%s(?![0-9.\\]])",
                              gsub("([.\\\\])", "\\\\\\1", bare)),
                      txt, perl = TRUE)[[1]]
    n_loose <- if (loose[1] == -1L) 0L else length(loose)
    expect_equal(n_loose, 0L,
                 info = sprintf("%s: %s appears %d time(s) WITHOUT brackets in %s",
                                unres$claim_id[i], bare, n_loose, unres$artifact[i]))
  }
})

test_that("adversarial: every Abstract placeholder in the manuscript is registered", {
  # The reverse direction. Without it, a new bracketed value could be added to the Abstract and
  # never declared, and the registry would still pass while describing less than it claims.
  txt <- readLines(artifact_path("manuscript_cite.md"), warn = FALSE)
  start <- grep("^#+\\s*Abstract", txt, ignore.case = TRUE)[1]
  skip_if(is.na(start), "manuscript_cite.md has no Abstract heading")
  rest <- txt[start:min(length(txt), start + 60L)]
  found <- unique(unlist(regmatches(rest, gregexpr("\\[[0-9][0-9.]*\\]", rest))))
  # Registered AT ALL, not registered-as-unresolved. [200] and [400] are bracketed design
  # values that the registry correctly calls `verified`; demanding `unresolved` would force a
  # true row to lie about its own status. The contract is that every bracketed value is
  # DECLARED, and its status says what kind of value it is.
  registered <- claims$match_string
  unregistered <- found[!vapply(found, function(f) any(grepl(f, registered, fixed = TRUE)),
                                logical(1))]
  expect_equal(unregistered, character(0),
               info = paste("bracketed Abstract value(s) not in the registry:",
                            paste(unregistered, collapse = ", ")))
})
