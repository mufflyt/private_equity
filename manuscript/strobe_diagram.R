# R Script to Generate Interactive STROBE Flowchart using mysterycall package
library(mysterycall)

# Define counts at each stage of the matching pipeline
counts <- c(
  "Initial Scraped PE Roster" = 1537,
  "Unique NPI Verified" = 1279,
  "OB-GYN Generalist Only" = 1021,
  "De-clustered (1/Office)" = 544,
  "Geographically Matched" = 544,
  "Fielded Cohort" = 200
)

# Define exclusions for each stage
exclusions <- list(
  "Unique NPI Verified" = "258 names unmatched/retired",
  "OB-GYN Generalist Only" = "258 subspecialists excluded",
  "De-clustered (1/Office)" = "477 clinicians excluded",
  "Fielded Cohort" = "344 matched pairs reserved"
)

# Generate DiagrammeR object
strobe_flowchart <- mysterycall_plot_inclexcl(
  counts = counts,
  exclusions = exclusions,
  title = "STROBE Flow Diagram: Clinician Inclusion and Exclusion Pathway"
)

# Print flowchart in RStudio viewer
print(strobe_flowchart)
