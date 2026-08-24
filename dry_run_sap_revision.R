#!/usr/bin/env Rscript
# Evaluate the REVISED analysis hierarchy against the same simulated design used by
# dry_run_analysis.R, before it is written into the SAP.
#
# The proposed primary obtainment estimand is a MATCHED-PAIR contrast (PE vs non-PE
# among Medicaid calls only), not two independent samples, so power.prop.test overstates
# what the design delivers if pair matching induces correlation. This checks it properly,
# and also checks the two estimands the hierarchy demotes or adds.
#
# Estimands evaluated:
#   1. PRIMARY obtainment  : PE vs non-PE among Medicaid calls, matched-pair logistic
#                            (also McNemar, since one Medicaid call per clinician)
#   2. PRIMARY wait time   : payer x ownership NB GLMM interaction (unchanged)
#   3. SECONDARY obtainment: payer x ownership logistic interaction (the demoted one)
#   4. UNCONDITIONAL access: expected days to appointment with non-obtainment handled
#                            explicitly, so selection is not hidden
#
# Usage: Rscript dry_run_sap_revision.R [--sims=200]

suppressMessages({library(readr); library(dplyr); library(tidyr); library(glmmTMB)})

SHEET  <- "pe_obgyn_final_calling_sheet_200.csv"
OUT    <- "dry_run_sap_revision_results.csv"
SEED   <- 1978L
args   <- commandArgs(trailingOnly = TRUE)
N_SIMS <- as.integer(sub("^--sims=", "", grep("^--sims=", args, value = TRUE)[1]))
if (is.na(N_SIMS)) N_SIMS <- 200L

P_OBTAIN <- c(ctrl_bcbs = 0.985, pe_bcbs = 0.990, ctrl_medicaid = 0.725, pe_medicaid = 0.410)
MU_WAIT  <- c(ctrl_bcbs = 12.1,  pe_bcbs = 14.5,  ctrl_medicaid = 23.4,  pe_medicaid = 36.8)
SD_WAIT  <- c(ctrl_bcbs = 6.8,   pe_bcbs = 8.2,   ctrl_medicaid = 11.2,  pe_medicaid = 18.4)
SD_CLIN  <- sqrt(0.082)
SD_PAIR  <- sqrt(0.054)
THETA    <- mean(MU_WAIT^2 / (SD_WAIT^2 - MU_WAIT))

# Truth for each estimand, on its own scale.
TRUE_OR_MEDICAID <- (P_OBTAIN["pe_medicaid"] / (1 - P_OBTAIN["pe_medicaid"])) /
                    (P_OBTAIN["ctrl_medicaid"] / (1 - P_OBTAIN["ctrl_medicaid"]))
TRUE_RD_MEDICAID <- P_OBTAIN["pe_medicaid"] - P_OBTAIN["ctrl_medicaid"]
TRUE_IRR_INT     <- (MU_WAIT["pe_medicaid"] / MU_WAIT["pe_bcbs"]) /
                    (MU_WAIT["ctrl_medicaid"] / MU_WAIT["ctrl_bcbs"])

sheet <- read_csv(SHEET, show_col_types = FALSE)
design <- sheet %>%
  transmute(npi = as.character(NPI), pair = `Matched Pair ID`,
            pe = as.integer(PE_or_Not == "PE"),
            # SAP.lock names CDC_SVI_real. This read as.numeric(CDC_SVI), the simulated
            # column, so every svi_z in this script was computed from rnorm() draws.
            svi = suppressWarnings(as.numeric(CDC_SVI_real))) %>%
  mutate(svi_z = as.numeric(scale(ifelse(is.na(svi), median(svi, na.rm = TRUE), svi)))) %>%
  tidyr::crossing(payer = c("BCBS", "Medicaid")) %>%
  mutate(medicaid = as.integer(payer == "Medicaid"),
         cell = paste0(ifelse(pe == 1, "pe", "ctrl"), "_", tolower(payer)))

simulate_calls <- function(d) {
  u_clin <- setNames(rnorm(n_distinct(d$npi),  0, SD_CLIN), unique(d$npi))
  u_pair <- setNames(rnorm(n_distinct(d$pair), 0, SD_PAIR), unique(d$pair))
  v_clin <- setNames(rnorm(n_distinct(d$npi),  0, SD_CLIN), unique(d$npi))
  v_pair <- setNames(rnorm(n_distinct(d$pair), 0, SD_PAIR), unique(d$pair))
  d$obtained <- rbinom(nrow(d), 1,
    plogis(qlogis(P_OBTAIN[d$cell]) + u_clin[d$npi] + u_pair[d$pair]))
  mu <- exp(log(MU_WAIT[d$cell]) + v_clin[d$npi] + v_pair[d$pair])
  d$business_days <- ifelse(d$obtained == 1, rnbinom(nrow(d), mu = mu, size = THETA), NA_integer_)
  d
}

pull <- function(m, term) {
  if (inherits(m, "try-error")) return(c(est = NA, lo = NA, hi = NA, p = NA))
  co <- try(summary(m)$coefficients$cond, silent = TRUE)
  if (inherits(co, "try-error") || !term %in% rownames(co)) return(c(est = NA, lo = NA, hi = NA, p = NA))
  b <- co[term, "Estimate"]; se <- co[term, "Std. Error"]
  c(est = exp(b), lo = exp(b - 1.96 * se), hi = exp(b + 1.96 * se), p = co[term, "Pr(>|z|)"])
}

one_rep <- function(d) {
  med <- filter(d, medicaid == 1)   # one call per clinician -> no clinician RE is estimable

  # 1. PRIMARY obtainment: matched-pair logistic on Medicaid calls only.
  m1 <- try(glmmTMB(obtained ~ pe + svi_z + (1 | pair), family = binomial, data = med), silent = TRUE)
  e1 <- pull(m1, "pe")

  # 1b. McNemar on the discordant pairs, as a distribution-free cross-check.
  w <- med %>% select(pair, pe, obtained) %>%
    tidyr::pivot_wider(names_from = pe, values_from = obtained, names_prefix = "arm") %>%
    filter(!is.na(arm0), !is.na(arm1))
  b <- sum(w$arm1 == 0 & w$arm0 == 1); cc <- sum(w$arm1 == 1 & w$arm0 == 0)
  p_mcn <- if ((b + cc) > 0) stats::binom.test(cc, b + cc, 0.5)$p.value else NA_real_
  rd <- mean(w$arm1) - mean(w$arm0)

  # 2. PRIMARY wait time: unchanged interaction model.
  m2 <- try(glmmTMB(business_days ~ pe * medicaid + svi_z + (1 | pair) + (1 | npi),
                    family = nbinom2, data = filter(d, obtained == 1)), silent = TRUE)
  e2 <- pull(m2, "pe:medicaid")

  # 3. SECONDARY obtainment: the demoted interaction.
  m3 <- try(glmmTMB(obtained ~ pe * medicaid + svi_z + (1 | pair) + (1 | npi),
                    family = binomial, data = d), silent = TRUE)
  e3 <- pull(m3, "pe:medicaid")

  # 4. UNCONDITIONAL access among Medicaid calls: non-obtainment is not missing data, it
  #    is the worst possible access outcome. Rank-based test avoids inventing a wait value.
  med2 <- med %>% mutate(acc = ifelse(obtained == 1, business_days, Inf))
  p_unc <- suppressWarnings(stats::wilcox.test(acc ~ pe, data = med2)$p.value)

  tibble(or_med = e1["est"], or_med_lo = e1["lo"], or_med_hi = e1["hi"], or_med_p = e1["p"],
         mcnemar_p = p_mcn, rd = rd, n_discordant = b + cc,
         irr_int = e2["est"], irr_int_lo = e2["lo"], irr_int_hi = e2["hi"], irr_int_p = e2["p"],
         or_int = e3["est"], or_int_lo = e3["lo"], or_int_hi = e3["hi"], or_int_p = e3["p"],
         uncond_p = p_unc)
}

cat(sprintf("Design: %d calls | %d pairs | replicates: %d\n\n",
            nrow(design), n_distinct(design$pair), N_SIMS))

res <- bind_rows(lapply(seq_len(N_SIMS), function(i) {
  set.seed(SEED + i)
  if (i %% 50 == 0) cat(sprintf("  ...%d/%d\n", i, N_SIMS))
  one_rep(simulate_calls(design))
}))
write_csv(res, OUT)

report <- function(est, lo, hi, p, truth, label, scale = "OR") {
  fit <- !is.na(est); usable <- fit & is.finite(p) & is.finite(lo) & is.finite(hi)
  cat(sprintf("\n%s\n", label))
  if (!is.na(truth)) cat(sprintf("  truth (%s)           : %.3f\n", scale, truth))
  cat(sprintf("  usable SE / CI / p    : %d/%d   (%d non-estimable)\n",
              sum(usable), length(est), sum(fit) - sum(usable)))
  if (sum(usable) == 0) { cat("  power                 : not estimable\n"); return(invisible()) }
  if (!is.na(truth)) {
    cat(sprintf("  median estimate       : %.3f   (bias %+.3f)\n",
                median(est[fit], na.rm = TRUE), median(est[fit], na.rm = TRUE) - truth))
    cat(sprintf("  95%% CI coverage       : %.1f%%\n",
                100 * mean(lo[usable] <= truth & hi[usable] >= truth)))
  }
  cat(sprintf("  POWER at p<0.05       : %.1f%% (of all %d replicates)\n",
              100 * sum(p[usable] < 0.05) / length(est), length(est)))
}

cat("================ PROPOSED SAP HIERARCHY ================")
report(res$or_med, res$or_med_lo, res$or_med_hi, res$or_med_p, as.numeric(TRUE_OR_MEDICAID),
       "1. PRIMARY obtainment: PE vs non-PE among Medicaid calls (matched-pair logistic)")
cat(sprintf("     mean risk difference : %+.1f pct pts (truth %+.1f)\n",
            100 * mean(res$rd), 100 * TRUE_RD_MEDICAID))
cat(sprintf("     McNemar power        : %.1f%%  | median discordant pairs: %.0f of 200\n",
            100 * mean(res$mcnemar_p < 0.05, na.rm = TRUE), median(res$n_discordant)))

report(res$irr_int, res$irr_int_lo, res$irr_int_hi, res$irr_int_p, as.numeric(TRUE_IRR_INT),
       "2. PRIMARY wait time: payer x ownership interaction (NB GLMM)", "IRR")
report(res$or_int, res$or_int_lo, res$or_int_hi, res$or_int_p, NA_real_,
       "3. SECONDARY obtainment: payer x ownership interaction (demoted)")
cat(sprintf("\n4. UNCONDITIONAL access among Medicaid calls (non-obtainment ranked worst)\n"))
cat(sprintf("  POWER at p<0.05       : %.1f%%\n", 100 * mean(res$uncond_p < 0.05, na.rm = TRUE)))
cat(sprintf("\nWrote %s\n", OUT))
