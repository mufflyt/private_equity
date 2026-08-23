# R Script to calculate geographic distances between matched pairs with different cities
# Resolves missing coordinate cities using manual overrides

library(mysterycall)
library(dplyr)

data(city_state_to_lat_long, package = "mysterycall")
lat_long_ref <- city_state_to_lat_long

abbrev_to_full <- c(
  'AL'='Alabama', 'AK'='Alaska', 'AZ'='Arizona', 'AR'='Arkansas', 'CA'='California',
  'CO'='Colorado', 'CT'='Connecticut', 'DE'='Delaware', 'DC'='District of Columbia',
  'FL'='Florida', 'GA'='Georgia', 'HI'='Hawaii', 'ID'='Idaho', 'IL'='Illinois',
  'IN'='Indiana', 'IA'='Iowa', 'KS'='Kansas', 'KY'='Kentucky', 'LA'='Louisiana',
  'ME'='Maine', 'MD'='Maryland', 'MA'='Massachusetts', 'MI'='Michigan', 'MN'='Minnesota',
  'MS'='Mississippi', 'MO'='Missouri', 'MT'='Montana', 'NE'='Nebraska', 'NV'='Nevada',
  'NH'='New Hampshire', 'NJ'='New Jersey', 'NM'='New Mexico', 'NY'='New York',
  'NC'='North Carolina', 'ND'='North Dakota', 'OH'='Ohio', 'OK'='Oklahoma', 'OR'='Oregon',
  'PA'='Pennsylvania', 'RI'='Rhode Island', 'SC'='South Carolina', 'SD'='South Dakota',
  'TN'='Tennessee', 'TX'='Texas', 'UT'='Utah', 'VT'='Vermont', 'VA'='Virginia',
  'WA'='Washington', 'WV'='West Virginia', 'WI'='Wisconsin', 'WY'='Wyoming',
  'PR'='Puerto Rico', 'VI'='Virgin Islands'
)

full_to_abbrev <- names(abbrev_to_full)
names(full_to_abbrev) <- abbrev_to_full
lat_long_ref$state_abbrev <- full_to_abbrev[lat_long_ref$state]
lat_long_ref$city_upper <- toupper(trimws(lat_long_ref$city))
lat_long_ref$state_upper <- toupper(trimws(lat_long_ref$state_abbrev))
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
    return(c(match_row$latitude[1], match_row$longitude[1]))
  }
  return(c(NA, NA))
}

haversine_distance <- function(lat1, lon1, lat2, lon2) {
  if (is.na(lat1) || is.na(lon1) || is.na(lat2) || is.na(lon2)) return(NA)
  r <- 3959 # Earth's radius in miles
  phi1 <- lat1 * pi / 180
  phi2 <- lat2 * pi / 180
  delta_phi <- (lat2 - lat1) * pi / 180
  delta_lambda <- (lon2 - lon1) * pi / 180
  
  a <- sin(delta_phi / 2)^2 + cos(phi1) * cos(phi2) * sin(delta_lambda / 2)^2
  c <- 2 * atan2(sqrt(a), sqrt(1 - a))
  return(r * c)
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
  
  distances[i] <- haversine_distance(coords_pe[1], coords_pe[2], coords_control[1], coords_control[2])
}

different_cities$Latitude_PE <- pe_lats
different_cities$Longitude_PE <- pe_lons
different_cities$Latitude_Control <- control_lats
different_cities$Longitude_Control <- control_lons
different_cities$Distance_Miles <- round(distances, 2)

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
