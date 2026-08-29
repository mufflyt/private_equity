"""Implementation 1 (Python/csv) of the PECOS relational chain.

npi -> individual enrlmt_id -> REASGN -> RCV enrlmt_id -> receiving org PAC ID.
Organisation identity is the PAC ID (pecos_asct_cntl_id), not the org NPI, because an
organisational enrolment can carry more than one NPI.
"""
import csv, sys, collections, json
W = sys.argv[1]; V = sys.argv[2]              # vintage label
ENROL, REASSIGN, ADDR = sys.argv[3], sys.argv[4], sys.argv[5]
csv.field_size_limit(1 << 24)

npis = {r["NPI"].strip() for r in csv.DictReader(open(f"{W}/cohort_key.csv"))}

# ---- enrolment: build both directions we need --------------------------------
ind_enr = collections.defaultdict(set)     # cohort npi -> {I enrlmt_id}
enr_npi = {}                               # I enrlmt_id -> cohort npi
enr_pac = {}                               # any enrlmt_id -> PAC ID
org_meta = {}                              # O enrlmt_id -> (pac, name, type, npi)
pac_orgnpi = collections.defaultdict(set)
n = 0
with open(ENROL, newline="", encoding="utf-8", errors="replace") as f:
    for r in csv.DictReader(f):
        n += 1
        eid = (r["enrlmt_id"] or "").strip(); pac = (r["pecos_asct_cntl_id"] or "").strip()
        npi = (r["npi"] or "").strip()
        enr_pac[eid] = pac
        if eid.startswith("O"):
            org_meta[eid] = (pac, (r["org_name"] or "").strip(),
                             (r["provider_type_desc"] or "").strip(), npi)
            if npi: pac_orgnpi[pac].add(npi)
        elif npi in npis:
            ind_enr[npi].add(eid); enr_npi[eid] = npi

# ---- reassignment: individual -> receiving entity ----------------------------
# Count members at PAC level: distinct INDIVIDUAL PAC IDs reassigning into the org PAC.
pac_members = collections.defaultdict(set)
cohort_links = collections.defaultdict(set)   # cohort npi -> {receiving enrlmt_id}
rr = 0; skipped_i2i = 0
with open(REASSIGN, newline="", encoding="utf-8", errors="replace") as f:
    for r in csv.DictReader(f):
        rr += 1
        i = (r["reasgn_bnft_enrlmt_id"] or "").strip()
        o = (r["rcv_bnft_enrlmt_id"] or "").strip()
        if not o.startswith("O"):
            skipped_i2i += 1                 # I->I: receiving party is a person, not an org
            continue
        opac = enr_pac.get(o)
        ipac = enr_pac.get(i)
        if opac and ipac: pac_members[opac].add(ipac)
        if i in enr_npi: cohort_links[enr_npi[i]].add(o)

# ---- practice locations of the receiving enrolment ---------------------------
enr_loc = collections.defaultdict(set)
need = {o for s in cohort_links.values() for o in s}
with open(ADDR, newline="", encoding="utf-8", errors="replace") as f:
    for r in csv.DictReader(f):
        eid = (r["enrlmt_id"] or "").strip()
        if eid in need:
            enr_loc[eid].add(((r["city_name"] or "").strip().upper(),
                              (r["state_cd"] or "").strip().upper(),
                              (r["zip_cd"] or "").strip()[:5]))

out = []
for npi in sorted(npis):
    for o in sorted(cohort_links.get(npi, ())):
        pac, name, ptype, onpi = org_meta.get(o, ("", "", "", ""))
        for (city, st, z5) in sorted(enr_loc.get(o, {("", "", "")})):
            out.append(dict(vintage=V, npi=npi, ind_enrlmt_ids="|".join(sorted(ind_enr[npi])),
                            rcv_enrlmt_id=o, org_pac_id=pac, org_npi=onpi, org_name=name,
                            org_type=ptype, pecos_national_members=len(pac_members.get(pac, ())),
                            org_city=city, org_state=st, org_zip5=z5,
                            org_n_locations=len(enr_loc.get(o, ()))))
with open(f"{W}/pecos_rows_{V}.csv", "w", newline="") as f:
    wr = csv.DictWriter(f, fieldnames=list(out[0].keys())); wr.writeheader(); wr.writerows(out)
print(json.dumps(dict(vintage=V, enrol_rows=n, reassign_rows=rr, i_to_i_skipped=skipped_i2i,
                      cohort_npis_enrolled=len(ind_enr),
                      cohort_npis_with_reassignment=len(cohort_links),
                      output_rows=len(out),
                      distinct_org_pacs=len({r['org_pac_id'] for r in out})), indent=1))
