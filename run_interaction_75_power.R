library(MASS)
library(lme4)

# ==========================================================================
# Power for the PE x Medicaid INTERACTION on wait time (2-call GYN design)
# Effect size: 7.5-day difference in the insurance-based wait-time gap.
#   Non-PE gap  = 30 - 15 = 15 days
#   PE gap      = 37.5 - 15 = 22.5 days  => 7.5-day difference in the gap
# Identical framework to run_new_power_analysis.R (which tests the 5-day gap).
# ==========================================================================

set.seed(42)

ns_to_test <- c(100, 150, 200, 250, 300, 400) # pairs (1 PE + 1 Control each)
sds_to_test <- c(10, 20)                       # SD of wait times
n_sims <- 200

mu_bcbs_nonpe <- 15.0
mu_med_nonpe  <- 30.0   # 15-day baseline insurance gap
mu_bcbs_pe    <- 15.0
mu_med_pe     <- 37.5   # PE Medicaid mean => 22.5-day gap => 7.5-day interaction

beta_0           <- log(mu_bcbs_nonpe)
beta_medicaid    <- log(mu_med_nonpe / mu_bcbs_nonpe)
beta_pe          <- log(mu_bcbs_pe / mu_bcbs_nonpe)
beta_interaction <- log(mu_med_pe / (mu_bcbs_pe * (mu_med_nonpe / mu_bcbs_nonpe)))

results <- data.frame()

for (sd_val in sds_to_test) {
  theta_val <- if (sd_val == 10) 6.87 else 1.40   # Var = mu + mu^2/theta, calibrated at mean ~23
  cat(paste("\n=== 7.5-day interaction | SD =", sd_val, "(Theta =", round(theta_val, 2), ") ===\n"))

  for (n_pairs in ns_to_test) {
    n_physicians <- 2 * n_pairs
    significant_lrt_count <- 0

    for (sim in 1:n_sims) {
      physician_ids   <- rep(1:n_physicians, each = 2)
      pe_status       <- rep(c(rep(1, n_physicians/2), rep(0, n_physicians/2)), each = 2)
      insurance_status<- rep(c(0, 1), n_physicians)          # 0 = BCBS, 1 = Medicaid
      u_j             <- rep(rnorm(n_physicians, mean = 0, sd = 0.2), each = 2)

      eta <- beta_0 + beta_pe * pe_status + beta_medicaid * insurance_status +
             beta_interaction * (pe_status * insurance_status) + u_j
      wait_times <- rnbinom(n = length(eta), mu = exp(eta), size = theta_val)

      sim_df <- data.frame(wait_time = wait_times, pe = pe_status,
                           insurance = insurance_status, physician = factor(physician_ids))

      tryCatch({
        fit_full    <- glm.nb(wait_time ~ pe * insurance, data = sim_df)
        fit_reduced <- glm.nb(wait_time ~ insurance, data = sim_df)   # same test as the 5-day run (comparable)
        p_val <- anova(fit_reduced, fit_full)$`Pr(Chi)`[2]
        if (!is.na(p_val) && p_val < 0.05) significant_lrt_count <- significant_lrt_count + 1
      }, error = function(e) {})
    }

    power <- significant_lrt_count / n_sims
    cat(paste("N Pairs:", n_pairs, "| Calls:", n_physicians * 2, "| Power:", round(power, 3), "\n"))
    results <- rbind(results, data.frame(Effect = "interaction_7.5day", SD = sd_val,
      Pairs = n_pairs, Physicians = n_physicians, Total_Calls = n_physicians * 2, Power = power))
  }
}

write.csv(results, "/Users/tylermuffly/private_equity/power_interaction_75_results.csv", row.names = FALSE)
print("7.5-day interaction power analysis complete!")
