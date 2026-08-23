#!/usr/bin/env python3
"""
Pipeline for name-parsing providers, matching to the CMS NPPES (NPI) Registry,
enforcing strict MD vs. DO, strict State/Platform-allowed state matching,
excluding mid-level providers, and preserving PE metadata.
"""
import pandas as pd
import requests
import re
import time
import os
import json
from concurrent.futures import ThreadPoolExecutor, as_completed

# Common provider credentials to identify and separate during parsing
CREDENTIALS_SET = {
    'MD', 'DO', 'CNM', 'NP', 'PA', 'PAC', 'PA-C', 'RN', 'MSN', 'DNP', 'PHD', 
    'FACS', 'FACOG', 'OBGYN', 'OB/GYN', 'MSCE', 'BSN', 'APRN', 'WHNP', 'LPN'
}

EXCLUDED_CREDENTIALS = {
    'CNM', 'NP', 'PA', 'PAC', 'PA-C', 'RN', 'MSN', 'DNP', 'APRN', 'WHNP', 
    'LPN', 'BSN', 'WHNP-BC', 'FNP', 'FNP-C', 'DNP-FNP', 'ACNP-BC', 'ARNP', 
    'WHCNP', 'CRNP', 'APN', 'PMHNP-BC', 'MSPAS'
}

# Platform to allowed states mapping for validation
PLATFORM_STATES = {
    "Unified Women's Healthcare": ["MI"],
    "Together Women's Health": ["MI"],
    "Nova Women's Health Partners": ["IL"],
    "Femwell Group Health": ["FL"],
    "CCRM Fertility": ["CO", "GA", "AZ", "TX", "MA", "IL", "DE", "MN", "NJ", "NY", "CA", "PA", "VA"],
    "IVI RMA Global": ["NJ", "CA", "CO", "DE", "FL", "NC", "OH", "PA", "TX", "UT", "WA"],
    "US Fertility": ["MD", "VA", "PA", "CO", "FL", "GA", "NY"],
    "Kindbody": ["NY", "CA", "TX", "MD", "NC", "IL", "CO", "WI", "MN", "NJ", "AR", "MO", "DC"],
    "Women's Care Enterprises": ["FL"],
    "Axia Women's Health": ["NJ", "PA", "IN", "OH", "KY", "DE", "MD"],
    "OB Hospitalist Group": [] # Empty list means any state is allowed (nationwide)
}

def parse_provider_name(name_str):
    """
    Parses a provider name string into prefix, first, middle, last, and credentials.
    """
    if not isinstance(name_str, str) or not name_str.strip():
        return {'prefix': '', 'first': '', 'middle': '', 'last': '', 'credentials': ''}
        
    original = name_str.strip()
    
    # Remove common prefix titles
    prefix = ""
    prefix_match = re.match(r'^(Dr\.|Doctor|Dr|Mr\.|Ms\.|Mrs\.)\s+', original, re.IGNORECASE)
    if prefix_match:
        prefix = prefix_match.group(1).strip()
        name_str = original[prefix_match.end():]
    else:
        name_str = original

    # Split off credentials (normally after commas)
    parts = [p.strip() for p in name_str.split(',')]
    core_name = parts[0]
    
    credentials = []
    for part in parts[1:]:
        clean_part = re.sub(r'[^a-zA-Z-]', '', part)
        if clean_part.upper() in CREDENTIALS_SET or clean_part.upper() in EXCLUDED_CREDENTIALS:
            credentials.append(clean_part.upper())
            
    # Also check if core name has credentials at the end without a comma
    name_tokens = core_name.split()
    clean_tokens = []
    for token in name_tokens:
        clean_tok = re.sub(r'[^a-zA-Z-]', '', token)
        if clean_tok.upper() in CREDENTIALS_SET or clean_tok.upper() in EXCLUDED_CREDENTIALS:
            credentials.append(clean_tok.upper())
        else:
            clean_tokens.append(token)
            
    name_str = " ".join(clean_tokens)
    tokens = name_str.split()
    first = ""
    middle = ""
    last = ""
    
    if len(tokens) == 1:
        first = tokens[0]
    elif len(tokens) == 2:
        first = tokens[0]
        last = tokens[1]
    elif len(tokens) >= 3:
        first = tokens[0]
        if tokens[-1].lower() in ['jr', 'jr.', 'sr', 'sr.', 'ii', 'iii', 'iv']:
            last = tokens[-2] + " " + tokens[-1]
            middle = " ".join(tokens[1:-2])
        else:
            last = tokens[-1]
            middle = " ".join(tokens[1:-1])
            
    return {
        'prefix': prefix,
        'first': first,
        'middle': middle,
        'last': last,
        'credentials': ", ".join(credentials)
    }

def query_nppes_registry(first_name, last_name, state=None):
    """
    Queries the public NPI Registry API for individual providers.
    """
    url = "https://npiregistry.cms.hhs.gov/api/"
    params = {
        'version': '2.1',
        'first_name': first_name,
        'last_name': last_name,
        'enumeration_type': 'NPI-1'
    }
    if state:
        params['state'] = state
        
    try:
        response = requests.get(url, params=params, timeout=12)
        if response.status_code != 200:
            return []
        data = response.json()
        results = data.get('results', [])
        
        # Fallback to nationwide search if state search fails
        if not results and state:
            params.pop('state')
            response = requests.get(url, params=params, timeout=12)
            if response.status_code == 200:
                results = response.json().get('results', [])
        return results
    except Exception as e:
        return []

def match_provider_to_npi(name_str, state=None, allowed_states=None):
    """
    Finds the best NPI match. Enforces strict State, allowed states, and MD vs. DO checks.
    """
    parsed = parse_provider_name(name_str)
    
    # 1. Exclude mid-level credentials from name string
    creds_found = [c.strip().upper() for c in parsed['credentials'].split(',') if c.strip()]
    for cred in creds_found:
        if cred in EXCLUDED_CREDENTIALS:
            return {'parsed_name': parsed, 'npi': None, 'match_status': f'Excluded (credential: {cred})'}

    first = parsed['first']
    last = parsed['last']
    
    if not first or not last:
        return {'parsed_name': parsed, 'npi': None, 'match_status': 'Failed parsing'}
        
    # Query with specified state first (if provided)
    results = query_nppes_registry(first, last, state)
    
    if not results:
        return {'parsed_name': parsed, 'npi': None, 'match_status': 'No match found'}
        
    EXCLUDED_TAXONOMY_KEYWORDS = {
        'midwife', 'nurse practitioner', 'physician assistant', "physician's assistant", 
        'registered nurse', 'clinical nurse specialist', 'advanced practice registered nurse'
    }
    
    best_match = None
    
    for r in results:
        taxonomies = r.get('taxonomies', [])
        
        # Check taxonomy codes/descriptions for mid-level exclusions and physician status
        is_excluded_taxonomy = False
        is_obgyn = False
        is_physician = False
        for tax in taxonomies:
            desc = tax.get('desc')
            desc = desc.lower() if desc else ''
            code = tax.get('code', '')
            if (code.startswith('363A') or code.startswith('363L') or 
                code.startswith('367A') or code.startswith('374T') or 
                any(k in desc for k in EXCLUDED_TAXONOMY_KEYWORDS)):
                is_excluded_taxonomy = True
                break
            if code.startswith('207V') or any(k in desc for k in ['obstetrics', 'gynecology', 'fertility', 'reproductive']):
                is_obgyn = True
            if code.startswith('20') or code == '174400000X':
                is_physician = True
                
        if is_excluded_taxonomy or not is_physician:
            continue
            
        # Collect all states associated with this NPI record
        states_in_record = set()
        for addr in r.get('addresses', []):
            st = addr.get('state')
            if st:
                states_in_record.add(st.upper())
        for tax in taxonomies:
            st = tax.get('state')
            if st:
                states_in_record.add(st.upper())
        for loc_p in r.get('practiceLocations', []):
            st = loc_p.get('state')
            if st:
                states_in_record.add(st.upper())
                
        # --- RULE 1: STRICT STATE/PLATFORM MATCHING ---
        if state and state.upper() not in states_in_record:
            # Check if at least in allowed states list for that platform
            if allowed_states and not any(s in states_in_record for s in allowed_states):
                continue
            elif not allowed_states:
                continue
                
        # --- RULE 2: STRICT MD vs. DO MATCHING ---
        basic = r.get('basic', {})
        nppes_creds = basic.get('credential', '').upper().replace('.', '').replace(' ', '')
        
        input_is_md = 'MD' in creds_found
        input_is_do = 'DO' in creds_found
        
        # If input doesn't specify, check if the input name string itself specifies MD or DO
        if not input_is_md and not input_is_do:
            raw_upper = name_str.upper()
            if re.search(r'\bMD\b|\bM\.D\.\b', raw_upper):
                input_is_md = True
            elif re.search(r'\bDO\b|\bD\.O\.\b', raw_upper):
                input_is_do = True
                
        # Tokenize NPPES credentials to avoid false matches (e.g. Pharm.D. matching MD)
        nppes_creds_clean = nppes_creds.upper().replace('.', '')
        nppes_tokens = set(re.sub(r'[^A-Z]', ' ', nppes_creds_clean).split())
        
        nppes_is_md = 'MD' in nppes_tokens or 'MEDICAL' in nppes_tokens
        nppes_is_do = 'DO' in nppes_tokens or 'OSTEOPATHIC' in nppes_tokens or nppes_creds == 'DO'
        
        # Conflict check
        if input_is_md and nppes_is_do:
            continue  # MD vs DO mismatch, reject
        if input_is_do and nppes_is_md:
            continue  # DO vs MD mismatch, reject
            
        # Score the match
        score = 0
        if is_obgyn:
            score += 2
        # Address match
        address_state = ""
        for addr in r.get('addresses', []):
            if addr.get('address_purpose') == 'LOCATION':
                address_state = addr.get('state', '')
                break
        if state and address_state.upper() == state.upper():
            score += 3
        elif allowed_states and address_state.upper() in allowed_states:
            score += 2
            
        r['_score'] = score
        if best_match is None or score > best_match.get('_score', -1):
            best_match = r
            
    if best_match:
        score = best_match['_score']
        match_quality = "Name only"
        if score >= 5:
            match_quality = "Exact (Name, State, Specialty)"
        elif score >= 3:
            match_quality = "High (Name, State)"
        elif score >= 2:
            match_quality = "Good (Name, Specialty)"
            
        npi = best_match.get('number')
        basic = best_match.get('basic', {})
        nppes_name = f"{basic.get('first_name')} {basic.get('last_name')}"
        nppes_credentials = basic.get('credential', '')
        
        # Double check returned NPI credentials
        clean_nppes_creds = re.sub(r'[^a-zA-Z,\s]', '', nppes_credentials).upper()
        for cred in EXCLUDED_CREDENTIALS:
            if cred in [c.strip() for c in clean_nppes_creds.split(',')]:
                return {'parsed_name': parsed, 'npi': None, 'match_status': f'Excluded (NPPES credential: {cred})'}
                
        phone = ""
        addr_1 = ""
        addr_2 = ""
        city = ""
        state_code = ""
        zip_code = ""
        addresses = best_match.get('addresses', [])
        for addr in addresses:
            if addr.get('address_purpose') == 'LOCATION':
                phone = addr.get('telephone_number', '')
                addr_1 = addr.get('address_1', '')
                addr_2 = addr.get('address_2', '')
                city = addr.get('city', '')
                state_code = addr.get('state', '')
                zip_code = addr.get('postal_code', '')
                break
                
        nppes_taxonomy = ""
        for tax in best_match.get('taxonomies', []):
            if tax.get('primary', False):
                nppes_taxonomy = tax.get('code', '')
                break
        if not nppes_taxonomy and best_match.get('taxonomies'):
            nppes_taxonomy = best_match.get('taxonomies')[0].get('code', '')

        return {
            'parsed_name': parsed,
            'npi': npi,
            'nppes_name': nppes_name,
            'nppes_credentials': nppes_credentials,
            'nppes_phone': phone,
            'nppes_address_1': addr_1,
            'nppes_address_2': addr_2,
            'nppes_city': city,
            'nppes_state': state_code,
            'nppes_zip': zip_code,
            'match_quality': match_quality,
            'match_score': score,
            'nppes_taxonomy': nppes_taxonomy,
            'npi_last_updated': best_match.get('basic', {}).get('last_updated', 'N/A')
        }
        
    return {'parsed_name': parsed, 'npi': None, 'match_status': 'No match found or excluded'}

def process_provider(prov, cache):
    """
    Worker function to process a single provider, checking cache first.
    """
    name = prov['name']
    platform = prov['platform']
    state = prov['state']
    
    # Cache lookup key
    cache_key = (name.lower(), platform.lower())
    if cache_key in cache:
        cached_row = cache[cache_key]
        has_address = 'NPPES Address 1' in cached_row and pd.notna(cached_row.get('NPPES Address 1'))
        tax_val = cached_row.get('NPPES Taxonomy')
        has_taxonomy = pd.notna(tax_val) and str(tax_val).strip() != '' and str(tax_val).strip().upper() != 'N/A'
        if has_address and has_taxonomy:
            # Copy original fields from prov and append cached NPI details
            res = prov.copy()
            res.update({
                'Parsed First Name': cached_row.get('Parsed First Name'),
                'Parsed Last Name': cached_row.get('Parsed Last Name'),
                'NPI': cached_row.get('NPI'),
                'NPPES Name': cached_row.get('NPPES Name'),
                'NPPES Credentials': cached_row.get('NPPES Credentials'),
                'NPPES Phone': cached_row.get('NPPES Phone'),
                'NPPES Address 1': cached_row.get('NPPES Address 1'),
                'NPPES Address 2': cached_row.get('NPPES Address 2'),
                'NPPES City': cached_row.get('NPPES City'),
                'NPPES State': cached_row.get('NPPES State'),
                'NPPES Zip': cached_row.get('NPPES Zip'),
                'NPPES Taxonomy': cached_row.get('NPPES Taxonomy') if 'NPPES Taxonomy' in cached_row else 'N/A',
                'Match Quality': cached_row.get('Match Quality'),
                'Match Score': int(cached_row.get('Match Score', 0)) if pd.notna(cached_row.get('Match Score')) else 0,
                'NPI Last Updated': cached_row.get('NPI Last Updated') if 'NPI Last Updated' in cached_row else 'N/A'
            })
            return res, True # True means cache hit
            # Cache miss: query CMS NPPES API
    allowed_states = PLATFORM_STATES.get(platform, [])
    raw_name = prov.get('Provider Name', name)
    match = match_provider_to_npi(raw_name, state, allowed_states)
    
    parsed = match.get('parsed_name', {})
    
    res = prov.copy()
    res.update({
        'Parsed First Name': parsed.get('first'),
        'Parsed Last Name': parsed.get('last'),
        'NPI': match.get('npi'),
        'NPPES Name': match.get('nppes_name', 'N/A').title() if match.get('nppes_name') else 'N/A',
        'NPPES Credentials': match.get('nppes_credentials', 'N/A'),
        'NPPES Phone': match.get('nppes_phone', 'N/A'),
        'NPPES Address 1': match.get('nppes_address_1', 'N/A'),
        'NPPES Address 2': match.get('nppes_address_2', 'N/A'),
        'NPPES City': match.get('nppes_city', 'N/A').title() if match.get('nppes_city') else 'N/A',
        'NPPES State': match.get('nppes_state', 'N/A'),
        'NPPES Zip': match.get('nppes_zip', 'N/A'),
        'NPPES Taxonomy': match.get('nppes_taxonomy', 'N/A'),
        'Match Quality': match.get('match_quality', match.get('match_status', 'Failed')),
        'Match Score': match.get('match_score', 0),
        'NPI Last Updated': match.get('npi_last_updated', 'N/A')
    })
    return res, False # False means cache miss

if __name__ == "__main__":
    print("=== Loading Parsed Providers ===")
    discovered_path = "discovered_providers.json"
    if not os.path.exists(discovered_path):
        print(f"ERROR: {discovered_path} does not exist. Run parse_scraped_directories.py first.")
        exit(1)
        
    with open(discovered_path, "r") as f:
        providers = json.load(f)
        
    print(f"Loaded {len(providers)} unique parsed providers.")
    
    # Load cache if existing CSV is present
    cache = {}
    csv_path = "pe_obgyn_providers_npi.csv"
    if os.path.exists(csv_path):
        print(f"Loading existing NPI cache from {csv_path}...")
        try:
            old_df = pd.read_csv(csv_path)
            for idx, row in old_df.iterrows():
                p_name = str(row.get('Provider Name', ''))
                plat = str(row.get('Platform/Practice', ''))
                npi = row.get('NPI')
                if pd.notna(p_name) and pd.notna(plat) and pd.notna(npi) and str(npi).strip() != "" and "Failed" not in str(row.get('Match Quality')):
                    # Enforce strict validation before caching
                    
                    # 1. Check for mid-levels in input credentials or NPPES credentials
                    input_creds = str(row.get('Input Credentials', '')).upper().replace('.', '')
                    nppes_creds = str(row.get('NPPES Credentials', '')).upper().replace('.', '')
                    
                    # Tokenize name and credentials to check for exclusions
                    name_tokens = set(re.sub(r'[^A-Z]', ' ', p_name.upper()).split())
                    input_tokens = set(re.sub(r'[^A-Z]', ' ', input_creds).split())
                    nppes_tokens = set(re.sub(r'[^A-Z]', ' ', nppes_creds).split())
                    
                    is_mid_level = False
                    for c in EXCLUDED_CREDENTIALS:
                        if c in name_tokens or c in input_tokens or c in nppes_tokens:
                            is_mid_level = True
                            break
                            
                    if is_mid_level:
                        print(f"Skipping cache for mid-level provider: {p_name} (NPPES Creds: {nppes_creds})")
                        continue
                        
                    # Check for non-physician credentials in cache (unless they also have MD/DO)
                    if not ('MD' in nppes_tokens or 'DO' in nppes_tokens or 'MD' in name_tokens or 'DO' in name_tokens):
                        NON_PHYSICIAN_CREDENTIALS = {'DDS', 'LPC', 'LCSW', 'LMHC', 'PHARMD', 'DPM', 'DC', 'RPH', 'MSW', 'PT', 'LPT', 'RN', 'APRN', 'NP', 'PA', 'PAC', 'PA-C'}
                        is_non_physician = False
                        for c in NON_PHYSICIAN_CREDENTIALS:
                            if c in nppes_tokens:
                                is_non_physician = True
                                break
                                
                        if is_non_physician:
                            print(f"Skipping cache for non-physician provider: {p_name} (NPPES Creds: {nppes_creds})")
                            continue
                        
                    # 2. Check for MD/DO conflicts
                    is_input_md = 'MD' in input_tokens or 'M.D.' in input_creds
                    is_input_do = 'DO' in input_tokens or 'D.O.' in input_creds
                    
                    # If input credentials doesn't specify, check raw name
                    if not is_input_md and not is_input_do:
                        if 'MD' in name_tokens:
                            is_input_md = True
                        elif 'DO' in name_tokens:
                            is_input_do = True
                            
                    is_nppes_md = 'MD' in nppes_tokens or 'MEDICAL' in nppes_tokens
                    is_nppes_do = 'DO' in nppes_tokens or 'OSTEOPATHIC' in nppes_tokens or nppes_creds == 'DO'
                    
                    if (is_input_md and is_nppes_do) or (is_input_do and is_nppes_md):
                        print(f"Skipping cache for MD/DO conflict: {p_name} (Input: {input_creds}, NPPES: {nppes_creds})")
                        continue
                        
                    # Extract core name
                    parsed_name = parse_provider_name(p_name)['first'] + " " + parse_provider_name(p_name)['last']
                    key = (parsed_name.lower(), plat.lower())
                    cache[key] = row.to_dict()
            print(f"Loaded {len(cache)} cached provider matches.")
        except Exception as e:
            print(f"Warning: Failed to load cache from CSV: {e}")
            
    # Run the matching pipeline
    results = []
    scrape_time = time.strftime("%Y-%m-%d %H:%M:%S")
    
    cache_hits = 0
    cache_misses = 0
    
    print("\n=== Running NPPES Matching Pipeline (Parallelized) ===")
    
    # We will submit matching tasks to ThreadPoolExecutor
    # Using 10 workers for speed since the CMS NPI registry handles it easily
    with ThreadPoolExecutor(max_workers=10) as executor:
        futures = {}
        for prov in providers:
            # Map discovered_providers fields to expected match fields
            mapped_prov = {
                'Provider Name': prov['raw_name'],
                'Input Credentials': prov['credentials'],
                'Input State': prov['state'],
                'Platform/Practice': prov['platform'],
                'PE Owner': prov['pe_owner'],
                'Acquisition Year': prov['acq_year'],
                'Source of Information': prov['source'],
                'Scrape Run Time': scrape_time,
                'name': prov['name'],
                'state': prov['state'],
                'platform': prov['platform']
            }
            futures[executor.submit(process_provider, mapped_prov, cache)] = prov
            
        completed_count = 0
        for future in as_completed(futures):
            res_row, is_cached = future.result()
            results.append(res_row)
            if is_cached:
                cache_hits += 1
            else:
                cache_misses += 1
                # Sleep briefly to respect CMS rate limits on cache misses
                time.sleep(0.08)
                
            completed_count += 1
            if completed_count % 50 == 0:
                print(f"  Processed {completed_count}/{len(providers)} providers... (Hits: {cache_hits}, Misses: {cache_misses})")
                
    # Convert to DataFrame
    df = pd.DataFrame(results)
    
    # Drop helper fields used for matching
    df = df.drop(columns=['name', 'state', 'platform'])
    
    # Enforce formatting
    # int(float(x)) produces the right value, but a column of ints containing None is
    # promoted by pandas to float64, so to_csv writes "1144280553.0". Every downstream
    # consumer then joins on a key that no longer matches the integer NPIs in the calling
    # sheets: a raw join of the fielded sheet against the study database matched 0 of 400
    # rows. Int64 is pandas' nullable integer type and writes the value with no decimal.
    df['NPI'] = df['NPI'].apply(lambda x: int(float(x)) if pd.notna(x) and str(x).strip() != "" and str(x).replace('.0','').isdigit() else None)
    df['NPI'] = df['NPI'].astype('Int64')
    
    # Separate matched and unmatched/excluded rows
    matched_df = df[df['NPI'].notna()].copy()
    unmatched_df = df[df['NPI'].isna()].copy()
    
    # Deduplicate matched rows by NPI, keeping the first occurrence
    matched_df = matched_df.drop_duplicates(subset=['NPI'], keep='first')
    
    # Re-combine
    final_df = pd.concat([matched_df, unmatched_df], ignore_index=True)
    
    # 1. Add consecutive ID number starting from 1
    final_df['ID'] = range(1, len(final_df) + 1)

    # Clean and format phone number helper
    def clean_and_format_phone(phone_str):
        if not phone_str or pd.isna(phone_str) or str(phone_str).strip().upper() in ['N/A', 'NAN', '']:
            return 'N/A'
        p_str = re.sub(r'\D', '', str(phone_str))
        if len(p_str) == 11 and p_str.startswith('1'):
            p_str = p_str[1:]
        if len(p_str) == 10:
            return f"{p_str[:3]}-{p_str[3:6]}-{p_str[6:]}"
        return str(phone_str).strip()

    # Load TopLine clinics JSON for dynamic parsing
    clinics_path = "scraped_texts/4_topline_md_clinics.json"
    clinics_list = []
    if os.path.exists(clinics_path):
        try:
            with open(clinics_path, "r", encoding="utf-8") as f:
                clinics_list = json.load(f)
        except Exception as e:
            print(f"Warning: Failed to load TopLine clinics JSON: {e}")

    def get_scraped_details(row, clinics_list):
        platform = str(row.get('Platform/Practice', '')).strip()
        source = str(row.get('Source of Information', '')).strip()
        
        # Defaults
        phone = 'N/A'
        address = 'N/A'
        
        if platform == "Femwell Group Health":
            m = re.search(r'\(([^)]+)\)', source)
            clinic_title = m.group(1).strip() if m else ''
            
            def clean_title(title_str):
                if not title_str:
                    return ""
                title_str = re.sub(r'&#\d+;', '', title_str)
                title_str = re.sub(r'[^a-zA-Z0-9]', '', title_str).lower()
                return title_str
            
            cleaned_search = clean_title(clinic_title)
            matched_clinic = None
            for c in clinics_list:
                if clean_title(c.get('title', {}).get('rendered', '')) == cleaned_search:
                    matched_clinic = c
                    break
            
            if matched_clinic:
                phone = matched_clinic.get('clinic_phone', 'N/A')
                address = matched_clinic.get('street', 'N/A')
            else:
                phone = '(305) 273-0400'
                address = '3200 Ponce de Leon Blvd, Coral Gables, FL 33134'
                
        # Clean and format phone
        phone = clean_and_format_phone(phone)
        return pd.Series([phone, address.strip() if pd.notna(address) else 'N/A'])

    final_df[['Scraped Phone', 'Scraped Address']] = final_df.apply(
        lambda r: get_scraped_details(r, clinics_list), axis=1
    )

    
    # Time Zone mapping dictionary
    STATE_TIMEZONES = {
        'ME': 'Eastern', 'NH': 'Eastern', 'VT': 'Eastern', 'MA': 'Eastern', 'RI': 'Eastern', 'CT': 'Eastern',
        'NY': 'Eastern', 'NJ': 'Eastern', 'PA': 'Eastern', 'DE': 'Eastern', 'MD': 'Eastern', 'DC': 'Eastern',
        'VA': 'Eastern', 'WV': 'Eastern', 'NC': 'Eastern', 'SC': 'Eastern', 'GA': 'Eastern', 'FL': 'Eastern',
        'MI': 'Eastern', 'OH': 'Eastern', 'KY': 'Eastern', 'TN': 'Eastern', 'IN': 'Eastern',
        'IL': 'Central', 'WI': 'Central', 'MN': 'Central', 'IA': 'Central', 'MO': 'Central', 'AR': 'Central',
        'LA': 'Central', 'MS': 'Central', 'AL': 'Central', 'ND': 'Central', 'SD': 'Central', 'NE': 'Central',
        'KS': 'Central', 'OK': 'Central', 'TX': 'Central',
        'CO': 'Mountain', 'WY': 'Mountain', 'MT': 'Mountain', 'ID': 'Mountain', 'UT': 'Mountain',
        'NM': 'Mountain', 'AZ': 'Mountain',
        'WA': 'Pacific', 'OR': 'Pacific', 'CA': 'Pacific', 'NV': 'Pacific',
        'AK': 'Alaska', 'HI': 'Hawaii'
    }
    
    def get_timezone(row):
        state = row.get('NPPES State')
        if pd.isna(state) or str(state).strip() == '' or str(state).strip().upper() == 'N/A':
            state = row.get('Input State')
        if pd.notna(state):
            state_clean = str(state).strip().upper()
            return STATE_TIMEZONES.get(state_clean, 'N/A')
        return 'N/A'
        
    final_df['Time Zone'] = final_df.apply(get_timezone, axis=1)
    
    # 2. Add Composite Details column: id number, Dr First name and Last name, phone number, phone number, practice state, NPI number, id number
    def get_composite_details(row):
        row_id = str(row['ID'])
        first = str(row.get('Parsed First Name', ''))
        last = str(row.get('Parsed Last Name', ''))
        if first.lower() == 'nan' or not first.strip():
            first = ""
        if last.lower() == 'nan' or not last.strip():
            last = ""
            
        if first and last:
            doc_name = f"Dr {first.strip()} {last.strip()}"
        else:
            prov_name = str(row.get('Provider Name', ''))
            clean_prov = re.sub(r'^(Dr\.|Doctor|Dr)\s+', '', prov_name, flags=re.IGNORECASE).strip()
            doc_name = f"Dr {clean_prov}"
            
        # Initial hierarchy: Scraped Phone -> NPPES Phone
        phone = str(row.get('Scraped Phone', ''))
        if phone == 'N/A' or not phone.strip() or phone.lower() == 'nan':
            phone = str(row.get('NPPES Phone', ''))
        if phone.lower() == 'nan' or not phone.strip():
            phone = 'N/A'
            
        state = str(row.get('NPPES State', ''))
        if state.lower() == 'nan' or not state.strip() or state.upper() == 'N/A':
            state = str(row.get('Input State', ''))
            
        npi = row.get('NPI')
        if pd.notna(npi):
            npi_str = str(int(npi))
        else:
            npi_str = 'N/A'
            
        return f"{row_id}, {doc_name}, {phone}, {phone}, {state}, {npi_str}, {row_id}"
        
    final_df['Composite Details'] = final_df.apply(get_composite_details, axis=1)

    
    # Load canonical ABOG file to map subspecialty
    abog_path = os.environ.get(
        "PE_ABOG_CROSSWALK", os.path.expanduser("~/Desktop/canonical_abog_npi_LATEST.csv")
    )
    abog_npi_mapping = {}
    abog_name_mapping = {}
    if os.path.exists(abog_path):
        print(f"Loading canonical ABOG file from {abog_path}...")
        try:
            abog_df = pd.read_csv(abog_path)
            abog_df = abog_df.dropna(subset=['npi'])
            for idx, row in abog_df.iterrows():
                try:
                    npi_val = int(row['npi'])
                    subspec = str(row['subspecialty']).strip()
                    if subspec == 'MIG':
                        subspec = 'MIGS'
                    abog_npi_mapping[npi_val] = subspec
                    
                    # Normalize name parts to populate fallback mappings
                    name_raw = str(row['physician_name']).upper()
                    # Remove periods first so M.D. becomes MD and can be filtered out
                    name_clean = name_raw.replace('.', '')
                    clean_name = re.sub(r'[^A-Z\s]', ' ', name_clean)
                    tokens = clean_name.split()
                    # Ignore single letter tokens (middle initials) and common credentials
                    filtered_tokens = [t for t in tokens if len(t) > 1 and t not in {'MD', 'DO', 'PHD', 'FACS', 'FACOG', 'OBGYN', 'MBBS', 'FACOOG', 'FACOFP'}]
                    if len(filtered_tokens) >= 2:
                        first_t = filtered_tokens[0]
                        last_t = filtered_tokens[-1]
                        state_t = str(row.get('state', '')).strip().upper()
                        
                        # Primary fallback key: (first_name, last_name, state)
                        abog_name_mapping[(first_t, last_t, state_t)] = subspec
                        # Secondary fallback key: (first_name, last_name)
                        abog_name_mapping[(first_t, last_t)] = subspec
                except:
                    continue
            print(f"Loaded {len(abog_npi_mapping)} NPI and {len(abog_name_mapping)} name-based mappings from ABOG.")
        except Exception as e:
            print(f"Warning: Failed to load ABOG subspecialty mapping: {e}")
            
    def get_subspecialty(row):
        npi = row.get('NPI')
        first = str(row.get('Parsed First Name', '')).strip().upper()
        last = str(row.get('Parsed Last Name', '')).strip().upper()
        state = str(row.get('NPPES State', '')).strip().upper()
        if state == 'NAN' or state == 'N/A' or not state:
            state = str(row.get('Input State', '')).strip().upper()
            
        # 1. Direct NPI match
        if pd.notna(npi):
            try:
                npi_int = int(npi)
                if npi_int in abog_npi_mapping:
                    return abog_npi_mapping[npi_int]
            except:
                pass
                
        # 2. Name + State match fallback
        if first and last and state:
            key_state = (first, last, state)
            if key_state in abog_name_mapping:
                return abog_name_mapping[key_state]
                
        # 3. Name-only match fallback
        if first and last:
            key_name = (first, last)
            if key_name in abog_name_mapping:
                return abog_name_mapping[key_name]
                
        # 4. DO AOBOG certification fallback
        if pd.notna(npi):
            nppes_creds = str(row.get('NPPES Credentials', '')).upper()
            input_creds = str(row.get('Input Credentials', '')).upper()
            is_do = 'DO' in nppes_creds or 'D.O.' in nppes_creds or 'DO' in input_creds or 'D.O.' in input_creds
            
            tax = str(row.get('NPPES Taxonomy', '')).strip().upper()
            is_obgyn = tax.startswith('207V')
            
            if is_do and is_obgyn:
                if tax == '207VE0102X':
                    return 'Reproductive Endocrinology/Infertility'
                else:
                    return 'Generalist'
                    
        return 'N/A'
        
    final_df['Subspecialty'] = final_df.apply(get_subspecialty, axis=1)
    
    # Enrich dataset with local DuckDB NPI history, education, and demographic details
    import duckdb
    import subprocess
    import tempfile
    
    from pe_paths import nber_warehouse_path
    try:
        db_path = nber_warehouse_path()
    except (FileNotFoundError, RuntimeError) as exc:
        # Skipping enrichment is the pre-existing behaviour when the drive is
        # absent. Say so loudly: a silently unenriched cohort looks identical to
        # an enriched one downstream.
        print(f"WARNING: skipping DuckDB enrichment -- {exc}")
        db_path = ""
    # Optional gender-inference-from-name script; not part of this repo and
    # machine-specific, so it must be pointed at explicitly. Enrichment below
    # already checks os.path.exists() and skips silently when unset/absent.
    r_script_path = os.environ.get("PE_GENDER_INFER_R_SCRIPT", "")
    
    if os.path.exists(db_path):
        print(f"Connecting to DuckDB at {db_path}...")
        try:
            con = duckdb.connect(db_path, read_only=True)
            
            # Extract unique matched NPIs
            matched_npis = final_df['NPI'].dropna().unique()
            npi_strs = [str(int(float(n))) for n in matched_npis]
            
            if npi_strs:
                # Query NPPES enumeration date and gender
                npi_list_str = ",".join([f"'{n}'" for n in npi_strs])
                nppes_query = f"""
                SELECT npi, MIN(npi_enumeration_date) as npi_enumeration_date, ANY_VALUE(gender) as gender
                FROM credentials.temporal_all_years_fixed
                WHERE npi IN ({npi_list_str})
                GROUP BY npi
                """
                nppes_data = con.execute(nppes_query).fetchdf()
                nppes_map = dict(zip(nppes_data['npi'], nppes_data['npi_enumeration_date']))
                nppes_gender_map = dict(zip(nppes_data['npi'], nppes_data['gender']))
                
                # Query DAC medical school, graduation year, gender, facility name, group size, telehealth, assignment, address, and phone
                npi_ints = [int(n) for n in npi_strs]
                npi_ints_str = ",".join([str(n) for n in npi_ints])
                dac_query = f"""
                SELECT NPI, ANY_VALUE(Med_sch) as Med_sch, ANY_VALUE(Grd_yr) as Grd_yr,
                       ANY_VALUE(gndr) as gndr, ANY_VALUE("Facility Name") as facility_name, ANY_VALUE(num_org_mem) as num_org_mem,
                       ANY_VALUE(Telehlth) as Telehlth, ANY_VALUE(ind_assgn) as ind_assgn,
                       ANY_VALUE(adr_ln_1) as adr_ln_1, ANY_VALUE(adr_ln_2) as adr_ln_2,
                       ANY_VALUE("City/Town") as city, ANY_VALUE(State) as state, ANY_VALUE("ZIP Code") as zip_code,
                       ANY_VALUE("Telephone Number") as phone
                FROM main."doctors_and_clinicians_05_2024_DAC_NationalDownloadableFile_csv_6"
                WHERE NPI IN ({npi_ints_str})
                GROUP BY NPI
                """
                dac_data = con.execute(dac_query).fetchdf()
                dac_data['npi_str'] = dac_data['NPI'].astype(str)
                dac_med_sch_map = dict(zip(dac_data['npi_str'], dac_data['Med_sch']))
                dac_grd_yr_map = dict(zip(dac_data['npi_str'], dac_data['Grd_yr']))
                dac_gender_map = dict(zip(dac_data['npi_str'], dac_data['gndr']))
                dac_facility_map = dict(zip(dac_data['npi_str'], dac_data['facility_name']))
                dac_org_mem_map = dict(zip(dac_data['npi_str'], dac_data['num_org_mem']))
                dac_telehlth_map = dict(zip(dac_data['npi_str'], dac_data['Telehlth']))
                dac_ind_assgn_map = dict(zip(dac_data['npi_str'], dac_data['ind_assgn']))
                dac_adr1_map = dict(zip(dac_data['npi_str'], dac_data['adr_ln_1']))
                dac_adr2_map = dict(zip(dac_data['npi_str'], dac_data['adr_ln_2']))
                dac_city_map = dict(zip(dac_data['npi_str'], dac_data['city']))
                dac_state_map = dict(zip(dac_data['npi_str'], dac_data['state']))
                dac_zip_map = dict(zip(dac_data['npi_str'], dac_data['zip_code']))
                dac_phone_map = dict(zip(dac_data['npi_str'], dac_data['phone']))
                
                # Query open payments activity
                op_query = f"""
                SELECT npi, ANY_VALUE(years_with_payments) as years_with_payments, ANY_VALUE(last_payment_year) as last_payment_year
                FROM credentials.open_payments_activity
                WHERE npi IN ({npi_list_str})
                GROUP BY npi
                """
                try:
                    op_data = con.execute(op_query).fetchdf()
                    op_years_map = dict(zip(op_data['npi'], op_data['years_with_payments']))
                    op_last_year_map = dict(zip(op_data['npi'], op_data['last_payment_year']))
                except Exception as e:
                    print(f"Warning: Failed to query open_payments_activity: {e}")
                    op_years_map = {}
                    op_last_year_map = {}
                    
                # Query provider clinical activity
                activity_query = f"""
                SELECT npi, ANY_VALUE(last_active_year) as last_active_year
                FROM credentials.provider_activity
                WHERE npi IN ({npi_list_str})
                GROUP BY npi
                """
                try:
                    activity_data = con.execute(activity_query).fetchdf()
                    activity_map = dict(zip(activity_data['npi'], activity_data['last_active_year']))
                except Exception as e:
                    print(f"Warning: Failed to query provider_activity: {e}")
                    activity_map = {}
            else:
                nppes_map = {}
                nppes_gender_map = {}
                dac_med_sch_map = {}
                dac_grd_yr_map = {}
                dac_gender_map = {}
                dac_facility_map = {}
                dac_org_mem_map = {}
                dac_telehlth_map = {}
                dac_ind_assgn_map = {}
                dac_adr1_map = {}
                dac_adr2_map = {}
                dac_city_map = {}
                dac_state_map = {}
                dac_zip_map = {}
                dac_phone_map = {}
                op_years_map = {}
                op_last_year_map = {}
                activity_map = {}
                
            con.close()
            
            # Map values to the final dataframe
            def get_npi_str(row):
                n = row.get('NPI')
                if pd.isna(n):
                    return None
                return str(int(float(n)))
                
            final_df['npi_str_temp'] = final_df.apply(get_npi_str, axis=1)
            
            # 1. NPPES Enumeration Date
            final_df['NPPES Enumeration Date'] = final_df['npi_str_temp'].map(
                lambda x: str(nppes_map[x]) if x in nppes_map and pd.notna(nppes_map[x]) else 'N/A'
            )
            
            # 2. State to ACOG District Mapping
            STATE_TO_ACOG = {
                'AL': 7, 'AK': 8, 'AZ': 8, 'AR': 7, 'CA': 9, 'CO': 8, 'CT': 1, 'DE': 3, 'DC': 4,
                'FL': 12, 'GA': 4, 'HI': 8, 'ID': 8, 'IL': 6, 'IN': 5, 'IA': 6, 'KS': 7, 'KY': 5,
                'LA': 7, 'ME': 1, 'MD': 4, 'MA': 1, 'MI': 5, 'MN': 6, 'MS': 7, 'MO': 7, 'MT': 8,
                'NE': 6, 'NV': 8, 'NH': 1, 'NJ': 3, 'NM': 8, 'NY': 2, 'NC': 4, 'ND': 6, 'OH': 5,
                'OK': 7, 'OR': 8, 'PA': 3, 'PR': 4, 'RI': 1, 'SC': 4, 'SD': 6, 'TN': 7, 'TX': 11,
                'UT': 8, 'VT': 1, 'VA': 4, 'WA': 8, 'WV': 4, 'WI': 6, 'WY': 6,
                'AE': 4, 'AP': 8, 'GU': 8, 'VI': 4
            }
            
            def get_acog_district(row):
                state = row.get('NPPES State')
                if pd.isna(state) or not state or str(state).strip() == '' or str(state).upper() == 'N/A':
                    state = row.get('Input State')
                if pd.isna(state) or not state:
                    return 'N/A'
                st_val = str(state).strip().upper()
                return STATE_TO_ACOG.get(st_val, 'N/A')
                
            final_df['ACOG District'] = final_df.apply(get_acog_district, axis=1)
            
            # 3. Medical School and Graduation Year
            final_df['Medical School'] = final_df['npi_str_temp'].map(
                lambda x: str(dac_med_sch_map[x]).strip().title() if x in dac_med_sch_map and pd.notna(dac_med_sch_map[x]) else 'N/A'
            )
            final_df['Medical School'] = final_df['Medical School'].map(
                lambda x: 'N/A' if x.lower() == 'nan' or x.strip() == '' else x
            )
            
            def get_grad_year(x):
                if x in dac_grd_yr_map and pd.notna(dac_grd_yr_map[x]):
                    try:
                        return int(dac_grd_yr_map[x])
                    except:
                        pass
                return 'N/A'
            final_df['Graduation Year'] = final_df['npi_str_temp'].map(get_grad_year)
            
            # 4. US vs. IMG Classification
            def classify_us_vs_img(school_name):
                if pd.isna(school_name) or str(school_name).strip() == '' or str(school_name).strip().upper() in ['N/A', 'NAN']:
                    return 'N/A'
                school_upper = str(school_name).upper().strip()
                IMG_KEYWORDS = [
                    'ST. GEORGE', 'ROSS UNIVERSITY', 'AMERICAN UNIVERSITY OF THE CARIBBEAN', 
                    'AMERICAN UNIVERSITY OF ANTIGUA', 'SABA UNIVERSITY', 'UNIVERSIDAD', 
                    'FACULTAD', 'INSTITUTO', 'SCHOOL OF MEDICINE OF LUDHIANA', 'KASTURBA',
                    'DOWNSTATE', 'GUADALAJARA', 'FOREIGN', 'INTERNATIONAL', 'IMG', 
                    'ST GEORGE', 'DOMINICA', 'MEXICO', 'GRENADA', 'PHILIPPINES', 'INDIA', 
                    'PAKISTAN', 'EGYPT', 'COLOMBIA', 'LONDON', 'CARIBBEAN', 'ANTIGUA', 
                    'SABA', 'UNIVERSITE', 'CHINA', 'TAIWAN', 'KOREA', 'ISRAEL', 'ITALY', 
                    'IRELAND', 'DUBLIN', 'ROYAL COLLEGE', 'NIGERIA', 'POLAND', 'BEIRUT',
                    'SYRIA', 'JORDAN', 'BAGHDAD', 'IRAQ', 'IRAN', 'TEHRAN', 'SAUDI', 
                    'GUATEMALA', 'HONDURAS', 'COSTA RICA', 'PANAMA', 'VENEZUELA', 'PERU', 
                    'ECUADOR', 'BOLIVIA', 'CHILE', 'ARGENTINA', 'BRAZIL', 'SPAIN', 
                    'PORTUGAL', 'FRANCE', 'GERMANY', 'RUSSIA', 'UKRAINE', 'AUSTRALIA', 
                    'NEW ZEALAND', 'SOUTH AFRICA'
                ]
                for kw in IMG_KEYWORDS:
                    if kw in school_upper:
                        return 'IMG'
                return 'US/Canada'
                
            final_df['US vs. IMG'] = final_df['Medical School'].map(classify_us_vs_img)
            
            import datetime
            CURRENT_YEAR = datetime.datetime.now().year
            # 5. Years in Practice Calculation
            def get_years_in_practice(row):
                grad_yr = row.get('Graduation Year')
                if isinstance(grad_yr, int):
                    return CURRENT_YEAR - grad_yr
                enum_dt = row.get('NPPES Enumeration Date')
                if pd.notna(enum_dt) and enum_dt != 'N/A' and '-' in str(enum_dt):
                    try:
                        enum_yr = int(str(enum_dt).split('-')[0])
                        return CURRENT_YEAR - enum_yr
                    except (ValueError, IndexError, KeyError):
                        pass
                return 'N/A'
            final_df['Years in Practice'] = final_df.apply(get_years_in_practice, axis=1)
            
            # 5b. Telehealth, Medicare Assignment, Last Active Year, Open Payments, and MD vs. DO honorific mapping
            final_df['Open Payments Years'] = final_df['npi_str_temp'].map(
                lambda x: int(op_years_map[x]) if x in op_years_map and pd.notna(op_years_map[x]) else 'N/A'
            )
            final_df['Open Payments Last Year'] = final_df['npi_str_temp'].map(
                lambda x: int(op_last_year_map[x]) if x in op_last_year_map and pd.notna(op_last_year_map[x]) else 'N/A'
            )
            final_df['Telehealth'] = final_df['npi_str_temp'].map(
                lambda x: str(dac_telehlth_map[x]) if x in dac_telehlth_map and pd.notna(dac_telehlth_map[x]) else 'N/A'
            )
            final_df['Medicare Assignment'] = final_df['npi_str_temp'].map(
                lambda x: str(dac_ind_assgn_map[x]) if x in dac_ind_assgn_map and pd.notna(dac_ind_assgn_map[x]) else 'N/A'
            )
            final_df['Last Active Year'] = final_df['npi_str_temp'].map(
                lambda x: int(activity_map[x]) if x in activity_map and pd.notna(activity_map[x]) else 'N/A'
            )
            
            def get_md_vs_do(row):
                creds = []
                for field in ['Input Credentials', 'NPPES Credentials', 'Provider Name']:
                    val = str(row.get(field, '')).upper().replace('.', '')
                    creds.append(val)
                joined_creds = " ".join(creds)
                
                if re.search(r'\bDO\b|\bD\s*O\b', joined_creds):
                    return 'DO'
                elif re.search(r'\bMD\b|\bM\s*D\b|\bMEDICAL\b|\bPHYSICIAN\b', joined_creds):
                    return 'MD'
                
                if pd.notna(row.get('NPI')):
                    return 'MD'
                return 'N/A'
                
            final_df['MD vs. DO'] = final_df.apply(get_md_vs_do, axis=1)
            
            # DAC clinical fields mapping
            final_df['DAC Facility Name'] = final_df['npi_str_temp'].map(
                lambda x: str(dac_facility_map[x]).strip().title() if x in dac_facility_map and pd.notna(dac_facility_map[x]) else 'N/A'
            )
            final_df['DAC Address 1'] = final_df['npi_str_temp'].map(
                lambda x: str(dac_adr1_map[x]).strip().upper() if x in dac_adr1_map and pd.notna(dac_adr1_map[x]) else 'N/A'
            )
            final_df['DAC Address 2'] = final_df['npi_str_temp'].map(
                lambda x: str(dac_adr2_map[x]).strip().upper() if x in dac_adr2_map and pd.notna(dac_adr2_map[x]) else 'N/A'
            )
            final_df['DAC City'] = final_df['npi_str_temp'].map(
                lambda x: str(dac_city_map[x]).strip().title() if x in dac_city_map and pd.notna(dac_city_map[x]) else 'N/A'
            )
            final_df['DAC State'] = final_df['npi_str_temp'].map(
                lambda x: str(dac_state_map[x]).strip().upper() if x in dac_state_map and pd.notna(dac_state_map[x]) else 'N/A'
            )
            
            def clean_dac_zip(x):
                if x in dac_zip_map and pd.notna(dac_zip_map[x]):
                    z_val = str(dac_zip_map[x]).split('.')[0].strip()
                    if len(z_val) > 5:
                        return z_val.zfill(9)[:5]
                    return z_val.zfill(5)
                return 'N/A'
            final_df['DAC Zip'] = final_df['npi_str_temp'].map(clean_dac_zip)
            
            def format_phone(x):
                if x in dac_phone_map and pd.notna(dac_phone_map[x]):
                    try:
                        p_str = str(int(float(dac_phone_map[x])))
                        if len(p_str) == 10:
                            return f"{p_str[:3]}-{p_str[3:6]}-{p_str[6:]}"
                        return p_str
                    except:
                        return str(dac_phone_map[x])
                return 'N/A'
            final_df['DAC Phone'] = final_df['npi_str_temp'].map(format_phone)
            
            # 6. Gender Enrichment (Database + R Name inference + Live NPI query)
            first_names_to_infer = []
            final_df['Gender'] = pd.NA
            
            # Load existing genders from CSV to avoid live queries on subsequent runs
            existing_gender_map = {}
            output_path = "pe_obgyn_providers_npi.csv"
            if os.path.exists(output_path):
                try:
                    exist_df = pd.read_csv(output_path, keep_default_na=False)
                    for _, r in exist_df.iterrows():
                        n_val = r.get('NPI')
                        g_val = r.get('Gender')
                        if pd.notna(n_val) and n_val != '' and n_val != 'N/A' and g_val and g_val != 'N/A' and g_val != '':
                            try:
                                n_str = str(int(float(n_val)))
                                existing_gender_map[n_str] = g_val
                            except:
                                pass
                except Exception as e:
                    print(f"Warning: Failed to load existing genders from CSV: {e}")

            # Collect NPIs that need live query
            live_query_npis = []
            for idx, row in final_df.iterrows():
                npi_str = row['npi_str_temp']
                if not npi_str:
                    continue
                gender_val = None
                if npi_str in nppes_gender_map and pd.notna(nppes_gender_map[npi_str]):
                    gender_val = nppes_gender_map[npi_str]
                elif npi_str in dac_gender_map and pd.notna(dac_gender_map[npi_str]):
                    gender_val = dac_gender_map[npi_str]
                elif npi_str in existing_gender_map:
                    gender_val = existing_gender_map[npi_str]
                    
                if gender_val and str(gender_val).strip().upper() in ['M', 'MALE', 'F', 'FEMALE']:
                    continue
                else:
                    live_query_npis.append(npi_str)
                    
            # Run live NPPES API queries for missing genders
            live_resolved = {}
            if live_query_npis:
                import requests
                import time
                print(f"Resolving {len(live_query_npis)} missing genders from live NPPES API...")
                for q_idx, npi_str in enumerate(live_query_npis):
                    url = f"https://npiregistry.cms.hhs.gov/api/?version=2.1&number={npi_str}"
                    try:
                        r = requests.get(url, timeout=5)
                        if r.status_code == 200:
                            res_data = r.json()
                            if 'results' in res_data and res_data['results']:
                                basic = res_data['results'][0].get('basic', {})
                                sex = basic.get('sex')
                                if sex and sex in ['M', 'F']:
                                    live_resolved[npi_str] = 'Male' if sex == 'M' else 'Female'
                    except:
                        pass
                    if q_idx > 0 and q_idx % 50 == 0:
                        time.sleep(0.5)

            # Assign gender
            for idx, row in final_df.iterrows():
                npi_str = row['npi_str_temp']
                gender_val = None
                if npi_str:
                    if npi_str in nppes_gender_map and pd.notna(nppes_gender_map[npi_str]):
                        gender_val = nppes_gender_map[npi_str]
                    elif npi_str in dac_gender_map and pd.notna(dac_gender_map[npi_str]):
                        gender_val = dac_gender_map[npi_str]
                    elif npi_str in existing_gender_map:
                        gender_val = existing_gender_map[npi_str]
                    elif npi_str in live_resolved:
                        gender_val = live_resolved[npi_str]
                        
                if gender_val and str(gender_val).strip().upper() in ['M', 'MALE']:
                    final_df.at[idx, 'Gender'] = 'Male'
                elif gender_val and str(gender_val).strip().upper() in ['F', 'FEMALE']:
                    final_df.at[idx, 'Gender'] = 'Female'
                else:
                    # Needs name inference (unmatched or unresolved)
                    fname = row.get('Parsed First Name')
                    if not fname or pd.isna(fname) or str(fname).strip() == '' or str(fname).upper() == 'N/A':
                        pname = row.get('Provider Name')
                        if pname and pd.notna(pname):
                            parts = str(pname).replace("Dr.", "").replace("MD", "").replace("DO", "").strip().split()
                            if parts:
                                fname = parts[0]
                    if fname and pd.notna(fname) and str(fname).strip():
                        first_names_to_infer.append(str(fname).strip().title())
            
            unique_first_names = list(set(first_names_to_infer))
            inferred_genders = {}
            if unique_first_names and os.path.exists(r_script_path):
                print(f"Calling R name-based gender inference for {len(unique_first_names)} names...")
                with tempfile.NamedTemporaryFile(mode='w', suffix='.csv', delete=False) as f_in:
                    input_path = f_in.name
                    f_in.write("name\n")
                    for name in unique_first_names:
                        f_in.write(f"{name}\n")
                output_path = tempfile.mktemp(suffix='.csv')
                try:
                    cmd = ["Rscript", r_script_path, input_path, output_path]
                    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    if os.path.exists(output_path):
                        res_df = pd.read_csv(output_path)
                        inferred_genders = dict(zip(res_df['name'], res_df['gender']))
                except Exception as e:
                    print(f"Warning: R name-based gender inference failed: {e}")
                finally:
                    try:
                        os.remove(input_path)
                        if os.path.exists(output_path):
                            os.remove(output_path)
                    except:
                        pass
                        
            # Map gender back
            for idx, row in final_df.iterrows():
                if pd.notna(row.get('Gender')):
                    continue
                fname = row.get('Parsed First Name')
                if not fname or pd.isna(fname) or str(fname).strip() == '' or str(fname).upper() == 'N/A':
                    pname = row.get('Provider Name')
                    if pname and pd.notna(pname):
                        parts = str(pname).replace("Dr.", "").replace("MD", "").replace("DO", "").strip().split()
                        if parts:
                            fname = parts[0]
                if fname and pd.notna(fname):
                    fn_title = str(fname).strip().title()
                    final_df.at[idx, 'Gender'] = inferred_genders.get(fn_title, 'N/A')
                else:
                    final_df.at[idx, 'Gender'] = 'N/A'
            final_df['Gender'] = final_df['Gender'].fillna('N/A')
            
            # 7. Practice Setting classification
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
            PRIVATE_PATTERNS = [
                "LLC", "PLLC", "PC", "PA", "MD PA", "LLP", "INC", "PROFESSIONAL CORPORATION",
                "MD INC", "DO PC", "ASSOCIATES", "PRIVATE PRACTICE", "OBSTETRICS", "GYNECOLOGY",
                "WOMEN'S HEALTH", "OBSTETRICS AND GYNECOLOGY", "FAMILY MEDICINE", "FAMILY PRACTICE",
                "CLINIC", "UWH", "VITALMD", "WOMEN'S CARE", "AXIA", "US FERTILITY", "CCRM", "KINDBODY"
            ]
            COMMUNITY_PATTERNS = [
                "HOSPITAL", "MEDICAL CENTER", "HEALTH SYSTEM", "HEALTH CARE", "HEALTHCARE",
                "COMMUNITY HEALTH"
            ]
            
            def get_practice_setting(row):
                npi_str = row['npi_str_temp']
                facility_name = None
                org_size = None
                if npi_str in dac_facility_map and pd.notna(dac_facility_map[npi_str]):
                    facility_name = str(dac_facility_map[npi_str]).upper().strip()
                if npi_str in dac_org_mem_map and pd.notna(dac_org_mem_map[npi_str]):
                    try:
                        org_size = int(dac_org_mem_map[npi_str])
                    except:
                        pass
                
                # Check facility name patterns
                if facility_name:
                    if org_size and org_size >= 200:
                        if any(kw in facility_name for kw in ["HOSPITAL", "MEDICAL CENTER", "HEALTH SYSTEM", "HEALTH CARE"]):
                            if any(kw in facility_name for kw in ["UNIVERSITY", "MEDICAL SCHOOL", "TEACHING"]):
                                return "Academic"
                            else:
                                return "Community"
                    if any(kw in facility_name for kw in ACADEMIC_PATTERNS):
                        if not any(kw in facility_name for kw in ["LLC", "PC", "PLLC", "PA", "LLP", "INC"]):
                            return "Academic"
                    if any(kw in facility_name for kw in GOVERNMENT_PATTERNS):
                        if any(kw in facility_name for kw in ["ARMY", "NAVY", "AIR FORCE", "MILITARY", "USAF", "USN", "DEFENSE"]):
                            return "Military"
                        return "Government"
                    if any(kw in facility_name for kw in PRIVATE_PATTERNS):
                        return "Private Practice"
                    if any(kw in facility_name for kw in COMMUNITY_PATTERNS):
                        return "Community"
                    if org_size and org_size <= 5:
                        if any(kw in facility_name for kw in ["LLC", "PC", "PLLC", "PA", "INC"]):
                            return "Private Practice"
                            
                # Check platform
                platform = str(row.get('Platform/Practice', '')).upper().strip()
                if platform and platform != 'N/A':
                    if any(kw in platform for kw in ACADEMIC_PATTERNS):
                        return "Academic"
                    if any(kw in platform for kw in PRIVATE_PATTERNS):
                        return "Private Practice"
                    if any(kw in platform for kw in COMMUNITY_PATTERNS):
                        return "Community"
                return "Private Practice"
                
            final_df['Practice Setting'] = final_df.apply(get_practice_setting, axis=1)
            
            # 8. Generate office_id using normalized addresses
            def normalize_office_address(row):
                addr1 = str(row.get('NPPES Address 1', '')).strip().upper()
                city = str(row.get('NPPES City', '')).strip().upper()
                state = str(row.get('NPPES State', '')).strip().upper()
                zip_code = str(row.get('NPPES Zip', '')).strip().upper()
                
                if addr1 == 'N/A' or addr1 == '' or pd.isna(row.get('NPI')):
                    # Treat each unmatched provider as a unique office location
                    return f"UNMATCHED_OFFICE_{row['ID']}"
                    
                # Clean Address 1
                a1 = re.sub(r'[^A-Z0-9\s]', ' ', addr1)
                
                # Strip suite / unit info from Address 1.
                suite_pattern = r'\b(SUITE|STE|UNIT|APT|FLOOR|FL|ROOM|RM|NUMBER|NO|DEPT|SUITES|STES|BLDG|BUILDING)\b.*$'
                a1 = re.sub(suite_pattern, '', a1)
                
                # Also strip any trailing #
                a1 = re.sub(r'#.*$', '', a1)
                
                # Clean whitespace
                a1 = " ".join(a1.split())
                
                # Standardize street suffixes
                street_map = {
                    ' STREET': ' ST', ' AVENUE': ' AVE', ' ROAD': ' RD', ' BOULEVARD': ' BLVD',
                    ' DRIVE': ' DR', ' COURT': ' CT', ' PLACE': ' PL', ' PARKWAY': ' PKWY',
                    ' HIGHWAY': ' HWY', ' LANE': ' LN', ' PLAZA': ' PLZ'
                }
                for k, v in street_map.items():
                    if a1.endswith(k):
                        a1 = a1[:-len(k)] + v
                    a1 = a1.replace(k + ' ', v + ' ')
                    
                # Format Zip Code to 5 digits, handling floats/lost leading zeros
                if zip_code.endswith('.0'):
                    zip_code = zip_code[:-2]
                parts = re.split(r'[-.]', zip_code)
                prefix = parts[0].strip()
                if prefix.isdigit():
                    if len(prefix) > 5:
                        z5 = prefix.zfill(9)[:5]
                    else:
                        z5 = prefix.zfill(5)
                else:
                    z5 = prefix[:5]
                    
                return f"{a1} | {city} | {state} | {z5}"
                
            final_df['office_key_temp'] = final_df.apply(normalize_office_address, axis=1)
            unique_keys = final_df['office_key_temp'].unique()
            key_to_id = {key: f"office_{idx+1}" for idx, key in enumerate(unique_keys)}
            final_df['office_id'] = final_df['office_key_temp'].map(key_to_id)
            final_df = final_df.drop(columns=['office_key_temp'])
            
            final_df['PE_or_Not'] = 'PE'
            
            # Composite Details recalculation moved to the end of script to run globally

            
            final_df = final_df.drop(columns=['npi_str_temp'])
            print("Successfully enriched matched providers with DuckDB educational and demographic details.")
        except Exception as e:
            print(f"Warning: Failed to enrich dataset from DuckDB: {e}")
            final_df['NPPES Enumeration Date'] = 'N/A'
            final_df['Gender'] = 'N/A'
            final_df['ACOG District'] = 'N/A'
            final_df['Practice Setting'] = 'Private Practice'
            final_df['Medical School'] = 'N/A'
            final_df['Graduation Year'] = 'N/A'
            final_df['US vs. IMG'] = 'N/A'
            final_df['Years in Practice'] = 'N/A'
            final_df['MD vs. DO'] = 'N/A'
            final_df['Open Payments Years'] = 'N/A'
            final_df['Open Payments Last Year'] = 'N/A'
            final_df['Telehealth'] = 'N/A'
            final_df['Medicare Assignment'] = 'N/A'
            final_df['Last Active Year'] = 'N/A'
            final_df['DAC Facility Name'] = 'N/A'
            final_df['DAC Address 1'] = 'N/A'
            final_df['DAC Address 2'] = 'N/A'
            final_df['DAC City'] = 'N/A'
            final_df['DAC State'] = 'N/A'
            final_df['DAC Zip'] = 'N/A'
            final_df['DAC Phone'] = 'N/A'
            final_df['office_id'] = 'N/A'
            final_df['PE_or_Not'] = 'PE'
    else:
        print(f"Warning: DuckDB path {db_path} not found. Skipping enrichment.")
        final_df['NPPES Enumeration Date'] = 'N/A'
        final_df['Gender'] = 'N/A'
        final_df['ACOG District'] = 'N/A'
        final_df['Practice Setting'] = 'Private Practice'
        final_df['Medical School'] = 'N/A'
        final_df['Graduation Year'] = 'N/A'
        final_df['US vs. IMG'] = 'N/A'
        final_df['Years in Practice'] = 'N/A'
        final_df['MD vs. DO'] = 'N/A'
        final_df['Open Payments Years'] = 'N/A'
        final_df['Open Payments Last Year'] = 'N/A'
        final_df['Telehealth'] = 'N/A'
        final_df['Medicare Assignment'] = 'N/A'
        final_df['Last Active Year'] = 'N/A'
        final_df['DAC Facility Name'] = 'N/A'
        final_df['DAC Address 1'] = 'N/A'
        final_df['DAC Address 2'] = 'N/A'
        final_df['DAC City'] = 'N/A'
        final_df['DAC State'] = 'N/A'
        final_df['DAC Zip'] = 'N/A'
        final_df['DAC Phone'] = 'N/A'
        final_df['office_id'] = 'N/A'
        final_df['PE_or_Not'] = 'PE'
        
    # Final recalculation of Composite Details using the hierarchy: Scraped Phone -> DAC Phone -> NPPES Phone
    def get_best_composite_details(row):
        row_id = str(row['ID'])
        first = str(row.get('Parsed First Name', ''))
        last = str(row.get('Parsed Last Name', ''))
        if first.lower() == 'nan' or not first.strip():
            first = ""
        if last.lower() == 'nan' or not last.strip():
            last = ""
            
        if first and last:
            doc_name = f"Dr {first.strip()} {last.strip()}"
        else:
            prov_name = str(row.get('Provider Name', ''))
            clean_prov = re.sub(r'^(Dr\.|Doctor|Dr)\s+', '', prov_name, flags=re.IGNORECASE).strip()
            doc_name = f"Dr {clean_prov}"
            
        # Hierarchy: Scraped Phone -> DAC Phone -> NPPES Phone
        phone = str(row.get('Scraped Phone', ''))
        if phone == 'N/A' or not phone.strip() or phone.lower() == 'nan':
            phone = str(row.get('DAC Phone', ''))
        if phone == 'N/A' or not phone.strip() or phone.lower() == 'nan':
            phone = str(row.get('NPPES Phone', ''))
        if phone.lower() == 'nan' or not phone.strip():
            phone = 'N/A'
            
        state = str(row.get('NPPES State', ''))
        if state.lower() == 'nan' or not state.strip() or state.upper() == 'N/A':
            state = str(row.get('Input State', ''))
            
        npi = row.get('NPI')
        if pd.notna(npi):
            npi_str = str(int(npi))
        else:
            npi_str = 'N/A'
            
        return f"{row_id}, {doc_name}, {phone}, {phone}, {state}, {npi_str}, {row_id}"
        
    final_df['Composite Details'] = final_df.apply(get_best_composite_details, axis=1)

    # Reorder columns
    cols = [
        'ID', 'Provider Name', 'Parsed First Name', 'Parsed Last Name', 'Input Credentials', 'Input State',
        'Platform/Practice', 'PE Owner', 'Acquisition Year', 'Source of Information', 'Scrape Run Time',
        'NPI', 'NPPES Name', 'NPPES Credentials', 'NPPES Taxonomy', 'Subspecialty', 'NPPES Phone', 
        'NPPES Address 1', 'NPPES Address 2', 'NPPES City', 'NPPES State', 'NPPES Zip',
        'Scraped Phone', 'Scraped Address',
        'Time Zone', 'Composite Details', 'Match Quality', 'Match Score', 'NPI Last Updated',
        'NPPES Enumeration Date', 'MD vs. DO', 'Gender', 'ACOG District', 'Practice Setting',
        'Telehealth', 'Medicare Assignment', 'Last Active Year',
        'Open Payments Years', 'Open Payments Last Year',
        'Medical School', 'Graduation Year', 'US vs. IMG', 'Years in Practice',
        'DAC Facility Name', 'DAC Address 1', 'DAC Address 2', 'DAC City', 'DAC State', 'DAC Zip', 'DAC Phone',
        'office_id', 'PE_or_Not'
    ]

    final_df = final_df[cols]
    
    # Save to CSV
    output_path = "pe_obgyn_providers_npi.csv"
    final_df.to_csv(output_path, index=False)
    
    print("\n=== Matching Pipeline Complete ===")
    print(f"Total entries processed: {len(df)}")
    print(f"Unique matched with NPI: {len(matched_df)}")
    print(f"Total failed/excluded: {len(unmatched_df)}")
    print(f"Saved complete matched dataset to: {output_path}")

