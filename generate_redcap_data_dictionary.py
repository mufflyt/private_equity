import csv
import pandas as pd

calling_sheet_path = "pe_obgyn_final_calling_sheet_300.csv"
dictionary_path = "PrivateVsPublicDoesEquityOwner_DataDictionary_2026-08-23.csv"

# Load calling sheet
df_sheet = pd.read_csv(calling_sheet_path)

# Generate dropdown choices for physician_name
choices_list = []
for idx, row in df_sheet.iterrows():
    choice_id = idx + 1
    
    p_name = row['Provider Name']
    backup_name = row['Backup Provider Name']
    cohort = row['PE_or_Not']
    city = row['City']
    state = row['State']
    npi = row['NPI']
    phone = row['Phone']
    
    # Format choice label
    label = f"{p_name} (Backup: {backup_name}), {cohort}, {city}, {state}, NPI: {npi}, {phone}"
    
    # REDCap format: "code, label"
    choices_list.append(f"{choice_id}, {label}")

choices_str = " | ".join(choices_list)

# Load data dictionary
with open(dictionary_path, 'r', newline='') as f:
    reader = list(csv.reader(f))

# Find the header indices
headers = reader[0]
var_idx = headers.index("Variable / Field Name")
choices_idx = headers.index("Choices, Calculations, OR Slider Labels")

# Find and update physician_name variable
updated = False
for row in reader:
    if row[var_idx] == "physician_name":
        row[choices_idx] = choices_str
        updated = True
        break

if updated:
    print("Updated physician_name choices successfully.")

# Remove the old backup tracking fields if they exist, and insert 'doctor_called'
# Filter out old backup fields
reader_filtered = [
    row for row in reader 
    if row[var_idx] not in ["backup_called", "actual_physician_name", "actual_physician_npi", "doctor_called"]
]

# Create 'doctor_called' radio button
doctor_called_row = [
    # Variable / Field Name, Form Name, Section Header, Field Type, Field Label, Choices, Field Note, Text Validation Type, Min, Max, Identifier?, Branching Logic, Required Field?, Custom Alignment, Question Number, Matrix Group Name, Matrix Ranking?, Field Annotation
    "doctor_called", "acost_three_dx_urogyn_2", "", "radio", "Which physician was actually called?", "1, Primary Physician | 2, Backup Physician", "", "", "", "", "", "", "y", "", "", "", "", ""
]

# Find index of physician_name in filtered list and insert doctor_called right after it
phys_name_idx = next(i for i, row in enumerate(reader_filtered) if row[var_idx] == "physician_name")
updated_rows = reader_filtered[:phys_name_idx + 1] + [doctor_called_row] + reader_filtered[phys_name_idx + 1:]

# Write back
with open(dictionary_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerows(updated_rows)

print("REDCap data dictionary successfully regenerated and saved!")
