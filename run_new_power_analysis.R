library(MASS)
library(lme4)

# Set seed for reproducibility
set.seed(42)

# Power analysis simulation parameters
ns_to_test <- c(100, 150, 200, 250, 300, 400) # Number of pairs (each pair = 1 PE + 1 Control physician)
sds_to_test <- c(10, 20)                       # SD of wait times
n_sims <- 200                                 # Number of simulation iterations (keep at 200 for speed)

# Baseline parameters:
# - Baseline wait time (BCBS, Non-PE): 15 days
# - Medicaid main effect: 15 days increase (so Medicaid mean = 30 days)
# - PE main effect: 0 days (BCBS wait is same for PE and Non-PE, 15 days)
# - PE * Medicaid interaction: 5 days increase (PE Medicaid mean = 35 days, which is a 5-day difference in the insurance gap!)
# - GYN Scenario main effect: let's assume GYN has slightly shorter wait times than OB (-2 days, mean GYN BCBS = 13 days)
# - Random intercept SD (physician-level correlation): 3 days

mu_bcbs_nonpe <- 15.0
mu_med_nonpe <- 30.0  # 15-day baseline insurance gap
mu_bcbs_pe <- 15.0
mu_med_pe <- 35.0     # 20-day PE insurance gap (5-day interaction effect)

beta_0 <- log(mu_bcbs_nonpe)                  # Intercept
beta_medicaid <- log(mu_med_nonpe / mu_bcbs_nonpe) # log(30/15) = 0.693
beta_pe <- log(mu_bcbs_pe / mu_bcbs_nonpe)         # log(15/15) = 0
beta_interaction <- log(mu_med_pe / (mu_bcbs_pe * (mu_med_nonpe / mu_bcbs_nonpe))) # log(35/30) = 0.154
beta_scenario <- log(13 / 15)                      # Scenario GYN effect: log(13/15) = -0.143

# Dispersion parameter theta calculation based on Var = mu + mu^2 / theta
# Since we want SD = 10 or 20 when mean is around 20-25 days:
# If mean is ~23 days:
# SD = 10 => Var = 100 => theta = 23^2 / (100 - 23) = 529 / 77 = 6.87
# SD = 20 => Var = 400 => theta = 23^2 / (400 - 23) = 529 / 377 = 1.40

results <- data.frame()

for (sd_val in sds_to_test) {
  # Calculate theta for target SD when mean is around 23 days
  if (sd_val == 10) {
    theta_val <- 6.87
  } else {
    theta_val <- 1.40
  }
  
  cat(paste("\n=== Running Simulations for SD =", sd_val, "(Theta =", round(theta_val, 2), ") ===\n"))
  
  for (n_pairs in ns_to_test) {
    n_physicians <- 2 * n_pairs
    significant_lrt_count <- 0
    
    for (sim in 1:n_sims) {
      # Create dataset
      # Each physician has 2 calls: (BCBS vs Medicaid) for GYN scenario
      physician_ids <- rep(1:n_physicians, each = 2)
      pe_status <- rep(c(rep(1, n_physicians/2), rep(0, n_physicians/2)), each = 2)
      insurance_status <- rep(c(0, 1), n_physicians) # 0 = BCBS, 1 = Medicaid
      
      # Simulate random intercept for each physician
      u_j <- rep(rnorm(n_physicians, mean = 0, sd = 0.2), each = 2) # Physician random effect
      
      # Calculate linear predictor
      eta <- beta_0 + 
             beta_pe * pe_status + 
             beta_medicaid * insurance_status + 
             beta_interaction * (pe_status * insurance_status) + 
             u_j
      
      mu <- exp(eta)
      
      # Simulate wait times from Negative Binomial
      wait_times <- rnbinom(n = length(mu), mu = mu, size = theta_val)
      
      # Create dataframe
      sim_df <- data.frame(
        wait_time = wait_times,
        pe = pe_status,
        insurance = insurance_status,
        physician = factor(physician_ids)
      )
      
      # Fit negative binomial models
      tryCatch({
        fit_full <- glm.nb(wait_time ~ pe * insurance, data = sim_df)
        fit_reduced <- glm.nb(wait_time ~ insurance, data = sim_df)
        
        # Likelihood Ratio Test (LRT)
        lrt <- anova(fit_reduced, fit_full)
        p_val <- lrt$`Pr(Chi)`[2]
        
        if (!is.na(p_val) && p_val < 0.05) {
          significant_lrt_count <- significant_lrt_count + 1
        }
      }, error = function(e) {})
    }
    
    power <- significant_lrt_count / n_sims
    cat(paste("N Pairs:", n_pairs, "| Physicians:", n_physicians, "| Calls:", n_physicians * 2, "| Power:", round(power, 3), "\n"))
    
    results <- rbind(results, data.frame(
      SD = sd_val,
      Pairs = n_pairs,
      Physicians = n_physicians,
      Total_Calls = n_physicians * 2,
      Power = power
    ))
  }
}

# Write results table to CSV
write.csv(results, "/Users/tylermuffly/private_equity/power_analysis_new_results.csv", row.names = FALSE)
print("Power analysis simulation complete!")
