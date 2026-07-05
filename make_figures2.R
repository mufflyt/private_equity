#!/usr/bin/env Rscript
# Fast rebuild: figure 3 (from already-computed power grid) + templates 6/8/9.
suppressMessages({
  library(mysterycall); library(readr); library(dplyr); library(tidyr)
  library(ggplot2); library(MASS)
})
fig_dir <- "figures"; dir.create(fig_dir, showWarnings = FALSE)
ok  <- function(f,p) cat(sprintf("  [OK]  Figure %s -> %s\n", f, p))
bad <- function(f,e) cat(sprintf("  [FAIL] Figure %s: %s\n", f, conditionMessage(e)))

# =====================================================================
# 3. Wait-time power curve -- from the three simulations already run
# =====================================================================
tryCatch({
  main <- read_csv("power_maineffect_results.csv", show_col_types=FALSE) %>%
    transmute(Test="PE main effect", Effect=Delta, SD, Pairs, Power)
  i5 <- read_csv("power_analysis_new_results.csv", show_col_types=FALSE) %>%
    transmute(Test="Insurance x ownership (DiD)", Effect=5, SD, Pairs, Power)
  i75 <- read_csv("power_interaction_75_results.csv", show_col_types=FALSE) %>%
    transmute(Test="Insurance x ownership (DiD)", Effect=7.5, SD, Pairs, Power)
  pw <- bind_rows(main,i5,i75) %>%
    mutate(series = paste0(Test, " (", Effect, "-day)"),
           SDlab = factor(paste0("SD = ", SD, " business days"), levels=c("SD = 10 business days","SD = 20 business days")))
  p <- ggplot(pw, aes(Pairs, Power, color=series)) +
    geom_hline(yintercept=0.8, linetype="dashed", color="grey50") +
    geom_vline(xintercept=200, linetype="dotted", color="grey40") +
    geom_line(linewidth=0.9) + geom_point(size=1.6) +
    facet_wrap(~SDlab) +
    scale_y_continuous(labels=scales::percent, limits=c(0,1)) +
    annotate("text", x=200, y=0.02, label="800-call design", angle=90, hjust=0, vjust=-0.4, size=2.8, color="grey30") +
    mysterycall_scale_color_green_journal() +
    labs(title="Statistical power vs. number of matched pairs",
         subtitle="Negative-binomial GLMM simulation; dashed = 80% power, dotted = fielded 200-pair design",
         x="Matched pairs", y="Power", color=NULL) +
    mysterycall_theme_green_journal_faceted() +
    theme(legend.position="bottom")
  path <- file.path(fig_dir,"fig3_power_curve.png")
  ggsave(path, p, width=10, height=5.2, dpi=300, bg="white")
  ok(3, path)
}, error=function(e) bad(3,e))

# =====================================================================
# Simulated results (templates 6/8/9)
# =====================================================================
set.seed(2026)
np <- 200L
base_mu <- c("Independent.BCBS PPO"=15,"Independent.Medicaid"=30,"PE.BCBS PPO"=20,"PE.Medicaid"=37)
sim <- do.call(rbind, lapply(seq_len(np), function(i)
  do.call(rbind, lapply(c("PE","Independent"), function(own)
    data.frame(pair_id=i, ownership=own, physician_id=paste0(substr(own,1,3),"_",i),
               insurance=c("BCBS PPO","Medicaid"), stringsAsFactors=FALSE)))))
sim$mu <- base_mu[paste(sim$ownership, sim$insurance, sep=".")] * exp(rnorm(nrow(sim),0,0.2))
sim$wait_days <- MASS::rnegbin(nrow(sim), mu=sim$mu, theta=2)
sim$ownership <- factor(sim$ownership, levels=c("Independent","PE"))
sim$insurance <- factor(sim$insurance, levels=c("BCBS PPO","Medicaid"))
write_csv(sim[c("pair_id","physician_id","ownership","insurance","wait_days")], file.path(fig_dir,"SIMULATED_wait_times.csv"))
NOTE <- "ILLUSTRATIVE - SIMULATED DATA (template; pending call campaign)"

# ---- 6. distributions ----
tryCatch({
  p <- ggplot(sim, aes(wait_days, fill=ownership)) +
    geom_density(alpha=0.55, color=NA) + facet_wrap(~insurance) +
    mysterycall_scale_fill_green_journal() +
    labs(title="New-patient GYN wait-time distribution", subtitle=NOTE,
         x="Business days to first appointment", y="Density", fill="Ownership") +
    mysterycall_theme_green_journal_faceted()
  path <- file.path(fig_dir,"fig6_wait_distributions.png"); ggsave(path,p,width=9,height=5,dpi=300,bg="white"); ok(6,path)
}, error=function(e) bad(6,e))

# ---- 8. forest ----
tryCatch({
  m <- MASS::glm.nb(wait_days ~ ownership*insurance, data=sim)
  p <- mysterycall_forest_plot(m,
    term_labels=c("ownershipPE"="PE ownership","insuranceMedicaid"="Medicaid (vs BCBS)","ownershipPE:insuranceMedicaid"="PE x Medicaid"),
    title="Adjusted wait-time incidence-rate ratios", subtitle=NOTE)
  path <- file.path(fig_dir,"fig8_forest_plot.png"); ggsave(path,p,width=9,height=4,dpi=300,bg="white"); ok(8,path)
}, error=function(e) bad(8,e))

# ---- 9. interaction ----
tryCatch({
  m <- MASS::glm.nb(wait_days ~ ownership*insurance, data=sim)
  emm <- as.data.frame(emmeans::emmeans(m, ~ ownership*insurance, type="response"))
  yv <- intersect(c("response","rate","emmean"), names(emm))[1]
  emm$lo <- emm[[intersect(c("asymp.LCL","lower.CL","LCL"), names(emm))[1]]]
  emm$hi <- emm[[intersect(c("asymp.UCL","upper.CL","UCL"), names(emm))[1]]]
  p <- ggplot(emm, aes(insurance, .data[[yv]], color=ownership, group=ownership)) +
    geom_line(linewidth=1) + geom_pointrange(aes(ymin=lo,ymax=hi), linewidth=0.8, size=0.6) +
    mysterycall_scale_color_green_journal() +
    labs(title="Wait time by ownership x insurance (estimated means)", subtitle=NOTE,
         x="Insurance arm", y="Predicted wait (business days)", color="Ownership") +
    mysterycall_theme_green_journal()
  path <- file.path(fig_dir,"fig9_interaction.png"); ggsave(path,p,width=7.5,height=5,dpi=300,bg="white"); ok(9,path)
}, error=function(e) bad(9,e))
cat("Done.\n")
