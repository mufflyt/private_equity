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
