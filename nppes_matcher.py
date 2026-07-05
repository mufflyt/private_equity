#!/usr/bin/env python3
"""
Pipeline for name-parsing providers and matching them to the CMS NPPES (NPI) Registry.
"""
import pandas as pd
import requests
import re
import time

# A list of common provider credentials to strip/identify during parsing
CREDENTIALS_SET = {
    'MD', 'DO', 'CNM', 'NP', 'PA', 'PAC', 'PA-C', 'RN', 'MSN', 'DNP', 'PHD', 
    'FACS', 'FACOG', 'OBGYN', 'OB/GYN', 'MSCE', 'BSN', 'APRN', 'WHNP', 'LPN'
}

def parse_provider_name(name_str):
    """
    Parses a provider name string (e.g., 'Dr. Laxmi A. Kondapalli, MD, MSCE')
    into prefix, first, middle, last, and credentials.
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

    # Split off credentials (normally after commas, e.g., 'Laxmi Kondapalli, MD, MSCE')
    parts = [p.strip() for p in name_str.split(',')]
    core_name = parts[0]
    
    credentials = []
    for part in parts[1:]:
        # check if it is a credential
        clean_part = re.sub(r'[^a-zA-Z-]', '', part)
        if clean_part.upper() in CREDENTIALS_SET:
            credentials.append(clean_part.upper())
            
    # Also check if the core name has credentials at the end without a comma
    name_tokens = core_name.split()
    clean_tokens = []
    for token in name_tokens:
        clean_tok = re.sub(r'[^a-zA-Z-]', '', token)
        if clean_tok.upper() in CREDENTIALS_SET:
            credentials.append(clean_tok.upper())
        else:
            clean_tokens.append(token)
            
    # Reconstruct name without credentials
    name_str = " ".join(clean_tokens)
    
    # Split remaining name into First, Middle, Last
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
        # Check if the last token is a suffix (Jr., III, etc.)
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

def query_nppes_registry(first_name, last_name, state=None, taxonomy_description="Obstetrics & Gynecology"):
    """
    Queries the public NPI Registry API and returns matching records.
    """
    url = "https://npiregistry.cms.hhs.gov/api/"
    params = {
        'version': '2.1',
        'first_name': first_name,
        'last_name': last_name,
        'enumeration_type': 'NPI-1' # Individual providers only
    }
    if state:
        params['state'] = state
        
    try:
        response = requests.get(url, params=params, timeout=10)
        if response.status_code != 200:
            return []
            
        data = response.json()
        results = data.get('results', [])
        
        # If no results with state filter, try searching without state filter as fallback
        if not results and state:
            params.pop('state')
            response = requests.get(url, params=params, timeout=10)
            if response.status_code == 200:
                results = response.json().get('results', [])
                
        return results
    except Exception as e:
        print(f"Error querying NPI API for {first_name} {last_name}: {e}")
        return []

def match_provider_to_npi(name_str, state=None):
    """
    Parses name, queries NPI registry, and finds the best match.
    Excludes mid-level providers (CNM, NP, PA-C) from matching.
    """
    parsed = parse_provider_name(name_str)
    
    # 1. Exclude based on name credentials (CNM, NP, PA-C, etc.)
    EXCLUDED_CREDENTIALS = {'CNM', 'NP', 'PA', 'PAC', 'PA-C', 'RN', 'MSN', 'DNP', 'APRN', 'WHNP', 'LPN', 'BSN'}
    creds_found = [c.strip().upper() for c in parsed['credentials'].split(',') if c.strip()]
    for cred in creds_found:
        if cred in EXCLUDED_CREDENTIALS:
            return {'parsed_name': parsed, 'npi': None, 'match_status': f'Excluded (credential: {cred})'}

    first = parsed['first']
    last = parsed['last']
    
    if not first or not last:
        return {'parsed_name': parsed, 'npi': None, 'match_status': 'Failed parsing'}
        
    results = query_nppes_registry(first, last, state)
    
    if not results:
        return {'parsed_name': parsed, 'npi': None, 'match_status': 'No match found'}
        
    # Best Match Logic
    # 1. Look for taxonomy description matching OB/GYN or fertility
    # 2. Exclude mid-level taxonomies (Midwife, NP, PA)
    # 3. Look for state matching
    # 4. Choose the primary or first result if multiple
    EXCLUDED_TAXONOMY_KEYWORDS = {'midwife', 'nurse practitioner', 'physician assistant', "physician's assistant", 'nurse midwife', 'registered nurse', 'clinical nurse specialist'}
    
    best_match = None
    match_quality = "Name only"
    
    for r in results:
        taxonomies = r.get('taxonomies', [])
        
        # Check if the NPI registry record is a mid-level provider
        is_excluded_taxonomy = False
        is_obgyn = False
        for tax in taxonomies:
            desc = tax.get('desc', '').lower()
            code = tax.get('code', '')
            
            # Exclude by code prefix (363A, 363L, 367A) or description keyword
            if code.startswith('363A') or code.startswith('363L') or code.startswith('367A') or any(k in desc for k in EXCLUDED_TAXONOMY_KEYWORDS):
                is_excluded_taxonomy = True
                break
            
            if any(k in desc for k in ['obstetrics', 'gynecology', 'fertility']):
                is_obgyn = True
                
        if is_excluded_taxonomy:
            continue # Skip this mid-level provider record
            
        address_state = ""
        addresses = r.get('addresses', [])
        for addr in addresses:
            if addr.get('address_purpose') == 'LOCATION':
                address_state = addr.get('state', '')
                break
                
        # Scoring match
        score = 0
        if is_obgyn:
            score += 2
        if state and address_state.upper() == state.upper():
            score += 3
            
        r['_score'] = score
        if best_match is None or score > best_match.get('_score', -1):
            best_match = r
            
    if best_match:
        score = best_match['_score']
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
        
        # Double check if the NPPES credentials contain excluded terms
        clean_nppes_creds = re.sub(r'[^a-zA-Z,\s]', '', nppes_credentials).upper()
        for cred in EXCLUDED_CREDENTIALS:
            if cred in [c.strip() for c in clean_nppes_creds.split(',')]:
                return {'parsed_name': parsed, 'npi': None, 'match_status': f'Excluded (NPPES credential: {cred})'}
                
        # Get location phone number
        phone = ""
        addresses = best_match.get('addresses', [])
        for addr in addresses:
            if addr.get('address_purpose') == 'LOCATION':
                phone = addr.get('telephone_number', '')
                break
                
        return {
            'parsed_name': parsed,
            'npi': npi,
            'nppes_name': nppes_name,
            'nppes_credentials': nppes_credentials,
            'nppes_phone': phone,
            'match_quality': match_quality,
            'match_score': score
        }
        
    return {'parsed_name': parsed, 'npi': None, 'match_status': 'No match found or excluded'}

if __name__ == "__main__":
    # Test dataset of providers from our compiled directory
    test_providers = [
        {"name": "Dr. Laxmi Kondapalli, MD", "state": "CO", "company": "CCRM Fertility"},
        {"name": "Dr. Alvin M. Schoenberger, MD", "state": "MI", "company": "Unified Women's Healthcare"},
        {"name": "Jane Doe, CNM", "state": "FL", "company": "Women's Care (Midwife - Exclude)"},
        {"name": "Mary Smith, NP", "state": "MI", "company": "Together Women's Health (Nurse Practitioner - Exclude)"},
        {"name": "John Davis, PA-C", "state": "IL", "company": "Nova Women's Health Partners (Physician Assistant - Exclude)"},
        {"name": "Dr. Elyse P. Erlich, MD", "state": "IL", "company": "Nova Women's Health Partners"},
        {"name": "Dr. Luis P. Leyva, Jr., MD", "state": "FL", "company": "Femwell/TopLine MD"}
    ]
    
    print("=== NPPES Provider Matcher Test ===")
    
    results_list = []
    for p in test_providers:
        print(f"\nMatching: {p['name']} ({p['state']}) - {p['company']}")
        match = match_provider_to_npi(p['name'], p['state'])
        
        parsed = match.get('parsed_name', {})
        res = {
            'Input Name': p['name'],
            'Input State': p['state'],
            'Input Company': p['company'],
            'Parsed First': parsed.get('first'),
            'Parsed Last': parsed.get('last'),
            'NPI': match.get('npi'),
            'NPPES Name': match.get('nppes_name', 'N/A'),
            'NPPES Credentials': match.get('nppes_credentials', 'N/A'),
            'NPPES Phone': match.get('nppes_phone', 'N/A'),
            'Match Quality': match.get('match_quality', match.get('match_status', 'Failed'))
        }
        results_list.append(res)
        
        # Small delay to respect CMS server
        time.sleep(0.5)
        
    df = pd.DataFrame(results_list)
    print("\n=== Final Matching DataFrame ===")
    print(df.to_string(index=False))
    
    # Save test results
    df.to_csv("/Users/tylermuffly/private_equity/nppes_matching_demo.csv", index=False)
    print("\nSaved demo DataFrame to /Users/tylermuffly/private_equity/nppes_matching_demo.csv")
