"""Reverse-engineer the REDCap physician_name dropdown choices back into a
plain CSV (choice_id, physician_name, city, state, phone, npi, insurance).

The choices are stored REDCap-style as one big "code, label | code, label | ..."
string in the data dictionary's "Choices, Calculations, OR Slider Labels"
column. Each label has the form:
  id: <n>, Dr. <Name>, <City>, <State>, Phone: <phone>, NPI: <npi>, Insurance: <ins>, id: <n>
(the leading/trailing "id: <n>" duplicate the REDCap choice code itself).

Output is local only (gitignored, like the source dictionary) since it
contains provider names alongside NPI and phone.
"""
import csv
import re

DICTIONARY = "PrivateVsPublicDoesEquityOwner_DataDictionary_2026-08-23.csv"
OUT = "redcap_physician_name_choices_parsed.csv"

with open(DICTIONARY, newline="") as f:
    reader = csv.DictReader(f)
    row = next(r for r in reader if r["Variable / Field Name"] == "physician_name")
choices = row["Choices, Calculations, OR Slider Labels"]

PATTERN = re.compile(
    r"^(?P<code>\d+),\s*id:\s*\d+,\s*(?P<name>.+?),\s*(?P<city>[^,]+),\s*(?P<state>[A-Z]{2}),"
    r"\s*Phone:\s*(?P<phone>[^,]+),\s*NPI:\s*(?P<npi>\d+),\s*Insurance:\s*(?P<insurance>.+?),"
    r"\s*id:\s*\d+$"
)

parsed, failed = [], []
for entry in choices.split(" | "):
    m = PATTERN.match(entry.strip())
    if m:
        parsed.append(m.groupdict())
    else:
        failed.append(entry)

with open(OUT, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=["code", "name", "city", "state", "phone", "npi", "insurance"])
    w.writeheader()
    for p in parsed:
        w.writerow(p)

print(f"Parsed {len(parsed)}/{len(choices.split(' | '))} choices -> {OUT}")
if failed:
    print(f"FAILED to parse {len(failed)} entries:")
    for entry in failed:
        print(" ", entry)
