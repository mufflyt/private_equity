library(MASS)

# ==========================================================================
# Power for the PE MAIN EFFECT on wait time (2-call GYN design).
# Question: is PE's overall new-patient GYN wait longer than control's,
# averaged across insurance arms? (No interaction assumed.)
#
# Control means: BCBS = 15 days, Medicaid = 30 days (15-day insurance gap).
# PE adds a constant `delta` days to BOTH arms (pure main effect):
#   delta = 5.0  -> PE BCBS = 20, PE Medicaid = 35
#   delta = 7.5  -> PE BCBS = 22.5, PE Medicaid = 37.5
# Test: LRT for the `pe` term, glm.nb(wait ~ pe + insurance) vs (wait ~ insurance).
# Same NB/log-link + physician random-effect framework as the interaction sims.
# ==========================================================================

set.seed(42)

ns_to_test    <- c(100, 150, 200, 250, 300, 400)  # pairs (1 PE + 1 Control each)
deltas_to_test<- c(5.0, 7.5)                        # PE main effect, in days
sds_to_test   <- c(10, 20)                          # SD of wait times
n_sims        <- 200

mu_bcbs_nonpe <- 15.0
mu_med_nonpe  <- 30.0

results <- data.frame()

for (delta in deltas_to_test) {
  # Per-cell means (additive PE main effect, no interaction)
  mu_map <- c(
    "0_0" = mu_bcbs_nonpe,          # control, BCBS
    "0_1" = mu_med_nonpe,           # control, Medicaid
    "1_0" = mu_bcbs_nonpe + delta,  # PE, BCBS
    "1_1" = mu_med_nonpe + delta    # PE, Medicaid
  )

  for (sd_val in sds_to_test) {
    theta_val <- if (sd_val == 10) 6.87 else 1.40
    cat(paste("\n=== PE main effect =", delta, "days | SD =", sd_val,
              "(Theta =", round(theta_val, 2), ") ===\n"))

    for (n_pairs in ns_to_test) {
      n_physicians <- 2 * n_pairs
      significant_lrt_count <- 0

      for (sim in 1:n_sims) {
        physician_ids    <- rep(1:n_physicians, each = 2)
        pe_status        <- rep(c(rep(1, n_physicians/2), rep(0, n_physicians/2)), each = 2)
        insurance_status <- rep(c(0, 1), n_physicians)      # 0 = BCBS, 1 = Medicaid
        u_j              <- rep(rnorm(n_physicians, mean = 0, sd = 0.2), each = 2)

        base_mu <- mu_map[paste(pe_status, insurance_status, sep = "_")]
        mu_ij   <- base_mu * exp(u_j)                        # multiplicative physician random effect
        wait_times <- rnbinom(n = length(mu_ij), mu = mu_ij, size = theta_val)

        sim_df <- data.frame(wait_time = wait_times, pe = pe_status,
                             insurance = insurance_status, physician = factor(physician_ids))

        tryCatch({
          fit_full    <- glm.nb(wait_time ~ pe + insurance, data = sim_df)
          fit_reduced <- glm.nb(wait_time ~ insurance, data = sim_df)   # drop the PE main effect
          p_val <- anova(fit_reduced, fit_full)$`Pr(Chi)`[2]
          if (!is.na(p_val) && p_val < 0.05) significant_lrt_count <- significant_lrt_count + 1
        }, error = function(e) {})
      }

      power <- significant_lrt_count / n_sims
      cat(paste("N Pairs:", n_pairs, "| Calls:", n_physicians * 2, "| Power:", round(power, 3), "\n"))
      results <- rbind(results, data.frame(Effect = paste0("main_", delta, "day"), Delta = delta,
        SD = sd_val, Pairs = n_pairs, Physicians = n_physicians,
        Total_Calls = n_physicians * 2, Power = power))
    }
  }
}

write.csv(results, "/Users/tylermuffly/private_equity/power_maineffect_results.csv", row.names = FALSE)
print("PE main-effect power analysis complete!")
