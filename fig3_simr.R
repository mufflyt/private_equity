#!/usr/bin/env Rscript
# Citable power curve via simr (Green & MacLeod 2016): power for the PE ownership
# main effect on wait time, negative-binomial GLMM with a physician random intercept.
suppressMessages({
  library(simr); library(lme4); library(MASS); library(mysterycall); library(ggplot2); library(readr)
})
set.seed(2026)

NMAX  <- 500L          # physicians in the base design (250 PE / 250 control, interleaved)
IRR   <- 1.33          # target: PE waits ~33% longer (e.g., 15 -> 20 business days)
THETA <- 2             # NB dispersion (SD ~ 20 d at these means)
NSIM  <- 50L
BREAKS <- c(100L, 200L, 300L, 400L, 500L)

# Interleave ownership by physician id so the first n levels stay balanced at every break.
own <- factor(ifelse(seq_len(NMAX) %% 2 == 1, "PE", "Independent"), levels = c("Independent","PE"))
df <- data.frame(
  physician_id = factor(rep(seq_len(NMAX), each = 2)),
  ownership    = factor(rep(as.character(own), each = 2), levels = c("Independent","PE")),
  insurance    = factor(rep(c("BCBS PPO","Medicaid"), times = NMAX), levels = c("BCBS PPO","Medicaid"))
)
b0 <- log(15); b_med <- log(30/15); b_pe <- log(IRR)
u  <- rnorm(NMAX, 0, 0.3)
eta <- b0 + b_pe*(df$ownership=="PE") + b_med*(df$insurance=="Medicaid") + u[as.integer(df$physician_id)]
df$wait_days <- MASS::rnegbin(nrow(df), mu = exp(eta), theta = THETA)

cat("Fitting base glmer.nb ...\n")
m <- lme4::glmer.nb(wait_days ~ ownership + insurance + (1 | physician_id), data = df)
fixef(m)["ownershipPE"] <- log(IRR)   # pin the effect size

cat("Running simr::powerCurve (nsim =", NSIM, ") ...\n")
pc <- powerCurve(m, test = fixed("ownershipPE", "z"),
                 along = "physician_id", breaks = BREAKS, nsim = NSIM, seed = 2026)
print(pc)

s <- summary(pc)                       # columns: nlevels, successes, trials, mean, lower, upper
s$pairs <- s$nlevels / 2
write_csv(s, "simr_power_results.csv")

p <- ggplot(s, aes(pairs, mean)) +
  geom_hline(yintercept = 0.8, linetype = "dashed", color = "grey50") +
  geom_vline(xintercept = 200, linetype = "dotted", color = "grey40") +
  geom_ribbon(aes(ymin = lower, ymax = upper), fill = "#1c5e46", alpha = 0.15) +
  geom_line(color = "#1c5e46", linewidth = 1) +
  geom_point(color = "#1c5e46", size = 2) +
  annotate("text", x = 200, y = 0.03, label = "fielded 200 pairs", angle = 90, hjust = 0, vjust = -0.4,
           size = 2.8, color = "grey30") +
  scale_y_continuous(labels = scales::percent, limits = c(0, 1), breaks = seq(0, 1, 0.2)) +
  labs(title = "PE main-effect power via simr (negative-binomial GLMM)",
       subtitle = sprintf("Target IRR = %.2f (PE waits ~%.0f%% longer); %d simulations/point; band = 95%% CI",
                          IRR, (IRR-1)*100, NSIM),
       x = "Matched pairs", y = "Power (Wald z, alpha = 0.05)") +
  mysterycall_theme_green_journal() +
  theme(axis.text = element_text(color = "grey20", size = 9),
        panel.grid.major.y = element_line(color = "grey92"))
ggsave("figures/fig3b_simr_power_curve.png", p, width = 8, height = 5.4, dpi = 300, bg = "white")
cat("[OK] wrote figures/fig3b_simr_power_curve.png\n")
