#!/usr/bin/env python3
"""Step 4. Pull CMS facility affiliations for the cohort.

RECORDED, NEVER USED TO CLASSIFY. CMS Facility Affiliation states where a clinician provides
services or holds privileges. An obstetrician-gynecologist needs admitting privileges to
deliver, so the relation is near-universal in this specialty and says nothing about who employs
or owns the practice. test-comparator-adjudication.R enforces that it never becomes evidence of
employment; it is extracted so that claim can be checked rather than asserted.

Usage:  python pecos/extract_facility_affiliation.py <workdir> <Facility_Affiliation.csv>
Writes: <workdir>/facility_affil.csv
"""
import csv, sys, collections
W, SRC = sys.argv[1], sys.argv[2]
csv.field_size_limit(1 << 24)
npis = {r["NPI"].strip() for r in csv.DictReader(open(f"{W}/cohort_key_union.csv"))}
hit = collections.defaultdict(set); types = collections.Counter(); n = 0
with open(SRC, newline="", encoding="utf-8", errors="replace") as f:
    for r in csv.DictReader(f):
        n += 1
        npi = (r.get("NPI") or "").strip()
        if npi in npis:
            t = (r.get("facility_type") or "").strip()
            hit[npi].add((t, (r.get("Facility Affiliations Certification Number") or "").strip()))
            types[t] += 1
with open(f"{W}/facility_affil.csv", "w", newline="") as f:
    w = csv.writer(f); w.writerow(["npi", "facility_type", "ccn"])
    for k, vs in sorted(hit.items()):
        for t, c in sorted(vs): w.writerow([k, t, c])
print(f"source rows {n:,}; cohort NPIs with an affiliation {len(hit)} of {len(npis)}")
for k, v in types.most_common(): print(f"   {v:>6}  {k}")
