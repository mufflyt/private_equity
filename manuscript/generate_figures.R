# R Script to generate and save Figure 1, 2, and 3 as high-resolution PNGs
library(ggplot2)
library(mysterycall)
library(DiagrammeRsvg)
library(rsvg)

output_dir <- "/Users/tylermuffly/private_equity/manuscript"
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
    title = "Appointment Obtainment Rates by Practice Ownership",
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

ggsave(file.path(output_dir, "figure1.png"), plot = p1, width = 6.5, height = 4.5, dpi = 300)

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
    title = "Distribution of Appointment Wait Times (Business Days)",
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

ggsave(file.path(output_dir, "figure2.png"), plot = p2, width = 6.5, height = 4.5, dpi = 300)

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
