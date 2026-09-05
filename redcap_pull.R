#!/usr/bin/env Rscript
# =============================================================================
# redcap_pull.R -- fetch the mystery-call outcome export from the REDCap API.
#
# THE MISSING LINK. build_study_database_from_redcap.R reads
# redcap/redcap_raw_export_800.csv and fails closed because nothing produces it: no script in
# this repository has ever reached the REDCap API, so the export had to arrive by hand through
# the web UI, unversioned and unattributed. This is that script, and it is the only one that
# should touch the network -- everything downstream consumes files.
#
# Writes into redcap/, which .gitignore covers for *.csv, so a real export carrying caller
# identity cannot be committed by accident:
#
#   redcap_raw_export_800.csv          THE INPUT the merge script names. Coded values, stable
#                                      filename, overwritten on each pull.
#   redcap_raw_export_<stamp>.csv      The same payload, timestamped: the audit trail, so an
#                                      analysis can be tied to the export it actually ran on.
#   redcap_labels_<stamp>.csv          Choice labels as values and headers, for reading by eye.
#   redcap_metadata_<stamp>.csv        The live data dictionary at pull time.
#   redcap_project_info_<stamp>.json   Project id, title, production flag.
#
#     Rscript redcap_pull.R
#
# Needs the project API token in ~/.Renviron. NEVER commit it, and never pass it on a command
# line, where it lands in shell history and in the process table:
#
#     REDCAP_PE_TOKEN=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
#
# Token: REDCap -> project 40415 -> Applications -> API -> "Generate token". Override the
# instance with REDCAP_URL if it ever moves.
# =============================================================================

suppressMessages({library(httr); library(readr)})

REDCAP_URL <- Sys.getenv("REDCAP_URL", "https://redcap.ucdenver.edu/api/")

# The filename build_study_database_from_redcap.R reads. Changing it breaks that script
# silently, so tests/testthat/test-redcap-pull-contract.R asserts the two still agree.
STABLE_RAW <- "redcap_raw_export_800.csv"

# One POST, with the two failure modes REDCap hides behind HTTP 200.
#
# A bad or revoked token returns a JSON error body; a moved instance returns an HTML login
# page. BOTH parse as a perfectly valid zero-row CSV if handed straight to read_csv, so a
# caller that checks only status_code reports success having downloaded nothing, and the
# analysis downstream sees an empty study rather than an error.
redcap_post <- function(token, content, ..., what = content) {
  body <- c(list(token = token, content = content, returnFormat = "json"), list(...))
  resp <- httr::POST(REDCAP_URL, body = body, encode = "form", httr::timeout(600))

  if (httr::status_code(resp) != 200) {
    stop(sprintf("REDCap returned HTTP %d for the %s export: %s",
                 httr::status_code(resp), what,
                 substr(httr::content(resp, "text", encoding = "UTF-8"), 1, 300)), call. = FALSE)
  }
  txt <- httr::content(resp, "text", encoding = "UTF-8")
  if (grepl('^\\s*\\{\\s*"error"', txt)) {
    stop("REDCap API error on the ", what, " export: ", substr(txt, 1, 300), call. = FALSE)
  }
  if (grepl("^\\s*<", txt)) {
    stop("REDCap returned HTML, not data, for the ", what, " export. Check REDCAP_URL (",
         REDCAP_URL, ").", call. = FALSE)
  }
  txt
}

# Count data rows by parsing, not by counting lines: the `notes` field and several field labels
# carry embedded newlines, so a line count over-reports.
n_rows <- function(path) {
  tryCatch(nrow(readr::read_csv(path, show_col_types = FALSE, progress = FALSE)),
           error = function(e) NA_integer_)
}

redcap_pull <- function(dest_dir = "redcap", token = Sys.getenv("REDCAP_PE_TOKEN")) {
  if (!nzchar(token)) {
    stop("No REDCap token found. Add REDCAP_PE_TOKEN=<token> to ~/.Renviron and restart R ",
         "(or run: readRenviron('~/.Renviron')).", call. = FALSE)
  }
  dir.create(dest_dir, showWarnings = FALSE, recursive = TRUE)
  stamp <- format(Sys.time(), "%Y-%m-%d_%H%M")
  written <- character(0)

  # ---- project info: proves which project the token actually opens ----------
  info <- redcap_post(token, "project", format = "json", what = "project info")
  info_path <- file.path(dest_dir, sprintf("redcap_project_info_%s.json", stamp))
  writeLines(info, info_path, useBytes = TRUE)
  pid   <- sub('.*"project_id":\\s*(\\d+).*', "\\1", info)
  title <- sub('.*"project_title":"(.*?)".*', "\\1", info)
  prod  <- grepl('"in_production":1', info)
  cat(sprintf("  project  %s (id %s, %s)\n", gsub("\\\\/", "/", title), pid,
              if (prod) "production" else "DEVELOPMENT"))
  written["project"] <- info_path

  # ---- data dictionary: the instrument contract at pull time ----------------
  meta <- redcap_post(token, "metadata", format = "csv", what = "metadata")
  meta_path <- file.path(dest_dir, sprintf("redcap_metadata_%s.csv", stamp))
  writeLines(meta, meta_path, useBytes = TRUE)
  cat(sprintf("  metadata redcap_metadata_%s.csv (%s fields)\n", stamp, n_rows(meta_path)))
  written["metadata"] <- meta_path

  # ---- records -------------------------------------------------------------
  # Raw is what the merge script consumes: it decodes the coded values itself against the
  # study's documented exclusion codes. Labels are pulled too, for reading by eye.
  flavors <- list(
    raw    = list(file = sprintf("redcap_raw_export_%s.csv", stamp),
                  args = list(rawOrLabel = "raw", rawOrLabelHeaders = "raw",
                              exportCheckboxLabel = "false")),
    labels = list(file = sprintf("redcap_labels_%s.csv", stamp),
                  args = list(rawOrLabel = "label", rawOrLabelHeaders = "label",
                              exportCheckboxLabel = "true")))

  for (nm in names(flavors)) {
    f <- flavors[[nm]]
    txt <- do.call(redcap_post, c(list(token, "record", format = "csv", type = "flat",
                                       what = paste(nm, "records")), f$args))
    path <- file.path(dest_dir, f$file)
    writeLines(txt, path, useBytes = TRUE)
    # An empty body is REDCap's honest answer for a project with no records yet. That is not an
    # error, but it is not something to hand an analysis either, so say it rather than let a
    # zero-row file look like a successful export.
    n <- if (!nzchar(trimws(txt))) 0L else n_rows(path)
    cat(sprintf("  %-8s %s (%s data rows)%s\n", nm, f$file, n,
                if (identical(n, 0L)) "  <- project has no records yet" else ""))
    written[nm] <- path
  }

  # ---- the stable filename the merge script reads ---------------------------
  # Copied rather than symlinked: build_study_database_from_redcap.R may run on a machine or in
  # a container where the timestamped sibling is absent, and a dangling symlink fails in a way
  # that reads like a missing export rather than a broken link.
  stable <- file.path(dest_dir, STABLE_RAW)
  file.copy(written[["raw"]], stable, overwrite = TRUE)
  cat(sprintf("  stable   %s  <- build_study_database_from_redcap.R reads this\n", STABLE_RAW))
  written["stable"] <- stable

  invisible(written)
}

if (sys.nframe() == 0L) {
  cat("-- Pulling the PE OB/GYN export from REDCap --\n")
  redcap_pull()
  cat("\nDone. Next: Rscript build_study_database_from_redcap.R\n")
}
