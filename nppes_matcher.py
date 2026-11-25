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
    'FACS', 'FACOG', 'OBGYN', 'OB/GYN', 'MSCE', 'BSN', 'APRN', 'WHNP', 'LPN',
    # Extended set unioned in from match_all_providers.py so one shared parser strips
    # everything either pipeline's mid-level exclusion rule needs to see.
    'WHNP-BC', 'FNP', 'FNP-C', 'DNP-FNP', 'ACNP-BC', 'ARNP', 'WHCNP', 'CRNP',
    'APN', 'PMHNP-BC', 'MSPAS'
}

# Generational suffixes are part of a person's name, not credentials. They must be
# captured separately: dropping them loses the suffix-agreement check, and gluing them
# onto the surname ("Leyva Jr") breaks the NPPES query, because the registry indexes the
# surname without the suffix.
SUFFIXES = {'JR', 'SR', 'II', 'III', 'IV', 'V'}

def _alpha(token):
    return re.sub(r'[^a-zA-Z-]', '', token)

def _is_credential(token, had_comma):
    """
    A token is a credential only if its letters are ALL UPPERCASE in the raw input.
    Case is the only signal that separates the DO credential from the (very common,
    mostly Vietnamese) surname 'Do', 'Pa' from the PA credential, and so on. A pure
    case-insensitive test silently ate those surnames: 'Dr. Jennifer Do, MD' parsed to
    last='' and the physician could never be matched. When the whole input is uppercased
    by the source this test cannot help, and the positional guards in parse_provider_name
    are what remains.
    """
    a = _alpha(token)
    if not a or len(a) < 2:
        return False
    if a.upper() not in CREDENTIALS_SET:
        return False
    return a == a.upper()

def _is_suffix(token):
    return _alpha(token).upper().rstrip('.') in SUFFIXES or _alpha(token).upper() in SUFFIXES

def parse_provider_name(name_str):
    """
    Parses a provider name string (e.g., 'Dr. Laxmi A. Kondapalli, MD, MSCE')
    into prefix, first, middle, last, suffix, and credentials.

    Invariants this parser must hold, each learned from a real loss:
      * a surname that looks like a credential ('Do', 'Pa') is never eaten as one;
      * a generational suffix is never glued onto the surname nor silently dropped;
      * stripping never leaves the parse without a surname -- a parse with no
        surname can never match anything downstream.
    """
    empty = {'prefix': '', 'first': '', 'middle': '', 'last': '', 'suffix': '', 'credentials': ''}
    if not isinstance(name_str, str) or not name_str.strip():
        return dict(empty)

    original = name_str.strip()

    # Remove common prefix titles
    prefix = ""
    prefix_match = re.match(r'^(Dr\.|Doctor|Dr|Mr\.|Ms\.|Mrs\.)\s+', original, re.IGNORECASE)
    if prefix_match:
        prefix = prefix_match.group(1).strip()
        name_str = original[prefix_match.end():]
    else:
        name_str = original

    # Split off what follows the commas (e.g., 'Laxmi Kondapalli, MD, MSCE' or 'Leyva, Jr., MD')
    parts = [p.strip() for p in name_str.split(',')]
    core_name = parts[0]

    credentials = []
    suffix = ""
    for part in parts[1:]:
        if not part:
            continue
        if _is_suffix(part):
            # 'Jr.' after a comma is a generational suffix, not a credential and not noise.
            suffix = _alpha(part).rstrip('.').upper() or _alpha(part).upper()
        elif _is_credential(part, had_comma=True):
            credentials.append(_alpha(part).upper())
        # anything else after a comma (a stray degree abbreviation in mixed case, etc.)
        # is noise and is not allowed to contaminate the name.

    # Within the core name, credentials can only appear as a TRAILING RUN (they follow
    # the name, never precede or interrupt it), e.g. 'Laxmi Kondapalli MD'. Scanning
    # from the end rather than testing every token is what keeps a middle token that
    # happens to resemble a credential inside the name where it belongs.
    tokens = core_name.split()
    trailing_creds = []
    while tokens and _is_credential(tokens[-1], had_comma=False):
        trailing_creds.insert(0, _alpha(tokens.pop()).upper())

    # Trailing generational suffix inside the core name, e.g. 'Luis P Leyva Jr' with no
    # comma: capture it, do NOT glue it onto the surname. (Gluing produced last='Leyva
    # Jr', which was then sent to the NPPES API as last_name and could match nothing,
    # because the registry surnames carry no suffix.)
    if tokens and _is_suffix(tokens[-1]):
        if not suffix:
            suffix = _alpha(tokens[-1]).rstrip('.').upper()
        tokens.pop()

    # If credential-stripping consumed every token but one, a collision surname may have
    # been eaten: 'Jennifer DO' with no comma is a physician named Do far more often than
    # it is a bare DO credential, and a parse with no surname cannot match anything at
    # all. Restore it -- but only for the tokens that are real surnames in the physician
    # population (Do, Pa). 'Smith MD' is a credential trailing a one-token name, not a
    # person surnamed Md, so MD/RN/etc. are not restored.
    COLLISION_SURNAMES = {'DO', 'PA'}
    if len(tokens) == 1 and trailing_creds and trailing_creds[0] in COLLISION_SURNAMES:
        tokens.append(trailing_creds.pop(0))

    credentials.extend(trailing_creds)

    first = middle = last = ""
    if len(tokens) == 1:
        first = tokens[0]
    elif len(tokens) == 2:
        first, last = tokens
    elif len(tokens) >= 3:
        first = tokens[0]
        last = tokens[-1]
        middle = " ".join(tokens[1:-1])

    return {
        'prefix': prefix,
        'first': first,
        'middle': middle,
        'last': last,
        'suffix': suffix,
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
    df.to_csv("nppes_matching_demo.csv", index=False)
    print("\nSaved demo DataFrame to nppes_matching_demo.csv")
