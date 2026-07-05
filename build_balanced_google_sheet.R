#' Export a balanced mystery-caller list in Google Sheets import format
#'
#' Regenerates the Google Sheet source file from a balanced (one-row-per-clinician)
#' calling sheet so the caller list matches the REDCap import. Rows are ordered by
#' state with each matched pair kept adjacent (Non-PE before PE). Output is a
#' title row, a `Provider Name, Phone, NPI, <stage_col>` header, then one row per
#' clinician with the stage column left blank for callers.
#'
#' Byte-for-byte compatible with the reference Python implementation
#' (`build_balanced_google_sheet.py`): CRLF line endings and minimal quoting.
#'
#' @param src Path to the balanced calling sheet (must contain columns
#'   `Provider Name`, `Phone`, `NPI`, `State`, `PE_or_Not`, `Matched Pair ID`).
#' @param out Path to write the Google Sheet source CSV.
#' @param backup Path for a one-time backup of an existing `out` file. The backup
#'   is only written if it does not already exist, so the true original is kept.
#' @param study_title Title placed in the first row (cell A1).
#' @param stage_col Name of the (blank) tracking column, e.g. `"Stage 1 Calling"`.
#' @param verbose Emit progress messages.
#' @return (Invisibly) the ordered data frame that was written.
#' @export
#' @examples
#' \dontrun{
#' mysterycall_export_gsheet_caller_list(
#'   src = "pe_obgyn_final_calling_sheet_200.csv",
#'   out = "Gatson_mystery_phase1_needs_be_called.csv")
#' }
mysterycall_export_gsheet_caller_list <- function(
    src         = "pe_obgyn_final_calling_sheet_200.csv",
    out         = "Gatson_mystery_phase1_needs_be_called.csv",
    backup      = "Gatson_mystery_phase1_ORIGINAL_backup.csv",
    study_title = "Gatson and Muffly Mystery Caller Study",
    stage_col   = "Stage 1 Calling",
    verbose     = TRUE) {

  checkmate::assert_file_exists(src)
  checkmate::assert_string(study_title)
  checkmate::assert_string(stage_col)
  checkmate::assert_flag(verbose)

  # Read everything as character so NPI/Phone are preserved verbatim
  df <- readr::read_csv(src, col_types = readr::cols(.default = readr::col_character()))
  required <- c("Provider Name", "Phone", "NPI", "State", "PE_or_Not", "Matched Pair ID")
  checkmate::assert_subset(required, colnames(df))

  # Order: state, then matched pair, then Non-PE (0) before PE (1).
  # method = "radix" -> C-locale byte order, matching Python's ordinal sort.
  pe_ord <- as.integer(df[["PE_or_Not"]] == "PE")
  pair   <- suppressWarnings(as.numeric(df[["Matched Pair ID"]]))
  df     <- df[order(df[["State"]], pair, pe_ord, method = "radix"), , drop = FALSE]

  out_df <- data.frame(
    `Provider Name` = df[["Provider Name"]],
    Phone           = df[["Phone"]],
    NPI             = df[["NPI"]],
    check.names     = FALSE,
    stringsAsFactors = FALSE)
  out_df[[stage_col]] <- ""

  # One-time backup of any existing file (git also retains history)
  if (file.exists(out) && !file.exists(backup)) {
    file.copy(out, backup)
    if (verbose) message("Backed up original -> ", backup)
  }

  # Title row (CRLF), then header + data via readr (CRLF, minimal quoting)
  cat(paste0(study_title, ",,,\r\n"), file = out, sep = "")
  readr::write_csv(out_df, out, append = TRUE, col_names = TRUE, eol = "\r\n", na = "")

  if (verbose) {
    n_fl <- sum(df[["State"]] == "FL")
    message(sprintf("Wrote %s: %d providers", out, nrow(df)))
    message(sprintf("States: %d | Florida: %d providers (%d pairs)",
                    length(unique(df[["State"]])), n_fl, n_fl %/% 2L))
    message(sprintf("PE / Non-PE: %s",
                    paste(names(table(df[["PE_or_Not"]])), table(df[["PE_or_Not"]]),
                          sep = "=", collapse = ", ")))
    message(sprintf("Calls implied: %d clinicians x 2 = %d", nrow(df), nrow(df) * 2L))
  }
  invisible(out_df)
}

# --- CLI runner: executes only under `Rscript build_balanced_google_sheet.R`,
# --- and is skipped on package load / interactive source() (safe for mysterycall).
if (sys.nframe() == 0L && !interactive()) {
  mysterycall_export_gsheet_caller_list()
}
