# R Script to test the advanced modeling and comparison functions
# added to the mysterycall package.

library(mysterycall)
library(dplyr)
library(glmmTMB)
library(splines)
library(ggplot2)

db_path <- "pe_obgyn_study_database_with_churn.csv"
if (!file.exists(db_path)) {
  stop("Study database not found.")
}

df <- read.csv(db_path, stringsAsFactors = FALSE)

# Filter complete cases for testing
test_df <- df %>%
  filter(!is.na(Latitude), !is.na(Longitude), !is.na(Years.in.Practice), !is.na(Matched_Pair_Group)) %>%
  mutate(
    PE_or_Not = factor(PE_or_Not),
    Matched_Pair_Group = factor(Matched_Pair_Group),
    Years_in_Practice = as.numeric(Years.in.Practice)
  )

# Simulate count wait times with zero-inflation (same-day appointments)
set.seed(42)
n_rows <- nrow(test_df)
test_df$Payer <- rep(c("Medicaid", "BCBS PPO"), length.out = n_rows)

# 1. Simulate wait times (some exactly 0, others positive overdispersed counts)
test_df$business_days <- sapply(1:n_rows, function(i) {
  # 15% probability of same-day appointment (wait time = 0)
  if (rbinom(1, 1, 0.15) == 1) {
    return(0L)
  } else {
    # Positive counts with overdispersion
    mu <- ifelse(test_df$PE_or_Not[i] == "PE", 24.5, 14.2)
    return(rnbinom(1, size = 1.2, mu = mu) + 1L)
  }
})

cat(sprintf("Generated test dataset with %d observations.\n", nrow(test_df)))
cat(sprintf("Proportion of same-day (zero wait) appointments: %.1f%%\n", mean(test_df$business_days == 0) * 100))

# ═══════════════════════════════════════════════════════════════════
# 1. Test mysterycall_model_zero_wait
# ═══════════════════════════════════════════════════════════════════
cat("\n=== Testing mysterycall_model_zero_wait (same-day logistic model) ===\n")
zero_model <- mysterycall_model_zero_wait(
  data = test_df,
  formula = appt_zero ~ PE_or_Not + Payer + Tract_Pct_Female_Medicaid,
  wait_col = "business_days"
)
print(summary(zero_model))

# ═══════════════════════════════════════════════════════════════════
# 2. Test mysterycall_compare_count_families
# ═══════════════════════════════════════════════════════════════════
cat("\n=== Testing mysterycall_compare_count_families (Poisson, nbinom1, nbinom2) ===\n")
# We restrict to positive wait days to meet standard count distribution assumptions
positive_df <- test_df %>% filter(business_days > 0)
comparison_results <- mysterycall_compare_count_families(
  data = positive_df,
  formula = business_days ~ PE_or_Not + Payer + (1 | Matched_Pair_Group)
)
print(comparison_results)

# ═══════════════════════════════════════════════════════════════════
# 3. Test mysterycall_model_nonlinear (Splines & Polynomials)
# ═══════════════════════════════════════════════════════════════════
cat("\n=== Testing mysterycall_model_nonlinear (Natural Cubic Splines) ===\n")
dir.create("figures", showWarnings = FALSE)
nonlinear_res <- mysterycall_model_nonlinear(
  data = positive_df,
  outcome_col = "business_days",
  predictor_col = "Years_in_Practice",
  other_covariates = c("Tract_Pct_Female_Medicaid"),
  type = "spline",
  df_degree = 3,
  plot = TRUE
)

print(summary(nonlinear_res$model))
ggsave("figures/nonlinear_spline_fit.png", plot = nonlinear_res$plot, width = 7.5, height = 4.5, dpi = 300)
cat("Saved non-linear spline visualization to: figures/nonlinear_spline_fit.png\n")
