# Gates that stop the analysis rather than report on it afterwards.
#
# This repository already had roughly 640 test assertions when these were written, and the
# analysis would still run with 85 of them failing. Tests report; gates block. Every function
# here throws.
#
# Each gate corresponds to a defect that actually occurred in this project:
#
#   gate_provenance    CDC_SVI and seven sibling columns were rnorm() draws presented as
#                      measurements. Nothing about the values revealed it.
#   gate_missingness   CDC_SVI was present for 200/200 PE clinicians and 106/200 controls;
#                      a complete-case fit would have deleted 47% of the control arm on a
#                      basis related to exposure.
#   key_join_index     The NPI float suffix, the ZIP leading-zero loss, and a sprintf("%02s")
#                      that pads with spaces each produced a silent zero-row or partial join.
#                      The coverage check itself is mysterycall::mysterycall_safe_left_join();
#                      only the key normalisation is local.
#   gate_sap           A power analysis reported a 2-df joint test of "any ownership effect"
#                      as though it were the 1-df interaction the plan names.
#   gate_clustering    400 clinicians are reached through 385 practice lines; two matched
#                      pairs put both arms on one line.
#   gate_analytic_n    The power calculation gave all 800 calls a wait time. The study will
#                      observe about 622, and the identifying cell falls from 200 to ~82.
#
# Sourcing this file has no side effects.

suppressMessages(library(mysterycall))

GATE_ROOT <- tryCatch(normalizePath(file.path(dirname(sys.frame(1)$ofile), "..")),
                      error = function(e) getwd())

gate_fail <- function(gate, ...) {
  msg <- paste0(...)
  stop(sprintf("\n\n  GATE FAILED: %s\n  %s\n\n  This gate blocks the analysis deliberately. ",
               gate, gsub("\n", "\n  ", msg)),
       "Fix the data or the code.\n  Do not relax the gate to get a run to complete.\n",
       call. = FALSE)
}

gate_pass <- function(gate, ...) {
  message(sprintf("  [pass] %-22s %s", gate, paste0(...)))
  invisible(TRUE)
}

# ---------------------------------------------------------------------------- manifest

#' Read the provenance manifest.
#'
#' Every column that reaches a model must be declared here with a status and a distributional
#' family. A column that is not declared is not usable, which inverts the default: silence
#' means "unknown provenance", not "fine".
read_manifest <- function(path = file.path(GATE_ROOT, "analysis_manifest.csv")) {
  if (!file.exists(path)) gate_fail("manifest", "No provenance manifest at ", path)
  m <- utils::read.csv(path, colClasses = "character", check.names = FALSE)
  need <- c("column", "status", "family", "source")
  miss <- setdiff(need, names(m))
  if (length(miss)) gate_fail("manifest", "Manifest lacks columns: ", paste(miss, collapse = ", "))
  ok_status <- c("measured", "derived", "simulated", "identifier", "outcome")
  bad <- setdiff(unique(m$status), ok_status)
  if (length(bad)) gate_fail("manifest", "Unknown status value(s): ", paste(bad, collapse = ", "),
                             "\nAllowed: ", paste(ok_status, collapse = ", "))
  m
}

#' Gate 1. Provenance.
#'
#' @param df       the analytic data frame
#' @param analytic character vector of columns that will enter a model
#' @param manifest as returned by read_manifest()
gate_provenance <- function(df, analytic, manifest = read_manifest()) {
  undeclared <- setdiff(analytic, manifest$column)
  if (length(undeclared)) {
    gate_fail("provenance",
              "Analytic variable(s) absent from analysis_manifest.csv:\n    ",
              paste(undeclared, collapse = "\n    "),
              "\n\n  A variable with no declared source cannot be distinguished from a ",
              "simulation.\n  Add it to the manifest with its status, family and source.")
  }
  rows <- manifest[match(analytic, manifest$column), , drop = FALSE]

  sim <- rows$column[rows$status == "simulated"]
  if (length(sim)) {
    gate_fail("provenance",
              "Simulated variable(s) entering a model:\n    ",
              paste(sprintf("%s  (%s)", sim, rows$source[rows$status == "simulated"]),
                    collapse = "\n    "),
              "\n\n  These are not measurements. Source them or remove them from the model.")
  }

  present <- intersect(analytic, names(df))
  if (length(present) != length(analytic)) {
    gate_fail("provenance", "Analytic variable(s) missing from the data frame: ",
              paste(setdiff(analytic, names(df)), collapse = ", "))
  }

  for (i in seq_len(nrow(rows))) gate_family(df[[rows$column[i]]], rows$column[i], rows$family[i])
  gate_pass("provenance", sprintf("%d analytic variable(s) declared and measured", length(analytic)))
}

#' Distributional contract implied by a variable's declared family.
#'
#' A percentile rank is uniform on [0,1] by construction, which is the property the simulated
#' CDC_SVI column failed: it rejected uniformity at P < 0.001 while failing to reject normality
#' at P = 0.985. The uniformity check is deliberately lenient (P > 0.001) so that a genuinely
#' non-representative sample of tracts does not trip it; it is aimed at a generated column, not
#' at sampling variation.
gate_family <- function(x, nm, family) {
  v <- suppressWarnings(as.numeric(x))
  v <- v[!is.na(v)]
  if (!length(v) && family %in% c("percentile", "proportion", "count", "continuous")) {
    gate_fail("family", nm, " has no non-missing numeric values")
  }
  chk <- function(cond, why) if (!isTRUE(cond)) gate_fail("family", nm, " (", family, "): ", why)

  switch(family,
    percentile = {
      chk(all(v >= 0 & v <= 1), sprintf("values outside [0,1]: min %.4f max %.4f", min(v), max(v)))
      clamp <- (isTRUE(all.equal(min(v), 0.01)) || isTRUE(all.equal(max(v), 0.99)))
      chk(!clamp, "extremes sit exactly on 0.01 / 0.99, the signature of a pmax/pmin clamp")
      chk(mean(v == min(v)) < 0.02 && mean(v == max(v)) < 0.02,
          "more than 2% of values pile on an extreme, which a percentile rank does not do")
      if (length(v) >= 30) {
        p <- suppressWarnings(stats::ks.test(v, "punif", 0, 1)$p.value)
        chk(p > 0.001, sprintf("rejects Uniform(0,1) at P = %.3g; a percentile rank should not", p))
      }
    },
    proportion = chk(all(v >= 0 & v <= 100), "values outside [0,100]"),
    count      = {
      chk(all(v >= 0), "negative count")
      chk(all(abs(v - round(v)) < 1e-8), "non-integer count")
    },
    continuous  = chk(all(is.finite(v)), "non-finite values"),
    identifier  = invisible(NULL),
    categorical = invisible(NULL),
    gate_fail("family", nm, ": unknown family '", family, "'")
  )
  invisible(TRUE)
}

# ---------------------------------------------------------------------------- missingness

#' Gate 2. Missingness must not depend on exposure.
#'
#' Delegates to mysterycall::mysterycall_gate_missingness(), which was promoted into the
#' package from this file so that every mystery-caller study inherits it rather than
#' re-deriving it. See docs/CANONICAL_SOURCES_AUDIT.md (A3). Only the study's default arm
#' column and the pass message are local.
gate_missingness <- function(df, analytic, arm_col = "PE_or_Not", alpha = 0.01) {
  if (!arm_col %in% names(df)) gate_fail("missingness", "No arm column '", arm_col, "'")
  out <- tryCatch(
    mysterycall::mysterycall_gate_missingness(df, vars = analytic, exposure = arm_col,
                                              alpha = alpha, action = "error"),
    error = function(e) gate_fail("missingness", conditionMessage(e)))
  gate_pass("missingness", sprintf("independent of arm for %d covariate(s)", length(analytic)))
  invisible(out)
}

# ---------------------------------------------------------------------------- joins
#
# There is no local join gate any more. mysterycall already exports the canonical ones:
#
#     mysterycall::mysterycall_safe_left_join(left, right, by, min_coverage = , ...)
#     mysterycall::mysterycall_safe_inner_join()
#     mysterycall::mysterycall_safe_semi_join()
#     mysterycall::mysterycall_safe_anti_join()
#     mysterycall::mysterycall_assert_unique_keys(.data, key_cols)
#
# They cover more than the local assert_join() did -- key uniqueness on the right-hand side,
# a duplication ceiling, and an optional written report -- and they are tested in the package.
# See docs/CANONICAL_SOURCES_AUDIT.md (A4).
#
# `key_join_index()` remains only because the study joins by a repaired key rather than by a
# shared column: the NPI is stored as "1003038688.0" in one artifact and "1003038688" in
# another, so the key has to be normalised on both sides before any join verb can see it. It
# delegates the coverage check to mysterycall rather than reimplementing it.

#' Match `x` into `table` on a normalised key, verifying coverage with mysterycall.
#'
#' @param key_fun applied to both sides before matching, e.g. `npi_key`
#' @param min_match required match rate; passed to mysterycall as `min_coverage`
key_join_index <- function(x, table, min_match = 1.0, label = "join", key_fun = identity) {
  lhs <- data.frame(.key = key_fun(x), stringsAsFactors = FALSE)
  rhs <- data.frame(.key = key_fun(table), stringsAsFactors = FALSE)
  rhs <- rhs[!duplicated(rhs$.key), , drop = FALSE]
  rhs$.present <- TRUE

  joined <- tryCatch(
    mysterycall::mysterycall_safe_left_join(
      lhs, rhs, by = ".key",
      min_coverage = min_match,
      label_left  = label,
      label_right = paste0(label, " (reference)")),
    error = function(e) gate_fail("join", label, ": ", conditionMessage(e),
                                  "\n\n  A partial join is how the NPI float suffix and the ZIP ",
                                  "zero-truncation reached the data.\n  Check for type coercion ",
                                  "and padding before widening the tolerance."))

  rate <- mean(!is.na(joined$.present))
  gate_pass("join", sprintf("%s matched %.1f%% of %d keys", label, 100 * rate, nrow(lhs)))
  match(lhs$.key, rhs$.key)
}

# ---------------------------------------------------------------------------- SAP lock

read_sap <- function(path = file.path(GATE_ROOT, "SAP.lock")) {
  if (!file.exists(path)) gate_fail("sap", "No frozen SAP at ", path)
  ln <- readLines(path, warn = FALSE)
  ln <- ln[!grepl("^\\s*#", ln) & nzchar(trimws(ln))]
  k <- trimws(sub("=.*$", "", ln))
  v <- trimws(sub("^[^=]*=", "", ln))
  stats::setNames(as.list(v), k)
}

norm_formula <- function(f) {
  s <- if (inherits(f, "formula")) paste(deparse(f), collapse = " ") else as.character(f)
  gsub("\\s+", " ", trimws(s))
}

#' Gate 4. The model about to be fitted must be the model the plan names.
#'
#' @param formula the formula being fitted
#' @param key     the SAP key prefix, e.g. "waittime_primary"
#' @param family  optional family name to check
gate_sap <- function(formula, key, family = NULL, sap = read_sap()) {
  fk <- paste0(key, "_formula")
  if (is.null(sap[[fk]])) gate_fail("sap", "SAP.lock has no entry '", fk, "'")
  want <- norm_formula(sap[[fk]])
  got  <- norm_formula(formula)
  if (!identical(want, got)) {
    gate_fail("sap",
              "The model does not match the frozen analysis plan.\n",
              "    plan: ", want, "\n",
              "    code: ", got,
              "\n\n  If the plan should change, amend SAP.lock, record the reason in its ",
              "amendments block,\n  and regenerate its hash. Do not edit the plan to match ",
              "an exploratory model.")
  }
  if (!is.null(family)) {
    wf <- sap[[paste0(key, "_family")]]
    if (!is.null(wf) && !identical(trimws(wf), trimws(as.character(family)))) {
      gate_fail("sap", key, " family: plan says ", wf, ", code uses ", family)
    }
  }
  gate_pass("sap", sprintf("%s matches the frozen plan", key))
  invisible(sap[[paste0(key, "_estimand")]])
}

#' Every assumed magnitude must cite a source.
gate_sourced_constants <- function(sap = read_sap()) {
  consts <- grep("^effect_.*[^e]$|^effect_.*_irr$", names(sap), value = TRUE)
  consts <- consts[!grepl("_source$", consts)]
  missing <- consts[!paste0(consts, "_source") %in% names(sap)]
  if (length(missing)) {
    gate_fail("constants", "Assumed magnitude(s) with no recorded source: ",
              paste(missing, collapse = ", "),
              "\n\n  The superseded 1.167 interaction was invented rather than derived. ",
              "Cite or remove.")
  }
  empty <- consts[vapply(paste0(consts, "_source"),
                         function(k) !nzchar(trimws(sap[[k]])), logical(1))]
  if (length(empty)) gate_fail("constants", "Empty source for: ", paste(empty, collapse = ", "))
  gate_pass("constants", sprintf("%d assumed magnitude(s) sourced", length(consts)))
}

sap_hash <- function(path = file.path(GATE_ROOT, "SAP.lock")) {
  body <- readLines(path, warn = FALSE)
  body <- body[!grepl("^# *sha256", body)]
  if (requireNamespace("digest", quietly = TRUE)) {
    digest::digest(paste(body, collapse = "\n"), algo = "sha256")
  } else {
    tf <- tempfile(); writeLines(body, tf)
    on.exit(unlink(tf))
    sub(" .*$", "", system(sprintf("shasum -a 256 %s", shQuote(tf)), intern = TRUE))
  }
}

sap_write_hash <- function(path = file.path(GATE_ROOT, "SAP.lock")) {
  h <- sap_hash(path)
  ln <- readLines(path, warn = FALSE)
  ln <- ln[!grepl("^# *sha256", ln)]
  writeLines(c(ln, sprintf("# sha256 = %s", h)), path)
  message("SAP.lock hash written: ", h)
  invisible(h)
}

# ---------------------------------------------------------------------------- structure

#' Gate 5. The declared clustering unit must exist and must describe the data.
gate_clustering <- function(df, unit, expect_n = NULL, max_size = NULL) {
  if (!unit %in% names(df)) gate_fail("clustering", "No clustering column '", unit, "'")
  k <- df[[unit]]
  if (any(is.na(k) | !nzchar(trimws(as.character(k))))) {
    gate_fail("clustering", unit, " has blank values; those rows would silently form one cluster")
  }
  n <- length(unique(k))
  sz <- max(table(k))
  if (!is.null(expect_n) && n != expect_n) {
    gate_fail("clustering", sprintf("%s yields %d clusters; %d were expected", unit, n, expect_n))
  }
  if (!is.null(max_size) && sz > max_size) {
    gate_fail("clustering", sprintf("largest %s cluster holds %d rows; the limit is %d",
                                    unit, sz, max_size))
  }
  gate_pass("clustering", sprintf("%s: %d clusters, largest %d rows", unit, n, sz))
}

#' Gate 6. The analytic sample must be the size the design implies.
#'
#' `expected` is a named vector of cell counts. A deviation beyond `tol` means the analysis is
#' fitting something other than the design that was powered.
gate_analytic_n <- function(observed, expected, tol = 0.05, label = "analytic N") {
  nm <- union(names(observed), names(expected))
  o <- as.numeric(observed[nm]); o[is.na(o)] <- 0
  e <- as.numeric(expected[nm]); e[is.na(e)] <- 0
  rel <- ifelse(e > 0, abs(o - e) / e, ifelse(o > 0, Inf, 0))
  bad <- which(rel > tol)
  if (length(bad)) {
    gate_fail("analytic n",
              label, " departs from the powered design:\n    ",
              paste(sprintf("%-24s observed %6.0f  expected %6.0f  (%.0f%%)",
                            nm[bad], o[bad], e[bad], 100 * rel[bad]), collapse = "\n    "),
              "\n\n  Power was computed for the expected counts. If the observed counts are ",
              "correct,\n  the power statement must be recomputed before the result is ",
              "interpreted.")
  }
  gate_pass("analytic n", sprintf("%s within %.0f%% of the powered design", label, 100 * tol))
}

# ---------------------------------------------------------------------------- preflight

#' Gate 7. Geographic joins on `tract_geoid` must share one Census vintage.
#'
#' ACS tract boundaries change at each redistricting; a 2010-vintage GEOID and a 2020-vintage
#' GEOID can be the same 11 digits in shape while identifying different geography. There is no
#' vintage column anywhere in this pipeline -- `tract_geoid` is a bare string on both sides of
#' every join -- so a future re-fetch on the wrong vintage would produce a join that succeeds
#' (same format, no error) while silently attaching each clinician's covariates to the wrong
#' tract. The only thing that would reveal that today is the match rate collapsing, which is
#' exactly what this gate checks instead of waiting for someone to notice.
#'
#' @param min_overlap required fraction of `left`'s distinct GEOIDs found in `right`
gate_tract_geoid_vintage <- function(left, right, left_col = "tract_geoid",
                                     right_col = "tract_geoid", min_overlap = 0.90,
                                     label = "tract_geoid vintage") {
  l <- as.character(left[[left_col]]); l <- l[nzchar(l) & !is.na(l)]
  r <- as.character(right[[right_col]]); r <- r[nzchar(r) & !is.na(r)]
  if (!length(l)) gate_fail(label, "left side has no non-empty ", left_col, " values")

  bad_len <- unique(nchar(l))[!unique(nchar(l)) %in% 11L]
  if (length(bad_len)) {
    gate_fail(label, "GEOID(s) not 11 characters (state+county+tract): lengths ",
              paste(bad_len, collapse = ", "),
              "\n\n  A short GEOID is usually a dropped leading zero, not a genuine mismatch, ",
              "but either way\n  it cannot be a valid 2020-vintage census tract identifier.")
  }

  overlap <- length(intersect(unique(l), r)) / length(unique(l))
  if (overlap < min_overlap) {
    gate_fail(label,
              sprintf("only %.1f%% of %d distinct GEOIDs on the left are found on the right ",
                      100 * overlap, length(unique(l))),
              "(need >= ", sprintf("%.0f%%", 100 * min_overlap), ").",
              "\n\n  Real 2010-vs-2020 tract boundaries overlap at a small fraction of this rate ",
              "because\n  redistricting splits and merges most tracts. This collapse is the ",
              "signature of joining\n  across a vintage boundary, not of ordinary missing data. ",
              "Check which vintage each side\n  was fetched on (search for 'vintage=' / ",
              "'Census2020_Current' / the ACS survey year) before\n  treating this as a coverage ",
              "problem to patch over.")
  }
  gate_pass(label, sprintf("%.1f%% GEOID overlap (%d distinct)", 100 * overlap, length(unique(l))))
}

# ---------------------------------------------------------------------------- power-curve output

#' Gate 8. A power-curve results table must be internally arithmetic-consistent and finite.
#'
#' Every power scenario in this pipeline is defined by a physician count, an arm count and a
#' calls-per-physician count that are supposed to multiply together; a scenario where they do
#' not is a scenario where someone edited one column (typically `Pairs`, to explore a new grid)
#' without regenerating the derived ones. Power itself is a probability: an NA/NaN/Inf value or
#' one outside [0,1] means a fit failed silently rather than a real result of 0 or 1.
#'
#' This does NOT check which denominator (e.g. all 800 calls vs. an obtainment-adjusted count)
#' is scientifically correct for a given scenario -- that is an estimand choice made at the call
#' site, not something a generic integrity check can decide. It only checks that whatever
#' denominator a row claims is the one its own other columns imply.
gate_power_curve_integrity <- function(df, pairs_col = "Pairs", physicians_col = "Physicians",
                                       calls_col = "Total_Calls", power_col = "Power",
                                       arms = 2L, label = "power curve") {
  need <- c(pairs_col, physicians_col, calls_col, power_col)
  miss <- setdiff(need, names(df))
  if (length(miss)) gate_fail(label, "missing column(s): ", paste(miss, collapse = ", "))

  p <- suppressWarnings(as.numeric(df[[power_col]]))
  bad_finite <- which(!is.finite(p))
  if (length(bad_finite)) {
    gate_fail(label, sprintf("%d row(s) have non-finite %s (NA/NaN/Inf); row(s): %s",
                             length(bad_finite), power_col, paste(bad_finite, collapse = ", ")),
              "\n\n  A silently failed model fit looks like a missing value here, not an error. ",
              "Trace which\n  simulation produced it before trusting any power number in the ",
              "same table.")
  }
  bad_range <- which(p < 0 | p > 1)
  if (length(bad_range)) {
    gate_fail(label, sprintf("%d row(s) have %s outside [0,1]: %s",
                             length(bad_range), power_col,
                             paste(sprintf("%.4f", p[bad_range]), collapse = ", ")))
  }

  physicians <- suppressWarnings(as.numeric(df[[physicians_col]]))
  pairs      <- suppressWarnings(as.numeric(df[[pairs_col]]))
  calls      <- suppressWarnings(as.numeric(df[[calls_col]]))
  want_phys  <- 2 * pairs
  bad_phys   <- which(abs(physicians - want_phys) > 1e-8)
  if (length(bad_phys)) {
    gate_fail(label, sprintf("%d row(s): %s != 2 x %s (1 PE + 1 control per pair); row(s): %s",
                             length(bad_phys), physicians_col, pairs_col,
                             paste(bad_phys, collapse = ", ")))
  }
  want_calls <- arms * physicians
  bad_calls  <- which(abs(calls - want_calls) > 1e-8)
  if (length(bad_calls)) {
    gate_fail(label, sprintf("%d row(s): %s != %d x %s (%d insurance arm(s) per physician); row(s): %s",
                             length(bad_calls), calls_col, arms, physicians_col, arms,
                             paste(bad_calls, collapse = ", ")))
  }
  gate_pass(label, sprintf("%d row(s) finite, in-range, and arithmetic-consistent", nrow(df)))
}

# ---------------------------------------------------------------------------- manifest sources

#' Gate 9. Every non-simulated, non-identifier manifest entry must cite a real source.
#'
#' `read_manifest()` already requires the `source` column to exist; it does not require it to
#' be non-empty or non-placeholder. A column marked "measured" with a blank or "TBD" source is
#' indistinguishable, to gate_provenance(), from one with a real citation -- it would pass
#' gate_provenance() while still being untraceable to anyone reading the manifest. This is the
#' check that closes that gap, run over the whole manifest rather than only the columns a given
#' model happens to use.
gate_manifest_sources_populated <- function(manifest = read_manifest(),
                                            placeholder = c("TBD", "TODO", "UNKNOWN", "?", "N/A", "NA")) {
  cited_statuses <- c("measured", "derived", "outcome")
  rows <- manifest[manifest$status %in% cited_statuses, , drop = FALSE]
  blank <- rows$column[!nzchar(trimws(rows$source))]
  vague <- rows$column[toupper(trimws(rows$source)) %in% toupper(placeholder)]
  bad <- union(blank, vague)
  if (length(bad)) {
    gate_fail("manifest sources",
              "Column(s) with status in {", paste(cited_statuses, collapse = ", "),
              "} but no real source:\n    ", paste(bad, collapse = "\n    "),
              "\n\n  A manifest entry that says 'measured' with an empty or placeholder source ",
              "is exactly the\n  gap that let CDC_SVI enter the model as a measurement while ",
              "actually being rnorm().\n  Cite the real source or change the status to ",
              "'simulated'.")
  }
  gate_pass("manifest sources", sprintf("%d/%d cited-status column(s) have a real source",
                                        nrow(rows) - length(bad), nrow(rows)))
}

#' Gate 10. A computed business-days-to-appointment column must match the canonical calculator.
#'
#' There is no local business-day arithmetic in this pipeline, and there should not be: getting
#' Mon-Fri-excluding-federal-holidays counting right by hand is exactly the kind of thing that
#' looks correct on a spot check and is quietly wrong on the case that matters (a call placed the
#' Friday before a federal Monday holiday, a same-day appointment, a multi-week span). The
#' canonical calculator is mysterycall_count_business_days(): start_date exclusive, end_date
#' inclusive, `end_date < start_date` or either NA returns NA, `end_date == start_date` returns 0.
#' This gate does not recompute the arithmetic itself; it re-derives the column from the raw
#' dates via that canonical function and asserts agreement, so a hand-rolled `as.numeric(appt -
#' call)` (which counts calendar days, includes weekends, and is off by the inclusive/exclusive
#' boundary) fails loudly instead of silently corrupting the primary outcome.
#'
#' @param df           data frame holding the raw dates and the already-computed column
#' @param call_col     column of call dates (Date, POSIXct, or "YYYY-MM-DD" character)
#' @param appt_col     column of appointment dates, same accepted types
#' @param computed_col column already claiming to hold business days from call_col to appt_col
#' @param calendar     passed through to mysterycall_count_business_days(); NULL uses its
#'                     built-in 2021-2036 US federal holiday calendar
gate_business_days_correct <- function(df, call_col = "call_date", appt_col = "appointment_date",
                                       computed_col = "business_days_until_appointment",
                                       calendar = NULL, label = "business days") {
  need <- c(call_col, appt_col, computed_col)
  miss <- setdiff(need, names(df))
  if (length(miss)) gate_fail(label, "missing column(s): ", paste(miss, collapse = ", "))

  want <- mysterycall::mysterycall_count_business_days(df[[call_col]], df[[appt_col]],
                                                       calendar = calendar)
  got  <- suppressWarnings(as.numeric(df[[computed_col]]))

  both_na <- is.na(want) & is.na(got)
  mism <- which(!both_na & (is.na(want) != is.na(got) | want != got))
  if (length(mism)) {
    show <- head(mism, 10)
    gate_fail(label,
              sprintf("%d/%d row(s) disagree with mysterycall_count_business_days(); row(s): %s%s",
                      length(mism), nrow(df), paste(show, collapse = ", "),
                      if (length(mism) > 10) ", ..." else ""),
              "\n\n  Detail for the first mismatch (row ", mism[1], "): ", call_col, " = ",
              as.character(df[[call_col]][mism[1]]), ", ", appt_col, " = ",
              as.character(df[[appt_col]][mism[1]]), ", stored ", computed_col, " = ",
              format(got[mism[1]]), ", canonical value = ", format(want[mism[1]]),
              "\n\n  Recompute ", computed_col, " with mysterycall::mysterycall_business_days() ",
              "or\n  mysterycall::mysterycall_count_business_days() rather than manual date ",
              "arithmetic.")
  }
  gate_pass(label, sprintf("%d row(s) match mysterycall_count_business_days()", nrow(df)))
}

# ---------------------------------------------------------------------------- overdispersion

#' Gate 11. A fitted Poisson model must not be overdispersed; if it is, say so and name the fix.
#'
#' Wait time, hold time, transfer count and calls-per-office are all counts in this study, and
#' count data this heterogeneous (physician-level random effects, insurance-arm heterogeneity,
#' a small number of clinics driving many calls) is routinely overdispersed -- which is exactly
#' why the frozen analysis plan already specifies glmmTMB(..., family = nbinom2) rather than
#' Poisson (SAP.lock; see also run_new_power_analysis.R's header note on the glm.nb-vs-glmmTMB
#' choice). A Poisson fit understates standard errors under overdispersion, which overstates
#' significance -- a silent false positive, not a crash, which is why this needs to be a gate
#' and not just a reviewer's habit of remembering to check. Uses the standard Pearson
#' chi-square/df dispersion statistic; a well-specified Poisson model has this near 1.
#'
#' Only fires for a Poisson family. A model already fit as negative-binomial (family name
#' matching "Negative Binomial" or "nbinom", e.g. MASS::glm.nb or glmmTMB(family = nbinom2))
#' passes without comment, since that is already the recommended remedy, not the defect.
#'
#' @param model     a fitted model with `family()`, `residuals(type = "pearson")` and
#'                  `df.residual()` methods (glm, MASS::glm.nb, glmmTMB, ...)
#' @param threshold dispersion ratio above which a Poisson fit is flagged
gate_overdispersion <- function(model, threshold = 1.5, label = "overdispersion") {
  fam <- tryCatch(family(model)$family, error = function(e) NA_character_)
  if (is.na(fam)) {
    gate_fail(label, "could not determine the model's family via family(model)$family; ",
              "pass a glm, MASS::glm.nb, or glmmTMB object")
  }
  if (grepl("negative binomial|nbinom", fam, ignore.case = TRUE)) {
    gate_pass(label, sprintf("family '%s' is already negative-binomial; not applicable", fam))
    return(invisible(TRUE))
  }
  if (!grepl("poisson", fam, ignore.case = TRUE)) {
    gate_pass(label, sprintf("family '%s' is neither Poisson nor negative-binomial; not applicable", fam))
    return(invisible(TRUE))
  }

  df_resid <- tryCatch(df.residual(model), error = function(e) NA_real_)
  if (is.na(df_resid) || df_resid <= 0) {
    gate_fail(label, "model has no usable residual degrees of freedom (df.residual() <= 0 or NA)")
  }
  pr <- tryCatch(residuals(model, type = "pearson"), error = function(e) {
    gate_fail(label, "could not extract Pearson residuals via residuals(model, type = 'pearson')")
  })
  ratio <- sum(pr^2, na.rm = TRUE) / df_resid

  if (ratio > threshold) {
    gate_fail(label,
              sprintf("Pearson dispersion ratio %.2f exceeds the threshold of %.2f for a Poisson fit",
                      ratio, threshold),
              "\n\n  A ratio this far above 1 means the variance is not equal to the mean the way ",
              "a Poisson\n  model assumes; standard errors from this fit are too small and P-",
              "values too optimistic.\n  Refit with MASS::glm.nb(...) or glmmTMB(..., family = ",
              "nbinom2), which this study's\n  own frozen plan already specifies for its count ",
              "outcomes. Do not raise `threshold` to make\n  this pass -- that hides the same ",
              "problem it is built to catch.")
  }
  gate_pass(label, sprintf("Pearson dispersion ratio %.2f (Poisson fit, threshold %.2f)",
                           ratio, threshold))
}

#' Run every gate that can be run before a model is fitted.
#'
#' Call this at the top of an analysis script. It throws on the first failure.
analysis_preflight <- function(df, analytic, arm_col = "PE_or_Not",
                               clustering_unit = NULL, expected_cells = NULL,
                               observed_cells = NULL, manifest = read_manifest(),
                               sap = read_sap()) {
  message("\n=== analysis preflight ===")
  gate_sourced_constants(sap)
  gate_provenance(df, analytic, manifest)
  gate_missingness(df, analytic, arm_col)
  if (!is.null(clustering_unit)) gate_clustering(df, clustering_unit)
  if (!is.null(expected_cells) && !is.null(observed_cells)) {
    gate_analytic_n(observed_cells, expected_cells)
  }
  svi <- sap[["svi_column"]]
  if (!is.null(svi) && !svi %in% analytic) {
    message(sprintf("  [note] SAP names %s as the deprivation covariate; it is not in this model.",
                    svi))
  }
  message("=== preflight passed ===\n")
  invisible(TRUE)
}
