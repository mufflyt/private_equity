#!/usr/bin/env python3
"""Compare implementation 1 against implementation 2, exactly.

Reports set differences rather than counts alone: two sets can be the same size and still
disagree, and a count-only comparison would call that a match. Exit status is non-zero on any
disagreement so this can gate a rebuild.

Usage: python pecos/verify/compare_implementations.py <workdir>
"""
import csv, sys, os

W = sys.argv[1]; bad = 0

def report(label, a, b):
    global bad
    ok = a == b
    if not ok: bad += 1
    print(f"  {label:<38} impl1 {len(a):>6}  impl2 {len(b):>6}  "
          f"only1 {len(a - b):>4}  only2 {len(b - a):>4}  {'IDENTICAL' if ok else 'DIFFER'}")
    if not ok:
        for x in sorted(a - b)[:5]: print(f"      only in impl1: {x}")
        for x in sorted(b - a)[:5]: print(f"      only in impl2: {x}")

rows = list(csv.DictReader(open(f"{W}/pecos_rows_2019.csv")))
p1_rcv = {(r["npi"], r["rcv_enrlmt_id"]) for r in rows}
p1_org = {(r["npi"], r["org_pac_id"]) for r in rows}
p1_mem = {r["org_pac_id"]: int(r["pecos_national_members"]) for r in rows}

p2_rcv = {tuple(l.rstrip("\n").split("\t")) for l in open(f"{W}/sm/npi_rcv.tsv")}
enr_pac = dict(l.rstrip("\n").split("\t") for l in open(f"{W}/sm/enr_pac.tsv"))
p2_org = {(n, enr_pac.get(o, "")) for n, o in p2_rcv}
p2_mem = {k: int(v) for k, v in
          (l.rstrip("\n").split("\t") for l in open(f"{W}/sm/pac_members.tsv"))}

print("PECOS chain:")
report("(NPI, receiving enrolment) pairs", p1_rcv, p2_rcv)
report("(NPI, organisation PAC) pairs", p1_org, p2_org)
diff = [(k, v, p2_mem.get(k)) for k, v in p1_mem.items() if p2_mem.get(k) != v]
if diff: bad += 1
print(f"  {'PAC member counts':<38} {len(p1_mem):>6} organisations; "
      f"disagreements {len(diff)}  {'IDENTICAL' if not diff else 'DIFFER'}")

perl = f"{W}/v2/npi_org.tsv"
if os.path.exists(perl):
    d1 = {(r["npi"], r["org_pac_id"])
          for r in csv.DictReader(open(f"{W}/dac_rows_union.csv")) if r["org_pac_id"]}
    d2 = {tuple(l.rstrip("\n").split("\t")) for l in open(perl)}
    print("DAC parse:")
    report("(NPI, org PAC) pairs", d1, d2)
else:
    print("DAC parse: skipped (run pecos/verify/dac_parse.pl first)")

print("\nRESULT:", "all implementations agree" if not bad else f"{bad} DISAGREEMENT(S)")
sys.exit(1 if bad else 0)
