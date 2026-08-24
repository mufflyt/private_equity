# R Script to generate and save Figure 1, 2, and 3 as high-resolution PNGs
#
# WARNING, AND THE REASON THE OUTPUT NAMES CARRY A PREFIX.
#
# Figures 1 and 2 depict the study's PRIMARY OUTCOMES -- appointment obtainment by ownership
# and payer, and the wait-time distribution. Neither is measured. Figure 1's rates are typed
# into this file as literals, confidence intervals included. Figure 2 is rlnorm() draws around
# medians typed in the same way. No call has been placed, no REDCap outcome export exists, and
# the analysis in SAP.lock has never been run.
#
# Nothing in this script said so. The outputs were named figure1.png and figure2.png and their
# titles read as findings: "Appointment Obtainment Rates by Practice Ownership", "Distribution
# of Appointment Wait Times (Business Days)". A file in manuscript/ with that name and that
# title is one drag away from a draft.
#
# This repository already polices exactly this for columns -- CDC_SVI became SIMULATED_CDC_SVI
# so that "no column name in a fielded artifact asserts a measurement that was not made"
# (test-svi-provenance.R). The same rule now applies to figures. The outputs are prefixed, the
# titles say so on their face, and test-artifact-vintage.R fails if either is undone while no
# outcome data exists.
#
# When real outcomes arrive: delete the literals, read the REDCap export, drop the prefix.
library(ggplot2)
library(mysterycall)
library(DiagrammeRsvg)
library(rsvg)

# Resolve the repository root from this script's own path, so it runs from any working
# directory -- the blocking test invokes it from tests/testthat.
.self <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
.ROOT <- if (is.na(.self)) normalizePath(".") else normalizePath(file.path(dirname(.self), ".."))
source(file.path(.ROOT, "R", "pe_helpers.R"))
output_dir <- "manuscript"
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# Configure Green Journal theme color palette
green_color <- "#0C5A30"  # Forest green typical of the Green Journal
gray_color <- "#7F8C8D"   # Soft neutral gray for contrast

cat("=== Generating Figure 1: Appointment Obtainment (Medicaid Acceptance) ===\n")
fig1_data <- data.frame(
  Group = rep(c("Independent", "PE-Backed"), each = 2),
  Payer = rep(c("BCBS PPO (Commercial)", "Medicaid"), 2),
  Rate = c(0.985, 0.725, 0.990, 0.410),
  ymin = c(0.968, 0.663, 0.976, 0.342),
  ymax = c(1.000, 0.787, 1.000, 0.478)
)

p1 <- ggplot(fig1_data, aes(x = Group, y = Rate, fill = Payer)) +
  geom_bar(stat = "identity", position = position_dodge(0.8), width = 0.7) +
  geom_errorbar(aes(ymin = ymin, ymax = ymax), position = position_dodge(0.8), width = 0.2, color = "#2C3E50", linewidth = 0.8) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1), limits = c(0, 1.05)) +
  scale_fill_manual(values = c("BCBS PPO (Commercial)" = green_color, "Medicaid" = gray_color)) +
  labs(
    title = "SIMULATED - Appointment Obtainment Rates by Practice Ownership",
    subtitle = "Illustrative values. No calls have been placed; no outcome data exists.",
    x = "Practice Type",
    y = "Appointment Offer Rate (%)",
    fill = "Insurance Presenting"
  ) +
  theme_minimal(base_family = "Helvetica") +
  theme(
    plot.title = element_text(face = "bold", size = 12, hjust = 0.5),
    legend.position = "bottom",
    axis.title = element_text(face = "bold", size = 10),
    axis.text = element_text(size = 9)
  )

ggsave(file.path(output_dir, "SIMULATED_figure1_obtainment.png"), plot = p1, width = 6.5, height = 4.5, dpi = 300)
# No source artifact exists for this figure, and saying so is the point. NONE is a record;
# silence is not.
record_output_provenance("SIMULATED_figure1_obtainment.png", NA_character_,
                         "manuscript/generate_figures.R", "simulated",
                         path = file.path(.ROOT, "manuscript", "PROVENANCE.csv"))

cat("=== Generating Figure 2: Wait Time Distribution ===\n")
set.seed(123)
n_sim <- 1000

ind_bcbs <- rlnorm(n_sim, meanlog = log(12) - 0.5 * 0.15, sdlog = 0.4)
pe_bcbs <- rlnorm(n_sim, meanlog = log(14.5) - 0.5 * 0.15, sdlog = 0.4)
ind_med <- rlnorm(n_sim, meanlog = log(23.4) - 0.5 * 0.15, sdlog = 0.4)
pe_med <- rlnorm(n_sim, meanlog = log(36.8) - 0.5 * 0.15, sdlog = 0.4)

fig2_data <- data.frame(
  Wait_Time = c(ind_bcbs, pe_bcbs, ind_med, pe_med),
  Group = rep(c("Independent", "PE-Backed", "Independent", "PE-Backed"), each = n_sim),
  Payer = rep(c("BCBS PPO", "BCBS PPO", "Medicaid", "Medicaid"), each = n_sim)
)

p2 <- ggplot(fig2_data, aes(x = Wait_Time, color = Payer, linetype = Group)) +
  geom_density(linewidth = 1) +
  scale_x_continuous(limits = c(0, 80), breaks = seq(0, 80, 10)) +
  scale_color_manual(values = c("BCBS PPO" = green_color, "Medicaid" = gray_color)) +
  labs(
    title = "SIMULATED - Distribution of Appointment Wait Times (Business Days)",
    subtitle = "Illustrative values. No calls have been placed; no outcome data exists.",
    x = "Business Days to First Available Appointment",
    y = "Density",
    color = "Payer",
    linetype = "Practice Type"
  ) +
  theme_minimal(base_family = "Helvetica") +
  theme(
    plot.title = element_text(face = "bold", size = 12, hjust = 0.5),
    legend.position = "bottom",
    axis.title = element_text(face = "bold", size = 10),
    axis.text = element_text(size = 9)
  )

ggsave(file.path(output_dir, "SIMULATED_figure2_wait_times.png"), plot = p2, width = 6.5, height = 4.5, dpi = 300)
record_output_provenance("SIMULATED_figure2_wait_times.png", NA_character_,
                         "manuscript/generate_figures.R", "simulated",
                         path = file.path(.ROOT, "manuscript", "PROVENANCE.csv"))

cat("=== Generating Figure 3: STROBE Flow Diagram ===\n")
# Define self-explanatory, descriptive text for the nodes and exclusions
counts <- c(
  "Initial Scraped Roster from Private Equity Platform Directories" = 1537,
  "Clinicians Verified with Unique National Provider Identifier (NPI)" = 1279,
  "NPI-Verified Generalist OB-GYNs" = 1021,
  "Unique Private Equity-Backed GYN Offices Available for Matching" = 544,
  "Geographically Matched Cohort (1-to-1 with Controls within 10 Miles)" = 544,
  "Fielded Study Sample for Crossover Calling Campaign" = 200
)

exclusions <- list(
  "Clinicians Verified with Unique National Provider Identifier (NPI)" = "Excluded: 258 Clinicians\\n- Unmatched to NPPES database (n = 142)\\n- Retired or inactive credentials (n = 116)",
  "NPI-Verified Generalist OB-GYNs" = "Excluded: 258 Subspecialists\\n- REI, Oncology, MFM, or MIGS listed in directories",
  "Unique Private Equity-Backed GYN Offices Available for Matching" = "Excluded: 477 Duplicate Office Locations\\n- Retained exactly 1 clinician per physical office location",
  "Fielded Study Sample for Crossover Calling Campaign" = "Reserved: 344 Matched Pairs (688 Clinicians)\\n- Retained in reserve pool to protect against calling attrition"
)

# Build flowchart using mysterycall package
# Increase node_width to 5.0 to accommodate the longer descriptive text lines cleanly
flowchart <- mysterycall_plot_inclexcl(counts, exclusions, node_width = 5.2, font_size = 9L)

# Export DiagrammeR htmlwidget to SVG string
svg_text <- DiagrammeRsvg::export_svg(flowchart)

# Write SVG string to PNG
rsvg::rsvg_png(charToRaw(svg_text), file = file.path(output_dir, "figure3.png"), width = 1600)

cat("Figures generation complete! Files saved to:", output_dir, "\n")
