# Scientific CI: provenance / trust-a-number.
# read_manifest() already requires the source column to EXIST; it has never required it to be
# non-empty or non-placeholder. A column declared "measured" with a blank or "TBD" source would
# pass gate_provenance() -- which only checks that a source column is present, not what's in it
# -- while remaining exactly as untraceable as CDC_SVI was before it was caught. This is the
# check that closes that specific gap.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)

man <- read_manifest(p("analysis_manifest.csv"))

test_that("semantic: the tracked manifest has a real source for every cited-status column", {
  expect_error(gate_manifest_sources_populated(man), NA,
               info = paste("as committed, every measured/derived/outcome column in",
                            "analysis_manifest.csv must cite something other than blank or a",
                            "placeholder; if this fails, a column was added without a real",
                            "source"))
})

test_that("adversarial: a blank source on a 'measured' column is caught", {
  broken <- man
  broken$source[broken$status == "measured"][1] <- ""
  expect_error(gate_manifest_sources_populated(broken), "no real source",
               info = paste("an empty string is the easiest placeholder to introduce by",
                            "accident (e.g. a half-finished CSV edit) and must not silently",
                            "pass"))
})

test_that("adversarial: common placeholder tokens (TBD/TODO/UNKNOWN/?) are caught case-insensitively", {
  for (placeholder in c("TBD", "todo", "Unknown", "?", "n/a")) {
    broken <- man
    broken$source[broken$status == "derived"][1] <- placeholder
    expect_error(gate_manifest_sources_populated(broken), "no real source",
                 info = sprintf("'%s' reads as unsourced regardless of case", placeholder))
  }
})

test_that("BVA: a one-character or unusually terse but real-looking source is NOT flagged", {
  # The gate must not overreach into judging source *quality*, only presence/placeholder-ness --
  # that judgment belongs to a human reviewing the manifest, not to a mechanical gate.
  ok <- man
  ok$source[ok$status == "measured"][1] <- "NPPES"
  expect_error(gate_manifest_sources_populated(ok), NA,
               info = paste("a short but genuine source label must not be treated the same as",
                            "a placeholder; this gate checks for known placeholder tokens, not",
                            "for string length"))
})

test_that("BVA: 'identifier' and 'simulated' status columns are exempt from the source-cited rule", {
  # identifier columns (NPI, phone) don't carry a "source" the way a measurement does, and a
  # simulated column is supposed to say so honestly in its source, not be forced to fake one.
  broken <- man
  id_rows <- which(broken$status == "identifier")
  skip_if(length(id_rows) == 0, "no identifier-status rows in the current manifest to exercise")
  broken$source[id_rows[1]] <- ""
  expect_error(gate_manifest_sources_populated(broken), NA,
               info = paste("identifier-status columns are not in the cited-status set and",
                            "must not be swept into this check"))
})

test_that("provenance: the gate's pass message reports the true cited-status denominator", {
  # A gate that silently miscounts its own denominator is exactly the class of bug this whole
  # test file exists to prevent elsewhere; hold this gate to the same standard.
  n_cited <- sum(man$status %in% c("measured", "derived", "outcome"))
  expect_gt(n_cited, 0, label = "sanity: the manifest must actually contain cited-status rows")
  msg <- tryCatch({ gate_manifest_sources_populated(man); NULL },
                  message = function(m) conditionMessage(m))
  expect_match(msg, sprintf("%d/%d", n_cited, n_cited),
               info = paste("pass message must report N/N for the cited-status subset, not",
                            "the full manifest row count"))
})
