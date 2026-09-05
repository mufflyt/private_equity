"""Build the README contract figures from the repository's own state.

Usage:  python3 make_contract_figures.py
Writes: figures/fig_readme_{gate_coverage,contract_map}.svg

Stdlib only, and SVG rather than PNG, deliberately. make_readme_figures.py needs matplotlib;
these need nothing, so the figures can be regenerated on any checkout without an install step,
and an SVG diff shows which number moved rather than reporting that some bytes changed.

Every value plotted is COUNTED FROM THE REPOSITORY at run time: the blocking list, the test
sources, the contract files. Nothing is typed in. A figure that hard-codes its own numbers is
the defect docs/MANUSCRIPT_PROVENANCE_AUDIT.md was written about.
"""
import os, re, csv

D = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(D, "figures")
os.makedirs(OUT, exist_ok=True)

# Palette matched to make_readme_figures.py so the README reads as one document.
PE, PE_SOFT = "#2a78d6", "#c8d8ef"
INK, INK2, INK3 = "#0b0b0b", "#52514e", "#8a8880"
SURF, GRID = "#fcfcfb", "#e6e5e0"
FONT = "DejaVu Sans, Helvetica, Arial, sans-serif"


def esc(s):
    return (s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def text(x, y, s, size=10, color=INK, weight="normal", anchor="start"):
    return (f'<text x="{x:.1f}" y="{y:.1f}" font-family="{FONT}" font-size="{size}" '
            f'fill="{color}" font-weight="{weight}" text-anchor="{anchor}">{esc(s)}</text>')


def svg(w, h, body, title, subtitle):
    return "\n".join([
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
        f'viewBox="0 0 {w} {h}" role="img" aria-label="{esc(title)}">',
        f'<rect width="{w}" height="{h}" fill="{SURF}"/>',
        text(24, 30, title, 15, INK, "bold"),
        text(24, 50, subtitle, 10.5, INK2),
        body, "</svg>", ""])


# ---------------------------------------------------------------- read the repo
def blocking_nodata():
    out = []
    for line in open(os.path.join(D, "tests", "BLOCKING")):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        parts = s.split(None, 1)
        if len(parts) == 2 and parts[0] == "nodata":
            out.append(parts[1].strip())
    return out


def count_assertions(fname):
    p = os.path.join(D, "tests", "testthat", fname)
    if not os.path.exists(p):
        return 0, 0
    t = open(p, encoding="utf-8", errors="replace").read()
    return len(re.findall(r"\btest_that\(", t)), len(re.findall(r"\bexpect_[a-z_]+\(", t))


# ---------------------------------------------------------------- 1. gate coverage
rows = [(f, *count_assertions(f)) for f in blocking_nodata()]
rows = [r for r in rows if r[2] > 0]
rows.sort(key=lambda r: -r[2])

ROW_H, TOP, LEFT, BARX = 21, 78, 24, 268
W, H = 900, TOP + ROW_H * len(rows) + 46
mx = max(r[2] for r in rows)
body = []
for i, (f, nt, ne) in enumerate(rows):
    y = TOP + i * ROW_H
    bw = (W - BARX - 96) * ne / mx
    body.append(f'<rect x="{BARX}" y="{y - 10:.1f}" width="{bw:.1f}" height="13" rx="2" fill="{PE_SOFT}"/>')
    body.append(f'<rect x="{BARX}" y="{y - 10:.1f}" width="{bw * nt / ne:.1f}" height="13" rx="2" fill="{PE}"/>')
    body.append(text(LEFT, y, f.replace("test-", "").replace(".R", ""), 10, INK))
    body.append(text(BARX + bw + 8, y, f"{ne}", 10, INK2, "bold"))
body.append(text(LEFT, H - 16,
                 f"{sum(r[1] for r in rows)} tests and {sum(r[2] for r in rows)} expectations "
                 f"across {len(rows)} files, all runnable without cohort data.", 9.5, INK3))
open(os.path.join(OUT, "fig_readme_gate_coverage.svg"), "w").write(
    svg(W, H, "\n".join(body),
        "What CI blocks a commit on",
        "Expectations per blocking test file (light). The darker segment is test_that() blocks."))

# ---------------------------------------------------------------- 2. contract map
CONTRACTS = [
    ("SAP.lock", "the model", "formula, family, subset, estimand and reporting scale",
     lambda: sum(1 for l in open(os.path.join(D, "SAP.lock")) if "_formula" in l)),
    ("analysis_manifest.csv", "every column", "provenance, status and distributional family",
     lambda: sum(1 for _ in csv.DictReader(open(os.path.join(D, "analysis_manifest.csv"))))),
    ("config/row_contract.yml", "every row", "counts, keys, pair balance, id coverage, cross-artifact agreement",
     # [a-z_] alone silently excluded every dataset whose name ends in a number --
     # calling_sheet_200, call_schedule_800, slot_crosswalk_400, caller_sheet_800,
     # redcap_import_200 -- and reported 2 of the 7 entries. Digits belong in the class.
     lambda: sum(1 for l in open(os.path.join(D, "config", "row_contract.yml"))
                 if re.match(r"^  [a-z0-9_]+:\s*$", l))),
    ("config/dependencies.lock", "the software", "CRAN, GitHub and PyPI versions the analysis ran on",
     lambda: sum(1 for l in open(os.path.join(D, "config", "dependencies.lock"))
                 if re.match(r"^(cran|github|pypi)\s", l))),
    ("config/ci_contract.yml", "CI itself", "triggers, commands, timeouts and which gates may never leave",
     lambda: sum(1 for l in open(os.path.join(D, "config", "ci_contract.yml")) if "- file:" in l)),
    ("manuscript/manuscript_claims.csv", "every published number", "artifact, locator, provenance status and source",
     lambda: sum(1 for _ in csv.DictReader(open(os.path.join(D, "manuscript", "manuscript_claims.csv"))))),
]

ROW_H, TOP, LEFT = 62, 84, 24
W, H = 900, TOP + ROW_H * len(CONTRACTS) + 34
body = []
for i, (name, governs, detail, counter) in enumerate(CONTRACTS):
    y = TOP + i * ROW_H
    try:
        n = counter()
    except Exception:
        n = None
    body.append(f'<rect x="{LEFT}" y="{y - 22:.1f}" width="{W - 2 * LEFT}" height="48" rx="4" '
                f'fill="#ffffff" stroke="{GRID}"/>')
    body.append(f'<rect x="{LEFT}" y="{y - 22:.1f}" width="4" height="48" rx="2" fill="{PE}"/>')
    body.append(text(LEFT + 16, y - 4, name, 11.5, INK, "bold"))
    body.append(text(LEFT + 16, y + 13, detail, 9.5, INK2))
    body.append(text(W - LEFT - 16, y - 4, f"governs {governs}", 10, PE, "bold", "end"))
    if n is not None:
        body.append(text(W - LEFT - 16, y + 13, f"{n} entries", 9.5, INK3, "normal", "end"))
open(os.path.join(OUT, "fig_readme_contract_map.svg"), "w").write(
    svg(W, H, "\n".join(body),
        "Six frozen contracts, each checked on every commit",
        "Entry counts are read from the files themselves at figure-build time."))

print("wrote figures/fig_readme_gate_coverage.svg and figures/fig_readme_contract_map.svg")
