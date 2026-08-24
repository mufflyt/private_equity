# Pure helpers shared by the sampling and REDCap pipeline.
#
# Extracted verbatim from dedup_offices_and_backfill_200.R so they can be sourced and
# tested without executing a pipeline. Sourcing this file must have no side effects:
# it defines functions and nothing else.
#
# Contracts these functions are expected to honour are asserted in
# tests/testthat/test-pe_helpers.R. Change a contract there before changing it here.

# NPI is written as "1003038688.0" in pe_obgyn_study_database.csv but "1003038688" in
# the calling sheets, because pandas wrote a float column. Joining on the raw value
# silently matches nothing, which is the failure mode this exists to prevent.
npi_key <- function(x) sub("\\.0+$", "", trimws(as.character(x)))

# The dialed number, reduced to its last 10 digits. Anything shorter than 10 digits is
# not a dialable US number and returns NA rather than a truncated key, so that two
# unusable numbers never collide with each other.
phone_key <- function(x) {
  d <- gsub("\\D", "", ifelse(is.na(x), "", as.character(x)))
  ifelse(nchar(d) >= 10, substr(d, nchar(d) - 9, nchar(d)), NA_character_)
}

# Treat the several spellings of "no value" that appear across NPPES, CMS DAC and the
# scraped directories as equivalent to missing.
blank <- function(v) is.na(v) | v == "" | toupper(v) %in% c("N/A", "NAN", "NA")

# First non-blank value across a priority-ordered set of columns. Missing columns are
# skipped rather than erroring, because the study database and the calling sheets carry
# different subsets of the address fields.
coalesce_cols <- function(df, cols) {
  out <- rep(NA_character_, nrow(df))
  for (cn in cols) {
    if (!cn %in% names(df)) next
    v <- as.character(df[[cn]])
    out <- ifelse(blank(out) & !blank(v), v, out)
  }
  out
}

# Mirrors get_address_key() in build_matched_control_group_psm.R: same source priority
# and same suite-stripping regex, so office de-duplication agrees with the office_id
# assigned during matching. Returns NA when any component is missing, so that two
# unknown addresses never collide.
address_key <- function(df) {
  adr  <- coalesce_cols(df, c("Scraped Address", "NPPES Address 1", "DAC Address 1"))
  city <- coalesce_cols(df, c("DAC City", "NPPES City"))
  st   <- coalesce_cols(df, c("DAC State", "NPPES State", "Input State"))
  zip  <- coalesce_cols(df, c("DAC Zip", "NPPES Zip"))

  # Suite designators must be removed BEFORE separators are collapsed. Stripping
  # punctuation first destroys the word boundaries, after which "FL" matches the start
  # of FLAGLER and the greedy [0-9A-Z]* consumes the rest of the street name, silently
  # merging unrelated offices. Anchor on whole words while the gaps still exist.
  adr_up    <- gsub("[^A-Z0-9]+", " ", toupper(ifelse(is.na(adr), "", adr)))
  adr_up    <- gsub("\\b(SUITES|SUITE|STES|STE|UNIT|APT|FLOOR|FL|ROOM|RM|NUMBER|NO|DEPT|BLDG|BUILDING)\\b *[0-9A-Z]*",
                    "", adr_up)
  adr_clean <- gsub("[^A-Z0-9]", "", adr_up)
  city_clean <- gsub("[^A-Z0-9]", "", toupper(ifelse(is.na(city), "", city)))
  zip_clean  <- substr(gsub("\\D", "", sub("\\..*$", "", ifelse(is.na(zip), "", zip))), 1, 5)

  ok <- adr_clean != "" & city_clean != "" & nchar(zip_clean) == 5 & !blank(st)
  ifelse(ok, paste(adr_clean, city_clean, toupper(st), zip_clean, sep = "_"), NA_character_)
}

# Record numbering must not encode the exposure.
#
# The original build sorted by (pair, PE_or_Not) and numbered rows. "Non-PE" sorts before
# "PE", so every pair landed control-then-PE: record parity became a perfect predictor of
# ownership across all 200 pairs, and the two members of a pair sat adjacent in the dropdown.
# A caller who noticed either pattern was unblinded, and no @HIDDEN on an ownership field
# fixes that, because the leak is in the record id itself.
#
# This is a general risk for any two-arm matched-pairs mystery-caller study, not specific to
# this one, so the allocator now lives in mysterycall (mysterycall_assign_blinded_slots(),
# mufflyt/mysterycall#259) rather than staying a local reimplementation. Thin wrapper kept so
# call sites and this study's own tests don't need to change.
assign_blinded_slots <- function(pair, group, seed = 20260824L, max_tries = 1000L) {
  mysterycall::mysterycall_assign_blinded_slots(pair, group, seed = seed, max_tries = max_tries)
}

# One column, two spellings, depending on which database build you loaded.
#
# pe_obgyn_study_database.csv spells the coordinate columns "latitude"/"longitude"; the
# _with_churn build spells them "Latitude"/"Longitude". R's `$` does prefix matching, not
# case-insensitive matching, so db$Latitude on the lowercase build is NULL rather than an
# error -- and NULL then propagates into data.frame() as a differing-length argument, or into
# `nzchar(trimws(NULL)) && ...` as a zero-length condition, which is an error in R >= 4.2.
# Three separate call sites hit this: build_svi_covariate.R halted mid-run, and
# test-coordinate-integrity.R and test-geography-and-churn.R could not even load.
#
# Ask for the column by meaning, not by spelling.
col_ci <- function(df, nm) {
  hit <- match(tolower(nm), tolower(names(df)))
  if (is.na(hit)) NULL else df[[hit]]
}

# Hash an artifact so a generated output can name what it was built from.
#
# A figure that records its source and that source's digest can be checked; a figure that
# records nothing has to be trusted. The manuscript's two outcome figures were built from
# numbers typed into a script, and there was no place where that fact had to be written down.
artifact_sha256 <- function(path) {
  if (!file.exists(path)) return(NA_character_)
  if (!requireNamespace("digest", quietly = TRUE)) return(NA_character_)
  digest::digest(file = path, algo = "sha256")
}

#' Record what a publication-facing output was generated from.
#'
#' `sources` is a character vector of paths, or NA to declare explicitly that an output has no
#' source artifact -- which is the honest record for an illustrative figure, and the thing that
#' makes it detectable rather than merely undocumented.
record_output_provenance <- function(output, sources, generated_by, status,
                                     path = file.path("manuscript", "PROVENANCE.csv")) {
  rows <- data.frame(
    output       = basename(output),
    source       = if (all(is.na(sources))) "NONE" else paste(basename(sources), collapse = "; "),
    source_sha256 = if (all(is.na(sources))) "NONE"
                    else paste(vapply(sources, artifact_sha256, character(1)), collapse = "; "),
    generated_by = basename(generated_by),
    status       = status,
    stringsAsFactors = FALSE
  )
  old <- if (file.exists(path)) utils::read.csv(path, colClasses = "character") else NULL
  if (!is.null(old)) old <- old[old$output != rows$output, , drop = FALSE]
  utils::write.csv(rbind(old, rows), path, row.names = FALSE)
  invisible(rows)
}
