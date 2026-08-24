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
  "De-clustered (1/Office)" = NA_integer_,   # UNRESOLVED -- see the guard below
  "Geographically Matched" = 918,
  "Fielded Cohort" = 400
)

# FAIL CLOSED. Two stages could not be reproduced from any committed artifact:
# "OB-GYN Generalist Only" = 1021 and "De-clustered (1/Office)", which read 544. 544 matches
# nothing in the current pipeline, and a plausible-but-unproven cohort count is the same class
# of error as a simulated figure presented as a result -- it is simply harder to notice.
#
# Rather than deduce a replacement, the de-clustering stage is NA and this script stops. Fill
# it with the number that step actually produced, from the script that produced it, and this
# runs again. Do not fill it by subtraction from the stages around it.
UNRESOLVED <- names(counts)[is.na(counts)]
if (length(UNRESOLVED)) {
  stop("STROBE stages are unresolved and this figure will not be generated: ",
       paste(UNRESOLVED, collapse = ", "),
       "\n  Supply the count the pipeline actually produced. Do not infer it.",
       call. = FALSE)
}

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
