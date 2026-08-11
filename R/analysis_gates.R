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
#   assert_join        The NPI float suffix, the ZIP leading-zero loss, and a sprintf("%02s")
#                      that pads with spaces each produced a silent zero-row or partial join.
#   gate_sap           A power analysis reported a 2-df joint test of "any ownership effect"
#                      as though it were the 1-df interaction the plan names.
#   gate_clustering    400 clinicians are reached through 385 practice lines; two matched
#                      pairs put both arms on one line.
#   gate_analytic_n    The power calculation gave all 800 calls a wait time. The study will
#                      observe about 622, and the identifying cell falls from 200 to ~82.
#
# Sourcing this file has no side effects.

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
#' A covariate missing in one arm and not the other turns a complete-case fit into a
#' non-random deletion of that arm. The gate tests each analytic covariate against the
#' exposure with Fisher's exact test.
gate_missingness <- function(df, analytic, arm_col = "PE_or_Not", alpha = 0.01) {
  if (!arm_col %in% names(df)) gate_fail("missingness", "No arm column '", arm_col, "'")
  arm <- df[[arm_col]]
  bad <- character(0)
  for (nm in analytic) {
    miss <- is.na(suppressWarnings(if (is.numeric(df[[nm]])) df[[nm]] else as.character(df[[nm]]))) |
            (!is.numeric(df[[nm]]) & !nzchar(trimws(ifelse(is.na(df[[nm]]), "", as.character(df[[nm]])))))
    if (!any(miss) || all(miss)) next
    tb <- table(arm, miss)
    if (nrow(tb) < 2 || ncol(tb) < 2) next
    p <- stats::fisher.test(tb)$p.value
    if (p < alpha) {
      bad <- c(bad, sprintf("%s: Fisher P = %.3g\n%s", nm, p,
                            paste("      ", utils::capture.output(print(tb)), collapse = "\n")))
    }
  }
  if (length(bad)) {
    gate_fail("missingness",
              "Missingness depends on exposure for:\n    ", paste(bad, collapse = "\n    "),
              "\n\n  A complete-case fit would delete one arm preferentially. Repair the ",
              "covariate at source,\n  or pre-specify a missing-data model. Do not proceed to ",
              "a complete-case fit.")
  }
  gate_pass("missingness", sprintf("independent of arm for %d covariate(s)", length(analytic)))
}

# ---------------------------------------------------------------------------- joins

#' Gate 3. A join must match what it is expected to match.
#'
#' Returns the matched index vector so the call site reads as a normal lookup. The three join
#' defects in this project were all silent: nothing errored, a column simply arrived empty.
assert_join <- function(x, table, min_match = 1.0, label = "join", key_fun = identity) {
  xi <- key_fun(x)
  ti <- key_fun(table)
  idx <- match(xi, ti)
  rate <- mean(!is.na(idx))
  if (rate < min_match) {
    ex <- utils::head(unique(xi[is.na(idx)]), 5)
    gate_fail("join",
              sprintf("%s matched %.1f%% of %d keys; the contract requires %.1f%%.",
                      label, 100 * rate, length(xi), 100 * min_match),
              "\n  Unmatched example key(s): ", paste(ex, collapse = ", "),
              "\n  Example key(s) on the other side: ", paste(utils::head(unique(ti), 3), collapse = ", "),
              "\n\n  A partial join is how the NPI float suffix and the ZIP zero-truncation ",
              "reached the data.\n  Check for type coercion and for padding before widening ",
              "the tolerance.")
  }
  gate_pass("join", sprintf("%s matched %.1f%% of %d keys", label, 100 * rate, length(xi)))
  idx
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
