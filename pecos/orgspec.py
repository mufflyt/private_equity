"""Org-level specialty composition: a measurement, not a name heuristic.

An independent single-specialty OB/GYN practice is overwhelmingly OB/GYN. A health-system
employed group spans the whole of medicine. This does not by itself establish ownership --
large physician-owned multispecialty groups exist -- but it is evidence that does not depend
on what the organisation chose to call itself.
"""
import csv, sys, collections
DAC = "/Volumes/MufflySamsung/facility_affiliation/unzipped_files/doctors_and_clinicians_05_2024_DAC_NationalDownloadableFile.csv"
W = sys.argv[1]; csv.field_size_limit(1 << 24)
orgs = {r["dac_org_pac_id"] for r in csv.DictReader(open(f"{W}/comparator_classification.csv")) if r["dac_org_pac_id"]}
spec = collections.defaultdict(lambda: collections.defaultdict(set))
with open(DAC, newline="", encoding="utf-8", errors="replace") as f:
    for r in csv.DictReader(f):
        o = (r["org_pac_id"] or "").strip()
        if o in orgs: spec[o][(r["pri_spec"] or "").strip().upper()].add((r["NPI"] or "").strip())
rows = []
for o, d in spec.items():
    tot = len(set().union(*d.values())) if d else 0
    ob = len(set().union(*[v for k, v in d.items() if "OBSTETRIC" in k or "GYNECOL" in k]) or set()) if any("OBSTETRIC" in k or "GYNECOL" in k for k in d) else 0
    rows.append(dict(org_pac_id=o, n_specialties=len(d), n_clinicians=tot, n_obgyn=ob,
                     obgyn_share=round(ob / tot, 4) if tot else ""))
with open(f"{W}/org_specialty.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)
print(f"organisations profiled: {len(rows)}")
sr = sorted(rows, key=lambda z: -z["n_clinicians"])
print("  largest:")
for x in sr[:6]: print(f"    {x['n_clinicians']:>5} clin  {x['n_specialties']:>3} specialties  OB/GYN share {x['obgyn_share']}")
single = [x for x in rows if x["obgyn_share"] != "" and x["obgyn_share"] >= 0.9]
print(f"  organisations >=90% OB/GYN: {len(single)}")
