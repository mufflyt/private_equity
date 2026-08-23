import pandas as pd
import numpy as np
import re

# Load files
calling_sheet_path = "pe_obgyn_final_calling_sheet_300.csv"
study_db_path = "pe_obgyn_study_database.csv"
control_cands_path = "control_candidates_raw.csv"

df_sheet = pd.read_csv(calling_sheet_path)
df_study = pd.read_csv(study_db_path)
df_cands = pd.read_csv(control_cands_path)

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

# Clean address helper
def clean_address(adr):
    if pd.isna(adr):
        return ""
    s = re.sub(r'[^A-Z0-9]', '', str(adr).upper())
    s = re.sub(r'(SUITE|STE|UNIT|APT|FLOOR|FL|ROOM|RM|NUMBER|NO|DEPT|SUITES|STES|BLDG|BUILDING)[0-9A-Z]*', '', s)
    return s

# Clean phone helper
def clean_phone(ph):
    if pd.isna(ph):
        return ""
    digits = "".join([c for c in str(ph) if c.isdigit()])
    return digits[-10:] if len(digits) >= 10 else ""

# Pre-process cohorts to keep only generalists
df_study['subspec_clean'] = df_study['NPPES Taxonomy'].apply(get_subspecialty_from_tax)
pe_candidates = df_study[(df_study['PE_or_Not'] == 'PE') & (df_study['subspec_clean'] == 'Generalist')].copy()

df_cands['subspec_clean'] = df_cands['taxonomy'].apply(get_subspecialty_from_tax)
control_candidates = df_cands[df_cands['subspec_clean'] == 'Generalist'].copy()
control_candidates['clean_adr'] = control_candidates['adr_ln_1'].apply(clean_address)
control_candidates['clean_ph'] = control_candidates['phone'].apply(clean_phone)

# Reset backup columns
df_sheet['Backup Provider Name'] = "None"
df_sheet['Backup Phone'] = "N/A"

pe_backup_count = 0
control_backup_count = 0

for idx, row in df_sheet.iterrows():
    npi = row['NPI']
    is_pe = row['PE_or_Not'] == 'PE'
    
    if is_pe:
        # === PE BACKUP ===
        office_id = row['office_id']
        if pd.isna(office_id) or office_id == "N/A":
            continue
            
        office_cands = pe_candidates[(pe_candidates['office_id'] == office_id) & (pe_candidates['NPI'] != npi)]
        if len(office_cands) == 0:
            continue
            
        # Get primary doctor demographics
        p_row = df_study[df_study['NPI'] == npi]
        p_gender = p_row.iloc[0]['Gender'] if len(p_row) > 0 else "Female"
        p_cred = p_row.iloc[0]['MD vs. DO'] if len(p_row) > 0 else row['Credentials']
        p_years = p_row.iloc[0]['Years in Practice'] if len(p_row) > 0 else 15
        
        # Find best match
        best_cand = None
        best_score = float('inf')
        for _, cand in office_cands.iterrows():
            g_score = 0 if cand['Gender'] == p_gender else 2
            c_score = 0 if cand['MD vs. DO'] == p_cred else 2
            y1 = float(cand['Years in Practice']) if not pd.isna(cand['Years in Practice']) else 15.0
            y2 = float(p_years) if not pd.isna(p_years) else 15.0
            total_score = g_score + c_score + (abs(y1 - y2) * 0.1)
            
            if total_score < best_score:
                best_score = total_score
                best_cand = cand
                
        if best_cand is not None:
            first = str(best_cand['Parsed First Name']).strip().title()
            last = str(best_cand['Parsed Last Name']).strip().title()
            df_sheet.at[idx, 'Backup Provider Name'] = f"Dr. {first} {last}"
            
            raw_phone = best_cand['NPPES Phone']
            if pd.isna(raw_phone) or raw_phone == "":
                raw_phone = best_cand['DAC Phone']
            if not pd.isna(raw_phone) and raw_phone != "":
                digits = "".join([c for c in str(raw_phone) if c.isdigit()])
                df_sheet.at[idx, 'Backup Phone'] = f"{digits[:3]}-{digits[3:6]}-{digits[6:]}" if len(digits) == 10 else str(raw_phone)
            pe_backup_count += 1
            
    else:
        # === CONTROL (NON-PE) BACKUP ===
        p_row = df_study[df_study['NPI'] == npi]
        if len(p_row) == 0:
            continue
            
        p_gender = p_row.iloc[0]['Gender']
        p_cred = p_row.iloc[0]['MD vs. DO']
        p_years = p_row.iloc[0]['Years in Practice']
        
        # Get address and phone details
        p_adr = p_row.iloc[0]['DAC Address 1']
        if pd.isna(p_adr) or p_adr == "":
            p_adr = p_row.iloc[0]['NPPES Address 1']
            
        p_phone = p_row.iloc[0]['NPPES Phone']
        if pd.isna(p_phone) or p_phone == "":
            p_phone = p_row.iloc[0]['DAC Phone']
            
        clean_p_adr = clean_address(p_adr)
        clean_p_ph = clean_phone(p_phone)
        p_city = str(p_row.iloc[0]['DAC City']).strip().upper()
        p_state = str(p_row.iloc[0]['DAC State']).strip().upper()
        
        # Find candidates with same clean phone OR same clean address in same city/state
        cond_ph = (control_candidates['clean_ph'] == clean_p_ph) & (clean_p_ph != "")
        cond_adr = (control_candidates['clean_adr'] == clean_p_adr) & (control_candidates['city'].str.strip().str.upper() == p_city) & (control_candidates['state'].str.strip().str.upper() == p_state) & (clean_p_adr != "")
        
        control_cands = control_candidates[(cond_ph | cond_adr) & (control_candidates['npi'] != npi)]
        
        if len(control_cands) == 0:
            continue
            
        # Find best match
        best_cand = None
        best_score = float('inf')
        for _, cand in control_cands.iterrows():
            g_score = 0 if cand['gender'] == p_gender or (cand['gender'] == 'F' and p_gender == 'Female') or (cand['gender'] == 'M' and p_gender == 'Male') else 2
            
            c_cand = 'DO' if 'DO' in str(cand['cred']).upper() else 'MD'
            c_score = 0 if c_cand == p_cred else 2
            
            # Years in practice
            grad = cand['grad_yr']
            y1 = 2026 - int(grad) if not pd.isna(grad) else 15.0
            y2 = float(p_years) if not pd.isna(p_years) else 15.0
            total_score = g_score + c_score + (abs(y1 - y2) * 0.1)
            
            if total_score < best_score:
                best_score = total_score
                best_cand = cand
                
        if best_cand is not None:
            first = str(best_cand['first_name']).strip().title()
            last = str(best_cand['last_name']).strip().title()
            df_sheet.at[idx, 'Backup Provider Name'] = f"Dr. {first} {last}"
            
            raw_phone = best_cand['phone']
            if not pd.isna(raw_phone) and raw_phone != "":
                digits = "".join([c for c in str(raw_phone) if c.isdigit()])
                df_sheet.at[idx, 'Backup Phone'] = f"{digits[:3]}-{digits[3:6]}-{digits[6:]}" if len(digits) == 10 else str(raw_phone)
            control_backup_count += 1

print(f"Symmetric backup process complete:")
print(f"- PE Backups found: {pe_backup_count} offices")
print(f"- Non-PE Control Backups found: {control_backup_count} offices")

# Save calling sheet
# Drop old columns if they exist
if 'Backup PE Provider Name' in df_sheet.columns:
    df_sheet.drop(columns=['Backup PE Provider Name', 'Backup PE Phone'], inplace=True)
    
df_sheet.to_csv(calling_sheet_path, index=False)
print("Updated calling sheet overwritten successfully with symmetric backups.")
