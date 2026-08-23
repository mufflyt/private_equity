# Power analysis for the primary wait-time estimand: the ownership-by-insurance interaction.
#
# ANALYSIS MODEL. The simulation draws a per-physician random intercept and gives each
# physician two calls, so it is fitted with glmmTMB(... + (1 | physician), family = nbinom2),
# matching the SAP. An earlier version fitted glm.nb, which assumes independence. For THIS
# estimand the mixed model is more powerful, not less: ownership varies BETWEEN physicians
# while insurance varies WITHIN, so a random intercept absorbs between-physician variance and
# sharpens the within-physician interaction.
#
# HYPOTHESIS. Power is reported for the interaction term alone. An earlier version compared
# `~ pe * insurance` against `~ insurance`, dropping the ownership main effect AND the
# interaction: a 2-degree-of-freedom joint test of "any ownership effect", which is a
# different and easier question than the one the SAP asks.
#
# EFFECT SIZE. Anchored to the closest published mystery-caller study of private equity and
# appointment wait time: Nie et al., Urology 2022, 815 calls to 445 urology offices, mean wait
# 17.5 days at PE-affiliated practices versus 21.4 days at non-PE practices (P = .017). That
# is a wait-time ratio of 17.5/21.4 = 0.818, or 1.22 in the opposite direction.
#
# IMPORTANT: 1.22 is NOT a previously observed PE-by-insurance interaction. Nie et al. reported
# the ownership and insurance main effects separately and did not estimate their interaction
# for wait time; their Medicaid-versus-commercial wait ratio was only 1.047 (P = .59). The
# figure is used here as "the magnitude of the published PE-associated wait-time difference in
# the closest mystery-caller study", which is a defensible anchor for a magnitude we have no
# direct estimate of. Their ACCESS outcome does show the effect modification this study
# hypothesises (Medicaid availability 52.1% at PE versus 66.8% at non-PE; adjusted OR 0.55,
# 95% CI 0.37-0.83), which is why an interaction of this order is plausible for wait time.
#
# Scenarios: conservative 1.10, primary 1.22, larger plausible 1.35.

library(MASS)
suppressMessages(library(glmmTMB))

set.seed(42)

IRR_SCENARIOS <- c(conservative = 1.10, primary = 1.22, larger = 1.35)
ns_to_test    <- c(100, 150, 200, 250, 300, 400)   # matched pairs (1 PE + 1 control each)
sds_to_test   <- c(10, 20)                          # SD of wait times
n_sims        <- 200

# Baseline cell means (business days), unchanged from the original design:
#   commercial, non-PE  = 15      commercial, PE = 15
#   Medicaid,  non-PE   = 30      Medicaid,  PE  = 30 * IRR
mu_bcbs      <- 15.0
mu_med_nonpe <- 30.0

# Dispersion: Var = mu + mu^2/theta, solved at a mean of about 23 days.
theta_for_sd <- function(sd_val) if (sd_val == 10) 6.87 else 1.40

# Random intercept SD is 0.2 on the LOG scale, not in days; the linear predictor is log-link.
RE_SD <- 0.2

results <- data.frame()

for (scen in names(IRR_SCENARIOS)) {
  irr <- IRR_SCENARIOS[[scen]]
  mu_med_pe <- mu_med_nonpe * irr

  beta_0           <- log(mu_bcbs)
  beta_medicaid    <- log(mu_med_nonpe / mu_bcbs)
  beta_pe          <- 0
  beta_interaction <- log(irr)

  for (sd_val in sds_to_test) {
    theta_val <- theta_for_sd(sd_val)
    cat(sprintf("\n=== %s scenario (IRR %.2f, beta %.3f), SD = %d (theta %.2f) ===\n",
                scen, irr, beta_interaction, sd_val, theta_val))

    for (n_pairs in ns_to_test) {
      n_physicians <- 2 * n_pairs
      sig <- 0; usable <- 0

      for (sim in 1:n_sims) {
        physician_ids    <- rep(1:n_physicians, each = 2)
        pe_status        <- rep(c(rep(1, n_physicians / 2), rep(0, n_physicians / 2)), each = 2)
        insurance_status <- rep(c(0, 1), n_physicians)
        u_j              <- rep(rnorm(n_physicians, 0, RE_SD), each = 2)

        eta <- beta_0 + beta_pe * pe_status + beta_medicaid * insurance_status +
               beta_interaction * (pe_status * insurance_status) + u_j
        wait_times <- rnbinom(n = length(eta), mu = exp(eta), size = theta_val)

        sim_df <- data.frame(wait_time = wait_times, pe = pe_status,
                             insurance = insurance_status, physician = factor(physician_ids))

        fit <- try(glmmTMB(wait_time ~ pe * insurance + (1 | physician),
                           family = nbinom2, data = sim_df), silent = TRUE)
        if (inherits(fit, "try-error")) next
        co <- try(summary(fit)$coefficients$cond, silent = TRUE)
        if (inherits(co, "try-error") || !("pe:insurance" %in% rownames(co))) next
        usable <- usable + 1
        p_int <- co["pe:insurance", "Pr(>|z|)"]
        if (!is.na(p_int) && p_int < 0.05) sig <- sig + 1
      }

      power <- if (usable > 0) sig / usable else NA_real_
      cat(sprintf("  N Pairs: %3d | Calls: %4d | Power(interaction): %.3f | usable fits: %d/%d\n",
                  n_pairs, n_physicians * 2, power, usable, n_sims))

      results <- rbind(results, data.frame(
        Scenario = scen, IRR = irr, SD = sd_val, Pairs = n_pairs,
        Physicians = n_physicians, Total_Calls = n_physicians * 2,
        Power = power, Usable_Fits = usable
      ))
    }
  }
}

write.csv(results, "power_analysis_new_results.csv", row.names = FALSE)
cat("\nPower analysis complete.\n")
