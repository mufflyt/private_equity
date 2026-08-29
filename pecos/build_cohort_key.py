#!/usr/bin/env python3
"""Step 1. Build the union key the rest of the PECOS/DAC chain is driven from.

Three populations, labelled by `frame` so downstream steps can report on each separately:

  fielded           the 400 clinicians actually being called
  universe          the 459-pair post-exclusion matched universe (controls and PE arm)
  roster_only       the remainder of the PE platform roster

The roster is included because the exposure-contamination test asks whether a control's
organisation contains ANY rostered PE clinician, not only one who happens to have been drawn
into the fielded frame. Restricting to the fielded arm would understate it.

Usage:  python pecos/build_cohort_key.py <workdir> [repo_root]
Writes: <workdir>/cohort_key_union.csv
"""
import csv, sys, os, collections

W = sys.argv[1]; ROOT = sys.argv[2] if len(sys.argv) > 2 else "."
FIELDS = ["NPI", "Provider Name", "PE_or_Not", "Matched Pair ID", "City", "State",
          "Phone", "Platform", "Eligible", "office_addr_key", "frame"]
out = {}

for r in csv.DictReader(open(f"{ROOT}/pe_obgyn_final_calling_sheet_200_dedup.csv")):
    n = (r.get("NPI") or "").strip()
    if not n: continue
    out[n] = {k: (r.get(k) or "").strip() for k in FIELDS}
    out[n]["NPI"] = n; out[n]["frame"] = "fielded"

for r in csv.DictReader(open(f"{ROOT}/pe_obgyn_matched_calling_list.csv")):
    n = (r.get("NPI") or "").strip()
    if not n: continue
    if n in out:
        out[n]["frame"] = "fielded+universe"
    else:
        out[n] = {k: (r.get(k) or "").strip() for k in FIELDS}
        out[n]["NPI"] = n; out[n]["frame"] = "universe"

for r in csv.DictReader(open(f"{ROOT}/pe_obgyn_providers_active.csv")):
    n = (r.get("NPI") or "").strip()
    if not n or n in out: continue
    out[n] = {k: "" for k in FIELDS}
    out[n].update(NPI=n, frame="roster_only", PE_or_Not="PE",
                  **{"Provider Name": (r.get("Provider Name") or "").strip(),
                     "State": (r.get("Input State") or "").strip(),
                     "Platform": (r.get("Platform/Practice") or "").strip()})

os.makedirs(W, exist_ok=True)
with open(f"{W}/cohort_key_union.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=FIELDS); w.writeheader(); w.writerows(out.values())
print(f"cohort_key_union.csv  rows {len(out)}  "
      f"{dict(collections.Counter(r['frame'] for r in out.values()))}")
