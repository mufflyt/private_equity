#!/usr/bin/env Rscript
# =============================================================================
# Real ACS (2022 5-yr) tract-level female insurance coverage, replacing the
# seed-1978 rnorm placeholders Tract_Pct_Female_{Private,Medicaid,Medicare,
# Uninsured}.
#
# All four are TRUE female-specific rates (ACS 2022 5-yr, by sex by age):
#   Private   = B27002 female "With private health insurance" / B27002 female total
#   Medicaid  = C27007 female "With Medicaid/means-tested"     / C27007 female total
#   Medicare  = C27006 female "With Medicare coverage"         / C27006 female total
#   Uninsured = B27001 female "No health insurance coverage"   / B27001 female total
#
# Requires CENSUS_API_KEY in the environment (~/.Renviron). Pulls only the
# states present in data/covariates/npi_geography.csv.
#
# Output: data/covariates/tract_female_insurance.csv
#   tract_geoid, female_total, pct_female_private, pct_female_medicaid,
#   pct_female_medicare, pct_female_uninsured
# =============================================================================

suppressPackageStartupMessages({library(tidycensus); library(dplyr)})
options(stringsAsFactors = FALSE, tigris_use_cache = TRUE)
if (!nzchar(Sys.getenv("CENSUS_API_KEY"))) stop("CENSUS_API_KEY not set.")

geo <- read.csv("data/covariates/npi_geography.csv", colClasses = "character")
states <- sort(unique(geo$state[nzchar(geo$state) & geo$state %in% c(state.abb, "DC")]))
cat("Pulling ACS for", length(states), "states...\n")

vars <- load_variables(2022, "acs5")
lab  <- function(tbl) vars[grepl(paste0("^", tbl, "_"), vars$name), c("name","label")]
ids  <- function(tbl, rx) { L <- lab(tbl); L$name[grepl(rx, L$label, ignore.case = TRUE)] }

# variable id sets (label-driven female lines, by sex by age)
b1_ftot_id   <- ids("B27001", "^Estimate!!Total:!!Female:$")
f_uninsur_id <- ids("B27001", "Female:.*No health insurance coverage")
b2_ftot_id   <- ids("B27002", "^Estimate!!Total:!!Female:$")
f_private_id <- ids("B27002", "Female:.*With private health insurance")
c7_ftot_id   <- ids("C27007", "^Estimate!!Total:!!Female:$")
f_mcaid_id   <- ids("C27007", "Female:.*With Medicaid/means-tested")
c6_ftot_id   <- ids("C27006", "^Estimate!!Total:!!Female:$")
f_mcare_id   <- ids("C27006", "Female:.*With Medicare coverage")
stopifnot(length(b1_ftot_id) == 1, length(f_private_id) > 0,
          length(f_mcaid_id) > 0, length(f_mcare_id) > 0)

pull_state <- function(st) {
  allv <- unique(c(b1_ftot_id, f_uninsur_id, b2_ftot_id, f_private_id,
                   c7_ftot_id, f_mcaid_id, c6_ftot_id, f_mcare_id))
  d <- tryCatch(suppressMessages(get_acs(
    geography = "tract", variables = allv, state = st,
    year = 2022, survey = "acs5")), error = function(e) NULL)
  if (is.null(d)) return(NULL)
  g <- sort(unique(d$GEOID))
  s <- function(v) { x <- tapply(d$estimate[d$variable %in% v],
                                 d$GEOID[d$variable %in% v], sum, na.rm = TRUE)[g]
                     x[is.na(x)] <- 0; as.numeric(x) }
  data.frame(
    tract_geoid = g,
    female_total = s(b1_ftot_id),
    female_priv  = s(f_private_id),  priv_tot  = s(b2_ftot_id),
    female_unins = s(f_uninsur_id),
    female_mcaid = s(f_mcaid_id),    mcaid_tot = s(c7_ftot_id),
    female_mcare = s(f_mcare_id),    mcare_tot = s(c6_ftot_id)
  )
}

acc <- list()
for (st in states) { acc[[st]] <- pull_state(st); cat("  ", st, "\n") }
d <- do.call(rbind, acc)

safe_pct <- function(num, den) ifelse(den > 0, round(100 * num / den, 1), NA_real_)
out <- data.frame(
  tract_geoid          = d$tract_geoid,
  female_total         = d$female_total,
  pct_female_private   = safe_pct(d$female_priv,  d$priv_tot),
  pct_female_medicaid  = safe_pct(d$female_mcaid, d$mcaid_tot),
  pct_female_medicare  = safe_pct(d$female_mcare, d$mcare_tot),
  pct_female_uninsured = safe_pct(d$female_unins, d$female_total)
)
out <- out[!duplicated(out$tract_geoid), ]
utils::write.csv(out, "data/covariates/tract_female_insurance.csv", row.names = FALSE, na = "")
cat(sprintf("Wrote tract_female_insurance.csv: %d tracts\n", nrow(out)))
