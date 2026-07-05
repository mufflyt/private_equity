import pandas as pd
import numpy as np

# Load files
calling_sheet_path = "/Users/tylermuffly/private_equity/pe_obgyn_final_calling_sheet_300.csv"
study_db_path = "/Users/tylermuffly/private_equity/pe_obgyn_study_database.csv"

df_sheet = pd.read_csv(calling_sheet_path)
df_study = pd.read_csv(study_db_path)

# Helper to classify subspecialties from taxonomy
def get_subspecialty_from_tax(tax):
    if pd.isna(tax) or tax == "":
        return "Generalist"
    t = str(tax).strip().upper()
    if t == "207VE0102X":
        return "Reproductive Endocrinology/Infertility"
    if t == "207VX0201X":
        return "Gynecologic Oncology"
    if t == "207VM2500X":
        return "Maternal-Fetal Medicine"
    if t == "207VF0040X":
        return "Female Pelvic Medicine and Reconstructive Surgery"
    return "Generalist"

# Pre-process study database
df_study['subspec_clean'] = df_study['NPPES Taxonomy'].apply(get_subspecialty_from_tax)
# Keep only PE generalists for backups
pe_candidates = df_study[(df_study['PE_or_Not'] == 'PE') & (df_study['subspec_clean'] == 'Generalist')].copy()

# Add placeholder columns
df_sheet['Backup PE Provider Name'] = "None"
df_sheet['Backup PE Phone'] = "N/A"

backup_count = 0

# Loop through rows in calling sheet
for idx, row in df_sheet.iterrows():
    if row['PE_or_Not'] != 'PE':
        continue
    
    npi = row['NPI']
    office_id = row['office_id']
    
    if pd.isna(office_id) or office_id == "N/A":
        continue
        
    # Get all other PE generalists in the same office
    office_cands = pe_candidates[(pe_candidates['office_id'] == office_id) & (pe_candidates['NPI'] != npi)]
    
    if len(office_cands) == 0:
        continue
        
    # Primary doctor attributes
    p_row = df_study[df_study['NPI'] == npi]
    if len(p_row) == 0:
        # Fallback to sheet values
        p_gender = "Female"
        p_cred = row['Credentials']
        p_years = 15
    else:
        p_gender = p_row.iloc[0]['Gender']
        p_cred = p_row.iloc[0]['MD vs. DO']
        p_years = p_row.iloc[0]['Years in Practice']
        
    # Find the best match
    best_cand = None
    best_score = float('inf')
    
    for _, cand in office_cands.iterrows():
        # Score difference (lower is better)
        gender_score = 0 if cand['Gender'] == p_gender else 2
        cred_score = 0 if cand['MD vs. DO'] == p_cred else 2
        
        y1 = float(cand['Years in Practice']) if not pd.isna(cand['Years in Practice']) else 15.0
        y2 = float(p_years) if not pd.isna(p_years) else 15.0
        years_score = abs(y1 - y2)
        
        total_score = gender_score + cred_score + (years_score * 0.1) # low weight on years
        
        if total_score < best_score:
            best_score = total_score
            best_cand = cand
            
    if best_cand is not None:
        first = str(best_cand['Parsed First Name']).strip().title()
        last = str(best_cand['Parsed Last Name']).strip().title()
        backup_name = f"Dr. {first} {last}"
        
        # Phone formatting
        raw_phone = best_cand['NPPES Phone']
        if pd.isna(raw_phone) or raw_phone == "":
            raw_phone = best_cand['DAC Phone']
            
        if not pd.isna(raw_phone) and raw_phone != "":
            # Format phone
            digits = "".join([c for c in str(raw_phone) if c.isdigit()])
            if len(digits) == 10:
                phone_formatted = f"{digits[:3]}-{digits[3:6]}-{digits[6:]}"
            else:
                phone_formatted = str(raw_phone)
        else:
            phone_formatted = "N/A"
            
        df_sheet.at[idx, 'Backup PE Provider Name'] = backup_name
        df_sheet.at[idx, 'Backup PE Phone'] = phone_formatted
        backup_count += 1

print(f"Added backup PE physicians for {backup_count} offices out of 300 matched generalist pairs.")

# Align columns
# For Non-PE rows, keep Backup PE Provider Name and Backup PE Phone as "N/A" or match the PE row for the pair
# Actually, it's easiest if both rows in the pair show the backup details so caller sees it immediately
pair_to_backup_name = df_sheet[df_sheet['PE_or_Not'] == 'PE'].set_index('Matched Pair ID')['Backup PE Provider Name'].to_dict()
pair_to_backup_phone = df_sheet[df_sheet['PE_or_Not'] == 'PE'].set_index('Matched Pair ID')['Backup PE Phone'].to_dict()

for idx, row in df_sheet.iterrows():
    pair_id = row['Matched Pair ID']
    if pair_id in pair_to_backup_name:
        df_sheet.at[idx, 'Backup PE Provider Name'] = pair_to_backup_name[pair_id]
        df_sheet.at[idx, 'Backup PE Phone'] = pair_to_backup_phone[pair_id]

# Save calling sheet
df_sheet.to_csv(calling_sheet_path, index=False)
print("Updated calling sheet overwritten successfully.")
