#!/usr/bin/env Rscript
#' Regenerate the Google Sheet caller list from the balanced calling sheet.
#'
#' The exporter itself is not here. It lives in mysterycall as
#' `mysterycall_export_gsheet_caller_list()`: it was written in this file, contributed
#' upstream, and then left behind here as well. Two definitions of one name is not a
#' duplicate, it is a race -- whichever of `source()` and `library(mysterycall)` runs last
#' wins, silently. That is exactly the defect documented in docs/CANONICAL_SOURCES_AUDIT.md
#' (A1, A9), where four locally redefined names caused the simulated covariates, and it is
#' what test-analysis-gates.R checks for with "no script defines a name an attached canonical
#' package exports".
#'
#' Verified before removal: on the same input, the local definition and the package export
#' produced byte-identical output (18,204 bytes). Nothing about the artifact changes.
#'
#' This file now supplies only the study's arguments.

suppressMessages(library(mysterycall))

#' @param src Path to the balanced calling sheet (one row per clinician, with columns
#'   `Provider Name`, `Phone`, `NPI`, `State`, `PE_or_Not`, `Matched Pair ID`).
#' @param out Path to write the Google Sheet source CSV.
#' @param backup One-time backup of an existing `out`, written only if absent, so the true
#'   original survives a re-run.
#' @return (Invisibly) the ordered data frame that was written.
build_balanced_google_sheet <- function(
    src         = "pe_obgyn_final_calling_sheet_200_dedup.csv",
    out         = "Gatson_mystery_phase1_needs_be_called.csv",
    backup      = "Gatson_mystery_phase1_ORIGINAL_backup.csv",
    study_title = "Gatson and Muffly Mystery Caller Study",
    stage_col   = "Stage 1 Calling",
    verbose     = TRUE) {
  mysterycall::mysterycall_export_gsheet_caller_list(
    src         = src,
    out         = out,
    backup      = backup,
    study_title = study_title,
    stage_col   = stage_col,
    # Pairs stay adjacent with the control first, so a caller reading down the sheet does not
    # see the two arms in a fixed, learnable order within the pair.
    group_col   = "PE_or_Not",
    group_last  = "PE",
    verbose     = verbose)
}

# CLI runner: executes only under `Rscript build_balanced_google_sheet.R`, and is skipped on
# interactive source() so the file can be read without writing anything.
if (sys.nframe() == 0L && !interactive()) {
  build_balanced_google_sheet()
}
