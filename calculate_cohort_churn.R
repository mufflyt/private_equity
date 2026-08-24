# R Script to calculate historical clinician churn for the entire study cohort
# Loops through all unique practice locations in the study database,
# queries the 80 GB NPPES DuckDB database, and merges the churn metrics.

library(mysterycall)
library(dplyr)
library(readr)
library(DBI)
library(duckdb)

source("R/pe_warehouse.R")   # pe_nber_warehouse(): resolves the drive, refuses to guess
study_db_path <- "pe_obgyn_study_database.csv"
output_db_path <- "pe_obgyn_study_database_with_churn.csv"

if (!file.exists(study_db_path)) {
  stop("Study database not found.")
}

df_db <- read_csv(study_db_path, show_col_types = FALSE)

# Identify unique offices
unique_offices <- df_db %>%
  filter(!is.na(`NPPES Address 1`) & !is.na(`NPPES Zip`)) %>%
  distinct(`NPPES Address 1`, `NPPES Zip`, PE_or_Not) %>%
  rename(Address = `NPPES Address 1`, Zip = `NPPES Zip`)

cat(sprintf("Found %d unique clinic locations to query for churn...\n", nrow(unique_offices)))

# Connect to DuckDB once for speed (using direct queries rather than multiple function calls)
con <- pe_nber_warehouse(required_tables = "temporal_obgyn_only_all_years")

# Create a temporary table or map values in memory
# To optimize performance, we can extract all records matching our ZIP codes first
zips_to_query <- unique(substr(trimws(unique_offices$Zip), 1, 5))
zip_filter_str <- paste0("'", zips_to_query, "'", collapse = ", ")

cat("Pre-fetching ZIP-level records from historical DuckDB table...\n")
query_all <- sprintf("
  SELECT year, npi, first_name, last_name, practice_address_street, practice_address_zip
  FROM temporal_obgyn_only_all_years
  WHERE SUBSTR(practice_address_zip, 1, 5) IN (%s)
", zip_filter_str)

historical_data <- dbGetQuery(con, query_all)
dbDisconnect(con, shutdown = TRUE)

cat(sprintf("Fetched %d raw historical provider-year records from the DuckDB database.\n", nrow(historical_data)))

# Clean and normalize addresses using mysterycall package utilities to ensure robust matching
cat("Normalizing historical addresses...\n")
historical_data$addr_norm <- historical_data$practice_address_street %>%
  mysterycall:::mysterycall_normalize_directionals() %>%
  mysterycall:::mysterycall_normalize_suffix() %>%
  mysterycall:::mysterycall_strip_suite()

historical_data$zip_clean <- substr(trimws(historical_data$practice_address_zip), 1, 5)

# Calculate churn for each unique office using the pre-fetched dataset
office_churn_metrics <- data.frame()

for (i in 1:nrow(unique_offices)) {
  off <- unique_offices[i, ]
  addr_norm_target <- off$Address %>%
    mysterycall:::mysterycall_normalize_directionals() %>%
    mysterycall:::mysterycall_normalize_suffix() %>%
    mysterycall:::mysterycall_strip_suite()
  zip_clean <- substr(trimws(off$Zip), 1, 5)
  
  # Filter pre-fetched data using normalized address and ZIP code
  df <- historical_data %>%
    filter(addr_norm == !!addr_norm_target & zip_clean == !!zip_clean)
  
  if (nrow(df) == 0) {
    office_churn_metrics <- rbind(office_churn_metrics, data.frame(
      Address = off$Address,
      Zip = off$Zip,
      Mean_Annual_Churn = NA,
      Total_Exits = NA,
      Total_Entries = NA,
      Max_Staff_Count = NA
    ))
    next
  }
  
  years <- sort(unique(df$year))
  churn_rates <- numeric()
  total_joined <- 0
  total_left <- 0
  staff_counts <- numeric()
  
  for (j in seq_along(years)) {
    yr <- years[j]
    current_npis <- df$npi[df$year == yr]
    staff_counts <- c(staff_counts, length(current_npis))
    
    if (j > 1) {
      prev_yr <- years[j - 1]
      prev_npis <- df$npi[df$year == prev_yr]
      
      joined <- sum(!current_npis %in% prev_npis)
      left <- sum(!prev_npis %in% current_npis)
      
      total_joined <- total_joined + joined
      total_left <- total_left + left
      
      baseline_staff <- length(prev_npis)
      churn_rate <- if (baseline_staff > 0) (joined + left) / baseline_staff else 0.0
      churn_rates <- c(churn_rates, churn_rate)
    }
  }
  
  office_churn_metrics <- rbind(office_churn_metrics, data.frame(
    Address = off$Address,
    Zip = off$Zip,
    Mean_Annual_Churn = if (length(churn_rates) > 0) round(mean(churn_rates), 3) else 0.0,
    Total_Exits = total_left,
    Total_Entries = total_joined,
    Max_Staff_Count = if (length(staff_counts) > 0) max(staff_counts) else 0
  ))
}

# Merge churn metrics back to main database (dropping any pre-existing columns to prevent duplicates)
df_db_enriched <- df_db %>%
  select(-any_of(c("Mean_Annual_Churn", "Total_Exits", "Total_Entries", "Max_Staff_Count"))) %>%
  left_join(office_churn_metrics, by = c("NPPES Address 1" = "Address", "NPPES Zip" = "Zip"))

# Save enriched database
write_csv(df_db_enriched, output_db_path)
cat(sprintf("Enriched study database saved to: %s\n", output_db_path))

# Map to final calling sheets (dropping any pre-existing churn columns to prevent duplicates)
sheet300 <- read_csv("pe_obgyn_final_calling_sheet_300.csv", show_col_types = FALSE) %>%
  select(-any_of(c("Mean_Annual_Churn", "Total_Exits", "Total_Entries", "Max_Staff_Count")))
sheet200 <- read_csv("pe_obgyn_final_calling_sheet_200_dedup.csv", show_col_types = FALSE) %>%
  select(-any_of(c("Mean_Annual_Churn", "Total_Exits", "Total_Entries", "Max_Staff_Count")))

# sheet300 has NPI, which is unique. We can map from df_db_enriched using NPI!
churn_map_mean <- df_db_enriched %>% 
  distinct(NPI, .keep_all = TRUE) %>% 
  select(NPI, Mean_Annual_Churn, Total_Exits, Total_Entries, Max_Staff_Count)

sheet300_enriched <- sheet300 %>%
  left_join(churn_map_mean, by = "NPI")
write_csv(sheet300_enriched, "pe_obgyn_final_calling_sheet_300.csv")

sheet200_enriched <- sheet200 %>%
  left_join(churn_map_mean, by = "NPI")
write_csv(sheet200_enriched, "pe_obgyn_final_calling_sheet_200_dedup.csv")

cat("Updated calling sheets with churn metrics.\n")

# Calculate summary by PE status
summary_stats <- df_db_enriched %>%
  group_by(PE_or_Not) %>%
  summarise(
    Avg_Churn = mean(Mean_Annual_Churn, na.rm = TRUE),
    Exits = mean(Total_Exits, na.rm = TRUE),
    Entries = mean(Total_Entries, na.rm = TRUE),
    Count = n(),
    .groups = "drop"
  )
print(summary_stats)
