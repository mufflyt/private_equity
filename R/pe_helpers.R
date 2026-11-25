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
# this one, so the allocator lives in mysterycall (mysterycall_assign_blinded_slots(),
# mufflyt/mysterycall#259, merged as commit 42d66d92) rather than staying a local
# reimplementation. Thin wrapper kept so call sites and this study's own tests don't need to
# change.
#
# RE-DELEGATED 2026-08-25 after an intervening revert (2026-08-24) claimed the export "does
# not exist ... not in mysterycall's source at af004a1, not in its NAMESPACE". Re-verified
# from scratch rather than assumed: af004a14 is 14 commits BEHIND 42d66d92 on mysterycall's
# own history (`git merge-base --is-ancestor 42d66d92 af004a14` is false) -- it predates the
# merge, so of course it lacks the file; that is not evidence against the current export.
# Checked directly against the live GitHub API (`gh api repos/mufflyt/mysterycall/commits/main`)
# at delegation time: main's HEAD is 42d66d92, with R/assign_blinded_slots.R present. The
# installed package on THIS machine also has it (`exists("mysterycall_assign_blinded_slots")`
# is TRUE under a normal Rscript invocation) -- the earlier revert's "not in the installed
# package" reading is consistent with a *different* environment's stale local install (e.g. one
# that never ran `devtools::install()` after the merge, or one invoked with `Rscript --vanilla`,
# which skips ~/.Renviron's R_LIBS_USER and silently falls back to the system library where
# mysterycall was never installed) -- not with the export being genuinely absent. Both
# guarantees below were re-verified functionally before restoring this delegation: a fresh
# 400-record call (200 pairs, two arms) returns exact 100/100/100/100 parity balance and zero
# adjacent pairs. tests/testthat/test-blinded-slot-assignment.R (101 assertions) is the
# executable version of that same check and must pass before this commit lands.
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

# The REDCap `transfers` field is a dropdown, not a raw count: 1 = "No transfers", 2 = "One
# transfer", 3 = "Two transfers", 4 = "More than two transfers". Treating the stored value as
# the count itself is off by one for every row. A raw count of 3 and "more than two" are not
# distinguishable from this field alone, so 4 is capped at 3 rather than guessed, with an
# explicit censoring flag so a downstream analysis can tell the two apart if it needs to.
#
# @return a data.frame with `transfers` (0, 1, 2, or 3 = "3 or more") and `transfers_censored`
#   (TRUE where the true count could be higher than the reported 3).
decode_redcap_transfers <- function(x) {
  v <- suppressWarnings(as.integer(x))
  if (any(!is.na(v) & !(v %in% 1:4)))
    stop("transfers has value(s) outside the documented 1-4 dropdown range.", call. = FALSE)
  data.frame(transfers = pmin(v - 1L, 3L), transfers_censored = !is.na(v) & v == 4L)
}


# ------------------------------------------------------------------ gazetteer
#
# normalize_gazetteer() is the shared, fail-loud version of the schema adapter the matching
# pipeline documents inline in build_matched_control_group_psm.R. It exists because
# mysterycall's city_state_to_lat_long dataset has shipped under two schemas (full state
# names with latitude/longitude columns; state abbreviations with lat/long columns), and
# `$` partial matching silently rescues the wrong column for months before anyone notices.
# Everything downstream of this function sees exactly four columns -- city, state, lat,
# long -- whatever the package happens to ship. It errors rather than guesses.
#
# state_map: named character vector mapping full state names to two-letter abbreviations,
# used only when the gazetteer's state column is not already abbreviated. Base R's
# state.abb/state.name cover the 50 states; DC/PR/VI must be added by the caller.

#' Reduce any gazetteer schema to the pipeline contract: city, state, lat, long.
normalize_gazetteer <- function(g, state_map) {
  pick <- function(cands, what) {
    hit <- cands[cands %in% names(g)]
    if (!length(hit)) {
      stop(sprintf(paste0("Gazetteer has no %s column. Looked for: %s. Found: %s.\n",
                          "  The dependency's schema changed; extend normalize_gazetteer() ",
                          "rather than\n  relying on partial matching."),
                   what, paste(cands, collapse = ", "), paste(names(g), collapse = ", ")),
           call. = FALSE)
    }
    g[[hit[1]]]
  }

  raw_state <- pick(c("state", "state_abbrev", "STATE"), "state")
  out <- data.frame(
    city  = toupper(trimws(pick(c("city", "CITY"), "city"))),
    state = ifelse(nchar(trimws(raw_state)) == 2L, toupper(trimws(raw_state)),
                   unname(state_map[raw_state])),
    lat   = as.numeric(pick(c("lat", "latitude", "LAT"), "latitude")),
    long  = as.numeric(pick(c("long", "longitude", "lon", "lng", "LONG"), "longitude")),
    stringsAsFactors = FALSE
  )
  stopifnot(identical(names(out), c("city", "state", "lat", "long")))

  # Rows with a missing city, state or coordinate cannot match anything, but they are not
  # inert: an NA in the city column makes `df$city == x` evaluate to NA for that row, and
  # R's `[` then emits a phantom all-NA row at that position for EVERY lookup. The shipped
  # gazetteer carries exactly one NA-city row (position 17,364 of 31,909); because the
  # phantom sorted ahead of any real match sitting later in the table, every city past
  # that row silently resolved to NA coordinates even though its row was present. Drop
  # them here, once, so no call site has to remember this again.
  unusable <- is.na(out$city) | !nzchar(out$city) | is.na(out$state) | !nzchar(out$state) |
              is.na(out$lat) | is.na(out$long)
  if (any(unusable)) {
    message(sprintf("normalize_gazetteer: dropping %d row(s) with missing city/state/coordinates",
                    sum(unusable)))
    out <- out[!unusable, , drop = FALSE]
  }

  if (nrow(out) == 0L) {
    stop("Geocoding gazetteer is empty after normalisation: every row was dropped. ",
         "Check that the gazetteer's state column and state_map use the same vocabulary.")
  }
  out
}

# Base R's state.name/state.abb cover the 50 states; the cohort also draws on DC and the
# territories, which base R omits. Built once here rather than re-typed in every script
# that geocodes -- the hand-copied 52-entry tables in calculate_pair_distances.R and
# build_matched_control_group_psm.R had already drifted into two different orderings.
STATE_ABB_BY_NAME <- c(setNames(state.abb, state.name),
                       "District of Columbia" = "DC",
                       "Puerto Rico" = "PR",
                       "Virgin Islands" = "VI")


# ------------------------------------------------------------------ time zones
#
# Canonical time-zone assignment for the calling window, shared by every script that
# stamps a Time Zone column. The calling window is part of the measurement protocol in a
# mystery-caller study, so a mis-timed zone is a measurement defect, not a cosmetic one.
# This table exists because the defect has already happened twice: PR silently defaulted
# to Eastern (it is Atlantic), and a state-level table mis-times minority-zone cities in
# the 13 split-timezone states (the fielded sheet carried an Arlington TX office labelled
# "Eastern" and a Memphis TN office labelled "Eastern").
#
# The same mapping is exported to timezone_reference.csv by export_timezone_reference.R
# for the remaining Python pipeline pieces, and tests/testthat/test-timezone-reference.R
# proves the artifact and this function cannot drift apart.

TIME_ZONES <- c(
  'CT'='Eastern', 'ME'='Eastern', 'MA'='Eastern', 'NH'='Eastern', 'RI'='Eastern', 'VT'='Eastern',
  'NY'='Eastern', 'NJ'='Eastern', 'PA'='Eastern', 'DE'='Eastern', 'DC'='Eastern', 'MD'='Eastern',
  'VA'='Eastern', 'WV'='Eastern', 'NC'='Eastern', 'SC'='Eastern', 'GA'='Eastern', 'FL'='Eastern',
  'OH'='Eastern', 'MI'='Eastern', 'IN'='Eastern', 'KY'='Eastern',
  'AL'='Central', 'AR'='Central', 'IL'='Central', 'IA'='Central', 'KS'='Central', 'LA'='Central',
  'MN'='Central', 'MS'='Central', 'MO'='Central', 'NE'='Central', 'ND'='Central', 'OK'='Central',
  'SD'='Central', 'TN'='Central', 'TX'='Central', 'WI'='Central',
  'CO'='Mountain', 'MT'='Mountain', 'NM'='Mountain', 'UT'='Mountain', 'WY'='Mountain', 'ID'='Mountain',
  'AZ'='Mountain',
  'CA'='Pacific', 'NV'='Pacific', 'OR'='Pacific', 'WA'='Pacific',
  'AK'='Alaska', 'HI'='Hawaii',
  'PR'='Atlantic', 'VI'='Atlantic',
  'GU'='Chamorro', 'MP'='Chamorro', 'AS'='Samoa'
)

# Cities inside the minority time zone of a split-timezone state, for the states in which
# the minority zone contains a meaningful share of the population. The state table alone
# mis-times these offices (e.g. Pensacola FL is Central, not Eastern; El Paso TX is
# Mountain, not Central). Not exhaustive -- county-level granularity without a
# ZIP-to-timezone reference is not possible here -- but covers the population centers a
# sample is likely to draw. The value is the MINORITY zone; the state default covers
# everything else.
TZ_MINORITY_CITIES <- list(
  FL = list(zone = "Central", cities = c(
    "PENSACOLA", "PANAMA CITY", "DESTIN", "FORT WALTON BEACH", "CRESTVIEW", "NICEVILLE",
    "MILTON", "GULF BREEZE", "NAVARRE", "DEFUNIAK SPRINGS", "CHIPLEY", "MARIANNA",
    "BONIFAY", "PENSACOLA BEACH", "MARY ESTHER", "SHALIMAR", "VALPARAISO")),
  IN = list(zone = "Central", cities = c(
    "GARY", "HAMMOND", "EVANSVILLE", "MERRILLVILLE", "VALPARAISO", "MUNSTER", "HIGHLAND",
    "SCHERERVILLE", "CROWN POINT", "GRIFFITH", "EAST CHICAGO", "HOBART", "JASPER",
    "VINCENNES", "WASHINGTON", "PRINCETON", "MOUNT VERNON", "BOONVILLE", "NEWBURGH")),
  MI = list(zone = "Central", cities = c(
    "IRON MOUNTAIN", "IRONWOOD", "MENOMINEE", "KINGSFORD", "NORWAY", "IRON RIVER",
    "CRYSTAL FALLS", "STEPHENSON", "DAGGETT", "POWERS")),
  TX = list(zone = "Mountain", cities = c(
    "EL PASO", "SOCORRO", "HORIZON CITY", "SAN ELIZARIO", "FABENS", "FORT BLISS")),
  TN = list(zone = "Eastern", cities = c(
    "KNOXVILLE", "CHATTANOOGA", "JOHNSON CITY", "KINGSPORT", "BRISTOL", "OAK RIDGE",
    "CLEVELAND", "MARYVILLE", "MORRISTOWN", "GREENEVILLE", "SEVIERVILLE", "GATLINBURG",
    "PIGEON FORGE", "ATHENS", "HARRIMAN", "LENOIR CITY")),
  KY = list(zone = "Central", cities = c(
    "BOWLING GREEN", "OWENSBORO", "HOPKINSVILLE", "PADUCAH", "MURRAY", "MAYFIELD",
    "MADISONVILLE", "HENDERSON", "ELIZABETHTOWN", "FORT CAMPBELL", "GLASGOW", "RUSSELLVILLE")),
  ND = list(zone = "Mountain", cities = c(
    "DICKINSON", "WILLISTON", "BOWMAN", "BELFIELD", "KILLDEER", "BEULAH", "HAZEN", "CENTER")),
  SD = list(zone = "Mountain", cities = c(
    "RAPID CITY", "STURGIS", "SPEARFISH", "DEADWOOD", "LEAD", "HOT SPRINGS", "CUSTER",
    "HILL CITY", "WALL", "PHILIP", "WINNER", "MISSION", "MARTIN")),
  NE = list(zone = "Mountain", cities = c(
    "SCOTTSBLUFF", "GERING", "ALLIANCE", "CHADRON", "SIDNEY", "KIMBALL", "BRIDGEPORT",
    "OGALLALA", "IMPERIAL", "MCCOOK")),
  KS = list(zone = "Mountain", cities = c(
    "GOODLAND", "COLBY", "OAKLEY", "SHARON SPRINGS", "TRIBUNE", "LEOTI")),
  OR = list(zone = "Mountain", cities = c(
    "ONTARIO", "NYSSA", "VALE", "JORDAN VALLEY", "ADRIAN", "BURNS")),
  ID = list(zone = "Pacific", cities = c(
    "COEUR D'ALENE", "MOSCOW", "POST FALLS", "LEWISTON", "SANDPOINT", "HAYDEN",
    "RATHDRUM", "KELLOGG", "WALLACE", "OROFINO", "GRANGEVILLE"))
)

# Vectorised canonical assignment. Stops on any state it cannot map rather than silently
# defaulting to Eastern -- the silent default is how PR ended up mis-timed, and it must
# never come back. Geography decides; no scrape-era Time Zone column is consulted.
assign_time_zone <- function(state, city = NA_character_) {
  st <- toupper(trimws(ifelse(is.na(state), "", state)))
  ci <- toupper(trimws(ifelse(is.na(city), "", city)))
  out <- rep(NA_character_, length(st))
  for (i in seq_along(st)) {
    if (!nzchar(st[i]) || !(st[i] %in% names(TIME_ZONES))) {
      stop(sprintf("No time zone mapping for state '%s' (city '%s'). Add it to TIME_ZONES ",
                   st[i], ci[i]),
           "deliberately rather than inheriting a default; the calling window depends on it.",
           call. = FALSE)
    }
    z <- TIME_ZONES[[st[i]]]
    exc <- TZ_MINORITY_CITIES[[st[i]]]
    if (!is.null(exc) && nzchar(ci[i]) && ci[i] %in% exc$cities) z <- exc$zone
    out[i] <- z
  }
  out
}

# The full (state, city) -> zone reference as a data frame: one row per state with an
# empty city (the state default), plus one row per minority-zone city. This is what
# export_timezone_reference.R writes and what the Python pipeline reads, so there is one
# vocabulary for the calling window across both languages.
timezone_reference_df <- function() {
  base <- data.frame(state = names(TIME_ZONES), city = "",
                     timezone = unname(TIME_ZONES), stringsAsFactors = FALSE)
  exc <- do.call(rbind, lapply(names(TZ_MINORITY_CITIES), function(s) {
    e <- TZ_MINORITY_CITIES[[s]]
    data.frame(state = s, city = e$cities, timezone = e$zone, stringsAsFactors = FALSE)
  }))
  rbind(base, exc)
}


# ------------------------------------------------------------------ phone verification
#
# Count how many of the three phone databases (NPPES, CMS DAC, scraped) agree with the
# number being dialed, plus the human-readable status string the calling sheet carries.
# Extracted from dedup_offices_and_backfill_200.R so cross_reference_phones.R implements
# the same counting -- before this extraction the Python cross-referencer and the R dedup
# script were two implementations of one rule, free to drift.
#
# All inputs are character vectors of equal length; any may be NA. Keys are compared after
# phone_key() normalisation, so "float-suffixed" or punctuation-variant spellings of the
# same number cannot false-negative, and unresolvable numbers never count as agreeing.
phone_verification <- function(dialed, nppes, dac, scraped) {
  dk  <- phone_key(dialed)
  hits <- cbind(NPPES     = !is.na(dk) & !is.na(phone_key(nppes))   & dk == phone_key(nppes),
                `CMS-DAC` = !is.na(dk) & !is.na(phone_key(dac))     & dk == phone_key(dac),
                WebScrape = !is.na(dk) & !is.na(phone_key(scraped)) & dk == phone_key(scraped))
  hits[is.na(hits)] <- FALSE
  n <- rowSums(hits)
  first_src <- apply(hits, 1, function(r) if (any(r)) colnames(hits)[which(r)[1]] else NA_character_)
  data.frame(Phone_Database_Matches = as.integer(n),
             Phone_Verification_Status = ifelse(n >= 2, "Verified (2+ DBs)",
                                         ifelse(n == 1, sprintf("Verified (1 DB: %s)", first_src),
                                                "Unverified")),
             stringsAsFactors = FALSE)
}


# ------------------------------------------------------------------ merge safety

# merge() multiplies rows silently when the key is duplicated on either side. This keeps
# the first row per key with a loud count, so a downstream merge cannot fabricate rows and
# the arbitrariness of first-occurrence is visible rather than silent.
dedupe_first <- function(df, key, label = "") {
  k <- as.character(df[[key]])
  ndup <- sum(duplicated(k))
  if (ndup > 0)
    message(sprintf("dedupe_first: %s has %d duplicated '%s' row(s); keeping first occurrence.",
                    label, ndup, key))
  df[!duplicated(k), , drop = FALSE]
}

# ------------------------------------------------------------------ office churn

# Churn metrics for one office from its historical year/NPI panel: mean annual churn,
# total exits, total entries, max staff count.
#
# An office observed in a single year is UNMEASURABLE, not zero-churn: no turnover could
# have been observed, so Mean_Annual_Churn is NA. The zero-fill this replaces asserted no
# turnover for exactly the offices about which nothing could be said.
#
# The rate for a step is (joined + left) / prior-year staff. Steps are taken between
# consecutive OBSERVED years; a gap in the panel means one step spans several calendar
# years, which is a coarser measurement than annual -- callers with gappy panels should
# treat the mean accordingly.
office_churn <- function(year, npi) {
  years <- sort(unique(year))
  staff_counts <- vapply(years, function(y) length(unique(npi[year == y])), integer(1))
  churn_rates <- numeric(0)
  total_joined <- 0
  total_left <- 0
  if (length(years) > 1) {
    for (j in 2:length(years)) {
      cur  <- unique(npi[year == years[j]])
      prev <- unique(npi[year == years[j - 1]])
      joined <- sum(!cur %in% prev)
      left   <- sum(!prev %in% cur)
      total_joined <- total_joined + joined
      total_left   <- total_left + left
      base <- length(prev)
      churn_rates <- c(churn_rates, if (base > 0) (joined + left) / base else 0)
    }
  }
  list(Mean_Annual_Churn = if (length(churn_rates)) round(mean(churn_rates), 3) else NA_real_,
       Total_Exits       = total_left,
       Total_Entries     = total_joined,
       Max_Staff_Count   = if (length(staff_counts)) max(staff_counts) else 0L)
}
