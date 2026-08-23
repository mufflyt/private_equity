#!/usr/bin/env Rscript
# =============================================================================
# Build the ABOG NPI -> subspecialty crosswalk that match_all_providers.py
# looks for (PE_ABOG_CROSSWALK env var, default ~/Desktop/canonical_abog_npi_LATEST.csv).
# That file was missing on this machine; this script derives it from the
# longitudinal source (data-raw/google_drive/abog_longitudinal_addresses.csv,
# pulled from Drive -- see data-raw/google_drive/manifest.csv for provenance).
#
# Source columns: npi, physician_name, subspecialty, clinically_active,
# analysis_year, practice_address_*, is_move, is_city_change, is_state_change,
# prev_city, prev_state -- one row per NPI per year (2013-2024).
#
# For each NPI, keeps the row from its most recent analysis_year (its "LATEST"
# known subspecialty/name), regardless of clinically_active -- match_all_providers.py
# does not filter on that flag when building its npi/name lookup, so neither
# does this script. A retired physician's last known subspecialty is still a
# valid answer to "what subspecialty is this NPI".
#
# Output columns match what match_all_providers.py reads: npi, subspecialty,
# physician_name.
# =============================================================================

suppressPackageStartupMessages(library(data.table))

SRC <- "data-raw/google_drive/abog_longitudinal_addresses.csv"
OUT <- Sys.getenv("PE_ABOG_CROSSWALK", file.path(path.expand("~"), "Desktop", "canonical_abog_npi_LATEST.csv"))

if (!file.exists(SRC)) stop("Source not found: ", SRC)

dt <- fread(SRC, colClasses = list(character = c("npi", "physician_name", "subspecialty")))
dt <- dt[!is.na(npi) & nzchar(npi)]
setorder(dt, npi, -analysis_year)
latest <- dt[, .SD[1], by = npi][, .(npi, subspecialty, physician_name)]

dir.create(dirname(OUT), showWarnings = FALSE, recursive = TRUE)
fwrite(latest, OUT)

cat(sprintf("Wrote %s: %d NPIs (source: %d NPI-years, %s-%s)\n",
            OUT, nrow(latest), nrow(dt), min(dt$analysis_year), max(dt$analysis_year)))
print(latest[, .N, by = subspecialty][order(-N)])
