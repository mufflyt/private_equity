import pandas as pd
import duckdb
import os
import datetime

from pe_paths import open_nber_warehouse
OUTPUT_CSV = "control_candidates_raw.csv"
PE_CSV = "pe_obgyn_providers_active.csv"

# ACOG District Map
STATE_TO_ACOG = {
    'AL': 7, 'AK': 8, 'AZ': 8, 'AR': 7, 'CA': 9, 'CO': 8, 'CT': 1, 'DE': 3, 'DC': 4,
    'FL': 12, 'GA': 4, 'HI': 8, 'ID': 8, 'IL': 6, 'IN': 5, 'IA': 6, 'KS': 7, 'KY': 5,
    'LA': 7, 'ME': 1, 'MD': 4, 'MA': 1, 'MI': 5, 'MN': 6, 'MS': 7, 'MO': 7, 'MT': 8,
    'NE': 6, 'NV': 8, 'NH': 1, 'NJ': 3, 'NM': 8, 'NY': 2, 'NC': 4, 'ND': 6, 'OH': 5,
    'OK': 7, 'OR': 8, 'PA': 3, 'PR': 4, 'RI': 1, 'SC': 4, 'SD': 6, 'TN': 7, 'TX': 11,
    'UT': 8, 'VT': 1, 'VA': 4, 'WA': 8, 'WV': 4, 'WI': 6, 'WY': 6,
    'AE': 4, 'AP': 8, 'GU': 8, 'VI': 4
}

ACADEMIC_PATTERNS = [
    "UNIVERSITY", "MEDICAL SCHOOL", "SCHOOL OF MEDICINE", "COLLEGE OF MEDICINE",
    "TEACHING HOSPITAL", "RESIDENCY", "FELLOWSHIP", "ACADEMIC MEDICAL",
    "JOHNS HOPKINS", "MAYO CLINIC", "CLEVELAND CLINIC", "STANFORD",
    "HARVARD", "COLUMBIA", "YALE", "DUKE", "EMORY", "VANDERBILT",
    "CHILDREN'S HOSPITAL", "UNIVERSITY HOSPITAL", "MEDICAL COLLEGE"
]
GOVERNMENT_PATTERNS = [
    "VETERANS AFFAIRS", "VA", "VAMC", "DEPARTMENT OF DEFENSE",
    "USAF", "USN", "ARMY", "NAVY", "AIR FORCE", "MILITARY",
    "INDIAN HEALTH SERVICE", "IHS", "TRICARE", "PUBLIC HEALTH SERVICE",
    "COUNTY HEALTH", "STATE HEALTH", "FEDERAL BUREAU", "DEPARTMENT OF HEALTH"
]
COMMUNITY_PATTERNS = ["HOSPITAL", "MEDICAL CENTER", "HEALTH SYSTEM", "HEALTH CARE", "HEALTHCARE", "COMMUNITY HEALTH"]

def main():
        
    pe_df = pd.read_csv(PE_CSV)
    pe_npis = set(pe_df['NPI'].dropna().astype(int))
    print(f"Loaded {len(pe_df)} PE providers (NPIs: {len(pe_npis)})")
    
    print("Connecting to DuckDB...")
    con = open_nber_warehouse(required_tables=['temporal_obgyn_only_all_years'])
    
    try:
        # 1. Fetch raw candidates
        print("Querying all active OB/GYN candidates...")
        query = """
        SELECT 
            d.NPI as npi,
            d.gndr as gender,
            d.Cred as cred,
            upper(d."City/Town") as city,
            upper(d.State) as state,
            d."ZIP Code" as zip_code,
            d."Facility Name" as facility_name,
            d.num_org_mem,
            n."Provider Enumeration Date" as enum_date,
            n."Healthcare Provider Taxonomy Code_1" as taxonomy,
            d."Provider First Name" as first_name,
            d."Provider Last Name" as last_name,
            d.ind_assgn as med_assignment,
            d.Telehlth as telehealth,
            d."Telephone Number" as phone,
            d.adr_ln_1,
            d.adr_ln_2,
            d.Med_sch as med_sch,
            d.Grd_yr as grad_yr
        FROM main.doctors_and_clinicians_05_2024_DAC_NationalDownloadableFile_csv_6 d
        LEFT JOIN npi_dec_2024 n ON d.NPI = n.NPI
        WHERE d.pri_spec = 'OBSTETRICS/GYNECOLOGY'
          AND d."Telephone Number" IS NOT NULL
          AND trim(cast(d."Telephone Number" as VARCHAR)) != ''
          AND cast(d."Telephone Number" as VARCHAR) != 'NAN'
        """
        candidates = con.execute(query).fetchdf()
        print(f"Loaded {len(candidates)} raw OB/GYN candidates with phone numbers.")
        
        # Exclude PE providers
        candidates = candidates[~candidates['npi'].isin(pe_npis)].copy()
        print(f"Excluded PE providers. Remaining: {len(candidates)}")
        
        # Define Practice Setting
        def get_practice_setting(row):
            fac = str(row.get('facility_name', '')).upper()
            if not fac or fac == 'NAN':
                return 'Private Practice'
            if any(kw in fac for kw in ACADEMIC_PATTERNS):
                return 'Academic'
            if any(kw in fac for kw in GOVERNMENT_PATTERNS):
                return 'Government'
            if any(kw in fac for kw in COMMUNITY_PATTERNS):
                return 'Community'
            return 'Private Practice'
            
        candidates['Practice_Setting'] = candidates.apply(get_practice_setting, axis=1)
        candidates = candidates[candidates['Practice_Setting'] == 'Private Practice'].copy()
        print(f"Restricted to Private Practice setting: {len(candidates)}")
        
        # Fetch Open Payments details
        print("Querying Open Payments activity...")
        op_query = """
        SELECT npi, ANY_VALUE(years_with_payments) as op_years, ANY_VALUE(last_payment_year) as op_last_year
        FROM credentials.open_payments_activity
        GROUP BY npi
        """
        op_df = con.execute(op_query).fetchdf()
        op_df['npi'] = op_df['npi'].astype(int)
        
        # Fetch provider activity
        print("Querying provider activity...")
        act_query = """
        SELECT npi, ANY_VALUE(last_active_year) as last_active_year
        FROM credentials.provider_activity
        GROUP BY npi
        """
        act_df = con.execute(act_query).fetchdf()
        act_df['npi'] = act_df['npi'].astype(int)
        
        # Merge details into candidates
        print("Merging Open Payments and activity details...")
        candidates['npi'] = candidates['npi'].astype(int)
        candidates = candidates.merge(op_df, on='npi', how='left')
        candidates = candidates.merge(act_df, on='npi', how='left')
        
    except duckdb.Error as e:
        print(f"Database query error: {e}")
        con.close()
        raise
    con.close()
    
    # Save candidates to CSV
    candidates.to_csv(OUTPUT_CSV, index=False)
    print(f"Saved raw control candidates with covariates to: {OUTPUT_CSV} ({len(candidates)} records)")

if __name__ == "__main__":
    main()
