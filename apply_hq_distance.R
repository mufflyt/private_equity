# R Script to test and apply the mysterycall_calculate_hq_distance function
# to the study database and final calling lists.

library(mysterycall)
library(dplyr)
library(readr)

study_db_path <- "pe_obgyn_study_database_with_churn.csv"
sheet_path <- "pe_obgyn_final_calling_sheet_300.csv"
sheet200_path <- "pe_obgyn_final_calling_sheet_200_dedup.csv"

if (!file.exists(study_db_path)) {
  stop("Enriched study database file not found.")
}

df_db <- read_csv(study_db_path, show_col_types = FALSE)

# 1. Test the function
cat("Testing mysterycall_calculate_hq_distance with sample data...\n")
test_lats <- c(26.3683, 39.8459, 27.9506)
test_lons <- c(-80.1289, -74.9943, -82.4572)
test_plats <- c("Unified Women's Healthcare", "Axia Women's Health", "Women's Care Enterprises")
test_pairs <- c("pair_1", "pair_2", "pair_3")

test_dists <- mysterycall_calculate_hq_distance(test_lats, test_lons, test_plats, test_pairs)
cat("Test results (should all be 0 miles as they are the exact HQ coordinates):\n")
print(test_dists)

# 2. Apply to our cohort dataframe
cat("\nApplying HQ distance calculation to the study database...\n")
# Clean up any potential missing matched pair columns
df_db$Matched_Pair_Group <- as.character(df_db$Matched_Pair_Group)
df_db$Platform_Practice <- as.character(df_db$`Platform/Practice`)

df_db$HQ_Distance_Miles <- mysterycall_calculate_hq_distance(
  lats = df_db$Latitude,
  lons = df_db$Longitude,
  platforms = df_db$Platform_Practice,
  matched_pairs = df_db$Matched_Pair_Group
)

# 3. Save the updated database
write_csv(df_db, study_db_path)
cat(sprintf("Saved updated study database to: %s\n", study_db_path))

# Map to final calling sheets
dist_map <- df_db %>%
  distinct(NPI, .keep_all = TRUE) %>%
  select(NPI, HQ_Distance_Miles)

# Update 300 calling sheet (dropping pre-existing HQ distance columns to prevent duplicates)
sheet300 <- read_csv(sheet_path, show_col_types = FALSE) %>%
  select(-any_of(c("HQ_Distance_Miles")))
sheet300_enriched <- sheet300 %>%
  left_join(dist_map, by = "NPI")
write_csv(sheet300_enriched, sheet_path)

# Update 200 calling sheet (dropping pre-existing HQ distance columns to prevent duplicates)
sheet200 <- read_csv(sheet200_path, show_col_types = FALSE) %>%
  select(-any_of(c("HQ_Distance_Miles")))
sheet200_enriched <- sheet200 %>%
  left_join(dist_map, by = "NPI")
write_csv(sheet200_enriched, sheet200_path)

cat("Successfully updated calling sheets with HQ Distance column.\n")

# Print summary by group
summary_stats <- df_db %>%
  group_by(PE_or_Not) %>%
  summarise(
    Avg_Distance_HQ = mean(HQ_Distance_Miles, na.rm = TRUE),
    Min_Distance = min(HQ_Distance_Miles, na.rm = TRUE),
    Max_Distance = max(HQ_Distance_Miles, na.rm = TRUE),
    Valid_Count = sum(!is.na(HQ_Distance_Miles)),
    .groups = "drop"
  )
print(summary_stats)
