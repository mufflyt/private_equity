# Set seed for reproducibility
set.seed(42)

ns_to_test <- c(100, 150, 200, 250, 300) # Number of pairs (each pair = 1 PE + 1 Control)
pe_med_rates <- c(0.45, 0.40, 0.35, 0.30) # Medicaid acceptance rates for PE (Control Medicaid is fixed at 0.70)
n_sims <- 200

# Base parameters:
# - BCBS Private acceptance rate (both groups): 98%
# - Control Medicaid acceptance rate: 70%
# - We test the power to detect the interaction (PE * Insurance) using a mixed-effects logistic regression

results <- data.frame()

for (pe_rate in pe_med_rates) {
  cat(paste("\n=== Running Simulations for PE Medicaid Acceptance =", round(pe_rate * 100, 1), "% (Control = 70.0%) ===\n"))
  
  # Log-odds calculation:
  # - Non-PE BCBS: p = 0.98 => odds = 49 => log-odds = 3.89
  # - Non-PE Medicaid: p = 0.70 => odds = 2.33 => log-odds = 0.85
  #   Medicaid main effect = 0.85 - 3.89 = -3.04
  # - PE BCBS: p = 0.98 => odds = 49 => log-odds = 3.89 (PE main effect = 0)
  # - PE Medicaid: p = pe_rate
  #   If PE Medicaid = 0.40 => odds = 0.67 => log-odds = -0.41
  #   Interaction term = (-0.41 - 3.89) - (-3.04) = -4.30 - (-3.04) = -1.26
  
  p_ctrl_bcbs <- 0.98
  p_ctrl_med <- 0.70
  p_pe_bcbs <- 0.98
  p_pe_med <- pe_rate
  
  lo_ctrl_bcbs <- log(p_ctrl_bcbs / (1 - p_ctrl_bcbs))
  lo_ctrl_med <- log(p_ctrl_med / (1 - p_ctrl_med))
  lo_pe_bcbs <- log(p_pe_bcbs / (1 - p_pe_bcbs))
  lo_pe_med <- log(p_pe_med / (1 - p_pe_med))
  
  beta_0 <- lo_ctrl_bcbs
  beta_medicaid <- lo_ctrl_med - lo_ctrl_bcbs
  beta_pe <- lo_pe_bcbs - lo_ctrl_bcbs
  beta_interaction <- (lo_pe_med - lo_pe_bcbs) - (lo_ctrl_med - lo_ctrl_bcbs)
  
  for (n_pairs in ns_to_test) {
    n_physicians <- 2 * n_pairs
    significant_count <- 0
    
    for (sim in 1:n_sims) {
      # 2 calls per physician (1 Medicaid, 1 BCBS)
      phys_ids <- rep(1:n_physicians, each = 2)
      pe_status <- rep(c(rep(1, n_physicians/2), rep(0, n_physicians/2)), each = 2)
      insurance_status <- rep(c(0, 1), n_physicians) # 0 = BCBS, 1 = Medicaid
      
      # Simulate random intercept for matched pairs (or physician correlation)
      u_j <- rep(rnorm(n_physicians, 0, 0.5), each = 2)
      
      # Probability on logit scale
      logit_p <- beta_0 + 
                 beta_pe * pe_status + 
                 beta_medicaid * insurance_status + 
                 beta_interaction * (pe_status * insurance_status) + 
                 u_j
      
      p <- 1 / (1 + exp(-logit_p))
      
      # Simulate binary obtainment outcome
      obtained <- rbinom(length(p), 1, p)
      
      sim_df <- data.frame(
        obtained = obtained,
        pe = pe_status,
        insurance = insurance_status,
        physician = factor(phys_ids)
      )
      
      # Fit logistic mixed model or logistic regression
      tryCatch({
        fit <- glm(obtained ~ pe * insurance, data = sim_df, family = binomial(link = "logit"))
        coefs <- summary(fit)$coefficients
        p_val <- coefs["pe:insurance", "Pr(>|z|)"]
        
        if (!is.na(p_val) && p_val < 0.05) {
          significant_count <- significant_count + 1
        }
      }, error = function(e) {})
    }
    
    power <- significant_count / n_sims
    cat(paste("N Pairs:", n_pairs, "| Physicians:", n_physicians, "| Calls:", n_physicians * 2, "| Power:", round(power, 3), "\n"))
    
    results <- rbind(results, data.frame(
      PE_Medicaid_Rate = pe_rate,
      Pairs = n_pairs,
      Physicians = n_physicians,
      Total_Calls = n_physicians * 2,
      Power = power
    ))
  }
}

# Write results
write.csv(results, "/Users/tylermuffly/private_equity/obtainment_power_results.csv", row.names = FALSE)
print("Obtainment power simulation complete!")
