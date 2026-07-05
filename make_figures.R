#!/usr/bin/env Rscript
# =====================================================================
# Figures for the PE OB/GYN mystery-caller study, built with the
# mysterycall package (Green Journal styling).
#   1  Sampling / STROBE-style enrollment flow   (REAL data)
#   2  Geographic distribution across states      (REAL data)
#   3  Wait-time power curve                       (REAL simulation)
#   6  Wait-time distributions by group            (ILLUSTRATIVE template)
#   8  Forest plot of IRRs                          (ILLUSTRATIVE template)
#   9  Ownership x insurance interaction            (ILLUSTRATIVE template)
# Templates (#6/#8/#9) use SIMULATED data pending the call campaign.
# =====================================================================

suppressMessages({
  library(mysterycall); library(readr); library(dplyr)
  library(ggplot2); library(MASS); library(statebins)
})

fig_dir <- "figures"; dir.create(fig_dir, showWarnings = FALSE)
ok <- function(f, path) cat(sprintf("  [OK]  Figure %s -> %s\n", f, path))
fail <- function(f, e) cat(sprintf("  [FAIL] Figure %s: %s\n", f, conditionMessage(e)))

# ---- Real data --------------------------------------------------------------
db <- suppressWarnings(read_csv("pe_obgyn_study_database.csv", show_col_types = FALSE))
cl <- suppressWarnings(read_csv("pe_obgyn_matched_calling_list.csv", show_col_types = FALSE))
pe <- db %>% filter(PE_or_Not == "PE")

n_records <- nrow(pe)
n_npi     <- n_distinct(pe$NPI)
n_office  <- n_distinct(pe$office_id)
n_pairs   <- n_distinct(cl$`Matched Pair ID`)
n_clin    <- nrow(cl)
n_states  <- n_distinct(cl$State)

# =====================================================================
# 1. Sampling / enrollment flow (STROBE-style)  -- REAL numbers
# =====================================================================
tryCatch({
  p <- mysterycall_flow_diagram(
    n_identified        = n_records,
    n_contacted         = n_office,
    n_excluded_contact  = n_records - n_office,
    n_completed         = n_pairs,
    n_excluded_complete = n_office - n_pairs,
    n_analysed          = n_pairs,
    exclusion_reasons   = list(
      contact  = sprintf("Duplicate NPI listings and\nadditional generalists at same office\n(1 generalist sampled per office): %s",
                         format(n_records - n_office, big.mark = ",")),
      complete = sprintf("No independent private-practice control\ngeneralist within 10 mi in same state: %s",
                         n_office - n_pairs)),
    title = "PE OB/GYN cohort: sampling & matching flow"
  )
  path <- file.path(fig_dir, "fig1_enrollment_flow.png")
  ggsave(path, p, width = 8, height = 6.5, dpi = 300, bg = "white")
  ok(1, path)
}, error = function(e) fail(1, e))

# =====================================================================
# 2. Geographic distribution -- REAL numbers (matched pairs per state)
# =====================================================================
tryCatch({
  by_state <- cl %>% filter(PE_or_Not == "PE") %>% count(State, name = "pairs")
  p <- statebins(
    by_state, state_col = "State", value_col = "pairs",
    ggplot2_scale_function = ggplot2::scale_fill_distiller,
    palette = "Blues", direction = 1, name = "Matched pairs",
    round = TRUE, state_border_col = "white"
  ) +
    labs(title = "Matched PE / control pairs by state",
         subtitle = sprintf("%s pairs (%s clinicians) across %s states",
                            format(n_pairs, big.mark=","), format(n_clin, big.mark=","), n_states)) +
    theme(plot.title = element_text(face = "bold"))
  path <- file.path(fig_dir, "fig2_geographic_map.png")
  ggsave(path, p, width = 9, height = 6, dpi = 300, bg = "white")
  ok(2, path)
}, error = function(e) fail(2, e))

# =====================================================================
# 3. Wait-time power curve -- REAL Monte Carlo (package)
# =====================================================================
tryCatch({
  pc <- mysterycall_power_curve(
    n_range = c(100, 200, 300, 400, 500),  # physicians (200 pairs = 400 physicians)
    irr_values = c(0.70, 0.80),
    calls_per_physician = 2L, baseline_mean = 20, theta = 2, sigma_u = 0.3,
    n_sim = 120L, target_power = 0.8, plot = FALSE
  )
  p <- pc$plot +
    geom_vline(xintercept = 400, linetype = "dotted") +
    annotate("text", x = 400, y = 0.05, label = "800-call design\n(200 pairs)",
             hjust = -0.05, size = 3) +
    labs(title = "Wait-time power vs. sample size",
         subtitle = "Negative-binomial GLMM, 2 calls/clinician; dotted line = fielded design") +
    mysterycall_theme_green_journal()
  path <- file.path(fig_dir, "fig3_power_curve.png")
  ggsave(path, p, width = 8, height = 5.5, dpi = 300, bg = "white")
  ok(3, path)
}, error = function(e) fail(3, e))

# =====================================================================
# Simulated results (templates) -- consistent with power assumptions
# =====================================================================
set.seed(2026)
np <- 200L
base_mu <- c("Independent.BCBS PPO" = 15, "Independent.Medicaid" = 30,
             "PE.BCBS PPO" = 20, "PE.Medicaid" = 37)   # PE main effect + modest extra Medicaid gap
sim <- do.call(rbind, lapply(seq_len(np), function(i) {
  do.call(rbind, lapply(c("PE","Independent"), function(own) {
    u <- rnorm(1, 0, 0.2)
    data.frame(
      pair_id = i, ownership = own,
      physician_id = paste0(substr(own,1,3), "_", i),
      insurance = c("BCBS PPO","Medicaid"),
      stringsAsFactors = FALSE)
  }))
}))
sim$mu <- base_mu[paste(sim$ownership, sim$insurance, sep=".")] *
          exp(rnorm(nrow(sim), 0, 0.2))
sim$wait_days <- MASS::rnegbin(nrow(sim), mu = sim$mu, theta = 2)
sim$ownership <- factor(sim$ownership, levels = c("Independent","PE"))
sim$insurance <- factor(sim$insurance, levels = c("BCBS PPO","Medicaid"))
sim$group <- paste(sim$ownership, "/", sim$insurance)
write_csv(sim[c("pair_id","physician_id","ownership","insurance","wait_days")],
          file.path(fig_dir, "SIMULATED_wait_times.csv"))
SIM_NOTE <- "ILLUSTRATIVE - SIMULATED DATA (template; pending call campaign)"

# ---- 6. Wait-time distributions by ownership x insurance --------------------
tryCatch({
  p <- ggplot(sim, aes(x = wait_days, fill = ownership)) +
    geom_density(alpha = 0.55, color = NA) +
    facet_wrap(~ insurance) +
    mysterycall_scale_fill_green_journal() +
    labs(title = "New-patient GYN wait-time distribution",
         subtitle = SIM_NOTE, x = "Business days to first appointment",
         y = "Density", fill = "Ownership") +
    mysterycall_theme_green_journal_faceted()
  path <- file.path(fig_dir, "fig6_wait_distributions.png")
  ggsave(path, p, width = 9, height = 5, dpi = 300, bg = "white")
  ok(6, path)
}, error = function(e) fail(6, e))

# ---- 8. Forest plot of incidence-rate ratios --------------------------------
tryCatch({
  m <- MASS::glm.nb(wait_days ~ ownership * insurance, data = sim)
  p <- mysterycall_forest_plot(
    m,
    term_labels = c("ownershipPE" = "PE ownership",
                    "insuranceMedicaid" = "Medicaid (vs BCBS)",
                    "ownershipPE:insuranceMedicaid" = "PE x Medicaid"),
    title = "Adjusted wait-time incidence-rate ratios",
    subtitle = SIM_NOTE
  )
  path <- file.path(fig_dir, "fig8_forest_plot.png")
  ggsave(path, p, width = 9, height = 4, dpi = 300, bg = "white")
  ok(8, path)
}, error = function(e) fail(8, e))

# ---- 9. Ownership x insurance interaction -----------------------------------
tryCatch({
  m <- MASS::glm.nb(wait_days ~ ownership * insurance, data = sim)
  emm <- emmeans::emmeans(m, ~ ownership * insurance, type = "response")
  ed  <- as.data.frame(emm)
  yv  <- intersect(c("response","rate","emmean"), names(ed))[1]
  ed$lo <- ed[[intersect(c("asymp.LCL","lower.CL","LCL"), names(ed))[1]]]
  ed$hi <- ed[[intersect(c("asymp.UCL","upper.CL","UCL"), names(ed))[1]]]
  p <- ggplot(ed, aes(x = insurance, y = .data[[yv]], color = ownership, group = ownership)) +
    geom_line(linewidth = 1) +
    geom_pointrange(aes(ymin = lo, ymax = hi), linewidth = 0.8, size = 0.6) +
    mysterycall_scale_color_green_journal() +
    labs(title = "Wait time by ownership x insurance (estimated means)",
         subtitle = SIM_NOTE, x = "Insurance arm",
         y = "Predicted wait (business days)", color = "Ownership") +
    mysterycall_theme_green_journal()
  path <- file.path(fig_dir, "fig9_interaction.png")
  ggsave(path, p, width = 7.5, height = 5, dpi = 300, bg = "white")
  ok(9, path)
}, error = function(e) fail(9, e))

cat("\nDone. Files in ", normalizePath(fig_dir), "\n")
