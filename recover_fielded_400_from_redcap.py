"""Recover the true Aug-10 fielded 400-physician / 200-pair cohort from the
live REDCap physician_name dropdown, since the source CSVs
(pe_obgyn_final_calling_sheet_200.csv, redcap_call_schedule_800.csv, etc.)
were never committed to git and are not recoverable from any local machine,
drive, or Dropbox (exhaustively searched).

The ordering contract comes directly from build_200_redcap_import.R:
    phys <- sheet %>%
      arrange(as.numeric(str_remove(`Matched Pair ID`, "pair_")), PE_or_Not) %>%
      mutate(slot = row_number())
    code (Medicaid) = slot         (1..400)
    code (BCBS)      = slot + 400  (401..800)
"Non-PE" sorts before "PE" alphabetically, so within each pair the odd slot
is Non-PE and the even slot is PE. This recovers *which* 400 physicians are
fielded, the pairing structure, and PE/Non-PE assignment -- but NOT the
original textual "pair_N" label, since that depended on the numeric value
of the (lost) Matched Pair ID before sorting.

Writes audit files only. Does not touch any source artifact.
"""
import csv

RECOVERY_DIR = "recovery"

with open("redcap_physician_name_choices_parsed.csv") as f:
    redcap = list(csv.DictReader(f))

# --- Step 2-3: restrict to codes 1:400, verify ---------------------------
medicaid = [r for r in redcap if 1 <= int(r["code"]) <= 400]
assert len(medicaid) == 400, f"expected 400 Medicaid-coded rows, got {len(medicaid)}"
npis = [r["npi"] for r in medicaid]
assert len(set(npis)) == 400, f"expected 400 unique NPIs, got {len(set(npis))}"
codes = sorted(int(r["code"]) for r in medicaid)
assert codes == list(range(1, 401)), "codes are not exactly 1..400"

# --- Step 4-5: sort by code, assign recovered pair structure --------------
medicaid.sort(key=lambda r: int(r["code"]))
recovered = []
for r in medicaid:
    code = int(r["code"])
    pair_index = (code + 1) // 2  # ceiling(code/2)
    pe_or_not = "Non-PE" if code % 2 == 1 else "PE"
    recovered.append({
        **r,
        "recovered_pair_index": pair_index,
        "PE_or_Not": pe_or_not,
        "recovered_pair_id": f"recovered_pair_{pair_index:03d}",
    })

# --- Step 6: verify every recovered pair has exactly 2 physicians, 1/1 ---
from collections import defaultdict
by_pair = defaultdict(list)
for r in recovered:
    by_pair[r["recovered_pair_index"]].append(r)
assert len(by_pair) == 200, f"expected 200 recovered pairs, got {len(by_pair)}"
for idx, members in by_pair.items():
    assert len(members) == 2, f"pair {idx} has {len(members)} members"
    statuses = sorted(m["PE_or_Not"] for m in members)
    assert statuses == ["Non-PE", "PE"], f"pair {idx} is not 1 Non-PE / 1 PE: {statuses}"

# --- Step 7: join against the tracked 300-pair sheet ----------------------
with open("pe_obgyn_final_calling_sheet_300.csv") as f:
    sheet300 = list(csv.DictReader(f))
sheet300_by_npi = {row["NPI"]: row for row in sheet300}

for idx, members in by_pair.items():
    nonpe = next(m for m in members if m["PE_or_Not"] == "Non-PE")
    pe = next(m for m in members if m["PE_or_Not"] == "PE")
    a300 = sheet300_by_npi.get(nonpe["npi"])
    b300 = sheet300_by_npi.get(pe["npi"])
    a_in, b_in = a300 is not None, b300 is not None

    if a_in and b_in and a300["Matched Pair ID"] == b300["Matched Pair ID"]:
        status = "confirmed_both_agree"
        original_pair_id = a300["Matched Pair ID"]
    elif a_in and b_in:
        status = "conflict_both_in_300_but_different_pairs"
        original_pair_id = ""
    elif a_in or b_in:
        # The only NPI present in the 300-sheet points at a pair_id, but its
        # partner there is (by definition, since the other side is absent)
        # not our recovered partner -- so it can never be independently
        # confirmed. Report as an unconfirmed candidate, don't restore it.
        found = a300 or b300
        status = "candidate_unconfirmed_single_side"
        original_pair_id = ""
        for m in members:
            m["candidate_original_pair_id_from_300"] = found["Matched Pair ID"]
    else:
        status = "not_recoverable_from_300"
        original_pair_id = ""

    for m in members:
        m["pair_recovery_status"] = status
        m["original_pair_id"] = original_pair_id
        m.setdefault("candidate_original_pair_id_from_300", "")

import os
os.makedirs(RECOVERY_DIR, exist_ok=True)

fieldnames = ["code", "name", "city", "state", "phone", "npi", "insurance",
              "recovered_pair_index", "recovered_pair_id", "PE_or_Not",
              "pair_recovery_status", "original_pair_id",
              "candidate_original_pair_id_from_300"]
with open(f"{RECOVERY_DIR}/recovered_fielded_400_from_redcap.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=fieldnames)
    w.writeheader()
    for r in sorted(recovered, key=lambda r: int(r["code"])):
        w.writerow({k: r.get(k, "") for k in fieldnames})

# --- Step 8: compare against the Drive 397-person Stage-1 list ------------
with open("data-raw/google_drive/gatson_mystery_phase1_needs_be_called.csv") as f:
    lines = f.readlines()
drive_reader = csv.DictReader(lines[1:])  # skip the title row
drive_npis = set(row["NPI"] for row in drive_reader if row.get("NPI"))

redcap_npis = set(r["npi"] for r in recovered)
redcap_only = sorted(redcap_npis - drive_npis)
drive_only = sorted(drive_npis - redcap_npis)

with open(f"{RECOVERY_DIR}/redcap_vs_drive_397_audit.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["npi", "side"])
    for npi in redcap_only:
        w.writerow([npi, "redcap_only"])
    for npi in drive_only:
        w.writerow([npi, "drive_only"])

# --- Step 9: pair-ID recovery audit summary --------------------------------
status_counts = defaultdict(int)
for r in recovered:
    status_counts[r["pair_recovery_status"]] += 1
confirmed_pairs = len({r["recovered_pair_index"] for r in recovered
                        if r["pair_recovery_status"] == "confirmed_both_agree"})

with open(f"{RECOVERY_DIR}/pair_id_recovery_audit.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["metric", "value"])
    w.writerow(["unique_redcap_physicians", len(set(r["npi"] for r in recovered))])
    w.writerow(["reconstructed_pairs", len(by_pair)])
    w.writerow(["pe_count", sum(1 for r in recovered if r["PE_or_Not"] == "PE")])
    w.writerow(["nonpe_count", sum(1 for r in recovered if r["PE_or_Not"] == "Non-PE")])
    w.writerow(["found_in_300_sheet", sum(1 for r in recovered if r["npi"] in sheet300_by_npi)])
    w.writerow(["pairs_original_id_restored", confirmed_pairs])
    for status, count in status_counts.items():
        w.writerow([f"physicians_status__{status}", count])
    dials = [__import__("re").sub(r"\D", "", r["phone"])[-10:] for r in recovered]
    dup_phones = len(dials) - len(set(dials))
    dup_npis = len(npis) - len(set(npis))
    w.writerow(["duplicate_phone_count", dup_phones])
    w.writerow(["duplicate_npi_count", dup_npis])
    w.writerow(["state_count", len(set(r["state"] for r in recovered))])
    w.writerow(["redcap_only_vs_drive397", len(redcap_only)])
    w.writerow(["drive397_only_vs_redcap", len(drive_only)])

print("=== Recovery summary ===")
print(f"Unique REDCap physicians: {len(set(r['npi'] for r in recovered))}")
print(f"Reconstructed pairs: {len(by_pair)}")
print(f"PE / Non-PE: {sum(1 for r in recovered if r['PE_or_Not']=='PE')} / "
      f"{sum(1 for r in recovered if r['PE_or_Not']=='Non-PE')}")
print(f"Found in 300-pair sheet: {sum(1 for r in recovered if r['npi'] in sheet300_by_npi)}/400")
print(f"Pairs with original ID restored (both sides agree): {confirmed_pairs}/200")
for status, count in status_counts.items():
    print(f"  {status}: {count} physicians")
print(f"Duplicate phone count: {dup_phones}")
print(f"Duplicate NPI count: {dup_npis}")
print(f"State count: {len(set(r['state'] for r in recovered))}")
print(f"REDCap NPIs not in Drive 397-list ({len(redcap_only)}): {redcap_only}")
print(f"Drive 397-list NPIs not in REDCap ({len(drive_only)}): {drive_only}")
