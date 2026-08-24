# R Script to Generate Interactive STROBE Flowchart using mysterycall package
library(mysterycall)

# Define counts at each stage of the matching pipeline
counts <- c(
  "Initial Scraped PE Roster" = 1537,
  "Unique NPI Verified" = 1279,
  "OB-GYN Generalist Only" = 1021,
  # VERIFIED 2026-08-24 against the committed artifacts, in clinicians throughout.
  #   Initial Scraped PE Roster  1537  pe_obgyn_providers_active.csv, rows
  #   Unique NPI Verified        1279  distinct NPIs in that file
  #   Geographically Matched      918  pe_obgyn_matched_calling_list.csv (459 pairs)
  #   Fielded Cohort              400  pe_obgyn_final_calling_sheet_200_dedup.csv (200 pairs)
  #
  # "Geographically Matched" and "Fielded Cohort" were 544 and 200. 544 matches nothing in the
  # current pipeline, and 200 was pairs while every stage above it was clinicians, so the
  # figure changed units halfway down without saying so.
  #
  # "De-clustered (1/Office)" = 544 is NOT verifiable against any committed artifact and is
  # left as found rather than invented. It needs the value the de-clustering step actually
  # produced. test-artifact-vintage.R asserts only the four stages that can be checked.
  "De-clustered (1/Office)" = 544,
  "Geographically Matched" = 918,
  "Fielded Cohort" = 400
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
