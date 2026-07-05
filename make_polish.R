#!/usr/bin/env Rscript
# Polish pass: rebuild figure 1 (clean custom flow), fix figure 2 (map theme),
# restore axis tick labels on faceted figures 3 and 6.
suppressMessages({
  library(mysterycall); library(readr); library(dplyr); library(ggplot2)
  library(statebins); library(scales)
})
fig_dir <- "figures"
ok <- function(f,p) cat(sprintf("  [OK]  Figure %s -> %s\n", f, p))

# ---------------------------------------------------------------------
# 1. Custom sampling / matching flow (correct labels, no overprinting)
# ---------------------------------------------------------------------
boxes <- tibble::tribble(
  ~id,   ~xmin,~xmax,~ymin,~ymax, ~label,
  "B1", 0.02, 0.60, 0.83, 0.99, "PE generalist OB/GYNs identified from\nPE platform physician directories\nN = 1,537 records (1,280 unique NPIs)",
  "B2", 0.02, 0.60, 0.56, 0.72, "PE generalists sampled\n(one per physical office)\nN = 626 offices",
  "B3", 0.02, 0.60, 0.29, 0.45, "PE generalists matched to an independent\ncontrol generalist (10-mi radius, same state)\nN = 511 matched",
  "B4", 0.02, 0.60, 0.02, 0.18, "Final matched cohort\n511 pairs = 1,022 clinicians across 26 states\nFielded: 200 pairs (800 calls) + backups"
)
excl <- tibble::tribble(
  ~xmin,~xmax,~ymin,~ymax, ~label,
  0.64, 0.99, 0.585, 0.715, "Excluded (N = 911):\n• Duplicate NPI directory listings\n• Additional generalists at the same\n   office (1 sampled per office)",
  0.64, 0.99, 0.315, 0.445, "Excluded (N = 115):\n• No independent private-practice\n   control generalist within 10 mi\n   in the same state"
)
cx <- 0.31
arrows <- tibble::tribble(~x,~xend,~y,~yend,
  cx,cx, 0.83,0.72,  cx,cx, 0.56,0.45,  cx,cx, 0.29,0.18)
connt <- tibble::tribble(~x,~xend,~y,~yend,
  cx,0.64, 0.775,0.65,  cx,0.64, 0.505,0.38)

p1 <- ggplot() +
  geom_rect(data=boxes, aes(xmin=xmin,xmax=xmax,ymin=ymin,ymax=ymax),
            fill="grey97", color="grey25", linewidth=0.5) +
  geom_rect(data=excl, aes(xmin=xmin,xmax=xmax,ymin=ymin,ymax=ymax),
            fill="white", color="grey55", linewidth=0.4) +
  geom_segment(data=arrows, aes(x=x,xend=xend,y=y,yend=yend),
               arrow=arrow(length=unit(0.18,"cm"), type="closed"), linewidth=0.5, color="grey25") +
  geom_segment(data=connt, aes(x=x,xend=xend,y=y,yend=yend),
               arrow=arrow(length=unit(0.14,"cm"), type="closed"), linewidth=0.35, color="grey55") +
  geom_text(data=boxes, aes(x=(xmin+xmax)/2, y=(ymin+ymax)/2, label=label), size=3.15, lineheight=0.95) +
  geom_text(data=excl, aes(x=xmin+0.01, y=(ymin+ymax)/2, label=label), size=2.75, hjust=0, lineheight=0.95) +
  coord_cartesian(xlim=c(0,1), ylim=c(0,1), expand=FALSE) +
  labs(title="PE OB/GYN cohort: sampling & matching flow") +
  theme_void(base_size=12) +
  theme(plot.title=element_text(face="bold", hjust=0.02, margin=margin(b=6)),
        plot.margin=margin(10,10,10,10))
ggsave(file.path(fig_dir,"fig1_enrollment_flow.png"), p1, width=8.5, height=7.5, dpi=300, bg="white")
ok(1, "figures/fig1_enrollment_flow.png")

# ---------------------------------------------------------------------
# 2. Map with proper map theme (strip coordinate axes / grey panel)
# ---------------------------------------------------------------------
cl <- suppressWarnings(read_csv("pe_obgyn_matched_calling_list.csv", show_col_types=FALSE))
by_state <- cl %>% filter(PE_or_Not=="PE") %>% count(State, name="pairs")
n_pairs <- n_distinct(cl$`Matched Pair ID`); n_clin <- nrow(cl); n_states <- n_distinct(cl$State)
p2 <- statebins(by_state, state_col="State", value_col="pairs",
                ggplot2_scale_function=ggplot2::scale_fill_distiller,
                palette="Blues", direction=1, name="Matched pairs",
                round=TRUE, state_border_col="white") +
  labs(title="Matched PE / control pairs by state",
       subtitle=sprintf("%s pairs (%s clinicians) across %s states; note Florida concentration",
                        format(n_pairs,big.mark=","), format(n_clin,big.mark=","), n_states)) +
  mysterycall_theme_green_journal_map() +
  theme(plot.title=element_text(face="bold"))
ggsave(file.path(fig_dir,"fig2_geographic_map.png"), p2, width=9, height=6, dpi=300, bg="white")
ok(2, "figures/fig2_geographic_map.png")

# ---------------------------------------------------------------------
# 3. Power curve -- restore axis tick labels
# ---------------------------------------------------------------------
main <- read_csv("power_maineffect_results.csv", show_col_types=FALSE) %>%
  transmute(Test="PE main effect", Effect=Delta, SD, Pairs, Power)
i5  <- read_csv("power_analysis_new_results.csv", show_col_types=FALSE) %>%
  transmute(Test="Insurance x ownership (DiD)", Effect=5, SD, Pairs, Power)
i75 <- read_csv("power_interaction_75_results.csv", show_col_types=FALSE) %>%
  transmute(Test="Insurance x ownership (DiD)", Effect=7.5, SD, Pairs, Power)
pw <- bind_rows(main,i5,i75) %>%
  mutate(series=paste0(Test," (",Effect,"-day)"),
         SDlab=factor(paste0("SD = ",SD," business days"), levels=c("SD = 10 business days","SD = 20 business days")))
p3 <- ggplot(pw, aes(Pairs, Power, color=series)) +
  geom_hline(yintercept=0.8, linetype="dashed", color="grey50") +
  geom_vline(xintercept=200, linetype="dotted", color="grey40") +
  geom_line(linewidth=0.9) + geom_point(size=1.6) +
  facet_wrap(~SDlab) +
  scale_y_continuous(labels=percent, limits=c(0,1), breaks=seq(0,1,0.2)) +
  scale_x_continuous(breaks=c(100,200,300,400)) +
  annotate("text", x=200, y=0.02, label="800-call design", angle=90, hjust=0, vjust=-0.4, size=2.8, color="grey30") +
  mysterycall_scale_color_green_journal() +
  labs(title="Statistical power vs. number of matched pairs",
       subtitle="Negative-binomial GLMM simulation; dashed = 80% power, dotted = fielded 200-pair design",
       x="Matched pairs", y="Power", color=NULL) +
  mysterycall_theme_green_journal_faceted() +
  theme(legend.position="bottom",
        axis.text=element_text(color="grey20", size=9),
        axis.ticks=element_line(color="grey60"),
        panel.grid.major.y=element_line(color="grey92"))
ggsave(file.path(fig_dir,"fig3_power_curve.png"), p3, width=10, height=5.4, dpi=300, bg="white")
ok(3, "figures/fig3_power_curve.png")

# ---------------------------------------------------------------------
# 6. Distributions -- restore x-axis tick labels
# ---------------------------------------------------------------------
sim <- read_csv(file.path(fig_dir,"SIMULATED_wait_times.csv"), show_col_types=FALSE)
sim$ownership <- factor(sim$ownership, levels=c("Independent","PE"))
sim$insurance <- factor(sim$insurance, levels=c("BCBS PPO","Medicaid"))
p6 <- ggplot(sim, aes(wait_days, fill=ownership)) +
  geom_density(alpha=0.55, color=NA) + facet_wrap(~insurance) +
  scale_x_continuous(breaks=seq(0,90,15), limits=c(0,90)) +
  mysterycall_scale_fill_green_journal() +
  labs(title="New-patient GYN wait-time distribution",
       subtitle="ILLUSTRATIVE - SIMULATED DATA (template; pending call campaign)",
       x="Business days to first appointment", y="Density", fill="Ownership") +
  mysterycall_theme_green_journal_faceted() +
  theme(axis.text.x=element_text(color="grey20", size=9),
        axis.ticks.x=element_line(color="grey60"))
ggsave(file.path(fig_dir,"fig6_wait_distributions.png"), p6, width=9, height=5, dpi=300, bg="white")
ok(6, "figures/fig6_wait_distributions.png")
cat("Polish done.\n")
