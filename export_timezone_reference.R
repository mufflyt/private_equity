#!/usr/bin/env Rscript
# Write timezone_reference.csv: the canonical (state, city) -> time zone mapping, exported
# so the remaining Python pipeline pieces read ONE vocabulary instead of carrying their own
# drifted copy of the table. match_all_providers.py once had its own STATE_TIMEZONES with no
# territory coverage and no minority-zone cities -- the third implementation of the same
# logic, and the wrongest.
#
# One row per state with an empty city (the state default), plus one row per minority-zone
# city in the split-timezone states. Lookup rule for consumers: minority-city row if the
# city matches, else the state-default row. tests/testthat/test-timezone-reference.R proves
# this artifact cannot drift from assign_time_zone().
#
# Usage: Rscript export_timezone_reference.R

source(file.path("R", "pe_helpers.R"))
ref <- timezone_reference_df()
write.csv(ref, "timezone_reference.csv", row.names = FALSE, na = "")
cat(sprintf("Wrote timezone_reference.csv: %d rows (%d state defaults + %d minority cities)\n",
            nrow(ref), sum(!nzchar(ref$city)), sum(nzchar(ref$city))))
