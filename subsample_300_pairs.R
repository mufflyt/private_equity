# R Script to Subsample 300 Matched Pairs (600 Physicians) for the calling campaign
# Enforces reproducible random selection of matched pairs (without Caller Doctor Aliases)

cat("=== Subsampling 300 Matched Pairs (600 Clinicians) ===\n")
input_csv <- "pe_obgyn_matched_calling_list.csv"
output_csv <- "pe_obgyn_final_calling_sheet_300.csv"

if (!file.exists(input_csv)) {
  stop(paste("ERROR: Input file not found at:", input_csv))
}

# Read full matched calling list
df <- read.csv(input_csv, stringsAsFactors = FALSE, check.names = FALSE)
cat(sprintf("Loaded matched calling list with %d total records (778 pairs).\n", nrow(df)))

# Set seed for reproducibility
set.seed(1978)

# Extract unique Matched Pair IDs
pair_ids <- unique(df[["Matched Pair ID"]])
cat(sprintf("Found %d unique Matched Pair IDs.\n", length(pair_ids)))

# Randomly select 300 pair IDs
selected_pairs <- sample(pair_ids, 300)
cat("Successfully sampled 300 pairs.\n")

# Subset dataframe to only selected pairs
df_sampled <- df[df[["Matched Pair ID"]] %in% selected_pairs, ]

# Parse the numeric ID out of the pair ID for sorting (e.g. "pair_12" -> 12)
df_sampled$sort_id <- as.numeric(gsub("pair_", "", df_sampled[["Matched Pair ID"]]))
df_sampled <- df_sampled[order(df_sampled$sort_id, df_sampled$PE_or_Not), ]

# Drop the helper sort_id
df_sampled$sort_id <- NULL

# Write to CSV
write.csv(df_sampled, output_csv, row.names = FALSE)
cat(sprintf("Sampled Calling Sheet exported to: %s (%d records)\n", output_csv, nrow(df_sampled)))

# Verification
pe_count <- sum(df_sampled$PE_or_Not == "PE")
control_count <- sum(df_sampled$PE_or_Not == "Non-PE")
cat(sprintf("Verification: PE count = %d, Control count = %d\n", pe_count, control_count))
print(head(df_sampled[, c("Matched Pair ID", "Provider Name", "PE_or_Not")]))
