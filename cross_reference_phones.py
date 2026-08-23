import pandas as pd
import numpy as np

calling_sheet_path = "pe_obgyn_final_calling_sheet_300.csv"
study_db_path = "pe_obgyn_study_database.csv"

df_sheet = pd.read_csv(calling_sheet_path)
df_study = pd.read_csv(study_db_path)

def clean_phone(ph):
    if pd.isna(ph):
        return ""
    digits = "".join([c for c in str(ph) if c.isdigit()])
    return digits[-10:] if len(digits) >= 10 else ""

# Map study database columns for fast lookup
db_lookup = df_study.set_index('NPI')

matches_2_plus = 0
matches_1 = 0
matches_0 = 0

df_sheet['Phone_Database_Matches'] = 0
df_sheet['Phone_Verification_Status'] = "Unverified"

for idx, row in df_sheet.iterrows():
    npi = row['NPI']
    sheet_phone = clean_phone(row['Phone'])
    
    if npi not in db_lookup.index:
        continue
        
    db_row = db_lookup.loc[npi]
    if isinstance(db_row, pd.DataFrame):
        db_row = db_row.iloc[0]
        
    # Get phones from the three databases
    nppes_ph = clean_phone(db_row['NPPES Phone'])
    dac_ph = clean_phone(db_row['DAC Phone'])
    scraped_ph = clean_phone(db_row['Scraped Phone'])
    
    # Compare sheet phone to database phones
    match_sources = []
    if sheet_phone != "":
        if sheet_phone == nppes_ph:
            match_sources.append("NPPES")
        if sheet_phone == dac_ph:
            match_sources.append("CMS-DAC")
        if sheet_phone == scraped_ph:
            match_sources.append("WebScrape")
            
    match_count = len(set(match_sources))
    df_sheet.at[idx, 'Phone_Database_Matches'] = match_count
    
    if match_count >= 2:
        matches_2_plus += 1
        df_sheet.at[idx, 'Phone_Verification_Status'] = "Verified (2+ DBs)"
    elif match_count == 1:
        matches_1 += 1
        df_sheet.at[idx, 'Phone_Verification_Status'] = f"Verified (1 DB: {match_sources[0]})"
    else:
        matches_0 += 1
        df_sheet.at[idx, 'Phone_Verification_Status'] = "Unverified"

print("Phone validation cross-reference results:")
print(f"- Checked: {len(df_sheet)} rows")
print(f"- Matches in 2+ databases: {matches_2_plus} ({round(matches_2_plus / len(df_sheet) * 100, 1)}%)")
print(f"- Matches in 1 database: {matches_1} ({round(matches_1 / len(df_sheet) * 100, 1)}%)")
print(f"- Matches in 0 databases: {matches_0} ({round(matches_0 / len(df_sheet) * 100, 1)}%)")

# Overwrite sheet with verification columns
df_sheet.to_csv(calling_sheet_path, index=False)
print("Calling sheet updated with phone verification columns.")
