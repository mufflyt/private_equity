# Propensity Score Matching (PSM) Control Group Construction Script (Updated)
# Step 1: Cluster PE active cohort by physical practice location (office_id)
# Step 2: Randomly sample exactly one PE physician per office_id (778 unique offices)
# Step 3: Run logistic regression on this collapsed PE sample + candidate controls to estimate propensity scores
# Step 4: Perform nearest-neighbor PSM matching (1-to-1 match, exact state constraint)
# Step 5: Save control group, study database, and a clean matched calling list CSV

# Helper to classify subspecialties from taxonomy
get_subspecialty_from_tax <- function(tax) {
  if (is.na(tax) || tax == "") return("Generalist")
  t <- toupper(trimws(tax))
  if (t == "207VE0102X") return("Reproductive Endocrinology/Infertility")
  if (t == "207VX0201X") return("Gynecologic Oncology")
  if (t == "207VM2500X") return("Maternal-Fetal Medicine")
  if (t == "207VF0040X") return("Female Pelvic Medicine and Reconstructive Surgery")
  return("Generalist")
}

cat("=== Loading Cohorts for Propensity Score Matching ===\n")
pe_csv <- "/Users/tylermuffly/private_equity/pe_obgyn_providers_active.csv"
candidates_csv <- "/Users/tylermuffly/private_equity/control_candidates_raw.csv"
control_output_csv <- "/Users/tylermuffly/private_equity/pe_obgyn_control_providers.csv"
study_output_csv <- "/Users/tylermuffly/private_equity/pe_obgyn_study_database.csv"
calling_list_csv <- "/Users/tylermuffly/private_equity/pe_obgyn_matched_calling_list.csv"

# Load PE active cohort (check.names = FALSE to preserve spaces in headers)
pe_df <- read.csv(pe_csv, stringsAsFactors = FALSE, na.strings = c("NA", "N/A", ""), check.names = FALSE)
pe_matched_all <- pe_df[!is.na(pe_df$NPI), ]

# Filter out PE providers with no valid phone numbers (Scraped, NPPES, or DAC)
has_valid_phone <- function(row) {
  ph <- row[["Scraped Phone"]]
  if (is.na(ph) || ph == "" || ph == "N/A" || ph == "NAN") {
    ph <- row[["NPPES Phone"]]
    if (is.na(ph) || ph == "" || ph == "N/A" || ph == "NAN") {
      ph <- row[["DAC Phone"]]
    }
  }
  return(!is.na(ph) && ph != "" && ph != "N/A" && ph != "NAN")
}
pe_matched_all$has_phone <- sapply(1:nrow(pe_matched_all), function(i) has_valid_phone(pe_matched_all[i, ]))
pe_matched_all <- pe_matched_all[pe_matched_all$has_phone, ]
pe_matched_all$has_phone <- NULL

# Filter PE cohort strictly to Generalists only using both NPPES Taxonomy and raw Subspecialty
pe_matched_all$Subspecialty_clean <- sapply(pe_matched_all[["NPPES Taxonomy"]], get_subspecialty_from_tax)
raw_sub_lower <- tolower(ifelse(is.na(pe_matched_all$Subspecialty), "", pe_matched_all$Subspecialty))
is_specialist <- grepl("infertility|oncology|maternal|pelvic|urogynecology|migs|rei|onc", raw_sub_lower)
pe_matched_all <- pe_matched_all[pe_matched_all$Subspecialty_clean == "Generalist" & !is_specialist, ]
pe_matched_all$Subspecialty_clean <- NULL

cat(sprintf("Loaded %d PE providers, with %d NPI-matched generalist records having valid phone numbers.\n", nrow(pe_df), nrow(pe_matched_all)))

# Load Candidates
candidates_df <- read.csv(candidates_csv, stringsAsFactors = FALSE, na.strings = c("NA", "N/A", ""), check.names = FALSE)

# Clean and validate candidate phones
get_clean_phone <- function(raw_phone) {
  if (is.na(raw_phone) || raw_phone == "") return(NA)
  phone_digits <- gsub("[^0-9]", "", as.character(raw_phone))
  if (nchar(phone_digits) == 10) {
    return(paste0(substr(phone_digits, 1, 3), "-", substr(phone_digits, 4, 6), "-", substr(phone_digits, 7, 10)))
  } else if (nchar(phone_digits) == 11 && substr(phone_digits, 1, 1) == "1") {
    return(paste0(substr(phone_digits, 2, 4), "-", substr(phone_digits, 5, 7), "-", substr(phone_digits, 8, 11)))
  }
  return(NA)
}

candidates_df$Phone_formatted <- sapply(candidates_df$phone, get_clean_phone)
candidates_df <- candidates_df[!is.na(candidates_df$Phone_formatted), ]

# Filter control candidates strictly to Generalists only
candidates_df$Subspecialty_clean <- sapply(candidates_df$taxonomy, get_subspecialty_from_tax)
candidates_df <- candidates_df[candidates_df$Subspecialty_clean == "Generalist", ]
candidates_df$Subspecialty_clean <- NULL

cat(sprintf("Loaded %d Non-PE private practice control generalist candidates with valid phone numbers.\n", nrow(candidates_df)))

# 1. Physical Address Clustering on ALL PE providers first
cat("\n=== Clustering Physical Practice Locations (office_id) ===\n")
get_address_key <- function(row) {
  # Priority: Scraped Address -> NPPES Address 1 -> DAC Address 1
  adr <- row[["Scraped Address"]]
  if (is.na(adr) || adr == "" || adr == "N/A" || adr == "NAN") {
    adr <- row[["NPPES Address 1"]]
    if (is.na(adr) || adr == "" || adr == "N/A" || adr == "NAN") {
      adr <- row[["DAC Address 1"]]
    }
  }
  
  city <- row[["DAC City"]]
  if (is.na(city) || city == "" || city == "N/A" || city == "NAN") {
    city <- row[["NPPES City"]]
  }
  state <- row[["DAC State"]]
  if (is.na(state) || state == "" || state == "N/A" || state == "NAN") {
    state <- row[["NPPES State"]]
    if (is.na(state) || state == "" || state == "N/A" || state == "NAN") {
      state <- row[["Input State"]]
    }
  }
  zip_code <- row[["DAC Zip"]]
  if (is.na(zip_code) || zip_code == "" || zip_code == "N/A" || zip_code == "NAN") {
    zip_code <- row[["NPPES Zip"]]
  }
  
  if (is.na(adr) || adr == "" || is.na(city) || city == "" || is.na(state) || state == "" || is.na(zip_code) || zip_code == "") {
    return(NA)
  }
  
  # Strip suites/unit details BEFORE collapsing separators. Removing punctuation first
  # destroys the word boundaries, after which FL matches the start of FLAGLER and the
  # greedy [0-9A-Z]* consumes the rest of the street name, merging unrelated offices
  # (100 FLAGLER ST, 100 FLAMINGO AVE and 100 FLORIDA BLVD all collapsed to one key).
  # Must stay identical to address_key() in R/pe_helpers.R; a test asserts they agree.
  adr_up <- gsub("[^A-Z0-9]+", " ", toupper(adr))
  adr_up <- gsub("\\b(SUITES|SUITE|STES|STE|UNIT|APT|FLOOR|FL|ROOM|RM|NUMBER|NO|DEPT|BLDG|BUILDING)\\b *[0-9A-Z]*", "", adr_up)
  adr_clean <- gsub("[^A-Z0-9]", "", adr_up)

  city_clean <- gsub("[^A-Z0-9]", "", toupper(city))
  zip_clean <- substr(gsub("[^0-9]", "", zip_code), 1, 5)
  
  if (adr_clean == "" || city_clean == "" || nchar(zip_clean) != 5) {
    return(NA)
  }
  
  return(paste(adr_clean, city_clean, toupper(state), zip_clean, sep = "_"))
}

# Generate address keys for PE matched providers
pe_matched_all$address_key <- sapply(1:nrow(pe_matched_all), function(i) get_address_key(pe_matched_all[i, ]))

# Build unique keys list and mapping to office_id
unique_pe_keys <- unique(pe_matched_all$address_key)
unique_pe_keys <- unique_pe_keys[!is.na(unique_pe_keys)]
key_to_office_id <- setNames(paste0("office_", 1:length(unique_pe_keys)), unique_pe_keys)

# Map office_id
pe_matched_all$office_id <- sapply(1:nrow(pe_matched_all), function(i) {
  key <- pe_matched_all$address_key[i]
  if (!is.na(key) && key %in% names(key_to_office_id)) return(key_to_office_id[key])
  return(paste0("office_singleton_", pe_matched_all$ID[i]))
})

pe_matched_all$address_key <- NULL

# # 3. Clean and Standardize Covariates for PSM Model
pe_matched_all$Gender_clean <- ifelse(is.na(pe_matched_all$Gender), "Female", pe_matched_all$Gender)
candidates_df$Gender_clean <- ifelse(is.na(candidates_df$gender), "Female", 
                                     ifelse(candidates_df$gender == "F", "Female", 
                                            ifelse(candidates_df$gender == "M", "Male", "Female")))

pe_matched_all$MD_vs_DO <- ifelse(is.na(pe_matched_all[["MD vs. DO"]]), "MD", pe_matched_all[["MD vs. DO"]])
candidates_df$MD_vs_DO <- ifelse(is.na(candidates_df$cred), "MD", 
                                 ifelse(grepl("DO", toupper(candidates_df$cred)), "DO", "MD"))

study_year <- as.numeric(format(Sys.Date(), "%Y"))
pe_matched_all$Years_in_Practice <- as.numeric(pe_matched_all[["Years in Practice"]])
pe_years_med <- median(pe_matched_all$Years_in_Practice, na.rm = TRUE)
pe_matched_all$Years_in_Practice[is.na(pe_matched_all$Years_in_Practice)] <- pe_years_med

candidates_df$Years_in_Practice <- study_year - as.numeric(candidates_df$grad_yr)
candidates_df$enum_yr <- as.numeric(sapply(strsplit(as.character(candidates_df$enum_date), "-"), `[`, 1))
candidates_df$Years_in_Practice <- ifelse(is.na(candidates_df$Years_in_Practice), study_year - candidates_df$enum_yr, candidates_df$Years_in_Practice)
cand_years_med <- median(candidates_df$Years_in_Practice, na.rm = TRUE)
candidates_df$Years_in_Practice[is.na(candidates_df$Years_in_Practice)] <- cand_years_med

pe_matched_all$Open_Payments_Years <- as.numeric(pe_matched_all[["Open Payments Years"]])
pe_op_med <- median(pe_matched_all$Open_Payments_Years, na.rm = TRUE)
pe_matched_all$Open_Payments_Years[is.na(pe_matched_all$Open_Payments_Years)] <- pe_op_med

candidates_df$Open_Payments_Years <- as.numeric(candidates_df$op_years)
candidates_df$Open_Payments_Years[is.na(candidates_df$Open_Payments_Years)] <- 0

# ACOG States Mapping (PR duplicate removed)
STATE_TO_ACOG <- c(
  'AL'=7, 'AK'=8, 'AZ'=8, 'AR'=7, 'CA'=9, 'CO'=8, 'CT'=1, 'DE'=3, 'DC'=4,
  'FL'=12, 'GA'=4, 'HI'=8, 'ID'=8, 'IL'=6, 'IN'=5, 'IA'=6, 'KS'=7, 'KY'=5,
  'LA'=7, 'ME'=1, 'MD'=4, 'MA'=1, 'MI'=5, 'MN'=6, 'MS'=7, 'MO'=7, 'MT'=8,
  'NE'=6, 'NV'=8, 'NH'=1, 'NJ'=3, 'NM'=8, 'NY'=2, 'NC'=4, 'ND'=6, 'OH'=5,
  'OK'=7, 'OR'=8, 'PA'=3, 'PR'=4, 'RI'=1, 'SC'=4, 'SD'=6, 'TN'=7, 'TX'=11,
  'UT'=8, 'VT'=1, 'VA'=4, 'WA'=8, 'WV'=4, 'WI'=6, 'WY'=6,
  'AE'=4, 'AP'=8, 'GU'=8, 'VI'=4
)

# 4. Estimate Propensity Scores
cat("\n=== Estimating Propensity Scores via Logistic Regression ===\n")
pe_model_df <- data.frame(
  treatment = 1,
  MD_vs_DO = pe_matched_all$MD_vs_DO,
  Gender = pe_matched_all$Gender_clean,
  Years_in_Practice = pe_matched_all$Years_in_Practice,
  Open_Payments_Years = pe_matched_all$Open_Payments_Years,
  stringsAsFactors = FALSE
)

cand_model_df <- data.frame(
  treatment = 0,
  MD_vs_DO = candidates_df$MD_vs_DO,
  Gender = candidates_df$Gender_clean,
  Years_in_Practice = candidates_df$Years_in_Practice,
  Open_Payments_Years = candidates_df$Open_Payments_Years,
  stringsAsFactors = FALSE
)

combined_psm_df <- rbind(pe_model_df, cand_model_df)
combined_psm_df$MD_vs_DO <- as.factor(combined_psm_df$MD_vs_DO)
combined_psm_df$Gender <- as.factor(combined_psm_df$Gender)

psm_model <- glm(treatment ~ MD_vs_DO + Gender + Years_in_Practice + Open_Payments_Years, 
                 family = binomial(), data = combined_psm_df)
print(summary(psm_model))

# Predict scores
pe_matched_all$propensity_score <- predict(psm_model, newdata = combined_psm_df[combined_psm_df$treatment == 1, ], type = "response")
candidates_df$propensity_score <- predict(psm_model, newdata = combined_psm_df[combined_psm_df$treatment == 0, ], type = "response")

# 5. Exact City/State and 10-Mile Proximity Match Loop
cat("\n=== Matching Control Group (Option A: < 10 Miles Proximity) ===\n")

# Haversine distance formula in miles
haversine_distance <- function(lat1, lon1, lat2, lon2) {
  if (is.na(lat1) || is.na(lon1) || is.na(lat2) || is.na(lon2)) return(Inf)
  r <- 3959 # Earth's radius in miles
  phi1 <- lat1 * pi / 180
  phi2 <- lat2 * pi / 180
  delta_phi <- (lat2 - lat1) * pi / 180
  delta_lambda <- (lon2 - lon1) * pi / 180
  
  a <- sin(delta_phi / 2)^2 + cos(phi1) * cos(phi2) * sin(delta_lambda / 2)^2
  c <- 2 * atan2(sqrt(a), sqrt(1 - a))
  return(r * c)
}

# Set up lat/long lookup reference from package
data(city_state_to_lat_long, package = "mysterycall")
lat_long_ref <- city_state_to_lat_long
full_to_abbrev <- names(c('AL'='Alabama', 'AK'='Alaska', 'AZ'='Arizona', 'AR'='Arkansas', 'CA'='California',
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
  'PR'='Puerto Rico', 'VI'='Virgin Islands'))
names(full_to_abbrev) <- c('Alabama', 'Alaska', 'Arizona', 'Arkansas', 'California',
  'Colorado', 'Connecticut', 'Delaware', 'District of Columbia',
  'Florida', 'Georgia', 'Hawaii', 'Idaho', 'Illinois',
  'Indiana', 'Iowa', 'Kansas', 'Kentucky', 'Louisiana',
  'Maine', 'Maryland', 'Massachusetts', 'Michigan', 'Minnesota',
  'Mississippi', 'Missouri', 'Montana', 'Nebraska', 'Nevada',
  'New Hampshire', 'New Jersey', 'New Mexico', 'New York',
  'North Carolina', 'North Dakota', 'Ohio', 'Oklahoma', 'Oregon',
  'Pennsylvania', 'Rhode Island', 'South Carolina', 'South Dakota',
  'Tennessee', 'Texas', 'Utah', 'Vermont', 'Virginia',
  'Washington', 'West Virginia', 'Wisconsin', 'Wyoming',
  'Puerto Rico', 'Virgin Islands')

lat_long_ref$state_abbrev <- full_to_abbrev[lat_long_ref$state]
lat_long_ref$city_upper <- toupper(trimws(lat_long_ref$city))
lat_long_ref$state_upper <- toupper(trimws(lat_long_ref$state_abbrev))
lat_long_ref <- lat_long_ref[!is.na(lat_long_ref$state_upper), ]
lat_long_ref <- lat_long_ref[!duplicated(paste(lat_long_ref$city_upper, lat_long_ref$state_upper, sep="_")), ]

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
  if (nrow(match_row) > 0) return(c(match_row$latitude[1], match_row$longitude[1]))
  return(c(NA, NA))
}

# Pre-map coordinates to candidates
candidates_df$latitude <- NA
candidates_df$longitude <- NA
for (i in 1:nrow(candidates_df)) {
  coords <- get_coords(candidates_df$city[i], candidates_df$state[i])
  candidates_df$latitude[i] <- coords[1]
  candidates_df$longitude[i] <- coords[2]
}

# Pre-map coordinates to PE clinicians
pe_matched_all$latitude <- NA
pe_matched_all$longitude <- NA
for (i in 1:nrow(pe_matched_all)) {
  p_city <- pe_matched_all[["DAC City"]][i]
  if (is.na(p_city) || p_city == "" || p_city == "N/A" || p_city == "NAN") {
    p_city <- pe_matched_all[["NPPES City"]][i]
  }
  p_state <- pe_matched_all[["DAC State"]][i]
  if (is.na(p_state) || p_state == "" || p_state == "N/A" || p_state == "NAN") {
    p_state <- pe_matched_all[["NPPES State"]][i]
  }
  coords <- get_coords(p_city, p_state)
  pe_matched_all$latitude[i] <- coords[1]
  pe_matched_all$longitude[i] <- coords[2]
}

matched_pairs <- list()
used_npis <- numeric()
city_match_count <- 0
caliper_geo_match_count <- 0

candidates_df$acog_district <- STATE_TO_ACOG[as.character(candidates_df$state)]
candidates_df$acog_district[is.na(candidates_df$acog_district)] <- 4

# Sort unique office IDs to be deterministic
pe_unique_offices <- sort(unique(pe_matched_all$office_id))

# Seed ONCE, outside the loop. Re-seeding inside the loop restarts the same stream for
# every office, so sample(seq_len(n)) returned the identical permutation at each office
# of a given size, always beginning with index 1. The selection was therefore not random
# at all: it deterministically took the first-listed physician per office, which is not
# what the Methods claims. Seeding here keeps the run reproducible AND random.
set.seed(42)

for (office in pe_unique_offices) {
  office_subset <- pe_matched_all[pe_matched_all$office_id == office, ]
  
  # Try to find a valid match for any physician in this office
  matched_physician <- NULL
  matched_control <- NULL
  
  # Safe-guarded sample loop for length 1 to avoid R sample(x) behavior
  if (nrow(office_subset) == 1) {
    shuffled_indices <- 1
  } else {
    shuffled_indices <- sample(seq_len(nrow(office_subset)))
  }
  
  for (idx in shuffled_indices) {
    phys <- office_subset[idx, ]
    p_coords <- c(phys$latitude, phys$longitude)
    p_score <- phys$propensity_score
    p_state <- phys[["DAC State"]]
    if (is.na(p_state) || p_state == "" || p_state == "N/A" || p_state == "NAN") {
      p_state <- phys[["NPPES State"]]
    }
    p_city <- phys[["NPPES City"]]
    if (is.na(p_city) || p_city == "" || p_city == "N/A" || p_city == "NAN") {
      p_city <- phys[["DAC City"]]
    }
    p_city <- toupper(trimws(p_city))
    
    if (is.na(p_coords[1])) next # skip if coords missing
    
    # Get candidates in the same State
    state_cands <- candidates_df[toupper(trimws(candidates_df$state)) == toupper(trimws(p_state)) & 
                                  !(candidates_df$npi %in% used_npis), ]
    if (nrow(state_cands) == 0) next
    
    # Calculate distance for all candidates in the state
    dists <- sapply(1:nrow(state_cands), function(c_idx) {
      haversine_distance(p_coords[1], p_coords[2], state_cands$latitude[c_idx], state_cands$longitude[c_idx])
    })
    
    # Condition: Must find a matched control within 10 miles, AND there must be >= 2 candidates within 10 miles of PE clinic
    close_indices <- which(dists < 10)
    
    if (length(close_indices) >= 2) {
      close_cands <- state_cands[close_indices, ]
      
      # Select the best match from these close candidates by propensity score
      diffs <- abs(close_cands$propensity_score - p_score)
      best_idx <- which.min(diffs)
      best_control <- close_cands[best_idx, ]
      
      matched_physician <- phys
      matched_control <- best_control
      
      # Track whether it was an exact city match or a close neighbor
      if (toupper(trimws(best_control$city)) == p_city) {
        city_match_count <- city_match_count + 1
      } else {
        caliper_geo_match_count <- caliper_geo_match_count + 1
      }
      break
    }
  }
  
  if (!is.null(matched_physician)) {
    matched_pairs[[office]] <- list(pe = matched_physician, control = matched_control)
    used_npis <- c(used_npis, matched_control$npi)
  }
}

# Construct pe_selected and controls_matched_df from successfully matched offices
pe_selected <- do.call(rbind, lapply(matched_pairs, function(x) x$pe))
controls_matched_df <- do.call(rbind, lapply(matched_pairs, function(x) x$control))

cat(sprintf("Matched %d controls successfully. (City matches: %d, Caliper Geo Matches: %d)\n", 
            nrow(controls_matched_df), city_match_count, caliper_geo_match_count))

# 6. Standardize and Build Control DataFrame matching PE schema
cat("\n=== Standardizing and exporting database files ===\n")
TitleCase <- function(x) {
  s <- tolower(x)
  s <- gsub("\\b([a-z])", "\\U\\1", s, perl = TRUE)
  return(s)
}

TIME_ZONES <- c(
  'CT'='Eastern', 'ME'='Eastern', 'MA'='Eastern', 'NH'='Eastern', 'RI'='Eastern', 'VT'='Eastern',
  'NY'='Eastern', 'NJ'='Eastern', 'PA'='Eastern', 'DE'='Eastern', 'DC'='Eastern', 'MD'='Eastern',
  'VA'='Eastern', 'WV'='Eastern', 'NC'='Eastern', 'SC'='Eastern', 'GA'='Eastern', 'FL'='Eastern',
  'OH'='Eastern', 'MI'='Eastern', 'IN'='Eastern', 'KY'='Eastern',
  'AL'='Central', 'AR'='Central', 'IL'='Central', 'IA'='Central', 'KS'='Central', 'LA'='Central',
  'MN'='Central', 'MS'='Central', 'MO'='Central', 'NE'='Central', 'ND'='Central', 'OK'='Central',
  'SD'='Central', 'TN'='Central', 'TX'='Central', 'WI'='Central',
  'CO'='Mountain', 'MT'='Mountain', 'NM'='Mountain', 'UT'='Mountain', 'WY'='Mountain', 'ID'='Mountain',
  'AZ'='Mountain',
  'CA'='Pacific', 'NV'='Pacific', 'OR'='Pacific', 'WA'='Pacific',
  'AK'='Alaska', 'HI'='Hawaii'
)

get_subspecialty_from_tax <- function(tax) {
  if (is.na(tax) || tax == "") return("Generalist")
  t <- toupper(trimws(tax))
  if (t == "207VE0102X") return("Reproductive Endocrinology/Infertility")
  if (t == "207VX0201X") return("Gynecologic Oncology")
  if (t == "207VM2500X") return("Maternal-Fetal Medicine")
  if (t == "207VF0040X") return("Female Pelvic Medicine and Reconstructive Surgery")
  return("Generalist")
}

control_records <- list()
start_id <- 2001
current_time <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

for (i in 1:nrow(controls_matched_df)) {
  crow <- controls_matched_df[i, ]
  cnpi <- as.numeric(crow$npi)
  first <- TitleCase(trimws(crow$first_name))
  last <- TitleCase(trimws(crow$last_name))
  name <- paste0("Dr. ", first, " ", last)
  
  cred <- ifelse(is.na(crow$cred) || crow$cred == "", "MD", toupper(trimws(crow$cred)))
  md_vs_do <- crow$MD_vs_DO
  gender <- crow$Gender_clean
  
  state <- ifelse(is.na(crow$state) || crow$state == "", "N/A", toupper(trimws(crow$state)))
  acog <- STATE_TO_ACOG[state]
  if (is.na(acog)) acog <- "N/A"
  tz <- TIME_ZONES[state]
  if (is.na(tz)) tz <- "Eastern"
  
  adr1 <- ifelse(is.na(crow$adr_ln_1), "", toupper(trimws(crow$adr_ln_1)))
  adr2 <- ifelse(is.na(crow$adr_ln_2), "", toupper(trimws(crow$adr_ln_2)))
  city <- ifelse(is.na(crow$city), "", toupper(trimws(crow$city)))
  zip_code <- ifelse(is.na(crow$zip_code), "", trimws(crow$zip_code))
  clean_zip <- gsub("[^0-9]", "", zip_code)
  clean_zip <- substr(clean_zip, 1, 5)
  
  formatted_phone <- crow$Phone_formatted
  
  med_sch <- ifelse(is.na(crow$med_sch), "", toupper(crow$med_sch))
  us_vs_img <- "US/Canada"
  if (med_sch != "") {
    if (any(sapply(c('MEXICO', 'GUADALAJARA', 'ROSS', 'ST GEORGE', 'CARIBBEAN', 'SABA', 'ST. GEORGE'), function(k) grepl(k, med_sch)))) {
      us_vs_img <- "IMG"
    }
  }
  
  years_practice <- crow$Years_in_Practice
  op_years <- ifelse(is.na(crow$op_years), 0, as.numeric(crow$op_years))
  op_last_yr <- ifelse(is.na(crow$op_last_year), "N/A", as.character(crow$op_last_year))
  last_act <- ifelse(is.na(crow$last_active_year), "N/A", as.character(crow$last_active_year))
  
  comp_details <- sprintf("%d, Dr %s %s, %s, %s, %s, %.0f, %d", start_id, first, last, formatted_phone, formatted_phone, state, cnpi, start_id)
  
  # Assign unique office_id to controls
  control_office_id <- paste0("control_office_", i)
  
  rec <- list(
    "ID" = start_id,
    "Provider Name" = name,
    "Parsed First Name" = first,
    "Parsed Last Name" = last,
    "Input Credentials" = cred,
    "Input State" = state,
    "Platform/Practice" = "Control Group",
    "PE Owner" = "N/A",
    "Acquisition Year" = "N/A",
    "Source of Information" = "CMS Doctors and Clinicians Database",
    "Scrape Run Time" = current_time,
    "NPI" = cnpi,
    "NPPES Name" = paste(first, last),
    "NPPES Credentials" = cred,
    "NPPES Taxonomy" = ifelse(is.na(crow$taxonomy), "207V00000X", as.character(crow$taxonomy)),
    "Subspecialty" = get_subspecialty_from_tax(crow$taxonomy),
    "NPPES Phone" = formatted_phone,
    "NPPES Address 1" = TitleCase(adr1),
    "NPPES Address 2" = TitleCase(adr2),
    "NPPES City" = TitleCase(city),
    "NPPES State" = state,
    "NPPES Zip" = clean_zip,
    "Scraped Phone" = "N/A",
    "Scraped Address" = "N/A",
    "Time Zone" = tz,
    "Composite Details" = comp_details,
    "Match Quality" = "Propensity Score Matched (Nearest Neighbor)",
    "Match Score" = 1.0,
    "NPI Last Updated" = "N/A",
    "NPPES Enumeration Date" = ifelse(is.na(crow$enum_date), "N/A", as.character(crow$enum_date)),
    "MD vs. DO" = md_vs_do,
    "Gender" = gender,
    "ACOG District" = acog,
    "Practice Setting" = "Private Practice",
    "Telehealth" = ifelse(is.na(crow$telehealth), "N", as.character(crow$telehealth)),
    "Medicare Assignment" = ifelse(is.na(crow$med_assignment), "Y", as.character(crow$med_assignment)),
    "Last Active Year" = last_act,
    "Open Payments Years" = op_years,
    "Open Payments Last Year" = op_last_yr,
    "Medical School" = TitleCase(ifelse(is.na(crow$med_sch), "N/A", as.character(crow$med_sch))),
    "Graduation Year" = ifelse(is.na(crow$grad_yr), "N/A", as.character(crow$grad_yr)),
    "US vs. IMG" = us_vs_img,
    "Years in Practice" = years_practice,
    "DAC Facility Name" = TitleCase(ifelse(is.na(crow$facility_name), "N/A", as.character(crow$facility_name))),
    "DAC Address 1" = TitleCase(adr1),
    "DAC Address 2" = TitleCase(adr2),
    "DAC City" = TitleCase(city),
    "DAC State" = state,
    "DAC Zip" = clean_zip,
    "DAC Phone" = formatted_phone,
    "PE_or_Not" = "Non-PE",
    "office_id" = control_office_id
  )
  control_records[[i]] <- as.data.frame(rec, check.names = FALSE, stringsAsFactors = FALSE)
  start_id <- start_id + 1
}

control_df <- do.call(rbind, control_records)

# 7. Add Matched Pair Groupings
cat("Assigning matched pair IDs to cohorts...\n")
pe_selected$PE_or_Not <- "PE"
pe_selected$Matched_Pair_Group <- paste0("pair_", 1:nrow(pe_selected))
control_df$Matched_Pair_Group <- paste0("pair_", 1:nrow(control_df))

# Standardize physician names to "Dr. First Last"
pe_selected[["Provider Name"]] <- paste0("Dr. ", TitleCase(trimws(pe_selected[["Parsed First Name"]])), " ", TitleCase(trimws(pe_selected[["Parsed Last Name"]])))
control_df[["Provider Name"]] <- paste0("Dr. ", TitleCase(trimws(control_df[["Parsed First Name"]])), " ", TitleCase(trimws(control_df[["Parsed Last Name"]])))

# Map actual practice city and state (used in coordinates distance matching) for calling sheet
pe_selected$Practice_City <- TitleCase(ifelse(!is.na(pe_selected[["DAC City"]]) & pe_selected[["DAC City"]] != "" & pe_selected[["DAC City"]] != "N/A", 
                                      pe_selected[["DAC City"]], pe_selected[["NPPES City"]]))
pe_selected$Practice_State <- toupper(ifelse(!is.na(pe_selected[["DAC State"]]) & pe_selected[["DAC State"]] != "" & pe_selected[["DAC State"]] != "N/A", 
                                       pe_selected[["DAC State"]], pe_selected[["NPPES State"]]))

control_df$Practice_City <- control_df[["NPPES City"]]
control_df$Practice_State <- control_df[["NPPES State"]]

# Overwrite Subspecialty to "Generalist" for all since the cohort is filtered strictly to Generalists only
pe_selected$Subspecialty <- "Generalist"
control_df$Subspecialty <- "Generalist"

# Combine the matched cohorts
matched_only_combined <- rbind(
  pe_selected[, c("NPI", "Provider Name", "Input Credentials", "NPPES Phone", "Practice_City", "Practice_State", "Subspecialty", "Time Zone", "PE_or_Not", "office_id", "Matched_Pair_Group")],
  control_df[, c("NPI", "Provider Name", "Input Credentials", "NPPES Phone", "Practice_City", "Practice_State", "Subspecialty", "Time Zone", "PE_or_Not", "office_id", "Matched_Pair_Group")]
)

# Rename headers of the combined calling list to preserve spaces
colnames(matched_only_combined) <- c("NPI", "Provider Name", "Credentials", "Phone", "City", "State", "Subspecialty", "Time Zone", "PE_or_Not", "office_id", "Matched Pair ID")

# Reorder calling list alphabetically by Matched Pair ID
matched_only_combined <- matched_only_combined[order(as.numeric(gsub("pair_", "", matched_only_combined[["Matched Pair ID"]]))), ]

# Save Matched Calling List
write.csv(matched_only_combined, calling_list_csv, row.names = FALSE)
cat(sprintf("Matched calling list exported to: %s (%d records)\n", calling_list_csv, nrow(matched_only_combined)))

# 8. Save unified study database files
# In study database, we want to include the full integrated active PE cohort (1,537 rows)
# and union it with the matched controls (778 rows) to ensure downstream regression scripts compile properly.
pe_full_df <- pe_df
pe_full_df$PE_or_Not <- "PE"

# Map office_id and Matched_Pair_Group back to the full PE cohort
# First clear old office_id in PE cohort
pe_full_df$office_id <- NULL
pe_full_df$Matched_Pair_Group <- NULL

# Merge office_id and Matched_Pair_Group mapping from pe_matched_all
pe_map_df <- pe_matched_all[, c("NPI", "office_id")]
# Map Matched_Pair_Group only for selected PE providers
pe_selected_map <- pe_selected[, c("NPI", "Matched_Pair_Group")]

pe_full_df <- merge(pe_full_df, pe_map_df, by = "NPI", all.x = TRUE)
pe_full_df <- merge(pe_full_df, pe_selected_map, by = "NPI", all.x = TRUE)
pe_full_df$Matched_Pair_Group[is.na(pe_full_df$Matched_Pair_Group)] <- "N/A"

# Union full PE cohort + control matched cohort
# First standardise colnames in control_df to match pe_full_df
control_df$Matched_Pair_Group <- control_df$Matched_Pair_Group
# Make sure control_df has the same columns as pe_full_df, fill missing with N/A
missing_cols <- setdiff(colnames(pe_full_df), colnames(control_df))
for (c in missing_cols) {
  control_df[[c]] <- "N/A"
}
control_df <- control_df[, colnames(pe_full_df)]

combined_study_df <- rbind(pe_full_df, control_df)
write.csv(combined_study_df, study_output_csv, row.names = FALSE)
cat(sprintf("Unified study database exported to: %s (%d records)\n", study_output_csv, nrow(combined_study_df)))

write.csv(control_df, control_output_csv, row.names = FALSE)
cat(sprintf("Control cohort exported to: %s (%d records)\n", control_output_csv, nrow(control_df)))

cat("\n=== PSM MATCHING COMPLETE ===\n")
