#!/usr/bin/env Rscript
# One organisation classification per NPI, resolved deterministically.
#
# WHY. control_candidates_raw.csv holds 31,011 rows for 20,111 distinct NPIs. A clinician
# appears once per group affiliation in the CMS Doctors and Clinicians registry, so multiple
# rows are the registry's real structure rather than a defect -- but they carry conflicting
# organisation sizes and facility names, and 110 of the 200 fielded controls have more than
# one. Whether such a control counts as an "independent private practice" therefore depended
# on which row was read, and two independent implementations of the same count differed by two
# records for exactly that reason: match() takes the first row, a dict keyed by NPI takes the
# last. Neither is a rule; both are an accident of iteration order.
#
# THE RULE, stated so it can be argued with:
#   org_size_resolved = MAX organisation size across all rows for that NPI.
# A clinician affiliated with a 566-member health system is not an independent private
# practitioner because they are also listed under a 12-member group. The conservative
# direction is the one that refuses to call someone independent on the strength of their
# smallest affiliation.
#
# Nothing is discarded: every distinct facility and size is preserved in the output, and any
# NPI whose rows disagree about independence at the threshold is flagged rather than silently
# resolved.
#
# This is a MEASUREMENT artifact. It does not change pair assignments, the fielded cohort, or
# any stored matching decision.

suppressMessages({library(readr); library(dplyr)})
.self <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
ROOT  <- if (is.na(.self)) normalizePath(".") else normalizePath(dirname(.self))
source(file.path(ROOT, "R", "pe_helpers.R"))

THRESHOLD <- 10L   # "independent" ceiling used for the flag; the artifact carries the raw sizes

cand <- read.csv(file.path(ROOT, "control_candidates_raw.csv"),
                 colClasses = "character", check.names = FALSE)
cand$k   <- npi_key(cand$npi)
cand$org <- suppressWarnings(as.numeric(cand$num_org_mem))
cand$fac <- trimws(ifelse(is.na(cand$facility_name), "", cand$facility_name))

out <- cand %>%
  group_by(npi = k) %>%
  summarise(
    n_source_rows     = dplyr::n(),
    org_size_min      = if (all(is.na(org))) NA_real_ else min(org, na.rm = TRUE),
    org_size_max      = if (all(is.na(org))) NA_real_ else max(org, na.rm = TRUE),
    n_distinct_org    = dplyr::n_distinct(org[!is.na(org)]),
    facilities        = paste(sort(unique(fac[nzchar(fac)])), collapse = " | "),
    n_facilities      = dplyr::n_distinct(fac[nzchar(fac)]),
    .groups = "drop") %>%
  mutate(
    org_size_resolved = org_size_max,
    resolution_rule   = "max organisation size across all source rows for the NPI",
    independent_at_threshold = dplyr::case_when(
      is.na(org_size_resolved) ~ NA,
      org_size_resolved <= THRESHOLD ~ TRUE,
      TRUE ~ FALSE),
    # The rows disagree about independence: min says yes, max says no.
    ambiguous = !is.na(org_size_min) & !is.na(org_size_max) &
                (org_size_min <= THRESHOLD) & (org_size_max > THRESHOLD),
    org_size_unknown = is.na(org_size_resolved))

dest <- file.path(ROOT, "data", "covariates", "control_org_classification.csv")
dir.create(dirname(dest), showWarnings = FALSE, recursive = TRUE)
write_csv(out, dest)

cat(sprintf("NPIs classified              : %d (from %d source rows)\n", nrow(out), nrow(cand)))
cat(sprintf("with more than one source row: %d\n", sum(out$n_source_rows > 1)))
cat(sprintf("organisation size unknown    : %d\n", sum(out$org_size_unknown)))
cat(sprintf("ambiguous at <= %d clinicians : %d\n", THRESHOLD, sum(out$ambiguous)))
cat(sprintf("\nWrote %s\n", dest))
