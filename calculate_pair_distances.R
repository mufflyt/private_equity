# R Script to calculate geographic distances between matched pairs with different cities
# Resolves missing coordinate cities using manual overrides

library(mysterycall)
library(dplyr)

source(file.path("R", "pe_helpers.R"))

# Gazetteer access goes through normalize_gazetteer() (R/pe_helpers.R), never through
# direct column access: this script previously read lat_long_ref$latitude/$longitude, and
# when mysterycall renamed the dataset's columns to lat/long the `$` lookup returned NULL,
# degrading every coordinate to NA silently -- the same failure mode the matching pipeline
# documents for its own inline copy of this adapter.
data(city_state_to_lat_long, package = "mysterycall")
lat_long_ref <- normalize_gazetteer(city_state_to_lat_long, STATE_ABB_BY_NAME)
lat_long_ref$city_upper  <- lat_long_ref$city
lat_long_ref$state_upper <- lat_long_ref$state
lat_long_ref <- lat_long_ref[!is.na(lat_long_ref$state_upper), ]
lat_long_ref <- lat_long_ref[!duplicated(paste(lat_long_ref$city_upper, lat_long_ref$state_upper, sep="_")), ]

# Manual overrides for unincorporated towns/townships missing in dataset
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
  
  if (key %in% names(manual_coords)) {
    return(manual_coords[[key]])
  }
  
  match_row <- lat_long_ref[lat_long_ref$city_upper == city_clean & lat_long_ref$state_upper == state_clean, ]
  if (nrow(match_row) > 0) {
    return(c(match_row[["lat"]][1], match_row[["long"]][1]))
  }
  return(c(NA, NA))
}

# Distance is geosphere::distHaversine() with the same spherical radius (3959 miles) the
# historical hand-rolled copies used -- verified numerically identical to machine
# precision, so this change is a delegation, not a respecification. Note geosphere takes
# coordinates as (lon, lat) pairs, not (lat, lon).
dist_miles <- function(lat1, lon1, lat2, lon2) {
  if (any(is.na(c(lat1, lon1, lat2, lon2)))) return(NA_real_)
  geosphere::distHaversine(c(lon1, lat1), c(lon2, lat2), r = 3959)
}

# Load the calling sheet
df <- read.csv("pe_obgyn_final_calling_sheet_300.csv", stringsAsFactors = FALSE, check.names = FALSE)

# Split into PE and Non-PE
pe_df <- df[df$PE_or_Not == "PE", ]
control_df <- df[df$PE_or_Not == "Non-PE", ]

# Merge on Matched Pair ID
merged <- merge(
  pe_df[, c("Matched Pair ID", "Provider Name", "City", "State", "Phone")],
  control_df[, c("Matched Pair ID", "Provider Name", "City", "State", "Phone")],
  by = "Matched Pair ID",
  suffixes = c("_PE", "_Control")
)

# Filter to different cities or states
different_cities <- merged[toupper(trimws(merged$City_PE)) != toupper(trimws(merged$City_Control)) |
                             toupper(trimws(merged$State_PE)) != toupper(trimws(merged$State_Control)), ]

cat(sprintf("Found %d matched pairs with different cities or states out of 300 total pairs.\n\n", nrow(different_cities)))

distances <- numeric()
pe_lats <- numeric()
pe_lons <- numeric()
control_lats <- numeric()
control_lons <- numeric()

for (i in 1:nrow(different_cities)) {
  row <- different_cities[i, ]
  coords_pe <- get_coords(row$City_PE, row$State_PE)
  coords_control <- get_coords(row$City_Control, row$State_Control)
  
  pe_lats[i] <- coords_pe[1]
  pe_lons[i] <- coords_pe[2]
  control_lats[i] <- coords_control[1]
  control_lons[i] <- coords_control[2]
  
  distances[i] <- dist_miles(coords_pe[1], coords_pe[2], coords_control[1], coords_control[2])
}

different_cities$Latitude_PE <- pe_lats
different_cities$Longitude_PE <- pe_lons
different_cities$Latitude_Control <- control_lats
different_cities$Longitude_Control <- control_lons
different_cities$Distance_Miles <- round(distances, 2)

# Unresolvable cities must surface, not pass silently: a pair with no real coordinate
# cannot have a real distance, and how many of them there are is part of the output.
n_unresolved <- sum(is.na(different_cities$Distance_Miles))
if (n_unresolved) {
  cat(sprintf("WARNING: %d pair(s) have at least one city the gazetteer could not resolve; their distances are NA.\n",
              n_unresolved))
  print(different_cities[is.na(different_cities$Distance_Miles),
                         c("Matched Pair ID", "City_PE", "State_PE", "City_Control", "State_Control")])
}

# Sort by distance
different_cities <- different_cities[order(different_cities$Distance_Miles, na.last = TRUE), ]

# Save to CSV
write.csv(different_cities, "pe_obgyn_fallback_distances_300.csv", row.names = FALSE)
cat("Fallback distances exported to: pe_obgyn_fallback_distances_300.csv\n\n")

# Print complete table
print_cols <- c("Matched Pair ID", "City_PE", "State_PE", "City_Control", "State_Control", "Distance_Miles")
print(different_cities[, print_cols])

cat("\nSummary of distances (miles):\n")
print(summary(different_cities$Distance_Miles))
