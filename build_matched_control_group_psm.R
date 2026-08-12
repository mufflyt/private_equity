# Propensity Score Matching (PSM) Control Group Construction Script (Updated)
# Step 1: Cluster PE active cohort by physical practice location (office_id)
# Step 2: Randomly sample exactly one PE physician per office_id (778 unique offices)
# Step 3: Run logistic regression on this collapsed PE sample + candidate controls to estimate propensity scores
# Step 4: Perform nearest-neighbor PSM matching (1-to-1 match, exact state constraint)
# Step 5: Save control group, study database, and a clean matched calling list CSV

suppressMessages(library(dplyr))

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

# ---------------------------------------------------------------------------------------
# PLATFORM-LEVEL ELIGIBILITY EXCLUSION
#
# Five platforms cannot supply the appointment the study requests. The fielded vignette is
# abnormal uterine bleeding, a generalist outpatient GYN visit. Four are fertility practices
# (subspecialty referral settings) and one is an inpatient hospitalist group with no
# outpatient clinic at all. A caller asking them for this appointment is told none exists,
# which would enter the obtainment outcome as a refusal.
#
# This is an eligibility exclusion at the PLATFORM level, applied before office clustering,
# propensity estimation and matching. A taxonomy filter cannot do this job: a physician at a
# fertility platform can carry a generalist OB-GYN taxonomy and pass every subspecialty test.
#
# TWO COHORTS ARE MAINTAINED:
#   pe_roster_all  every PE-owned NPI, including excluded platforms. Used ONLY to keep all
#                  PE clinicians out of the control pool. Excluding a platform from the
#                  treated arm must not make its clinicians eligible as "independent".
#   pe_matched_all the study-eligible treated cohort, which feeds clustering, matching and
#                  the unified study database.
EXCLUDED_PLATFORMS <- c("CCRM Fertility", "IVI RMA Global", "US Fertility",
                        "Kindbody", "OB Hospitalist Group")

# Individually verified non-physicians. NPPES taxonomy alone is not a defensible eligibility
# criterion (it is self-reported, often a decade stale, and only one taxonomy per NPI is
# retained upstream), so these were confirmed one by one against the practice's own website
# rather than filtered by code. Verified 2026-08-10:
#   1144280553  Cindy Joslyn  - CNM. Women's Health of Central Massachusetts lists her as
#                               "Certified by the American College of Nurse Midwives"; the
#                               roster name "Cindy Joslyn, MD" is a scrape error, which is
#                               how she passed the MD/DO derivation.
# Checked and RETAINED (taxonomy wrong, clinician eligible):
#   1932194743  Claire Harraghy - taxonomy reads 363LW0102X (nurse practitioner) but she is a
#                               board-certified OB-GYN physician at A Woman's View, Hickory NC.
EXCLUDED_NPIS <- c("1144280553")

pe_roster_all <- pe_df[!is.na(pe_df$NPI), ]
pe_matched_all <- pe_roster_all

.npi_norm <- sub("\\.0+$", "", trimws(as.character(pe_matched_all$NPI)))
if (any(.npi_norm %in% EXCLUDED_NPIS)) {
  cat(sprintf("  Verified non-physicians excluded by NPI: %d\n", sum(.npi_norm %in% EXCLUDED_NPIS)))
  pe_matched_all <- pe_matched_all[!(.npi_norm %in% EXCLUDED_NPIS), ]
}

# ---------------------------------------------------------------------------------------
# ACTIVITY RECENCY EXCLUSION
#
# Drop clinicians not observed practising within MAX_INACTIVE_YEARS. A clinician who has
# left is recorded as a failure to contact, which enters the primary obtainment outcome as
# if it were a refusal to see the patient.
#
# The threshold is anchored to the NEWEST activity year present in the data, not to the
# calling year. The activity source stops at 2021, so measuring against 2026 would require
# activity in 2024 or later and would remove every clinician in the cohort. Anchoring to the
# data's own currency asks the answerable question, "was this clinician still practising at
# the end of the observation window", and self-calibrates if the source is ever refreshed.
#
# Clinicians with NO recorded activity year are RETAINED: absent evidence of activity is not
# evidence of absence, and excluding them would drop a further 505 roster rows on a missing
# value rather than an observation.
MAX_INACTIVE_YEARS <- 2

.last_active <- suppressWarnings(as.numeric(trimws(ifelse(
  is.na(pe_matched_all[["Last Active Year"]]), "", pe_matched_all[["Last Active Year"]]))))
ACTIVITY_REFERENCE_YEAR <- suppressWarnings(max(.last_active, na.rm = TRUE))

if (is.finite(ACTIVITY_REFERENCE_YEAR)) {
  .cutoff <- ACTIVITY_REFERENCE_YEAR - (MAX_INACTIVE_YEARS - 1L)
  .stale  <- !is.na(.last_active) & .last_active < .cutoff
  cat("\n=== Activity recency exclusion ===\n")
  cat(sprintf("  newest activity year in source: %d | keeping clinicians active %d or later\n",
              ACTIVITY_REFERENCE_YEAR, .cutoff))
  cat(sprintf("  excluded as inactive: %d | retained with no activity year recorded: %d\n",
              sum(.stale), sum(is.na(.last_active))))
  if (sum(.stale) > 0.5 * sum(!is.na(.last_active))) {
    stop("Activity recency exclusion would remove more than half the cohort; ",
         "check that Last Active Year is populated and current before proceeding.")
  }
  pe_matched_all <- pe_matched_all[!.stale, ]
}

.plat <- trimws(ifelse(is.na(pe_matched_all[["Platform/Practice"]]), "",
                       pe_matched_all[["Platform/Practice"]]))
cat("\n=== Platform-level eligibility exclusion ===\n")
for (px in EXCLUDED_PLATFORMS) {
  n_phys <- sum(.plat == px)
  cat(sprintf("  %-22s excluded: %4d physicians\n", px, n_phys))
}
pe_matched_all <- pe_matched_all[!(.plat %in% EXCLUDED_PLATFORMS), ]
cat(sprintf("  PE roster (all, control-ineligible): %d | study-eligible after exclusion: %d\n",
            nrow(pe_roster_all), nrow(pe_matched_all)))

# Filter out PE providers with no valid phone numbers (Scraped, NPPES, or DAC)
na_if_invalid <- function(x) {
  ifelse(is.na(x) | x == "" | x == "N/A" | x == "NAN", NA_character_, as.character(x))
}

pe_matched_all <- pe_matched_all %>%
  filter(!is.na(na_if_invalid(`Scraped Phone`)) | 
         !is.na(na_if_invalid(`NPPES Phone`)) | 
         !is.na(na_if_invalid(`DAC Phone`)))

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

# Every PE-owned NPI is ineligible as a control, including clinicians at the five platforms
# excluded from the treated arm above. Nothing previously enforced this; the pools happened
# not to overlap, which is a property of the source data rather than a guarantee.
.pe_all_npi <- sub("\\.0+$", "", trimws(as.character(pe_roster_all$NPI)))
.cand_npi   <- sub("\\.0+$", "", trimws(as.character(candidates_df$npi)))
.n_pe_in_ctl <- sum(.cand_npi %in% .pe_all_npi)
if (.n_pe_in_ctl > 0) {
  cat(sprintf("Removing %d PE-owned clinicians from the control candidate pool.\n", .n_pe_in_ctl))
  candidates_df <- candidates_df[!(.cand_npi %in% .pe_all_npi), ]
}

# Apply the SAME activity recency rule to controls. Filtering only the treated arm would
# give the two arms different eligibility criteria: PE clinicians would be guaranteed
# recently active while controls would not, so any difference in reachability between arms
# would partly reflect the filter rather than ownership. The 10 fielded controls last active
# before 2020 that this catches were invisible while the rule ran on one arm only.
if (is.finite(ACTIVITY_REFERENCE_YEAR) && "last_active_year" %in% names(candidates_df)) {
  .cand_last <- suppressWarnings(as.numeric(trimws(as.character(candidates_df$last_active_year))))
  .cand_stale <- !is.na(.cand_last) & .cand_last < .cutoff
  cat(sprintf("  control candidates excluded as inactive (same rule, cutoff %d): %d | retained with no year: %d\n",
              .cutoff, sum(.cand_stale), sum(is.na(.cand_last))))
  candidates_df <- candidates_df[!.cand_stale, ]
}

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
STUDY_YEAR <- 2026
study_year <- STUDY_YEAR

pe_matched_all <- pe_matched_all %>%
  mutate(
    Gender_clean = coalesce(Gender, "Female"),
    MD_vs_DO = coalesce(`MD vs. DO`, "MD"),
    Years_in_Practice = as.numeric(`Years in Practice`),
    Years_in_Practice = coalesce(Years_in_Practice, median(Years_in_Practice, na.rm = TRUE)),
    Open_Payments_Years = as.numeric(`Open Payments Years`),
    Open_Payments_Years = coalesce(Open_Payments_Years, median(Open_Payments_Years, na.rm = TRUE))
  )

candidates_df <- candidates_df %>%
  mutate(
    Gender_clean = case_when(
      is.na(gender) ~ "Female",
      gender == "F" ~ "Female",
      gender == "M" ~ "Male",
      TRUE ~ "Female"
    ),
    MD_vs_DO = if_else(is.na(cred), "MD", if_else(grepl("DO", toupper(cred)), "DO", "MD")),
    Years_in_Practice = study_year - as.numeric(grad_yr),
    enum_yr = as.numeric(sapply(strsplit(as.character(enum_date), "-"), `[`, 1)),
    Years_in_Practice = coalesce(Years_in_Practice, study_year - enum_yr),
    Years_in_Practice = coalesce(Years_in_Practice, median(Years_in_Practice, na.rm = TRUE)),
    Open_Payments_Years = coalesce(as.numeric(op_years), 0)
  )

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

# ---------------------------------------------------------------- gazetteer boundary
#
# The gazetteer is a FROZEN ANALYSIS DEPENDENCY, not a package implementation detail. The
# coordinate each clinician was assigned decides which controls fell inside the 10-mile
# caliper, so replacing the reference is a new matching specification, not an upgrade.
#
# mysterycall has since changed the dataset's schema (object renamed to snake_case, columns
# renamed to latitude/longitude). Re-resolving the fielded cohort through the current build
# reproduces only 82.2% of the persisted coordinates, with a maximum discrepancy of 54 degrees.
# The build the cohort was matched against no longer exists anywhere. See
# inst/frozen/PROVENANCE.md.
#
# Everything downstream of this boundary sees exactly four columns -- city, state, lat, long --
# whatever the package happens to ship. `normalize_gazetteer()` accepts either the historical
# abbreviated-state schema or the current full-name schema and errors rather than guessing.

#' Reduce any gazetteer schema to the pipeline contract: city, state, lat, long.
#'
#' Column resolution is EXACT. `$` partial matching silently rescued `$lat` against a
#' `latitude` column for months and would have stopped doing so the moment any other `lat*`
#' column appeared; nothing downstream may rely on it.
normalize_gazetteer <- function(g, full_to_abbrev) {
  pick <- function(cands, what) {
    hit <- cands[cands %in% names(g)]
    if (!length(hit)) {
      stop(sprintf(paste0("Gazetteer has no %s column. Looked for: %s. Found: %s.\n",
                          "  The dependency's schema changed; extend normalize_gazetteer() ",
                          "rather than\n  relying on partial matching."),
                   what, paste(cands, collapse = ", "), paste(names(g), collapse = ", ")),
           call. = FALSE)
    }
    g[[hit[1]]]
  }

  raw_state <- pick(c("state", "state_abbrev", "STATE"), "state")
  out <- data.frame(
    city  = toupper(trimws(pick(c("city", "CITY"), "city"))),
    state = ifelse(nchar(trimws(raw_state)) == 2L, toupper(trimws(raw_state)),
                   unname(full_to_abbrev[raw_state])),
    lat   = as.numeric(pick(c("lat", "latitude", "LAT"), "latitude")),
    long  = as.numeric(pick(c("long", "longitude", "lon", "lng", "LONG"), "longitude")),
    stringsAsFactors = FALSE
  )
  stopifnot(identical(names(out), c("city", "state", "lat", "long")))
  out
}

# Set up lat/long lookup reference from package
data(city_state_to_lat_long, package = "mysterycall")
lat_long_raw <- city_state_to_lat_long
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

# city_state_to_lat_long$state already holds two-letter abbreviations ("AL", "AZ"), but
# full_to_abbrev is keyed by full state names ("Alabama"). Mapping one through the other
# returned NA for all 31,909 rows, and the !is.na() filter below then emptied the entire
# gazetteer. get_coords() consequently fell through to the 17-entry manual_coords list and
# returned NA for every other city, which is why matching reported "Caliper Geo Matches: 0"
# and produced 2 pairs instead of 511. Accept either vocabulary.
lat_long_ref <- normalize_gazetteer(lat_long_raw, full_to_abbrev)
lat_long_ref$city_upper  <- lat_long_ref$city
lat_long_ref$state_upper <- lat_long_ref$state
lat_long_ref <- lat_long_ref[!is.na(lat_long_ref$state_upper), ]

# Fail loudly if the gazetteer has been emptied. This filter previously removed all
# 31,909 rows and the script carried on, geocoding everything to NA and reporting a
# successful matching run that had in fact matched almost nothing.
if (nrow(lat_long_ref) == 0L) {
  stop("Geocoding gazetteer is empty after state normalisation: every row was dropped. ",
       "Check that city_state_to_lat_long$state and full_to_abbrev use the same vocabulary.")
}
cat(sprintf("Gazetteer ready: %d city/state coordinates.\n", nrow(lat_long_ref)))
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
  # `[[` not `$`: the columns are guaranteed by normalize_gazetteer(), and `$` would partial
  # match `lat` against a `latitude` column, which is how this survived a schema change
  # without anyone noticing. `[[` errors on a missing name instead of silently succeeding.
  if (nrow(match_row) > 0) return(c(match_row[["lat"]][1], match_row[["long"]][1]))
  return(c(NA, NA))
}

# Pre-map coordinates to candidates
candidates_df <- candidates_df %>%
  rowwise() %>%
  mutate(
    coords = list(get_coords(city, state)),
    latitude = coords[1],
    longitude = coords[2]
  ) %>%
  ungroup() %>%
  select(-coords)

# Pre-map coordinates to PE clinicians
pe_matched_all <- pe_matched_all %>%
  mutate(
    p_city = coalesce(na_if_invalid(`DAC City`), na_if_invalid(`NPPES City`)),
    p_state = coalesce(na_if_invalid(`DAC State`), na_if_invalid(`NPPES State`))
  ) %>%
  rowwise() %>%
  mutate(
    coords = list(get_coords(p_city, p_state)),
    latitude = coords[1],
    longitude = coords[2]
  ) %>%
  ungroup() %>%
  select(-coords, -p_city, -p_state)

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
    # EXACT GENDER MATCH. The Methods states clinicians were matched "on provider gender
    # (exact match)". Gender previously entered only through the propensity score, which
    # balances the marginal distribution but not the pairs: 79 of 200 fielded pairs had
    # members of different gender while the marginal SMD was a well-balanced -0.011.
    # Aggregate balance and pair-level matching are different properties, so the constraint
    # is enforced here, in the candidate pool, where it can actually bind.
    #
    # Gender_clean defaults a missing value to "Female" (27 of 1,537 PE clinicians, none of
    # the controls), so those clinicians are matched to women by that default rather than by
    # an observation. Recorded rather than silently relied upon.
    p_gender <- phys$Gender_clean
    state_cands <- candidates_df[toupper(trimws(candidates_df$state)) == toupper(trimws(p_state)) &
                                  candidates_df$Gender_clean == p_gender &
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
# Control records are drawn from the CMS Doctors and Clinicians registry, not scraped from a
# platform directory, so they have no scrape time. Stamping them with the run clock both
# mislabels their provenance and makes the study database non-reproducible: two identical
# runs differed in exactly the 459 control rows. The run timestamp belongs in a sidecar,
# not in a data column, so the artifact is byte-identical across runs.
current_time <- NA_character_
run_stamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

for (i in 1:nrow(controls_matched_df)) {
  crow <- controls_matched_df[i, ]
  # Coordinates of the exact candidate row the matcher selected, not a later NPI lookup.
  ctrl_lat <- if ("latitude"  %in% names(crow)) crow$latitude[1]  else NA_real_
  ctrl_lon <- if ("longitude" %in% names(crow)) crow$longitude[1] else NA_real_
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
    "office_id" = control_office_id,
    # Carry the coordinates of the control row the matcher actually selected. NPI is not
    # unique in the candidate pool (one clinician can appear at several addresses), so
    # recovering coordinates later by NPI picks an arbitrary row and was wrong for 19% of
    # controls, making matched pairs appear to violate a caliper the matcher had enforced.
    "Matcher_Latitude"  = ctrl_lat,
    "Matcher_Longitude" = ctrl_lon
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
# The unified study database must be built from the STUDY-ELIGIBLE cohort. Resetting this to
# pe_df would reintroduce all five excluded platforms downstream, silently undoing the
# eligibility exclusion for every artifact derived from this database.
pe_full_df <- pe_matched_all
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
# Attach the PE side's matcher coordinates before column alignment, so that both arms carry
# Matcher_Latitude/Longitude and the alignment below preserves the control values already
# recorded from the selected candidate row.
pe_coord_idx <- match(pe_full_df$NPI, pe_matched_all$NPI)
pe_full_df$Matcher_Latitude  <- pe_matched_all$latitude[pe_coord_idx]
pe_full_df$Matcher_Longitude <- pe_matched_all$longitude[pe_coord_idx]

missing_cols <- setdiff(colnames(pe_full_df), colnames(control_df))
for (c in missing_cols) {
  control_df[[c]] <- "N/A"
}
control_df <- control_df[, colnames(pe_full_df)]

combined_study_df <- rbind(pe_full_df, control_df)

# Persist the coordinates the caliper actually matched on. Without this the study's central
# geographic claim is unauditable: the matcher computed latitude/longitude, used them for
# the 10-mile caliper, then discarded them, and the Latitude/Longitude columns that appeared
# downstream came from apply_hq_distance.R / calculate_pair_distances.R instead. Any audit
# of the 10-mile constraint was therefore measuring a different coordinate source than the
# one matching used. Writing them here makes the two the same by construction.
cat(sprintf("Persisted matcher coordinates for %d of %d records (PE %d, control %d).\n",
            sum(!is.na(combined_study_df$Matcher_Latitude)), nrow(combined_study_df),
            sum(!is.na(combined_study_df$Matcher_Latitude) & combined_study_df$PE_or_Not != "Non-PE"),
            sum(!is.na(combined_study_df$Matcher_Latitude) & combined_study_df$PE_or_Not == "Non-PE")))

write.csv(combined_study_df, study_output_csv, row.names = FALSE)
writeLines(sprintf("study_database_generated_at: %s\nrows: %d\nmatched_pairs: %d",
                   run_stamp, nrow(combined_study_df), nrow(controls_matched_df)),
           file.path(dirname(study_output_csv), "pe_obgyn_study_database.provenance.txt"))
cat(sprintf("Unified study database exported to: %s (%d records)\n", study_output_csv, nrow(combined_study_df)))

write.csv(control_df, control_output_csv, row.names = FALSE)
cat(sprintf("Control cohort exported to: %s (%d records)\n", control_output_csv, nrow(control_df)))

cat("\n=== PSM MATCHING COMPLETE ===\n")
