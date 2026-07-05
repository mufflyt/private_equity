import csv

input_path = "/Users/tylermuffly/private_equity/ICVsPOPVsSUI_DataDictionary_2026-07-05.csv"

# Read rows
with open(input_path, 'r', newline='') as f:
    reader = list(csv.reader(f))

# Check if fields are already added
if any(row[0] == "backup_called" for row in reader):
    print("REDCap dictionary already updated!")
else:
    # Create the new rows to insert
    new_rows = [
        # Variable / Field Name, Form Name, Section Header, Field Type, Field Label, Choices, Field Note, Text Validation Type, Min, Max, Identifier?, Branching Logic, Required Field?, Custom Alignment, Question Number, Matrix Group Name, Matrix Ranking?, Field Annotation
        ["backup_called", "acost_three_dx_urogyn_2", "", "yesno", "Was a backup physician called?", "", "", "", "", "", "", "", "y", "", "", "", "", ""],
        ["actual_physician_name", "acost_three_dx_urogyn_2", "", "text", "If yes, name of the backup physician called", "", "", "", "", "", "", "[backup_called] = '1'", "y", "", "", "", "", ""],
        ["actual_physician_npi", "acost_three_dx_urogyn_2", "", "text", "If yes, NPI of the backup physician called", "", "", "integer", "", "", "", "[backup_called] = '1'", "y", "", "", "", "", ""]
    ]

    # Insert after physician_name (which is at index 2)
    updated_rows = reader[:3] + new_rows + reader[3:]

    # Write back
    with open(input_path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerows(updated_rows)

    print("REDCap dictionary updated successfully!")
