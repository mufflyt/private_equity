#!/usr/bin/env python3
import base64, pathlib

FIGDIR = pathlib.Path("figures")
OUT = pathlib.Path("/Users/tylermuffly/Library/Caches/claude-code-tmp/claude-501/-Users-tylermuffly-private-equity/54f51cf9-b48a-4bff-ae07-09c6eb815859/scratchpad/figures_preview.html")

def uri(name):
    b = (FIGDIR / name).read_bytes()
    return "data:image/png;base64," + base64.b64encode(b).decode()

FIGS = [
    ("01", "fig1_enrollment_flow.png", "real", "Cohort sampling &amp; matching flow",
     "PE generalist OB/GYNs identified from platform directories, de-duplicated by NPI, reduced to one generalist per physical office, then matched to an independent private-practice control within 10 miles in the same state. Yields <strong>511 matched pairs (1,022 clinicians) across 26 states</strong>; 200 pairs are fielded to hit the 800-call ceiling."),
    ("02", "fig2_geographic_map.png", "real", "Geographic distribution across states",
     "Matched pairs per state (tile-grid cartogram). <strong>Florida contributes 256 pairs &mdash; roughly half the pool</strong> &mdash; so the protocol&rsquo;s &le;5-clinics-per-state cap still has to be applied when drawing the fielded 200; the current pool is not yet geographically balanced."),
    ("03", "fig3_power_curve.png", "real", "Statistical power vs. sample size",
     "Monte-Carlo power for the wait-time outcomes. The <strong>PE main effect</strong> (green/yellow) clears 80% at 200 pairs even under the conservative SD&nbsp;=&nbsp;20; the <strong>insurance&nbsp;&times;&nbsp;ownership interaction</strong> (orange/blue) stays underpowered at that variance &mdash; the basis for making the main effect the co-primary continuous outcome."),
    ("06", "fig6_wait_distributions.png", "sim", "Wait-time distributions by group",
     "Density of business days to first appointment, by ownership within each insurance arm. Shows the expected PE&ndash;control separation and the Medicaid shift. <strong>Illustrative simulated data</strong> &mdash; the template populates once calls are collected."),
    ("08", "fig8_forest_plot.png", "sim", "Adjusted incidence-rate ratios",
     "Wait-time IRRs with 95% CIs from a negative-binomial model; filled diamonds are significant, open are not. <strong>Illustrative simulated data</strong> &mdash; the real estimates replace these after the campaign."),
    ("09", "fig9_interaction.png", "sim", "Ownership &times; insurance interaction",
     "Estimated marginal mean waits across insurance arms by ownership &mdash; the visual form of the difference-in-differences. <strong>Illustrative simulated data.</strong>"),
]

cards = []
for num, fname, kind, title, cap in FIGS:
    badge = ('<span class="chip chip-real">From study data</span>' if kind == "real"
             else '<span class="chip chip-sim">Illustrative template</span>')
    cards.append(f"""      <figure class="card">
        <div class="card-head">
          <span class="fignum">Fig&nbsp;{num}</span>
          <h3>{title}</h3>
          {badge}
        </div>
        <div class="frame"><img src="{uri(fname)}" alt="Figure {num}: {title}" loading="lazy"></div>
        <figcaption>{cap}</figcaption>
      </figure>""")

real_cards = "\n".join(cards[:3])
sim_cards = "\n".join(cards[3:])

HTML = f"""<title>PE OB/GYN Study &mdash; Figures</title>
<style>
  :root {{
    --ground: #faf9f6; --panel: #ffffff; --ink: #16201b; --ink-2: #4b5751;
    --muted: #7c877f; --line: #e5e6df; --accent: #1c5e46; --accent-soft: #e7f0eb;
    --sim: #9a6a10; --sim-soft: #f6ecd6; --shadow: 0 1px 2px rgba(20,32,25,.05), 0 8px 24px rgba(20,32,25,.05);
  }}
  @media (prefers-color-scheme: dark) {{
    :root {{
      --ground: #10130f; --panel: #191d17; --ink: #eef1ea; --ink-2: #b4bdb2;
      --muted: #8a938a; --line: #2a2f27; --accent: #6fcaa4; --accent-soft: #17251d;
      --sim: #e2b661; --sim-soft: #2a2110; --shadow: 0 1px 2px rgba(0,0,0,.3), 0 10px 30px rgba(0,0,0,.35);
    }}
  }}
  :root[data-theme="light"] {{
    --ground: #faf9f6; --panel: #ffffff; --ink: #16201b; --ink-2: #4b5751; --muted: #7c877f;
    --line: #e5e6df; --accent: #1c5e46; --accent-soft: #e7f0eb; --sim: #9a6a10; --sim-soft: #f6ecd6;
  }}
  :root[data-theme="dark"] {{
    --ground: #10130f; --panel: #191d17; --ink: #eef1ea; --ink-2: #b4bdb2; --muted: #8a938a;
    --line: #2a2f27; --accent: #6fcaa4; --accent-soft: #17251d; --sim: #e2b661; --sim-soft: #2a2110;
  }}
  * {{ box-sizing: border-box; }}
  body {{ margin: 0; background: var(--ground); color: var(--ink);
    font-family: system-ui, -apple-system, "Segoe UI", sans-serif; line-height: 1.55;
    -webkit-font-smoothing: antialiased; }}
  .wrap {{ max-width: 960px; margin: 0 auto; padding: clamp(24px, 5vw, 64px) clamp(18px, 4vw, 40px) 80px; }}
  header {{ border-bottom: 1px solid var(--line); padding-bottom: 28px; margin-bottom: 40px; }}
  .eyebrow {{ text-transform: uppercase; letter-spacing: .13em; font-size: 12px; font-weight: 600;
    color: var(--accent); margin: 0 0 12px; }}
  h1 {{ font-size: clamp(26px, 4vw, 38px); line-height: 1.15; margin: 0 0 14px; font-weight: 700;
    letter-spacing: -.01em; text-wrap: balance; }}
  .lede {{ font-size: 17px; color: var(--ink-2); margin: 0; max-width: 62ch; }}
  .meta {{ display: flex; flex-wrap: wrap; gap: 8px 20px; margin-top: 20px; font-size: 13px; color: var(--muted); }}
  .meta b {{ color: var(--ink-2); font-weight: 600; }}
  .section-label {{ display: flex; align-items: baseline; gap: 12px; margin: 8px 0 22px; }}
  .section-label h2 {{ font-size: 14px; text-transform: uppercase; letter-spacing: .08em; margin: 0;
    color: var(--ink-2); font-weight: 600; white-space: nowrap; }}
  .section-label .rule {{ flex: 1; height: 1px; background: var(--line); }}
  .stack {{ display: flex; flex-direction: column; gap: 30px; margin-bottom: 52px; }}
  .card {{ margin: 0; background: var(--panel); border: 1px solid var(--line); border-radius: 14px;
    box-shadow: var(--shadow); overflow: hidden; }}
  .card-head {{ display: flex; align-items: center; gap: 12px; flex-wrap: wrap;
    padding: 18px 22px 14px; }}
  .fignum {{ font-size: 12px; font-weight: 700; letter-spacing: .04em; color: var(--accent);
    background: var(--accent-soft); padding: 3px 9px; border-radius: 999px; font-variant-numeric: tabular-nums; }}
  .card-head h3 {{ font-size: 18px; margin: 0; font-weight: 650; flex: 1; letter-spacing: -.005em; }}
  .chip {{ font-size: 11.5px; font-weight: 600; padding: 3px 10px; border-radius: 999px;
    letter-spacing: .02em; white-space: nowrap; }}
  .chip-real {{ color: var(--accent); background: var(--accent-soft); border: 1px solid color-mix(in srgb, var(--accent) 25%, transparent); }}
  .chip-sim {{ color: var(--sim); background: var(--sim-soft); border: 1px solid color-mix(in srgb, var(--sim) 30%, transparent); }}
  .frame {{ padding: 6px 22px 4px; overflow-x: auto; }}
  .frame img {{ display: block; width: 100%; max-width: 100%; height: auto; border-radius: 6px; }}
  figcaption {{ padding: 14px 22px 22px; font-size: 14.5px; color: var(--ink-2); border-top: 1px solid var(--line);
    margin-top: 8px; }}
  figcaption strong {{ color: var(--ink); font-weight: 650; }}
  .note {{ background: var(--sim-soft); border: 1px solid color-mix(in srgb, var(--sim) 28%, transparent);
    color: var(--ink-2); border-radius: 12px; padding: 14px 18px; font-size: 14px; margin-bottom: 40px; }}
  .note b {{ color: var(--sim); }}
  footer {{ border-top: 1px solid var(--line); padding-top: 22px; font-size: 13px; color: var(--muted); }}
  footer code {{ background: var(--accent-soft); color: var(--accent); padding: 1.5px 6px; border-radius: 5px;
    font-size: 12.5px; }}
</style>

<div class="wrap">
  <header>
    <p class="eyebrow">Mystery-caller study &middot; figure dossier</p>
    <h1>Private equity &amp; OB/GYN appointment access: study figures</h1>
    <p class="lede">Six figures for the wait-time and Medicaid-acceptance audit &mdash; three built from the
      matched sampling frame, three results templates awaiting the call campaign. All styled in the
      <em>Obstetrics &amp; Gynecology</em> (Green Journal) convention via the <code>mysterycall</code> package.</p>
    <div class="meta">
      <span><b>Cohort:</b> 511 matched pairs &middot; 1,022 clinicians &middot; 26 states</span>
      <span><b>Fielded:</b> 200 pairs / 800 calls</span>
      <span><b>Generated:</b> 2026-07-05</span>
    </div>
  </header>

  <div class="section-label"><h2>From the study data</h2><span class="rule"></span></div>
  <div class="stack">
{real_cards}
  </div>

  <div class="section-label"><h2>Planned results &mdash; illustrative templates</h2><span class="rule"></span></div>
  <p class="note"><b>These three use simulated data.</b> They fix the figure layout and analysis code now;
    the real estimates drop in once the 800 calls are logged in REDCap. Numbers shown are not findings.</p>
  <div class="stack">
{sim_cards}
  </div>

  <footer>
    Source PNGs (300&nbsp;dpi) in <code>figures/</code>; regenerate with <code>make_figures2.R</code> +
    <code>make_polish.R</code>. Power grid from <code>power_maineffect_results.csv</code> and the two interaction sims.
  </footer>
</div>
"""

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(HTML)
print("wrote", OUT, f"({len(HTML)//1024} KB)")
