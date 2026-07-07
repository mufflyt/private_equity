# R Script to test the no-external-validation helper layer functions
# in the mysterycall package.

library(mysterycall)
library(dplyr)
library(ggplot2)
library(glmmTMB)
library(splines)

db_path <- "/Users/tylermuffly/private_equity/pe_obgyn_study_database_with_churn.csv"
if (!file.exists(db_path)) {
  stop("Study database not found.")
}

df <- read.csv(db_path, stringsAsFactors = FALSE)

# Clean and prepare complete dataset for validation testing
test_df <- df %>%
  filter(!is.na(Latitude), !is.na(Longitude), !is.na(Matched_Pair_Group)) %>%
  mutate(
    PE_or_Not = factor(PE_or_Not),
    Matched_Pair_Group = factor(Matched_Pair_Group)
  )

# Add simulated outcome, temporal, and clustering columns for testing
set.seed(1234)
n_obs <- nrow(test_df)

# 1. Create a temporal column: random years from 2015 to 2024
test_df$Year <- sample(2015:2024, n_obs, replace = TRUE)

# 2. Create a cluster column: office_id (using existing or simulated)
test_df$Cluster_ID <- if ("office_id" %in% names(test_df)) {
  factor(test_df$office_id)
} else {
  factor(sample(1:50, n_obs, replace = TRUE))
}

# 3. Simulate binary obtainment outcome (0/1) and count wait times
test_df$appt_obtained <- rbinom(n_obs, 1, 0.6)
test_df$business_days <- rnbinom(n_obs, size = 1.5, mu = 15)

cat(sprintf("Prepared test dataset with %d observations and %d unique clusters.\n", 
            nrow(test_df), length(unique(test_df$Cluster_ID))))

# ═══════════════════════════════════════════════════════════════════
# 1. Test mysterycall_temporal_validation
# ═══════════════════════════════════════════════════════════════════
cat("\n=== 1. Testing mysterycall_temporal_validation ===\n")
temp_res <- mysterycall_temporal_validation(
  data = test_df,
  outcome = "business_days",
  predictors = c("PE_or_Not", "Tract_Pct_Female_Medicaid"),
  time_col = "Year",
  threshold = 2020,
  family = "nbinom"
)
print(temp_res$metrics)

# ═══════════════════════════════════════════════════════════════════
# 2. Test mysterycall_recalibration_assessment
# ═══════════════════════════════════════════════════════════════════
cat("\n=== 2. Testing mysterycall_recalibration_assessment ===\n")
# Fit a quick logistic model to get predicted probabilities
logistic_fit <- glm(appt_obtained ~ PE_or_Not + Tract_Pct_Female_Medicaid, data = test_df, family = binomial)
test_df$pred_prob <- predict(logistic_fit, type = "response")

recal_res <- mysterycall_recalibration_assessment(
  observed = test_df$appt_obtained,
  predicted = test_df$pred_prob,
  family = "binomial",
  plot = TRUE
)
cat(sprintf("Calibration Slope: %.3f (Ideal = 1.0)\n", recal_res$calibration_slope))
cat(sprintf("Calibration Intercept: %.3f (Ideal = 0.0)\n", recal_res$calibration_intercept))

# Save the calibration plot
dir.create("/Users/tylermuffly/private_equity/figures", showWarnings = FALSE)
ggsave("/Users/tylermuffly/private_equity/figures/recalibration_plot.png", plot = recal_res$plot, width = 7.5, height = 4.5, dpi = 300)
cat("Recalibration plot saved to: /Users/tylermuffly/private_equity/figures/recalibration_plot.png\n")

# ═══════════════════════════════════════════════════════════════════
# 3. Test mysterycall_provider_split_simulation (Cluster CV)
# ═══════════════════════════════════════════════════════════════════
cat("\n=== 3. Testing mysterycall_provider_split_simulation ===\n")
cv_res <- mysterycall_provider_split_simulation(
  data = test_df,
  outcome = "business_days",
  predictors = c("PE_or_Not", "Tract_Pct_Female_Medicaid"),
  cluster_col = "Cluster_ID",
  k = 5,
  family = "nbinom"
)
print(cv_res)

# ═══════════════════════════════════════════════════════════════════
# 4. Test mysterycall_bootstrap_predictor_stability
# ═══════════════════════════════════════════════════════════════════
cat("\n=== 4. Testing mysterycall_bootstrap_predictor_stability ===\n")
stability_res <- mysterycall_bootstrap_predictor_stability(
  data = test_df,
  outcome = "appt_obtained",
  predictors = c("PE_or_Not", "Tract_Pct_Female_Medicaid", "Tract_Pct_Female_Medicare"),
  n_boot = 50,
  p_threshold = 0.1,
  family = "binomial"
)
print(stability_res)
cat("\nAll 4 functions in the no-external-validation helper layer executed successfully!\n")
