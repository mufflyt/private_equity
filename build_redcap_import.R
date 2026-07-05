#!/usr/bin/env Rscript
# Build a REDCap-import-ready CSV from the 300-pair calling sheet.
# Model: one record per physician (600 records) on form `acost_three_dx_urogyn_2`,
# with physician_name set to the instrument's dropdown code. Outcome fields are
# left blank for callers. Uses mysterycall::parse_redcap_labels to read the codes.
suppressMessages({library(mysterycall); library(readr); library(dplyr); library(stringr)})

DICT  <- "ICVsPOPVsSUI_DataDictionary_2026-07-05.csv"
SHEET <- "pe_obgyn_final_calling_sheet_300.csv"
FORM  <- "acost_three_dx_urogyn_2"
OUT   <- "redcap_import_ready.csv"

# 1. Pull the physician_name dropdown choice string from the data dictionary
d  <- read.csv(DICT, check.names = FALSE)
choices <- d[d[[1]] == "physician_name", "Choices, Calculations, OR Slider Labels"]

# 2. Parse code -> label with the package helper (returns: field, code, label)
lab <- as.data.frame(mysterycall_parse_redcap_labels(choices))
lab$code  <- as.integer(str_trim(lab$code))
lab$npi   <- str_match(lab$label, "NPI:\\s*(\\d+)")[, 2]
cat(sprintf("Dropdown options parsed: %d (with NPI: %d)\n", nrow(lab), sum(!is.na(lab$npi))))

# 3. Cross-check against the calling sheet
cs <- read_csv(SHEET, show_col_types = FALSE)
matched <- sum(as.character(cs$NPI) %in% lab$npi)
cat(sprintf("Calling-sheet physicians: %d | matched to a dropdown code: %d\n", nrow(cs), matched))
if (matched < nrow(cs))
  cat("  WARNING: ", nrow(cs) - matched, "sheet physicians not found in dropdown codes.\n")

# 4. Build the import frame: one record per physician (ordered by dropdown code)
imp <- lab %>%
  arrange(code) %>%
  transmute(
    record_id      = code,          # 1..600, bijective with physician
    physician_name = code           # dropdown raw value = its code
  )
imp[[paste0(FORM, "_complete")]] <- 0L   # 0 = Incomplete (callers will fill)

write_csv(imp, OUT)
cat(sprintf("\nWrote %s: %d records x %d columns\n", OUT, nrow(imp), ncol(imp)))
cat("Columns:", paste(names(imp), collapse = ", "), "\n")
cat("Preview:\n"); print(utils::head(imp, 3))
