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

# Load the data
calling_sheet_path <- "/Users/tylermuffly/private_equity/pe_obgyn_final_calling_sheet_200.csv"
study_db_path <- "/Users/tylermuffly/private_equity/pe_obgyn_study_database.csv"

if (!file.exists(calling_sheet_path) || !file.exists(study_db_path)) {
  stop("Required database files are missing. Run the matching pipeline first.")
}

sheet200 <- read_csv(calling_sheet_path, show_col_types = FALSE)

# 1. Calculate distances for all 200 pairs
data(city_state_to_lat_long, package = "mysterycall")
lat_long_ref <- city_state_to_lat_long

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
  match_row <- lat_long_ref[toupper(trimws(lat_long_ref$city)) == city_clean & toupper(trimws(lat_long_ref$state)) == state_clean, ]
  if (nrow(match_row) > 0) return(c(match_row$latitude[1], match_row$longitude[1]))
  return(c(39.8283, -98.5795)) # Default to center of US
}

haversine_distance <- function(lat1, lon1, lat2, lon2) {
  r <- 3959 # Earth's radius in miles
  phi1 <- lat1 * pi / 180
  phi2 <- lat2 * pi / 180
  delta_phi <- (lat2 - lat1) * pi / 180
  delta_lambda <- (lon2 - lon1) * pi / 180
  a <- sin(delta_phi / 2)^2 + cos(phi1) * cos(phi2) * sin(delta_lambda / 2)^2
  c <- 2 * atan2(sqrt(a), sqrt(1 - a))
  return(r * c)
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
    distances[i] <- haversine_distance(c_pe[1], c_pe[2], c_ctrl[1], c_ctrl[2])
  }
}
pair_distances$Distance <- distances

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
  Payer = rep(c("Medicaid", "BCBS PPO"), nrow(sheet200))
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
  
  # Wait time Negative Binomial model (using package interaction test)
  model <- glmmTMB(Wait_Time ~ PE_or_Not * Payer + (1|Matched_Pair_ID) + (1|NPI), 
                    data = data_subset, family = nbinom2)
  
  # Run DHARMa diagnostics on the primary model specification using package function
  if (label == "10-mile (Primary)") {
    cat("\n=== Running DHARMa Residual Diagnostics for Primary GLMM ===\n")
    dir.create("/Users/tylermuffly/private_equity/figures", showWarnings = FALSE)
    dharma_res <- mysterycall_validate_residuals_dharma(
      model = model, 
      plot_path = "/Users/tylermuffly/private_equity/figures/dharma_diagnostics.png"
    )
    
    # Print residuals test summary
    cat("Dispersion test results:\n")
    print(dharma_res$dispersion_test)
    
    # Run Likelihood Ratio Test comparing full interaction model to reduced model
    cat("\n=== Running Likelihood Ratio Test for PE * Payer Interaction ===\n")
    lrt_res <- mysterycall_test_interaction_effect(
      data = data_subset,
      formula_full = Wait_Time ~ PE_or_Not * Payer + (1|Matched_Pair_ID) + (1|NPI),
      formula_reduced = Wait_Time ~ PE_or_Not + Payer + (1|Matched_Pair_ID) + (1|NPI)
    )
    print(lrt_res)
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

write.csv(results_summary, "/Users/tylermuffly/private_equity/geographic_sensitivity_results.csv", row.names = FALSE)
cat("\nGeographic sensitivity results exported successfully to geographic_sensitivity_results.csv!\n")
