#!/usr/bin/env Rscript
# Quick diagnostic: how much of the calling sheet is undialable. Port of verify_phones.py,
# which is deleted -- the pipeline is R-only for live data.
#
# Usage: Rscript verify_phones.R [--sheet=FILE]

suppressMessages(library(readr))
source(file.path("R", "pe_helpers.R"))

argval <- function(flag, default) {
  a <- commandArgs(trailingOnly = TRUE)
  v <- sub(paste0("^", flag, "="), "", grep(paste0("^", flag, "="), a, value = TRUE))
  if (length(v)) v[1] else default
}
SHEET <- argval("--sheet", "pe_obgyn_final_calling_sheet_300.csv")

df <- read_csv(SHEET, col_types = cols(.default = col_character()))
cat(sprintf("Total rows: %d\n", nrow(df)))
cat(sprintf("Missing Phone count: %d\n", sum(is.na(df$Phone))))
cat(sprintf("N/A Phone count: %d\n", sum(df$Phone == "N/A", na.rm = TRUE)))
cat(sprintf("Empty Phone count: %d\n", sum(df$Phone == "", na.rm = TRUE)))
cat(sprintf("Undialable after phone_key(): %d\n", sum(is.na(phone_key(df$Phone)))))
cat("\nFirst few rows:\n")
print(utils::head(df[, c("Provider Name", "Phone", "PE_or_Not", "Matched Pair ID")], 10))
