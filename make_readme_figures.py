"""Build the three README figures from the committed fielded-sample artifact.

Usage:  python make_readme_figures.py
Writes: figures/fig_readme_{sampling_funnel,fielded_geography,covariate_balance}.png

Every number plotted here is read from pe_obgyn_final_calling_sheet_200_dedup.csv or
from row counts of the committed pipeline artifacts. Nothing is simulated.
"""
import os, csv, collections, statistics as st
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

D = os.path.dirname(os.path.abspath(__file__))
OUT = D + "/figures"
PE, CTL = "#2a78d6", "#eb6834"
PE_SOFT, CTL_SOFT = "#c8d8ef", "#b9d0ec"
INK, INK2, INK3 = "#0b0b0b", "#52514e", "#8a8880"
SURF, GRID = "#fcfcfb", "#e6e5e0"
plt.rcParams.update({
    "font.family": "DejaVu Sans", "font.size": 10,
    "figure.facecolor": SURF, "axes.facecolor": SURF, "savefig.facecolor": SURF,
    "text.color": INK, "axes.edgecolor": GRID, "axes.labelcolor": INK2,
    "xtick.color": INK2, "ytick.color": INK2,
    "axes.spines.top": False, "axes.spines.right": False,
})
rows = list(csv.DictReader(open(D + "/pe_obgyn_final_calling_sheet_200_dedup.csv", encoding="utf-8-sig")))

def frame(w, h, t, sub, top=0.80, left=0.30, right=0.97, bottom=0.12):
    """Title block lives in figure space so it can never collide with the axes."""
    fig = plt.figure(figsize=(w, h))
    fig.text(left, 0.955, t, fontsize=13.5, fontweight="bold", color=INK, va="top", ha="left")
    fig.text(left, 0.885, sub, fontsize=9.5, color=INK2, va="top", ha="left")
    ax = fig.add_axes([left, bottom, right - left, top - bottom])
    return fig, ax

# ─────────────────────────── 1. sampling funnel ───────────────────────────
stages = [("PitchBook company universe", 4394),
          ("OB/GYN-relevant companies (keyword)", 72),
          ("Providers scraped + NPI-matched", 1537),
          ("Study database (PE-eligible + controls)", 1397),
          ("1:1 propensity-matched pool", 918),
          ("Fielded sample (200 pairs)", 400),
          ("Planned calls (2 insurance arms)", 800)]
fig, ax = frame(9.2, 4.7,
    "From PitchBook universe to fielded calls",
    "Row counts in each committed artifact. Blue marks the fielded study sample.",
    top=0.83, left=0.315, bottom=0.06)
ys = list(range(len(stages)))[::-1]
mx = max(v for _, v in stages)
for y, (lab, v) in zip(ys, stages):
    field = lab.startswith(("Fielded", "Planned"))
    ax.barh(y, v, height=0.52, color=PE if field else PE_SOFT,
            edgecolor=SURF, linewidth=2, zorder=3)
    ax.text(v + mx * 0.012, y, f"{v:,}", va="center", ha="left", fontsize=10,
            fontweight="bold", color=INK if field else INK2, zorder=4)
ax.set_yticks(ys); ax.set_yticklabels([s for s, _ in stages], fontsize=9.5, color=INK)
ax.set_xlim(0, mx * 1.14); ax.set_xticks([])
ax.spines["bottom"].set_visible(False); ax.tick_params(axis="y", length=0)
fig.savefig(OUT + "/fig_readme_sampling_funnel.png", dpi=200); plt.close(fig)

# ─────────────────────── 2. fielded sample geography ───────────────────────
pairs = collections.Counter(r["State"] for r in rows if r["PE_or_Not"] == "PE")
order = sorted(pairs.items(), key=lambda kv: (-kv[1], kv[0]))
fig, ax = frame(9.2, 4.5,
    "Fielded sample: 200 matched pairs across 26 states",
    "Pairs are matched within state, so the PE and control arms carry identical state counts.",
    top=0.83, left=0.075, bottom=0.13)
xs = list(range(len(order)))
ax.bar(xs, [n for _, n in order], width=0.62, color=PE, edgecolor=SURF, linewidth=2, zorder=3)
for x, (s, n) in zip(xs, order):
    ax.text(x, n + 0.6, str(n), ha="center", va="bottom", fontsize=8.5, color=INK2, zorder=4)
ax.set_xticks(xs); ax.set_xticklabels([s for s, _ in order], fontsize=9)
ax.set_ylabel("Matched pairs", fontsize=9.5)
ax.set_ylim(0, max(n for _, n in order) * 1.18)
ax.yaxis.grid(True, color=GRID, linewidth=0.8, zorder=0); ax.set_axisbelow(True)
ax.spines["left"].set_visible(False); ax.tick_params(axis="y", length=0)
ax.tick_params(axis="x", length=0)
fig.savefig(OUT + "/fig_readme_fielded_geography.png", dpi=200); plt.close(fig)

# ───────────────────────── 3. covariate balance ─────────────────────────
# CDC_SVI is deliberately ABSENT. The values carried in this artifact are the simulated
# draws documented in Appendix S2 / R/analysis_gates.R (gate_provenance); the real measure
# (CDC_SVI_real) exists for only 153 of the 400 fielded clinicians. Plotting the simulated
# column as though it were measured is the exact defect this repository's gates exist to stop.
COVS = [("Medicaid_Fee_Index","Medicaid-to-Medicare fee index"),
        ("PE_Concentration_15mi","PE clinic density within 15 mi"),
        ("HQ_Distance_Miles","Distance to platform HQ"),
        ("Tract_Pct_Female_Private","Tract % female, private ins."),
        ("Tract_Pct_Female_Medicaid","Tract % female, Medicaid"),
        ("Tract_Pct_Female_Medicare","Tract % female, Medicare"),
        ("Tract_Pct_Female_Uninsured","Tract % female, uninsured"),
        ("County_OBGYN_Count","County OB/GYN count"),
        ("County_Medicare_Enrollment","County Medicare enrollment"),
        ("County_Medicaid_Enrollment","County Medicaid enrollment")]
def arm(col, a):
    out = []
    for r in rows:
        if r["PE_or_Not"] != a: continue
        try: out.append(float(r.get(col, "")))
        except ValueError: pass
    return out
smds = []
for col, lab in COVS:
    a, b = arm(col, "PE"), arm(col, "Non-PE")
    p = ((st.pstdev(a)**2 + st.pstdev(b)**2) / 2) ** 0.5
    smds.append((lab, (st.mean(a) - st.mean(b)) / p if p else 0.0))
smds.sort(key=lambda kv: abs(kv[1]))
fig, ax = frame(9.2, 5.0,
    "Covariate balance after 1:1 propensity-score matching",
    "Committed covariates only. CDC SVI is excluded: its values here are simulated (Appendix S2).",
    top=0.845, left=0.265, bottom=0.135)
ys = list(range(len(smds)))
for y, (lab, v) in zip(ys, smds):
    over = abs(v) > 0.1
    ax.plot([0, v], [y, y], color=CTL if over else CTL_SOFT, linewidth=2,
            zorder=2, solid_capstyle="round")
    ax.plot(v, y, "o", markersize=9, color=CTL if over else PE,
            markeredgecolor=SURF, markeredgewidth=2, zorder=3)
ax.axvline(0, color=INK3, linewidth=1, zorder=1)
for t in (-0.1, 0.1):
    ax.axvline(t, color="#d5d3cc", linewidth=1.2, linestyle=(0, (4, 3)), zorder=1)
ax.set_yticks(ys); ax.set_yticklabels([l for l, _ in smds], fontsize=9.5, color=INK)
ax.set_xlabel("Standardized mean difference  (PE − control)", fontsize=9.5)
ax.set_xlim(-0.30, 0.30); ax.set_ylim(-0.8, len(smds) - 0.2)
# worst value labelled to the RIGHT of its dot, inside the plot, clear of the y labels
wlab, wval = max(smds, key=lambda kv: abs(kv[1]))
ax.text(wval, smds.index((wlab, wval)) + 0.30, f"{wval:+.2f}", fontsize=9.5,
        fontweight="bold", color=CTL, va="bottom", ha="center", zorder=4)
ax.text(0.115, -0.62, "±0.10 balance threshold", fontsize=8.5, color=INK3, ha="left", va="center")
ax.xaxis.grid(True, color=GRID, linewidth=0.8, zorder=0); ax.set_axisbelow(True)
ax.spines["left"].set_visible(False); ax.tick_params(axis="y", length=0)
fig.savefig(OUT + "/fig_readme_covariate_balance.png", dpi=200); plt.close(fig)
print("wrote 3 figures")
