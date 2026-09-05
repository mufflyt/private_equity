# Estimand drift: does what gets REPORTED still match what the plan NAMES?
#
# Sourcing this file has no side effects.
#
# WHAT DRIFT MEANS HERE. SAP.lock names, for each prespecified analysis, a formula, a family, a
# subset, an estimand (the fixed-effect term) and a REPORTING SCALE. gate_sap() already refuses
# to fit a formula the plan does not name, and primary_analysis.Rmd takes its term names from
# gate_sap()'s return value, so the term itself cannot drift.
#
# Three things still can, and none of them is caught by any existing gate:
#
#   scale drift        The plan says the wait-time interaction is reported as an incidence rate
#                      ratio. Nothing stops the manuscript printing "OR 1.31" beside it. Both
#                      numbers are exp(beta); only the label distinguishes them, and the label
#                      is prose.
#   undeclared report  A quantity extracted from a prespecified model that the plan does not
#                      name -- the commercial-arm `pe` main effect, for instance. That one is
#                      legitimate and documented, which is exactly why it needs DECLARING: an
#                      undocumented one would look identical.
#   orphaned estimand  An analysis the plan names that nothing reports. The plan then describes
#                      a study larger than the one performed.
#
# This module reads declarations only. It fits nothing, needs no cohort data, and therefore
# runs in CI, where the analysis itself cannot.

DRIFT_DERIVED <- "config/derived_estimands.csv"

# ---- what the plan names ----------------------------------------------------

#' Every prespecified analysis in SAP.lock, as one row each.
sap_estimands <- function(sap = read_sap()) {
  keys <- names(sap)
  base <- unique(sub("_(formula|family|subset|estimand|scale|function)$", "",
                     grep("_estimand$", keys, value = TRUE)))
  if (!length(base)) return(data.frame())
  get <- function(b, k) { v <- sap[[paste0(b, "_", k)]]; if (is.null(v)) NA_character_ else trimws(v) }
  data.frame(
    analysis = base,
    estimand = vapply(base, get, character(1), "estimand"),
    scale    = vapply(base, get, character(1), "scale"),
    family   = vapply(base, get, character(1), "family"),
    subset   = vapply(base, get, character(1), "subset"),
    stringsAsFactors = FALSE, row.names = NULL)
}

# ---- what the code reports --------------------------------------------------

#' Quantities the analysis source extracts on a named scale.
#'
#' Anchored on `scale = SAP[["<key>_scale"]]`, which is how every reporting frame in
#' primary_analysis.Rmd declares the scale it is printing on. A frame that hard-codes a scale
#' string instead is exactly the drift this looks for, so it is reported too.
reported_estimands <- function(path = "primary_analysis.Rmd") {
  if (!file.exists(path)) return(data.frame())
  txt <- readLines(path, warn = FALSE)
  one <- paste(txt, collapse = "\n")

  # Anchoring on `_scale` alone was too narrow: access_unconditional is read through
  # `_horizon` and `_function` and would have been reported as an orphaned estimand while the
  # source reports it perfectly well. Match ANY declaration key the source reads, then let the
  # caller intersect with the analyses the plan actually names.
  all_keys <- unique(sub('.*SAP\\[\\["([a-z_]+)"\\]\\].*', "\\1",
                         regmatches(one, gregexpr('SAP\\[\\["[a-z_]+"\\]\\]', one))[[1]]))
  via_sap <- unique(sub("_(formula|family|subset|estimand|scale|function|horizon)$", "", all_keys))
  # A literal scale string sitting in a `scale =` slot, i.e. not read from the plan.
  hard <- unique(trimws(gsub('^scale\\s*=\\s*["\']|["\'],?$', "",
                    grep('^\\s*scale\\s*=\\s*["\']', txt, value = TRUE))))

  rbind(
    if (length(via_sap)) data.frame(analysis = via_sap, source = "SAP.lock",
                                    scale_literal = NA_character_, stringsAsFactors = FALSE),
    if (length(hard)) data.frame(analysis = NA_character_, source = "hard-coded in source",
                                 scale_literal = hard, stringsAsFactors = FALSE))
}

# ---- what the manuscript prints ---------------------------------------------

# The abbreviations a reader actually sees, mapped to the scale names SAP.lock uses. A label
# outside this map is not drift, it is an unrecognised label, and is reported as such rather
# than silently ignored.
SCALE_LABELS <- c(OR = "odds ratio", IRR = "incidence rate ratio",
                  RR = "risk ratio", HR = "hazard ratio")

#' Scale abbreviations the manuscript prints next to a registered placeholder.
manuscript_scale_labels <- function(path = "manuscript/manuscript_cite.md") {
  if (!file.exists(path)) return(data.frame())
  txt <- paste(readLines(path, warn = FALSE), collapse = "\n")
  m <- regmatches(txt, gregexpr("\\b(OR|IRR|RR|HR)\\s*\\[[0-9.]+\\]", txt))[[1]]
  if (!length(m)) return(data.frame())
  # sub() replaces the FIRST match only, so "^.*\\[|\\]$" strips the opening bracket and
  # leaves the closing one -- values came out as "0.26]". Two passes, not one alternation.
  data.frame(label = sub("\\s*\\[.*$", "", m),
             value = sub("\\]$", "", sub("^.*\\[", "", m)),
             reported_scale = unname(SCALE_LABELS[sub("\\s*\\[.*$", "", m)]),
             stringsAsFactors = FALSE)
}

#' Quantities reported that the plan does not name, declared deliberately.
#'
#' The commercial-arm contrast is the worked example: it is the `pe` main effect of a
#' prespecified model read at medicaid = 0, so it is a reading OF the plan rather than a new
#' analysis. Declaring it is what separates it from an unplanned comparison that looks the same.
read_derived <- function(path = DRIFT_DERIVED) {
  if (!file.exists(path)) return(data.frame(reported_as = character(0), derived_from = character(0),
                                            term = character(0), scale = character(0),
                                            justification = character(0)))
  utils::read.csv(path, colClasses = "character", na.strings = character(0))
}

# ---- the report -------------------------------------------------------------

#' Compare plan, code and manuscript, and classify every disagreement.
estimand_drift <- function(sap = read_sap(), root = ".") {
  plan <- sap_estimands(sap)
  code <- reported_estimands(file.path(root, "primary_analysis.Rmd"))
  ms   <- manuscript_scale_labels(file.path(root, "manuscript", "manuscript_cite.md"))
  derived <- read_derived(file.path(root, DRIFT_DERIVED))

  rows <- list()
  add <- function(severity, item, detail) {
    rows[[length(rows) + 1L]] <<- data.frame(severity = severity, item = item, detail = detail,
                                             stringsAsFactors = FALSE)
  }

  # 1. An analysis the plan names that the reporting source never reads.
  reported <- unique(stats::na.omit(code$analysis))
  for (a in setdiff(plan$analysis, reported)) {
    add("orphaned estimand", a,
        "SAP.lock names this analysis; primary_analysis.Rmd never reads its scale.")
  }

  # 2. A scale hard-coded in the source rather than read from the plan.
  for (s in stats::na.omit(code$scale_literal)) {
    add("hard-coded scale", s,
        "A reporting frame names a scale as a literal instead of reading it from SAP.lock.")
  }

  # 3. A scale label in the manuscript that no prespecified analysis declares.
  if (nrow(ms)) {
    unknown <- ms[is.na(ms$reported_scale), , drop = FALSE]
    for (i in seq_len(nrow(unknown))) {
      add("unrecognised label", unknown$label[i], "Not a scale abbreviation this report knows.")
    }
    known <- ms[!is.na(ms$reported_scale), , drop = FALSE]
    for (i in seq_len(nrow(known))) {
      ok <- known$reported_scale[i] %in% plan$scale ||
            known$reported_scale[i] %in% derived$scale
      if (!ok) {
        add("scale drift", sprintf("%s [%s]", known$label[i], known$value[i]),
            sprintf("Manuscript reports on the %s scale; no prespecified or declared-derived analysis uses it. Plan scales: %s.",
                    known$reported_scale[i], paste(unique(plan$scale), collapse = "; ")))
      }
    }
  }

  out <- if (length(rows)) do.call(rbind, rows) else
    data.frame(severity = character(0), item = character(0), detail = character(0))
  attr(out, "plan") <- plan
  attr(out, "manuscript") <- ms
  attr(out, "derived") <- derived
  out
}

#' Write the human-readable report.
#' `sap` is a parameter rather than a default read: read_sap() resolves through GATE_ROOT,
#' which is the caller's working directory, so under testthat it looked for SAP.lock inside
#' tests/testthat/ and the gate failed. The report must be generatable from anywhere.
write_drift_report <- function(path = "docs/ESTIMAND_DRIFT_REPORT.md", root = ".",
                               sap = read_sap(file.path(root, "SAP.lock"))) {
  d <- estimand_drift(sap, root = root)
  plan <- attr(d, "plan"); ms <- attr(d, "manuscript"); der <- attr(d, "derived")
  L <- c(
    "# Estimand drift report",
    "",
    sprintf("Generated by `R/estimand_drift.R` on %s. Do not hand-edit.", Sys.Date()),
    "",
    "Compares three declarations of the same quantities: what `SAP.lock` names, what",
    "`primary_analysis.Rmd` reports, and what the manuscript prints. It reads declarations",
    "only, fits nothing, and needs no cohort data.",
    "",
    "## Prespecified analyses", "",
    "| Analysis | Estimand | Reporting scale | Family | Subset |", "|---|---|---|---|---|",
    sprintf("| `%s` | `%s` | %s | %s | %s |", plan$analysis, plan$estimand, plan$scale,
            ifelse(is.na(plan$family), "-", plan$family), ifelse(is.na(plan$subset), "-", plan$subset)),
    "", "## Scale labels printed in the manuscript", "")
  L <- c(L, if (nrow(ms)) c("| Label | Value | Scale it denotes |", "|---|---|---|",
                            sprintf("| %s | [%s] | %s |", ms$label, ms$value,
                                    ifelse(is.na(ms$reported_scale), "UNRECOGNISED", ms$reported_scale)))
              else "None found.")
  L <- c(L, "", "## Declared derived quantities", "",
         "Readings of a prespecified model that the plan does not name as its own analysis.",
         "Declaring one is what separates it from an unplanned comparison, which would look identical.",
         "")
  L <- c(L, if (nrow(der)) c("| Reported as | Derived from | Term | Scale | Justification |",
                             "|---|---|---|---|---|",
                             sprintf("| %s | %s | `%s` | %s | %s |", der$reported_as,
                                     der$derived_from, der$term, der$scale, der$justification))
              else "None declared.")
  L <- c(L, "", "## Findings", "")
  L <- c(L, if (nrow(d)) c("| Severity | Item | Detail |", "|---|---|---|",
                           sprintf("| %s | %s | %s |", d$severity, d$item, d$detail))
              else "No drift detected: every scale the manuscript prints is one a prespecified or declared-derived analysis uses.")
  dir.create(dirname(file.path(root, path)), showWarnings = FALSE, recursive = TRUE)
  writeLines(L, file.path(root, path))
  invisible(d)
}

if (sys.nframe() == 0L) {
  source("R/analysis_gates.R")
  d <- write_drift_report(root = ".")
  cat(sprintf("Wrote docs/ESTIMAND_DRIFT_REPORT.md -- %d finding(s).\n", nrow(d)))
  if (nrow(d)) print(d, row.names = FALSE)
}
