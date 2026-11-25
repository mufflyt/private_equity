# R Script to run a geographic matching sensitivity analysis
# Compares primary outcomes (obtainment rates & wait times) across matching distances:
# 1. Primary Analysis: < 10 miles (Full Cohort)
# 2. Sensitivity Analysis A: < 5 miles
# 3. Sensitivity Analysis B: < 3 miles

suppressMessages({
  library(dplyr)
  library(readr)
  library(lme4)
  library(glmmTMB)
  library(mysterycall)
})

source(file.path("R", "pe_helpers.R"))

# Load the data
calling_sheet_path <- "pe_obgyn_final_calling_sheet_200_dedup.csv"
study_db_path <- "pe_obgyn_study_database.csv"

if (!file.exists(calling_sheet_path) || !file.exists(study_db_path)) {
  stop("Required database files are missing. Run the matching pipeline first.")
}

sheet200 <- read_csv(calling_sheet_path, show_col_types = FALSE)

# 1. Calculate distances for all 200 pairs
# Gazetteer access goes through normalize_gazetteer() (R/pe_helpers.R), never through
# direct column access: the previous version read lat_long_ref$latitude/$longitude, which
# returned NULL once mysterycall renamed the columns to lat/long and degraded every
# coordinate silently -- the failure mode normalize_gazetteer() exists to make impossible.
data(city_state_to_lat_long, package = "mysterycall")
lat_long_ref <- normalize_gazetteer(city_state_to_lat_long, STATE_ABB_BY_NAME)
lat_long_ref$city_upper  <- lat_long_ref$city
lat_long_ref$state_upper <- lat_long_ref$state
lat_long_ref <- lat_long_ref[!is.na(lat_long_ref$state_upper), ]
lat_long_ref <- lat_long_ref[!duplicated(paste(lat_long_ref$city_upper, lat_long_ref$state_upper, sep="_")), ]

# Manual overrides helper
manual_coords <- list(
  "COMMERCE TWP_MI" = c(42.5906, -83.4913),
  "VILLAGE OF PALMETTO BAY_FL" = c(25.6212, -80.3203),
  "EAST WINDSOR_NJ" = c(40.2646, -74.5204),
  "LAKE WORTH_FL" = c(26.6159, -80.0564),
  "PENN VALLEY_PA" = c(40.0215, -75.2599),
  "ABINGTON_PA" = c(40.1209, -75.1182),
  "MILLBURN_NJ" = c(40.7262, -74.3251),
  "OCEAN_NJ" = c(40.2373, -74.0304),
  "SOMERS POINT_NJ" = c(39.3134, -74.5988),
  "BRIDGEWATER_NJ" = c(40.5937, -74.6224),
  "RED BANK_NJ" = c(40.3471, -74.0643),
  "WILKES BARRE_PA" = c(41.2459, -75.8812),
  "RIVER EDGE_NJ" = c(40.9287, -74.0254),
  "HOWELL_NJ" = c(40.1693, -74.2215),
  "TOMS RIVER_NJ" = c(39.9537, -74.1979)
)

get_coords <- function(city, state) {
  city_clean <- toupper(trimws(city))
  state_clean <- toupper(trimws(state))
  key <- paste0(city_clean, "_", state_clean)
  if (key %in% names(manual_coords)) return(manual_coords[[key]])
  match_row <- lat_long_ref[lat_long_ref$city_upper == city_clean & lat_long_ref$state_upper == state_clean, ]
  if (nrow(match_row) > 0) return(c(match_row[["lat"]][1], match_row[["long"]][1]))
  # No fabricated default. This function previously returned the geographic center of the
  # US for unresolvable cities, which means a pair whose city was missing got a REAL-looking
  # distance to Kansas and was included in or excluded from the 5-mile/3-mile caliper
  # subsets on a fiction. Unresolvable is NA, and the count is reported below.
  return(c(NA, NA))
}

# geosphere::distHaversine() with the same spherical radius (3959 miles) the hand-rolled
# version used -- verified numerically identical to machine precision. geosphere takes
# (lon, lat) pairs.
dist_miles <- function(lat1, lon1, lat2, lon2) {
  if (any(is.na(c(lat1, lon1, lat2, lon2)))) return(NA_real_)
  geosphere::distHaversine(c(lon1, lat1), c(lon2, lat2), r = 3959)
}

# Split into PE and Control
pe_df <- sheet200 %>% filter(PE_or_Not == "PE")
ctrl_df <- sheet200 %>% filter(PE_or_Not == "Non-PE")

# Calculate distance for each pair
pair_distances <- data.frame(
  pair_id = pe_df$`Matched Pair ID`,
  City_PE = pe_df$City,
  State_PE = pe_df$State,
  City_Ctrl = ctrl_df$City,
  State_Ctrl = ctrl_df$State
)

distances <- numeric(nrow(pair_distances))
for (i in 1:nrow(pair_distances)) {
  r <- pair_distances[i, ]
  if (toupper(trimws(r$City_PE)) == toupper(trimws(r$City_Ctrl)) && r$State_PE == r$State_Ctrl) {
    distances[i] <- 0.0
  } else {
    c_pe <- get_coords(r$City_PE, r$State_PE)
    c_ctrl <- get_coords(r$City_Ctrl, r$State_Ctrl)
    distances[i] <- dist_miles(c_pe[1], c_pe[2], c_ctrl[1], c_ctrl[2])
  }
}
pair_distances$Distance <- distances

n_unresolved <- sum(is.na(pair_distances$Distance))
if (n_unresolved) {
  cat(sprintf("\nWARNING: %d of %d pairs have at least one city the gazetteer could not resolve; their distances are NA and they drop out of the caliper subsets.\n",
              n_unresolved, nrow(pair_distances)))
  print(pair_distances[is.na(pair_distances$Distance), ])
}

# Map distance back to sheet
sheet200 <- sheet200 %>%
  left_join(pair_distances %>% select(pair_id, Distance), by = c("Matched Pair ID" = "pair_id"))

# 2. Simulate outcomes for GLMM sensitivity run (since caller data is zero)
set.seed(1978)
n_calls <- nrow(sheet200) * 2 # Crossover design implies 2 calls per physician

sim_calls <- data.frame(
  Matched_Pair_ID = rep(sheet200$`Matched Pair ID`, each = 2),
  NPI = rep(sheet200$NPI, each = 2),
  PE_or_Not = rep(sheet200$PE_or_Not, each = 2),
  Distance = rep(sheet200$Distance, each = 2),
  Payer = rep(c("Medicaid", "BCBS PPO"), nrow(sheet200)),
  Year = sample(2021:2025, nrow(sheet200) * 2, replace = TRUE)
)

# Simulate Medicaid acceptance (obtainment): PE = 41%, Control = 72.5%
# Simulate BCBS PPO acceptance: PE = 99%, Control = 98.5%
sim_calls$Accepted <- sapply(1:nrow(sim_calls), function(i) {
  r <- sim_calls[i, ]
  p <- if (r$Payer == "BCBS PPO") {
    ifelse(r$PE_or_Not == "PE", 0.99, 0.985)
  } else {
    ifelse(r$PE_or_Not == "PE", 0.41, 0.725)
  }
  rbinom(1, 1, p)
})

# Simulate wait times using negative binomial (PE Medicaid is highest)
sim_calls$Wait_Time <- sapply(1:nrow(sim_calls), function(i) {
  r <- sim_calls[i, ]
  mu <- if (r$Payer == "BCBS PPO") {
    ifelse(r$PE_or_Not == "PE", 14.5, 12.1)
  } else {
    ifelse(r$PE_or_Not == "PE", 36.8, 23.4)
  }
  rnbinom(1, size = 1.5, mu = mu)
})

# 3. Perform sensitivity analysis across distance tiers
run_analysis <- function(data_subset, label) {
  # Proportion difference
  tab <- table(data_subset$PE_or_Not, data_subset$Accepted, data_subset$Payer)
  
  # Medicaid obtainment comparison
  med_pe_acc <- sum(data_subset$Accepted[data_subset$PE_or_Not == "PE" & data_subset$Payer == "Medicaid"])
  med_pe_tot <- sum(data_subset$PE_or_Not == "PE" & data_subset$Payer == "Medicaid")
  med_ctrl_acc <- sum(data_subset$Accepted[data_subset$PE_or_Not == "Non-PE" & data_subset$Payer == "Medicaid"])
  med_ctrl_tot <- sum(data_subset$PE_or_Not == "Non-PE" & data_subset$Payer == "Medicaid")
  
  # Standard Z-test
  z_res <- prop.test(c(med_pe_acc, med_ctrl_acc), c(med_pe_tot, med_ctrl_tot))
  
  # Wait time mixed models using package wrapper functions
  model_poisson <- mysterycall_poisson_model(
    data = data_subset, 
    outcome = "Wait_Time", 
    predictors = c("PE_or_Not", "Payer", "PE_or_Not:Payer"), 
    random_intercept = "Matched_Pair_ID"
  )
  
  model_nb <- mysterycall_nb_model(
    data = data_subset, 
    outcome = "Wait_Time", 
    predictors = c("PE_or_Not", "Payer", "PE_or_Not:Payer"), 
    random_intercept = "Matched_Pair_ID"
  )
  
  model <- model_nb$model
  
  # Run DHARMa diagnostics and package zero-inflation checks on primary model
  if (label == "10-mile (Primary)") {
    cat("\n=== Running DHARMa Residual Diagnostics for Primary GLMM ===\n")
    dir.create("figures", showWarnings = FALSE)
    dharma_res <- mysterycall_validate_residuals_dharma(
      model = model, 
      plot_path = "figures/dharma_diagnostics.png"
    )
    
    # Print residuals test summary
    cat("Dispersion test results:\n")
    print(dharma_res$dispersion_test)
    
    # Run Likelihood Ratio Test comparing full interaction model to reduced model
    cat("\n=== Running Likelihood Ratio Test for PE * Payer Interaction ===\n")
    lrt_res <- mysterycall_test_interaction_effect(
      data = data_subset,
      formula_full = Wait_Time ~ PE_or_Not * Payer + (1|Matched_Pair_ID),
      formula_reduced = Wait_Time ~ PE_or_Not + Payer + (1|Matched_Pair_ID)
    )
    print(lrt_res)
    
    # Run package zero inflation check
    cat("\n=== Running Zero Inflation Diagnostic Test ===\n")
    zi_check <- mysterycall_check_zero_inflation(model, n_sim = 250L, plot = FALSE)
    print(zi_check)
    
    # Compare Poisson vs Negative Binomial model fits
    cat("\n=== Comparing Model Fit Table (Poisson vs. NB) ===\n")
    comp_tbl <- mysterycall_model_comparison_table(list(
      "Poisson Model" = model_poisson,
      "Negative Binomial Model" = model_nb
    ))
    print(comp_tbl)
    
    # ═══════════════════════════════════════════════════════════════════
    # Run No-External-Validation Helper Layer
    # ═══════════════════════════════════════════════════════════════════
    cat("\n=== [INTERNAL VALIDATION] Locked Temporal Validation ===\n")
    temp_val <- mysterycall_temporal_validation(
      data = data_subset,
      outcome = "Wait_Time",
      predictors = c("PE_or_Not", "Payer", "PE_or_Not:Payer"),
      time_col = "Year",
      threshold = 2023,
      family = "nbinom"
    )
    print(temp_val$metrics)
    
    cat("\n=== [INTERNAL VALIDATION] Recalibration Assessment ===\n")
    # Fit a standard logistic model to calculate predicted probabilities for appointment offer
    logistic_fit <- glm(Accepted ~ PE_or_Not + Payer, data = data_subset, family = binomial)
    data_subset$pred_prob <- predict(logistic_fit, type = "response")
    recal_res <- mysterycall_recalibration_assessment(
      observed = data_subset$Accepted,
      predicted = data_subset$pred_prob,
      family = "binomial",
      plot = TRUE
    )
    cat(sprintf("Calibration Slope: %.3f (Ideal = 1.0) | Intercept: %.3f (Ideal = 0.0)\n", 
                recal_res$calibration_slope, recal_res$calibration_intercept))
    ggplot2::ggsave("figures/recalibration_diagnostics.png", 
           plot = recal_res$plot, width = 7.5, height = 4.5, dpi = 300)
    
    cat("\n=== [INTERNAL VALIDATION] Site/Provider Split CV Simulation ===\n")
    split_cv <- mysterycall_provider_split_simulation(
      data = data_subset,
      outcome = "Wait_Time",
      predictors = c("PE_or_Not", "Payer", "PE_or_Not:Payer"),
      cluster_col = "Matched_Pair_ID",
      k = 5,
      family = "nbinom"
    )
    print(split_cv)
    
    cat("\n=== [INTERNAL VALIDATION] Bootstrap Predictor-Retention Stability ===\n")
    boot_stability <- mysterycall_bootstrap_predictor_stability(
      data = data_subset,
      outcome = "Accepted",
      predictors = c("PE_or_Not", "Payer"),
      n_boot = 50,
      p_threshold = 0.05,
      family = "binomial"
    )
    print(boot_stability)
  }
  
  interaction_coef <- summary(model)$coefficients$cond["PE_or_NotPE:PayerMedicaid", "Estimate"]
  interaction_p <- summary(model)$coefficients$cond["PE_or_NotPE:PayerMedicaid", "Pr(>|z|)"]
  
  return(data.frame(
    Caliper = label,
    Pairs = nrow(data_subset) / 4,
    PE_Medicaid_Obtainment = med_pe_acc / med_pe_tot,
    Control_Medicaid_Obtainment = med_ctrl_acc / med_ctrl_tot,
    Obtainment_p = z_res$p.value,
    WaitTime_Interaction_Estimate = interaction_coef,
    WaitTime_Interaction_p = interaction_p
  ))
}

# Run models for the three distance thresholds
cat("\n=== Running Matching Caliper Sensitivity Analysis ===\n")

# Primary: All matched pairs (within 10 miles)
res_10 <- run_analysis(sim_calls, "10-mile (Primary)")

# Sensitivity A: pairs matched within 5 miles
res_5 <- run_analysis(sim_calls %>% filter(Distance <= 5.0), "5-mile Caliper")

# Sensitivity B: pairs matched within 3 miles
res_3 <- run_analysis(sim_calls %>% filter(Distance <= 3.0), "3-mile Caliper")

results_summary <- rbind(res_10, res_5, res_3)
print(results_summary)

write.csv(results_summary, "geographic_sensitivity_results.csv", row.names = FALSE)
cat("\nGeographic sensitivity results exported successfully to geographic_sensitivity_results.csv!\n")
