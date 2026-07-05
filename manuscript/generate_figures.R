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
# Construct obtainment dataframe (Dummy values)
fig1_data <- data.frame(
  Group = rep(c("Independent", "PE-Backed"), each = 2),
  Payer = rep(c("BCBS PPO (Commercial)", "Medicaid"), 2),
  Rate = c(0.985, 0.725, 0.990, 0.410)
)

p1 <- ggplot(fig1_data, aes(x = Group, y = Rate, fill = Payer)) +
  geom_bar(stat = "identity", position = position_dodge(0.8), width = 0.7) +
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
# Simulate wait time distributions based on dummy statistics
set.seed(123)
n_sim <- 1000

# Simulate wait times using log-normal distributions matched to our means/SDs
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
# Define inclusion/exclusion counts
counts <- c(
  "Initial Scraped PE Roster" = 1537,
  "Unique NPI Verified" = 1279,
  "OB-GYN Generalist Only" = 1021,
  "De-clustered (1/Office)" = 544,
  "Geographically Matched" = 544,
  "Fielded Cohort" = 200
)

exclusions <- list(
  "Unique NPI Verified" = "258 names unmatched/retired",
  "OB-GYN Generalist Only" = "258 subspecialists excluded",
  "De-clustered (1/Office)" = "477 clinicians excluded",
  "Fielded Cohort" = "344 matched pairs reserved"
)

# Build flowchart using mysterycall package
flowchart <- mysterycall_plot_inclexcl(counts, exclusions)

# Export DiagrammeR htmlwidget to SVG string
svg_text <- DiagrammeRsvg::export_svg(flowchart)

# Write SVG string to PNG
rsvg::rsvg_png(charToRaw(svg_text), file = file.path(output_dir, "figure3.png"), width = 1200)

cat("Figures generation complete! Files saved to:", output_dir, "\n")
