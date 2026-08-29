#!/usr/bin/env python3
"""Build the comparator adjudication table from CMS DAC and PECOS extracts.

Reads intermediates produced by dac_extract.py, pecos_chain.py and orgspec.py (all of which
require the PECOS/DAC archive on an external drive), and writes one row per NPI covering the
fielded frame, the eligible matched universe, and the full PE roster.

Classification rules are fixed here and are applied without reference to any outcome; no
outcome data exist. Three states only, and ambiguity is never forced into a definitive one.
"""
import csv, sys, collections, re

W = sys.argv[1]; ROOT = sys.argv[2] if len(sys.argv) > 2 else "."
csv.field_size_limit(1 << 24)

key = {r["NPI"]: r for r in csv.DictReader(open(f"{W}/cohort_key_union.csv"))}
roster = {(r.get("NPI") or "").strip(): (r.get("Platform/Practice") or "").strip()
          for r in csv.DictReader(open(f"{ROOT}/pe_obgyn_providers_active.csv"))
          if (r.get("NPI") or "").strip()}
dac = list(csv.DictReader(open(f"{W}/dac_rows_union.csv")))
spec = {r["org_pac_id"]: r for r in csv.DictReader(open(f"{W}/org_specialty.csv"))}
pec = collections.defaultdict(list)
for r in csv.DictReader(open(f"{W}/pecos_rows_2019.csv")): pec[r["npi"]].append(r)
fac = collections.defaultdict(set)
for r in csv.DictReader(open(f"{W}/facility_affil.csv")): fac[r["npi"]].add(r["facility_type"])
exist = {r["npi"]: r for r in
         csv.DictReader(open(f"{ROOT}/data/covariates/control_org_classification.csv"))}

org_npis = collections.defaultdict(set); org_name = {}
for r in dac:
    if r["org_pac_id"]:
        org_npis[r["org_pac_id"]].add(r["npi"]); org_name[r["org_pac_id"]] = r["org_name"]
# An organisation is PE-platform-linked when any of its DAC members sits on the study roster.
pe_org = {}
for o, ns in org_npis.items():
    h = {n for n in ns if n in roster}
    if h: pe_org[o] = collections.Counter(roster[n] for n in h).most_common(1)[0][0]

SYS = re.compile(
    r"\bUNIVERSITY\b|\bUNIV\b|\bCOLLEGE\b|SCHOOL OF MEDICINE|\bFACULTY\b|HEALTH SYSTEM|"
    r"HEALTHCARE SYSTEM|HEALTH NETWORK|HEALTH SERVICES|HEALTH CARE SERVICES|\bHOSPITAL\b|"
    r"MEDICAL CENTER|\bPERMANENTE\b|\bKAISER\b|\bINFIRMARY\b|\bVETERANS\b|\bCOUNTY OF\b|"
    r"\bCITY OF\b|\bSTATE OF\b|DEPARTMENT OF|\bMEMORIAL\b|REGIONAL MEDICAL|\bGEISINGER\b|"
    r"\bWELLSTAR\b|\bINOVA\b|ORLANDO HEALTH|HACKENSACK|\bTRIHEALTH\b|PARK NICOLLET|"
    r"\bEINSTEIN\b|ASCENSION|\bBARNABAS\b|\bMCLAREN\b|ST VINCENT|\bWAKEMED\b|"
    r"PUBLIC HEALTH TRUST|PROSPECT HEALTH")
LARGE = 100          # triggers scrutiny; never classifies on its own
OB_PURE = 0.75       # single-specialty threshold for affirmative independence screening

by = collections.defaultdict(list)
for r in dac: by[r["npi"]].append(r)

def dig(s): return re.sub(r"\D", "", s or "")
def akey(s):
    s = (s or "").upper(); s = re.sub(r"[^A-Z0-9 ]", " ", s)
    s = re.sub(r"\b(STREET|ST|AVENUE|AVE|ROAD|RD|DRIVE|DR|BOULEVARD|BLVD|SUITE|STE|FLOOR|FL|"
               r"UNIT|NORTH|N|SOUTH|S|EAST|E|WEST|W)\b", " ", s)
    return re.sub(r"\s+", " ", s).strip()

BLANK = dict.fromkeys(
    ["dac_org_pac_id", "dac_org_name", "dac_national_clinicians", "dac_national_physicians",
     "dac_national_obgyn", "dac_local_clinicians", "dac_org_locations", "dac_num_org_mem",
     "org_n_specialties", "org_obgyn_share"], "")

out = []
for npi, c in sorted(key.items()):
    rows = by.get(npi, []); ph = {dig(c.get("Phone", ""))} - {""}
    city = (c.get("City") or "").upper(); st = (c.get("State") or "").upper()
    ak = akey(c.get("office_addr_key", ""))
    method = ""; sel = []
    if not rows:
        status = "no_dac_affiliation"
    else:
        m = [r for r in rows if r["phone"] and r["phone"] in ph]
        if m: method = "phone"
        if not m and ak:
            m = [r for r in rows if r["addr_key"] and r["addr_key"] == ak
                 and r["state"].upper() == st]
            if m: method = "address"
        if not m:
            m = [r for r in rows if r["city"].upper() == city and r["state"].upper() == st]
            if m: method = "city_state"
        if not m:
            status = "affiliation_location_mismatch"
        else:
            # A DAC row with an empty org_pac_id records NO organisational affiliation for that
            # row. Selecting one would report "organisation = nothing", which is not the same
            # claim and silently discards the organisation-bearing rows at the same office.
            # An earlier version did exactly that for 74 clinicians -- including one whose only
            # organisation was a PE platform -- so org-bearing rows are preferred here, and a
            # match consisting solely of blank-org rows gets its own status.
            withorg = [r for r in m if r["org_pac_id"]]
            if not withorg:
                status = "no_organisation_on_sampled_row"; sel = []
            else:
                sel = withorg
                status = ("location_resolved" if len({r["org_pac_id"] for r in withorg}) == 1
                          else "ambiguous_multiple_org")
    if sel:
        b = max(sel, key=lambda r: int(r["dac_national_clinicians"]))
        o = b["org_pac_id"]; sp = spec.get(o, {})
        rec = dict(dac_org_pac_id=o, dac_org_name=b["org_name"],
                   dac_national_clinicians=b["dac_national_clinicians"],
                   dac_national_physicians=b["dac_national_physicians"],
                   dac_national_obgyn=b["dac_national_obgyn"],
                   dac_local_clinicians=b["dac_local_clinicians"],
                   dac_org_locations=b["dac_org_locations"], dac_num_org_mem=b["num_org_mem"],
                   org_n_specialties=sp.get("n_specialties", ""),
                   org_obgyn_share=sp.get("obgyn_share", ""))
    else:
        o = ""; rec = dict(BLANK)
    pe_link = pe_org.get(o, "") if o else ""
    sysh = bool(rec["dac_org_name"] and SYS.search(rec["dac_org_name"].upper()))
    if status != "location_resolved":
        cls, why = "independence_unresolved", status
    elif pe_link:
        cls, why = ("not_independent_supported",
                    f'sampled organisation contains clinicians from PE platform "{pe_link}" '
                    f'on the study roster')
    elif sysh:
        cls, why = ("not_independent_supported",
                    "organisation name carries a hospital/system/academic/government token")
    elif rec["dac_national_clinicians"] and int(rec["dac_national_clinicians"]) >= LARGE:
        cls, why = ("independence_unresolved",
                    "large organisation, name uninformative; needs external adjudication")
    elif rec["org_obgyn_share"] and float(rec["org_obgyn_share"]) >= OB_PURE:
        cls, why = ("independent_supported",
                    "single-specialty OB/GYN organisation, no system token, no PE-roster member")
    else:
        cls, why = "independence_unresolved", "no affirmative evidence either way"

    # Sensitivity view: any affiliation at all, not only the sampled office. Reported beside the
    # primary figure rather than in place of it, because the two answer different questions.
    any_pe = sorted({pe_org[x] for x in {r["org_pac_id"] for r in rows if r["org_pac_id"]}
                     if x in pe_org})
    p = pec.get(npi, []); e = exist.get(npi, {})
    out.append(dict(
        npi=npi, name=c.get("Provider Name", ""), arm=c.get("PE_or_Not", ""),
        frame=c.get("frame", ""), pair=c.get("Matched Pair ID", ""),
        city=c.get("City", ""), state=c.get("State", ""),
        pecos_status=status, location_match_method=method, **rec,
        pe_platform_link=pe_link, pe_platform_any_affiliation="|".join(any_pe),
        hospital_affiliation="|".join(sorted(fac.get(npi, ()))),
        pecos2019_org_pacs="|".join(sorted({x["org_pac_id"] for x in p})),
        pecos2019_national_members=max([int(x["pecos_national_members"]) for x in p], default=""),
        pecos2019_org_names="|".join(sorted({x["org_name"] for x in p if x["org_name"]}))[:100],
        existing_org_size_max=e.get("org_size_max", ""),
        existing_facility=e.get("facilities", "")[:60],
        existing_independent_at_threshold=e.get("independent_at_threshold", ""),
        comparator_class=cls, classification_reason=why,
        external_source="", evidence_date="", adjudicator="",
        adjudication_confidence="", adjudication_note=""))

dest = f"{ROOT}/data/comparator/comparator_adjudication.csv"
with open(dest, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(out[0].keys())); w.writeheader(); w.writerows(out)
print(f"wrote {dest}  rows {len(out)}")
for lab, sub in (("FIELDED CONTROLS", [r for r in out if r["frame"].startswith("fielded") and r["arm"] != "PE"]),
                 ("UNIVERSE CONTROLS", [r for r in out if "universe" in r["frame"] and r["arm"] != "PE"])):
    cc = collections.Counter(r["comparator_class"] for r in sub)
    pe1 = sum(1 for r in sub if r["pe_platform_link"])
    pe2 = sum(1 for r in sub if r["pe_platform_any_affiliation"])
    print(f"\n{lab} n={len(sub)}")
    for k in ("not_independent_supported", "independence_unresolved", "independent_supported"):
        print(f"   {cc[k]:>4}  {k}")
    print(f"   PE link at sampled office {pe1} ({100*pe1/len(sub):.1f}%);  any affiliation {pe2}")
    print(f"   status {dict(collections.Counter(r['pecos_status'] for r in sub))}")
