"""Implementation 1 (Python/csv): resolve each cohort clinician's DAC organisation."""
import csv, sys, collections, json, re
DAC = "/Volumes/MufflySamsung/facility_affiliation/unzipped_files/doctors_and_clinicians_05_2024_DAC_NationalDownloadableFile.csv"
W = sys.argv[1]
csv.field_size_limit(1 << 24)

cohort = list(csv.DictReader(open(f"{W}/cohort_key_union.csv")))
npis = {r["NPI"].strip() for r in cohort}

def dig(s): return re.sub(r"\D", "", s or "")
def akey(s):
    s = (s or "").upper()
    s = re.sub(r"[^A-Z0-9 ]", " ", s)
    s = re.sub(r"\b(STREET|ST|AVENUE|AVE|ROAD|RD|DRIVE|DR|BOULEVARD|BLVD|SUITE|STE|FLOOR|FL|UNIT|NORTH|N|SOUTH|S|EAST|E|WEST|W)\b", " ", s)
    return re.sub(r"\s+", " ", s).strip()

# ---- pass 1: cohort rows -----------------------------------------------------
rows = []
with open(DAC, newline="", encoding="utf-8", errors="replace") as f:
    for r in csv.DictReader(f):
        if (r["NPI"] or "").strip() in npis:
            rows.append(r)
print(f"pass1: DAC rows for cohort NPIs {len(rows):,}; distinct NPIs {len({r['NPI'].strip() for r in rows})}")
orgs = {(r["org_pac_id"] or "").strip() for r in rows if (r["org_pac_id"] or "").strip()}
print(f"pass1: distinct org_pac_id to aggregate {len(orgs):,}")

# ---- pass 2: national / local aggregates for those orgs ----------------------
nat = collections.defaultdict(set); nat_phys = collections.defaultdict(set)
nat_ob = collections.defaultdict(set); locsize = collections.defaultdict(set)
locs = collections.defaultdict(set); orgname = {}
OB = ("OBSTETRICS", "GYNECOL")
with open(DAC, newline="", encoding="utf-8", errors="replace") as f:
    for r in csv.DictReader(f):
        o = (r["org_pac_id"] or "").strip()
        if o not in orgs: continue
        npi = (r["NPI"] or "").strip()
        nat[o].add(npi)
        if (r["Cred"] or "").strip().upper() in ("MD", "DO"): nat_phys[o].add(npi)
        if any(k in (r["pri_spec"] or "").upper() for k in OB): nat_ob[o].add(npi)
        aid = (r["adrs_id"] or "").strip() or (dig(r["ZIP Code"])[:5] + "|" + akey(r["adr_ln_1"]))
        locsize[(o, aid)].add(npi); locs[o].add(aid)
        orgname.setdefault(o, (r["Facility Name"] or "").strip())
print(f"pass2: aggregated {len(nat):,} organisations")

out = []
for r in rows:
    o = (r["org_pac_id"] or "").strip()
    aid = (r["adrs_id"] or "").strip() or (dig(r["ZIP Code"])[:5] + "|" + akey(r["adr_ln_1"]))
    out.append(dict(
        npi=(r["NPI"] or "").strip(), ind_pac_id=(r["Ind_PAC_ID"] or "").strip(),
        org_pac_id=o, org_name=orgname.get(o, (r["Facility Name"] or "").strip()),
        num_org_mem=(r["num_org_mem"] or "").strip(), pri_spec=(r["pri_spec"] or "").strip(),
        cred=(r["Cred"] or "").strip(),
        adr=(r["adr_ln_1"] or "").strip(), city=(r["City/Town"] or "").strip(),
        state=(r["State"] or "").strip(), zip5=dig(r["ZIP Code"])[:5],
        phone=dig(r["Telephone Number"]), adrs_id=aid, addr_key=akey(r["adr_ln_1"]),
        dac_national_clinicians=len(nat.get(o, ())), dac_national_physicians=len(nat_phys.get(o, ())),
        dac_national_obgyn=len(nat_ob.get(o, ())), dac_local_clinicians=len(locsize.get((o, aid), ())),
        dac_org_locations=len(locs.get(o, ()))))
with open(f"{W}/dac_rows_union.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(out[0].keys())); w.writeheader(); w.writerows(out)
print(f"wrote {len(out):,} rows -> dac_rows_union.csv")
found = {r['npi'] for r in out}
print(f"cohort NPIs present in DAC 05/2024: {len(found)} of {len(npis)}")
