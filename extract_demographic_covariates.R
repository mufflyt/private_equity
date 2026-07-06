# R Script to extract methodological covariates for the OB/GYN study
# Implements:
# 1. NPPES Historical Clinician Churn Tracker (via DuckDB)
# 2. Census ACS Table S2701 Female Insurance Percentages (via Census API)
# 3. HRSA Area Health Resources File (AHRF) County-Level Metrics
# 4. CMS Monthly County-Level Enrollment Retrieval

library(DBI)
library(duckdb)
library(httr)
library(jsonlite)
library(dplyr)

#' 1. Track Clinician Churn at a Specific Practice Location (NPPES History)
#' Since Tax Identifiers (TINs) are private, we track offices longitudinally using
#' physical practice address matches and organization NPI (Type 2) associations.
#'
#' @param db_path Path to the 80 GB DuckDB database (e.g. "/Volumes/MufflySamsung 1/nppes_historical.duckdb")
#' @param street_address Character. Practice Location Address Line 1 (e.g. "123 Main St").
#' @param zip_code Character. Five-digit ZIP code.
#' @return A data frame containing annual staffing levels, entries, exits, and churn rates.
#' @export
mysterycall_track_clinician_churn <- function(db_path, street_address, zip_code, table_name = "temporal_obgyn_only_all_years") {
  if (!file.exists(db_path)) {
    stop("DuckDB database not found at the specified path.")
  }
  
  con <- dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
  on.exit(dbDisconnect(con, shutdown = TRUE))
  
  # Standardize inputs for SQL matching
  addr_clean <- toupper(trimws(street_address))
  zip_clean <- substr(trimws(zip_code), 1, 5)
  
  # Query based on selected table name
  if (table_name == "temporal_obgyn_only_all_years") {
    query <- sprintf("
      SELECT year, npi, first_name as provider_first_name, last_name as provider_last_name
      FROM temporal_obgyn_only_all_years
      WHERE UPPER(TRIM(practice_address_street)) = '%s'
        AND SUBSTR(practice_address_zip, 1, 5) = '%s'
      ORDER BY year, npi
    ", addr_clean, zip_clean)
  } else {
    query <- sprintf("
      SELECT year, npi, provider_first_name, provider_last_name
      FROM nppes_history
      WHERE UPPER(TRIM(practice_address_line1)) = '%s'
        AND SUBSTR(practice_postal_code, 1, 5) = '%s'
        AND entity_type_code = 1
      ORDER BY year, npi
    ", addr_clean, zip_clean)
  }
  
  df <- dbGetQuery(con, query)
  if (nrow(df) == 0) {
    message("No clinicians found matching the specified address and ZIP.")
    return(NULL)
  }
  
  years <- sort(unique(df$year))
  churn_results <- data.frame()
  
  for (i in seq_along(years)) {
    yr <- years[i]
    current_npis <- df$npi[df$year == yr]
    
    if (i == 1) {
      # Baseline year
      churn_results <- rbind(churn_results, data.frame(
        Year = yr,
        Staff_Count = length(current_npis),
        Joined = 0,
        Left = 0,
        Churn_Rate = 0.0
      ))
    } else {
      prev_yr <- years[i - 1]
      prev_npis <- df$npi[df$year == prev_yr]
      
      joined <- sum(!current_npis %in% prev_npis)
      left <- sum(!prev_npis %in% current_npis)
      retained <- sum(current_npis %in% prev_npis)
      
      # Churn rate: (Joined + Left) / Baseline Staff
      baseline_staff <- length(prev_npis)
      churn_rate <- if (baseline_staff > 0) (joined + left) / baseline_staff else 0.0
      
      churn_results <- rbind(churn_results, data.frame(
        Year = yr,
        Staff_Count = length(current_npis),
        Joined = joined,
        Left = left,
        Churn_Rate = round(churn_rate, 3)
      ))
    }
  }
  
  return(churn_results)
}


#' 2. Extract Female Insurance Percentages from Census ACS Table S2701
#' Queries the US Census Bureau API for the smallest geographic unit (Census Tract).
#'
#' @param api_key Character. US Census API key.
#' @param state_fips Character. Two-digit State FIPS code.
#' @param county_fips Character. Three-digit County FIPS code.
#' @return A data frame containing percentages of females enrolled in Medicaid, Medicare, private plans, and uninsured.
#' @export
mysterycall_get_acs_female_insurance <- function(api_key, state_fips, county_fips) {
  # ACS 5-year Table S2701 variables for females:
  # C01_010E: Total Female Population
  # C02_010E: Female with Private Health Insurance
  # C03_010E: Female with Public Health Insurance
  # C04_010E: Female with Medicaid/means-tested coverage
  # C05_010E: Female with Medicare
  # C06_010E: Female Uninsured
  
  base_url <- "https://api.census.gov/data/2022/acs/acs5/subject"
  vars <- "S2701_C01_010E,S2701_C02_010E,S2701_C03_010E,S2701_C04_010E,S2701_C05_010E,S2701_C06_010E"
  
  url <- sprintf("%s?get=NAME,%s&for=tract:*&in=state:%s+county:%s&key=%s", 
                 base_url, vars, state_fips, county_fips, api_key)
  
  response <- GET(url)
  if (status_code(response) != 200) {
    stop(paste("Census API request failed with status:", status_code(response)))
  }
  
  data <- fromJSON(content(response, "text", encoding = "UTF-8"))
  headers <- data[1, ]
  rows <- data[-1, ]
  df <- as.data.frame(rows, stringsAsFactors = FALSE)
  colnames(df) <- headers
  
  # Convert numeric columns
  num_cols <- c("S2701_C01_010E", "S2701_C02_010E", "S2701_C03_010E", "S2701_C04_010E", "S2701_C05_010E", "S2701_C06_010E")
  df[num_cols] <- lapply(df[num_cols], as.numeric)
  
  # Compute percentages
  df_clean <- df %>%
    transmute(
      Census_Tract = NAME,
      State_FIPS = state,
      County_FIPS = county,
      Tract_FIPS = tract,
      Total_Females = S2701_C01_010E,
      Pct_Female_Private = (S2701_C02_010E / S2701_C01_010E) * 100,
      Pct_Female_Public = (S2701_C03_010E / S2701_C01_010E) * 100,
      Pct_Female_Medicaid = (S2701_C04_010E / S2701_C01_010E) * 100,
      Pct_Female_Medicare = (S2701_C05_010E / S2701_C01_010E) * 100,
      Pct_Female_Uninsured = (S2701_C06_010E / S2701_C01_010E) * 100
    )
  
  return(df_clean)
}


#' 3. Extract County-Level Metrics from HRSA Area Health Resources File (AHRF)
#'
#' @param ahrf_db_path Path to the local AHRF DuckDB or CSV database.
#' @param county_fips Character. Five-digit State-County FIPS code.
#' @return A data frame containing total population, OB-GYN supply, and public coverage metrics.
#' @export
mysterycall_get_hrsa_ahrf <- function(ahrf_db_path, county_fips) {
  if (!file.exists(ahrf_db_path)) {
    stop("AHRF database file not found.")
  }
  
  con <- dbConnect(duckdb::duckdb(), ahrf_db_path, read_only = TRUE)
  on.exit(dbDisconnect(con, shutdown = TRUE))
  
  # AHRF stores county data by FIPS.
  # We query total population, active OB-GYNs (F11942 or similar variable codes),
  # and total Medicaid enrollment.
  query <- sprintf("
    SELECT fips, county_name, state_abbrev,
           pop_total, 
           obgyn_count, 
           medicaid_enrolled
    FROM ahrf_county_data
    WHERE fips = '%s'
  ", county_fips)
  
  res <- dbGetQuery(con, query)
  return(res)
}


#' 4. Retrieve CMS Monthly County-Level Enrollment Reports
#'
#' @param cms_csv_path Path to the downloaded CMS monthly enrollment CSV.
#' @param county_fips Character. Five-digit State-County FIPS code.
#' @return A data frame with monthly Medicare and Medicaid/CHIP enrollment counts.
#' @export
mysterycall_get_cms_enrollment <- function(cms_csv_path, county_fips) {
  if (!file.exists(cms_csv_path)) {
    stop("CMS monthly enrollment file not found.")
  }
  
  # Read CMS file
  df <- read.csv(cms_csv_path, stringsAsFactors = FALSE, check.names = FALSE)
  
  # Filter by FIPS
  res <- df %>%
    filter(FIPS == county_fips) %>%
    select(FIPS, County, State, `Medicare Enrollment`, `Medicaid/CHIP Enrollment`, Report_Month)
  
  return(res)
}
