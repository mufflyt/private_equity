"""Comparator classification. Rules are fixed here BEFORE any arm-level result is looked at."""
import csv, sys, re, collections, json
W = sys.argv[1]

# ---- pre-specified screening vocabulary -------------------------------------
# Tokens that identify an organisation as a hospital, health system, academic faculty
# practice, or government entity. Deliberately explicit and auditable rather than fuzzy.
SYSTEM = [r"\bUNIVERSITY\b", r"\bUNIV\b", r"\bCOLLEGE\b", r"SCHOOL OF MEDICINE", r"\bFACULTY\b",
          r"HEALTH SYSTEM", r"HEALTHCARE SYSTEM", r"HEALTH NETWORK", r"HEALTH SERVICES",
          r"HEALTH CARE SERVICES", r"\bHOSPITAL\b", r"MEDICAL CENTER", r"MEDICAL CTR",
          r"\bPERMANENTE\b", r"\bKAISER\b", r"CLINIC FOUNDATION", r"\bINFIRMARY\b",
          r"\bVETERANS\b", r"\bCOUNTY OF\b", r"\bCITY OF\b", r"\bSTATE OF\b",
          r"DEPARTMENT OF", r"\bMEMORIAL\b", r"REGIONAL MEDICAL", r"\bCLINIC\b.*FOUNDATION"]
SYS_RE = re.compile("|".join(SYSTEM))
LARGE = 100   # triggers scrutiny, never classifies on its own

cohort = list(csv.DictReader(open(f"{W}/cohort_key.csv")))
dac = list(csv.DictReader(open(f"{W}/dac_rows.csv")))
pec = list(csv.DictReader(open(f"{W}/pecos_rows_2019.csv")))
fac = collections.defaultdict(set)
for r in csv.DictReader(open(f"{W}/facility_affil.csv")): fac[r["npi"]].add(r["facility_type"])
exist = {r["npi"]: r for r in csv.DictReader(open("/Users/tylermuffly/private_equity/data/covariates/control_org_classification.csv"))}

by_npi = collections.defaultdict(list)
for r in dac: by_npi[r["npi"]].append(r)
pec_by = collections.defaultdict(list)
for r in pec: pec_by[r["npi"]].append(r)

def dig(s): return re.sub(r"\D", "", s or "")
def akey(s):
    s = (s or "").upper(); s = re.sub(r"[^A-Z0-9 ]", " ", s)
    s = re.sub(r"\b(STREET|ST|AVENUE|AVE|ROAD|RD|DRIVE|DR|BOULEVARD|BLVD|SUITE|STE|FLOOR|FL|UNIT|NORTH|N|SOUTH|S|EAST|E|WEST|W)\b", " ", s)
    return re.sub(r"\s+", " ", s).strip()

out = []
for c in cohort:
    npi = c["NPI"]; rows = by_npi.get(npi, [])
    phones = {dig(c.get("Phone", ""))} - {""}
    city = (c.get("City") or "").strip().upper(); st = (c.get("State") or "").strip().upper()
    ak = akey(c.get("office_addr_key", "")) if c.get("office_addr_key") else ""

    method = ""; sel = []
    if not rows:
        status = "no_dac_affiliation"
    else:
        m = [r for r in rows if r["phone"] and r["phone"] in phones]
        if m: method = "phone"
        if not m and ak:
            m = [r for r in rows if r["addr_key"] and r["addr_key"] == ak and r["state"].upper() == st]
            if m: method = "address"
        if not m:
            m = [r for r in rows if r["city"].upper() == city and r["state"].upper() == st]
            if m: method = "city_state"
        if not m:
            status = "affiliation_location_mismatch"; sel = []
        else:
            orgs = {r["org_pac_id"] for r in m}
            sel = m
            status = "location_resolved" if len(orgs) == 1 else "ambiguous_multiple_org"

    if sel:
        best = max(sel, key=lambda r: int(r["dac_national_clinicians"]))
        org_name = best["org_name"]; org_pac = best["org_pac_id"]
        nat = int(best["dac_national_clinicians"]); natp = int(best["dac_national_physicians"])
        natob = int(best["dac_national_obgyn"]); loc = int(best["dac_local_clinicians"])
        nloc = int(best["dac_org_locations"]); nom = best["num_org_mem"]
    else:
        org_name = org_pac = ""; nat = natp = natob = loc = nloc = ""; nom = ""

    sys_hit = bool(org_name and SYS_RE.search(org_name.upper()))
    if status in ("no_dac_affiliation", "affiliation_location_mismatch", "ambiguous_multiple_org"):
        cls, why = "independence_unresolved", status
    elif sys_hit:
        cls, why = "not_independent_supported", "organisation name carries a hospital/system/academic/government token"
    elif isinstance(nat, int) and nat >= LARGE:
        cls, why = "independence_unresolved", f"organisation has {nat} clinicians nationally but the name is uninformative; requires external verification"
    else:
        cls, why = "independent_supported", "resolved to a single organisation with no system/academic/government token and fewer than %d clinicians nationally" % LARGE

    p = pec_by.get(npi, [])
    ppacs = {x["org_pac_id"] for x in p}
    pmem = max([int(x["pecos_national_members"]) for x in p], default="")
    e = exist.get(npi, {})
    out.append(dict(
        npi=npi, name=c.get("Provider Name", ""), arm=c.get("PE_or_Not", ""),
        pair=c.get("Matched Pair ID", ""), eligible=c.get("Eligible", ""),
        city=c.get("City", ""), state=c.get("State", ""),
        pecos_status=status, location_match_method=method,
        dac_org_pac_id=org_pac, dac_org_name=org_name,
        dac_national_clinicians=nat, dac_national_physicians=natp, dac_national_obgyn=natob,
        dac_local_clinicians=loc, dac_org_locations=nloc, dac_num_org_mem=nom,
        dac_n_affiliations=len({r["org_pac_id"] for r in rows}),
        pecos2019_n_org=len(ppacs), pecos2019_org_pacs="|".join(sorted(ppacs)),
        pecos2019_national_members=pmem,
        pecos2019_org_names="|".join(sorted({x["org_name"] for x in p if x["org_name"]}))[:120],
        cms_facility_types="|".join(sorted(fac.get(npi, ()))),
        existing_org_size_max=e.get("org_size_max", ""), existing_facility=e.get("facilities", "")[:70],
        existing_independent_at_threshold=e.get("independent_at_threshold", ""),
        comparator_class=cls, classification_reason=why))

with open(f"{W}/comparator_classification.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(out[0].keys())); w.writeheader(); w.writerows(out)

ctl = [r for r in out if r["arm"] != "PE"]
print(f"rows {len(out)}  controls {len(ctl)}")
for lab, sub in (("ALL 400", out), ("CONTROLS (200)", ctl)):
    print(f"\n{lab}")
    for k, v in collections.Counter(r["pecos_status"] for r in sub).most_common():
        print(f"   status  {v:>4}  {k}")
    for k, v in collections.Counter(r["comparator_class"] for r in sub).most_common():
        print(f"   CLASS   {v:>4}  {k}")
