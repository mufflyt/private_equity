#!/usr/bin/env Rscript
# Dry run of the pre-specified analysis, before any real calls are logged.
#
# Purpose: rehearse the exact models the manuscript specifies against the REAL fielded
# design (real 200 pairs, real ownership assignment, real CDC SVI) with SIMULATED call
# outcomes, to answer three questions before Taylor starts dialling:
#   1. Do the specified models converge and are all terms identifiable at n = 200 pairs?
#   2. Do they recover the effects they were generated from (no coding/spec error)?
#   3. What is the realised power for the two interaction terms that carry the paper?
#
# NOTHING HERE IS A RESULT. Every outcome is simulated. The point is to test the
# analysis code, not to learn anything about private equity.
#
# Usage:
#   Rscript dry_run_analysis.R              # 1 showcase fit + 200-replicate power run
#   Rscript dry_run_analysis.R --sims=50    # quicker
#   Rscript dry_run_analysis.R --sims=0     # showcase fit only

suppressMessages({library(readr); library(dplyr); library(tidyr); library(glmmTMB)})

SHEET  <- "pe_obgyn_final_calling_sheet_200.csv"
OUT    <- "dry_run_analysis_results.csv"
SEED   <- 1978L
args   <- commandArgs(trailingOnly = TRUE)
N_SIMS <- as.integer(sub("^--sims=", "", grep("^--sims=", args, value = TRUE)[1]))
if (is.na(N_SIMS)) N_SIMS <- 200L

# ---------------------------------------------------------------- targets
# Cell means taken verbatim from the manuscript's dummy Tables 2 and 3, so the
# simulation reproduces the paper's own placeholder story.
P_OBTAIN <- c(ctrl_bcbs = 0.985, pe_bcbs = 0.990, ctrl_medicaid = 0.725, pe_medicaid = 0.410)
MU_WAIT  <- c(ctrl_bcbs = 12.1,  pe_bcbs = 14.5,  ctrl_medicaid = 23.4,  pe_medicaid = 36.8)
SD_WAIT  <- c(ctrl_bcbs = 6.8,   pe_bcbs = 8.2,   ctrl_medicaid = 11.2,  pe_medicaid = 18.4)

# Supplemental Table 1 variance components, on the log/logit scale.
SD_CLIN <- sqrt(0.082)
SD_PAIR <- sqrt(0.054)

# Negative binomial dispersion implied by the Table 3 mean/SD pairs: theta = mu^2/(var-mu).
THETA <- local({
  th <- MU_WAIT^2 / (SD_WAIT^2 - MU_WAIT)
  cat(sprintf("Dispersion implied by Table 3 (theta): %s -> using %.2f\n",
              paste(sprintf("%.2f", th), collapse = ", "), mean(th)))
  mean(th)
})

# Truth on the model scale, i.e. what a correctly specified fit must return.
TRUE_OR_INT  <- (P_OBTAIN["pe_medicaid"] / (1 - P_OBTAIN["pe_medicaid"])) /
                (P_OBTAIN["pe_bcbs"]     / (1 - P_OBTAIN["pe_bcbs"])) /
               ((P_OBTAIN["ctrl_medicaid"] / (1 - P_OBTAIN["ctrl_medicaid"])) /
                (P_OBTAIN["ctrl_bcbs"]     / (1 - P_OBTAIN["ctrl_bcbs"])))
TRUE_IRR_INT <- (MU_WAIT["pe_medicaid"] / MU_WAIT["pe_bcbs"]) /
                (MU_WAIT["ctrl_medicaid"] / MU_WAIT["ctrl_bcbs"])

# ---------------------------------------------------------------- design

if (!file.exists(SHEET)) stop(sprintf("Fielded sheet not found: %s", SHEET))
sheet <- read_csv(SHEET, show_col_types = FALSE)
stopifnot("expected 400 fielded clinicians" = nrow(sheet) == 400L)

# One row per call: 400 clinicians x 2 payer arms = 800.
design <- sheet %>%
  transmute(npi = as.character(NPI), pair = `Matched Pair ID`, State,
            pe = as.integer(PE_or_Not == "PE"),
            svi = suppressWarnings(as.numeric(CDC_SVI))) %>%
  mutate(svi_z = as.numeric(scale(ifelse(is.na(svi), median(svi, na.rm = TRUE), svi)))) %>%
  tidyr::crossing(payer = c("BCBS", "Medicaid")) %>%
  mutate(medicaid = as.integer(payer == "Medicaid"),
         cell = paste0(ifelse(pe == 1, "pe", "ctrl"), "_", tolower(payer)))

cat(sprintf("Design: %d calls | %d clinicians | %d pairs | %d states | SVI missing: %d\n",
            nrow(design), n_distinct(design$npi), n_distinct(design$pair),
            n_distinct(design$State), sum(is.na(design$svi))))

# ---------------------------------------------------------------- simulate

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

# ---------------------------------------------------------------- fit
# Exactly the manuscript specification: ownership x payer interaction, CDC SVI, and
# random intercepts for matched pair and individual clinician.

fit_both <- function(d) {
  ob <- try(glmmTMB(obtained ~ pe * medicaid + svi_z + (1 | pair) + (1 | npi),
                    family = binomial, data = d), silent = TRUE)
  wt <- try(glmmTMB(business_days ~ pe * medicaid + svi_z + (1 | pair) + (1 | npi),
                    family = nbinom2, data = filter(d, obtained == 1)), silent = TRUE)
  list(ob = ob, wt = wt)
}

grab <- function(m, term) {
  if (inherits(m, "try-error")) return(c(est = NA, lo = NA, hi = NA, p = NA))
  co <- summary(m)$coefficients$cond
  if (!term %in% rownames(co)) return(c(est = NA, lo = NA, hi = NA, p = NA))
  b <- co[term, "Estimate"]; se <- co[term, "Std. Error"]
  c(est = exp(b), lo = exp(b - 1.96 * se), hi = exp(b + 1.96 * se), p = co[term, "Pr(>|z|)"])
}

set.seed(SEED)
d1  <- simulate_calls(design)
f1  <- fit_both(d1)

cat("\n================ SHOWCASE REPLICATE (one simulated dataset) ================\n")
cat(sprintf("Obtainment model: %s | Wait-time model: %s\n",
            ifelse(inherits(f1$ob, "try-error"), "FAILED", "converged"),
            ifelse(inherits(f1$wt, "try-error"), "FAILED", "converged")))

cat("\n--- Table 2: appointment obtainment (simulated) ---\n")
t2 <- d1 %>% group_by(Ownership = ifelse(pe == 1, "PE-backed", "Independent"), payer) %>%
  summarise(n = n(), n_obtained = sum(obtained), pct = 100 * mean(obtained), .groups = "drop") %>%
  arrange(payer, Ownership)
print(as.data.frame(t2), row.names = FALSE, digits = 3)

cat("\n--- Table 3: wait times among scheduled (simulated) ---\n")
t3 <- d1 %>% filter(obtained == 1) %>%
  group_by(Ownership = ifelse(pe == 1, "PE-backed", "Independent"), payer) %>%
  summarise(n = n(), mean_days = mean(business_days), sd = sd(business_days), .groups = "drop") %>%
  arrange(Ownership, payer)
print(as.data.frame(t3), row.names = FALSE, digits = 3)
gap <- t3 %>% select(Ownership, payer, mean_days) %>%
  tidyr::pivot_wider(names_from = payer, values_from = mean_days) %>%
  mutate(gap_days = Medicaid - BCBS)
print(as.data.frame(gap), row.names = FALSE, digits = 3)

cat("\n--- Table 4: model estimates (simulated) ---\n")
terms <- c(Payer = "medicaid", Ownership = "pe", `Payer x Ownership` = "pe:medicaid", SVI = "svi_z")
t4 <- bind_rows(lapply(names(terms), function(nm) {
  o <- grab(f1$ob, terms[[nm]]); w <- grab(f1$wt, terms[[nm]])
  tibble(Term = nm,
         OR = o["est"], OR_CI = sprintf("%.2f-%.2f", o["lo"], o["hi"]), OR_p = o["p"],
         IRR = w["est"], IRR_CI = sprintf("%.2f-%.2f", w["lo"], w["hi"]), IRR_p = w["p"])
}))
print(as.data.frame(t4), row.names = FALSE, digits = 3)

vc <- function(m, lbl) {
  if (inherits(m, "try-error")) return(invisible(NULL))
  v <- glmmTMB::VarCorr(m)$cond
  cat(sprintf("  %-18s clinician var = %.4f | pair var = %.4f\n", lbl,
              as.numeric(v$npi), as.numeric(v$pair)))
}
cat("\n--- Variance components (Supplemental Table 1) ---\n")
cat(sprintf("  %-18s clinician var = %.4f | pair var = %.4f  (generated)\n",
            "TRUTH", SD_CLIN^2, SD_PAIR^2))
vc(f1$ob, "obtainment"); vc(f1$wt, "wait time")

# ---------------------------------------------------------------- replicates

if (N_SIMS > 0) {
  cat(sprintf("\n================ %d REPLICATES (recovery + power) ================\n", N_SIMS))
  res <- vector("list", N_SIMS)
  for (i in seq_len(N_SIMS)) {
    set.seed(SEED + i)
    f <- fit_both(simulate_calls(design))
    o <- grab(f$ob, "pe:medicaid"); w <- grab(f$wt, "pe:medicaid")
    res[[i]] <- tibble(sim = i,
                       or_est = o["est"], or_p = o["p"], or_lo = o["lo"], or_hi = o["hi"],
                       or_ok = !inherits(f$ob, "try-error"),
                       irr_est = w["est"], irr_p = w["p"], irr_lo = w["lo"], irr_hi = w["hi"],
                       irr_ok = !inherits(f$wt, "try-error"))
    if (i %% 25 == 0) cat(sprintf("  ...%d/%d\n", i, N_SIMS))
  }
  res <- bind_rows(res)
  write_csv(res, OUT)

  summarise_term <- function(est, p, lo, hi, ok, truth, label) {
    fit  <- ok & !is.na(est)
    # A fit can return a point estimate but no usable standard error when the Hessian is
    # not positive-definite. Those replicates yield no CI and no p-value, so they cannot
    # contribute to power -- count them rather than dropping them silently.
    usable <- fit & is.finite(p) & is.finite(lo) & is.finite(hi)
    cat(sprintf("\n%s (truth = %.3f)\n", label, truth))
    cat(sprintf("  model returned estimate : %d/%d\n", sum(fit), length(est)))
    cat(sprintf("  usable SE / CI / p      : %d/%d   (%d with non-estimable SE)\n",
                sum(usable), length(est), sum(fit) - sum(usable)))
    cat(sprintf("  median estimate         : %.3f   (bias %+.3f)\n",
                median(est[fit], na.rm = TRUE), median(est[fit], na.rm = TRUE) - truth))
    if (sum(usable) == 0) { cat("  CI coverage / power     : not estimable\n"); return(invisible()) }
    cat(sprintf("  95%% CI coverage         : %.1f%% (of usable)\n",
                100 * mean(lo[usable] <= truth & hi[usable] >= truth)))
    cat(sprintf("  POWER at p<0.05         : %.1f%% (of usable)  |  %.1f%% (of all %d replicates)\n",
                100 * mean(p[usable] < 0.05),
                100 * sum(p[usable] < 0.05) / length(est), length(est)))
  }
  summarise_term(res$or_est, res$or_p, res$or_lo, res$or_hi, res$or_ok,
                 as.numeric(TRUE_OR_INT),  "Obtainment: payer x ownership OR")
  summarise_term(res$irr_est, res$irr_p, res$irr_lo, res$irr_hi, res$irr_ok,
                 as.numeric(TRUE_IRR_INT), "Wait time: payer x ownership IRR")
  cat(sprintf("\nWrote %s\n", OUT))
}

# ---------------------------------------------------------------- coherence check
# The dummy tables should agree with each other. Recompute Table 4's interaction terms
# from the Table 2 / Table 3 cell values and compare with what Table 4 states.
cat("\n================ MANUSCRIPT INTERNAL COHERENCE ================\n")
cat(sprintf("Interaction OR  implied by Table 2 cells : %.3f   | Table 4 states 0.28\n", TRUE_OR_INT))
cat(sprintf("Interaction IRR implied by Table 3 cells : %.3f   | Table 4 states 1.62\n", TRUE_IRR_INT))
cat(sprintf("Payer IRR       implied by Table 3 cells : %.3f   | Table 4 states 1.93\n",
            MU_WAIT["ctrl_medicaid"] / MU_WAIT["ctrl_bcbs"]))
cat(sprintf("Ownership IRR   implied by Table 3 cells : %.3f   | Table 4 states 1.20\n",
            MU_WAIT["pe_bcbs"] / MU_WAIT["ctrl_bcbs"]))
