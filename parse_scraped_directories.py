import os
import json
import re
from bs4 import BeautifulSoup

output_dir = "scraped_texts"
parsed_providers = []

# Helper to normalize names and credentials
def clean_credentials(cred_str):
    if not cred_str:
        return ""
    clean = re.sub(r'[^a-zA-Z,]', '', cred_str).upper()
    parts = [p.strip() for p in clean.split(',')]
    valid = []
    for p in parts:
        if p in ['MD', 'DO', 'CNM', 'NP', 'PA', 'PAC', 'PAC', 'RN']:
            valid.append(p)
    return ", ".join(valid)

# 1. Unified Women's Healthcare (Michigan Affiliate)
file_1 = os.path.join(output_dir, "1_uwh_michigan.html")
if os.path.exists(file_1):
    with open(file_1, "r", encoding="utf-8") as f:
        soup = BeautifulSoup(f.read(), 'html.parser')
    count = 0
    for h in soup.find_all(['h1', 'h2', 'h3', 'h4', 'h5', 'h6']):
        text = h.get_text(strip=True)
        # matches: Name, MD or Name, DO
        m = re.match(r'^([^,\n]+),\s*(MD|DO|M\.D\.|D\.O\.)(?:\s*,.*)?$', text, re.IGNORECASE)
        if m:
            name, cred = m.groups()
            parsed_providers.append({
                "raw_name": text,
                "name": name.strip(),
                "credentials": cred.upper().replace(".", ""),
                "state": "MI",
                "platform": "Unified Women's Healthcare",
                "pe_owner": "Altas Partners, Ares Management, Oak HC/FT",
                "acq_year": "2020",
                "source": "uwhmichigan.com/providers"
            })
            count += 1
    print(f"Parsed {count} providers from UWH Michigan")

# 2. Together Women's Health - Comprehensive
file_2a = os.path.join(output_dir, "2_together_comprehensive.html")
if os.path.exists(file_2a):
    with open(file_2a, "r", encoding="utf-8") as f:
        soup = BeautifulSoup(f.read(), 'html.parser')
    text = soup.get_text()
    count = 0
    # Search for pattern: Name, MD or Name, DO
    matches = re.finditer(r'([A-Z][a-z]+(?:\s+[A-Z]\.?)?\s+[A-Z][a-zA-Z-]+(?:\s+[A-Z][a-z]+)?),\s*(MD|DO|M\.D\.|D\.O\.)', text)
    seen = set()
    for m in matches:
        full_match = m.group(0)
        name, cred = m.groups()
        if name not in seen:
            seen.add(name)
            parsed_providers.append({
                "raw_name": full_match,
                "name": name.strip(),
                "credentials": cred.upper().replace(".", ""),
                "state": "MI",
                "platform": "Together Women's Health",
                "pe_owner": "Shore Capital Partners",
                "acq_year": "2020",
                "source": "comprehensivewomanscare.com"
            })
            count += 1
    print(f"Parsed {count} providers from Together Comprehensive")

# 3. Together Women's Health - Eastside
file_2b = os.path.join(output_dir, "2_together_eastside.html")
if os.path.exists(file_2b):
    with open(file_2b, "r", encoding="utf-8") as f:
        soup = BeautifulSoup(f.read(), 'html.parser')
    text = soup.get_text()
    count = 0
    matches = re.finditer(r'([A-Z][a-z]+(?:\s+[A-Z]\.?)?\s+[A-Z][a-zA-Z-]+(?:\s+[A-Z][a-z]+)?),\s*(MD|DO|M\.D\.|D\.O\.)', text)
    seen = set()
    for m in matches:
        full_match = m.group(0)
        name, cred = m.groups()
        if name not in seen:
            seen.add(name)
            parsed_providers.append({
                "raw_name": full_match,
                "name": name.strip(),
                "credentials": cred.upper().replace(".", ""),
                "state": "MI",
                "platform": "Together Women's Health",
                "pe_owner": "Shore Capital Partners",
                "acq_year": "2020",
                "source": "togetherwomenshealth.com (Eastside)"
            })
            count += 1
    print(f"Parsed {count} providers from Together Eastside")

# 4. Nova - WomanCare PC
file_3a = os.path.join(output_dir, "3_nova_womancare.html")
if os.path.exists(file_3a):
    with open(file_3a, "r", encoding="utf-8") as f:
        soup = BeautifulSoup(f.read(), 'html.parser')
    count = 0
    # Names are in h2, h3, or text nodes
    for h in soup.find_all(['h1', 'h2', 'h3', 'h4', 'h5', 'h6']):
        text = h.get_text(strip=True)
        # matches: Name, MD or Name, DO
        m = re.match(r'^([^,\n]+),\s*(MD|DO|M\.D\.|D\.O\.)(?:\s*,.*)?$', text, re.IGNORECASE)
        if m:
            name, cred = m.groups()
            parsed_providers.append({
                "raw_name": text,
                "name": name.strip(),
                "credentials": cred.upper().replace(".", ""),
                "state": "IL",
                "platform": "Nova Women's Health Partners",
                "pe_owner": "Webster Equity Partners",
                "acq_year": "2024",
                "source": "womancarepc.com/find-care/providers"
            })
            count += 1
    print(f"Parsed {count} providers from Nova WomanCare")

# 5. Nova - Women's HealthFirst
file_3b = os.path.join(output_dir, "3_nova_healthfirst.html")
if os.path.exists(file_3b):
    with open(file_3b, "r", encoding="utf-8") as f:
        soup = BeautifulSoup(f.read(), 'html.parser')
    count = 0
    # Accordion titles contain names, e.g. "Nancy Singh, MD" or "Cecilia Chui, DO, FACOOG"
    titles = soup.find_all('div', class_='sow-accordion-title')
    for t in titles:
        # Extract text ignoring link children
        # Get first child text or clean text
        text = t.get_text(separator='|', strip=True).split('|')[0].strip()
        m = re.match(r'^([^,\n]+),\s*(MD|DO|M\.D\.|D\.O\.)(?:\s*,.*)?$', text, re.IGNORECASE)
        if m:
            name, cred = m.groups()
            parsed_providers.append({
                "raw_name": text,
                "name": name.strip(),
                "credentials": cred.upper().replace(".", ""),
                "state": "IL",
                "platform": "Nova Women's Health Partners",
                "pe_owner": "Webster Equity Partners",
                "acq_year": "2024",
                "source": "womenfirst.net/our-providers/physicians/"
            })
            count += 1
    print(f"Parsed {count} providers from Nova HealthFirst")

# 6. Femwell / TopLine MD Clinics
file_4 = os.path.join(output_dir, "4_topline_md_clinics.json")
if os.path.exists(file_4):
    with open(file_4, "r", encoding="utf-8") as f:
        clinics = json.load(f)
    count = 0
    seen = set()
    
    # We loop through each clinic. In its content.rendered (or just content) we parse all doctor names.
    for c in clinics:
        content = c.get("content", {}).get("rendered", "")
        title = c.get("title", {}).get("rendered", "")
        
        # Check if it's an OBGYN clinic or general
        is_obgyn_clinic = any(k in title.lower() or k in content.lower() for k in ["ob/gyn", "obgyn", "obstetrics", "gynecology", "women's health", "woman care", "fertility", "midwifery"])
        
        # Parse names in content: e.g. "Dr. Manal Antoun" or "Dr. Ana Hernandez"
        matches = re.finditer(r'Dr\.\s+([A-Z][a-z]+(?:\s+[A-Z]\.?)?\s+[A-Z][a-zA-Z-]+)(?:\s+(?:Jr\.|Sr\.|III))?', content)
        for m in matches:
            name = m.group(1).strip()
            # Also check if it specifies MD or DO in the surrounding text (up to 30 chars after)
            pos = m.end()
            surr = content[pos:pos+30]
            cred = "" # default
            if re.search(r'\bDO\b|\bD\.O\.\b', surr.upper()):
                cred = "DO"
            elif re.search(r'\bMD\b|\bM\.D\.\b', surr.upper()):
                cred = "MD"
            elif any(x in surr.upper() for x in ["CNM", "APRN", "NP", "PA", "PAC"]):
                continue # Skip mid-levels early
                
            key = (name, c['link'])
            if key not in seen:
                seen.add(key)
                parsed_providers.append({
                    "raw_name": f"Dr. {name}, {cred}" if cred else f"Dr. {name}",
                    "name": name,
                    "credentials": cred,
                    "state": "FL",
                    "platform": "Femwell Group Health",
                    "pe_owner": "LightBay Capital",
                    "acq_year": "2021",
                    "source": f"toplinemd.com ({title})"
                })
                count += 1
                
        # Also parse "Name, MD" or "Name, DO" format
        matches2 = re.finditer(r'([A-Z][a-z]+(?:\s+[A-Z]\.?)?\s+[A-Z][a-zA-Z-]+),\s*(MD|DO|M\.D\.|D\.O\.)', content)
        for m in matches2:
            name, cred = m.groups()
            key = (name, c['link'])
            if key not in seen:
                seen.add(key)
                parsed_providers.append({
                    "raw_name": m.group(0),
                    "name": name.strip(),
                    "credentials": cred.upper().replace(".", ""),
                    "state": "FL",
                    "platform": "Femwell Group Health",
                    "pe_owner": "LightBay Capital",
                    "acq_year": "2021",
                    "source": f"toplinemd.com ({title})"
                })
                count += 1
                
    print(f"Parsed {count} providers from TopLine MD Clinics")

# 7. CCRM Fertility
file_5 = os.path.join(output_dir, "5_ccrm_fertility.html")
if os.path.exists(file_5):
    with open(file_5, "r", encoding="utf-8") as f:
        soup = BeautifulSoup(f.read(), 'html.parser')
    text = soup.get_text()
    count = 0
    lines = [l.strip() for l in text.split('\n') if l.strip()]
    
    # Let's iterate through lines and find Name on line N and MD/DO on line N+1
    for idx in range(len(lines) - 1):
        line = lines[idx]
        next_line = lines[idx+1]
        
        # Name: 2-3 capitalized words, no punctuation
        is_name = re.match(r'^[A-Z][a-z]+(?:\s+(?:[A-Z]\.?|[A-Z][a-z]+))?\s+[A-Z][a-zA-Z-]+$', line)
        # Credential: MD or DO (or with other things like HCLD, MSCE)
        is_cred = re.match(r'^(?:MD|DO|M\.D\.|D\.O\.)(?:\s*,\s*.*)?$', next_line, re.IGNORECASE)
        
        if is_name and is_cred:
            name = line
            cred_raw = next_line.split(',')[0].strip().upper().replace(".", "")
            
            # Find the state of this doctor
            # CCRM has headings like "Colorado fertility specialists" preceding the doctor list
            state = "CO" # Default
            # Let's search backwards for city/state headings
            for back_idx in range(idx, 0, -1):
                back_line = lines[back_idx]
                if "specialists" in back_line.lower():
                    # extract state
                    if "colorado" in back_line.lower():
                        state = "CO"
                    elif "atlanta" in back_line.lower() or "georgia" in back_line.lower():
                        state = "GA"
                    elif "arizona" in back_line.lower():
                        state = "AZ"
                    elif "austin" in back_line.lower() or "houston" in back_line.lower() or "dallas" in back_line.lower() or "texas" in back_line.lower():
                        state = "TX"
                    elif "boston" in back_line.lower() or "massachusetts" in back_line.lower():
                        state = "MA"
                    elif "chicago" in back_line.lower() or "illinois" in back_line.lower():
                        state = "IL"
                    elif "delaware" in back_line.lower():
                        state = "DE"
                    elif "minneapolis" in back_line.lower() or "minnesota" in back_line.lower():
                        state = "MN"
                    elif "new jersey" in back_line.lower():
                        state = "NJ"
                    elif "new york" in back_line.lower():
                        state = "NY"
                    elif "orange county" in back_line.lower() or "newport beach" in back_line.lower() or "san francisco" in back_line.lower() or "california" in back_line.lower():
                        state = "CA"
                    elif "philadelphia" in back_line.lower() or "pennsylvania" in back_line.lower():
                        state = "PA"
                    elif "virginia" in back_line.lower():
                        state = "VA"
                    elif "toronto" in back_line.lower() or "canada" in back_line.lower():
                        state = "ON" # Ontario
                    break
            
            # Skip Canada
            if state == "ON":
                continue
                
            parsed_providers.append({
                "raw_name": f"{name}, {cred_raw}",
                "name": name,
                "credentials": cred_raw,
                "state": state,
                "platform": "CCRM Fertility",
                "pe_owner": "Altas Partners, Ares Management, Oak HC/FT",
                "acq_year": "2021",
                "source": f"ccrmivf.com ({state})"
            })
            count += 1
            
    print(f"Parsed {count} providers from CCRM Fertility")

# 8. IVI RMA Global / RMA New Jersey
file_6 = os.path.join(output_dir, "6_ivi_rma.html")
if os.path.exists(file_6):
    with open(file_6, "r", encoding="utf-8") as f:
        soup = BeautifulSoup(f.read(), 'html.parser')
    count = 0
    # Find all divs with class specialist-text
    specialists = soup.find_all('div', class_='specialist-text')
    for s in specialists:
        name_tag = s.find('p', class_='name')
        title_tag = s.find('p', class_='title')
        clinics_div = s.find('div', class_='clinics')
        
        if name_tag:
            name = name_tag.get_text(strip=True)
            title = title_tag.get_text(strip=True) if title_tag else ""
            
            # Parse state from clinics
            state = "NJ" # default
            if clinics_div:
                h5_tags = clinics_div.find_all('h5')
                states_found = []
                for h5 in h5_tags:
                    txt = h5.get_text(strip=True)
                    m_state = re.search(r',\s*([A-Z]{2})$', txt)
                    if m_state:
                        states_found.append(m_state.group(1).upper())
                if states_found:
                    state = states_found[0] # Take first clinic state
                    
            # Parse credential from name or title
            cred = "" # default
            if re.search(r'\bDO\b|\bD\.O\.\b', name.upper()) or re.search(r'\bDO\b|\bD\.O\.\b', title.upper()):
                cred = "DO"
            elif re.search(r'\bMD\b|\bM\.D\.\b', name.upper()) or re.search(r'\bMD\b|\bM\.D\.\b', title.upper()):
                cred = "MD"
                
            parsed_providers.append({
                "raw_name": f"{name}, {cred}" if cred else name,
                "name": name,
                "credentials": cred,
                "state": state,
                "platform": "IVI RMA Global",
                "pe_owner": "KKR (80% stake)",
                "acq_year": "2023",
                "source": "rmanetwork.com/resources/our-fertility-specialists/"
            })
            count += 1
    print(f"Parsed {count} providers from IVI RMA")

# 9. Shady Grove Fertility
file_7 = os.path.join(output_dir, "7_shady_grove.html")
if os.path.exists(file_7):
    with open(file_7, "r", encoding="utf-8") as f:
        soup = BeautifulSoup(f.read(), 'html.parser')
    text = soup.get_text()
    count = 0
    # Matches Name, M.D. or Name, D.O.
    matches = re.finditer(r'([A-Z][a-z]+(?:\s+[A-Z]\.?)?\s+[A-Z][a-zA-Z-]+(?:\s+[A-Z][a-z]+)?),\s*(M\.D\.|D\.O\.|MD|DO)', text)
    seen = set()
    for m in matches:
        full_match = m.group(0)
        name, cred = m.groups()
        if name not in seen:
            seen.add(name)
            
            # Find state from following text
            pos = m.end()
            surr = text[pos:pos+150]
            state = "MD" # Default
            if "Maryland" in surr or " MD " in surr:
                state = "MD"
            elif "Virginia" in surr or " VA " in surr:
                state = "VA"
            elif "Pennsylvania" in surr or " PA " in surr:
                state = "PA"
            elif "Colorado" in surr or " CO " in surr:
                state = "CO"
            elif "Florida" in surr or " FL " in surr:
                state = "FL"
            elif "Georgia" in surr or " GA " in surr:
                state = "GA"
            elif "New York" in surr or " NY " in surr:
                state = "NY"
                
            parsed_providers.append({
                "raw_name": full_match,
                "name": name.strip(),
                "credentials": cred.upper().replace(".", ""),
                "state": state,
                "platform": "US Fertility",
                "pe_owner": "Amulet Capital Partners, L Catterton",
                "acq_year": "2020",
                "source": "shadygrovefertility.com"
            })
            count += 1
    print(f"Parsed {count} providers from Shady Grove")

# 10. Kindbody
file_8 = os.path.join(output_dir, "8_kindbody.html")
if os.path.exists(file_8):
    with open(file_8, "r", encoding="utf-8") as f:
        soup = BeautifulSoup(f.read(), 'html.parser')
    count = 0
    # Find all divs with class team-member
    members = soup.find_all('div', class_='team-member')
    for m in members:
        h6 = m.find('h6')
        title_div = m.find('div', class_='title')
        loc_divs = m.find_all('div', class_='location')
        
        if h6:
            name = h6.get_text(strip=True)
            # Remove "Dr." prefix for name
            name_clean = re.sub(r'^(Dr\.|Doctor|Dr)\s+', '', name, flags=re.IGNORECASE).strip()
            title = title_div.get_text(strip=True) if title_div else ""
            
            # Parse state
            state = "NY" # Default
            if loc_divs:
                txt = loc_divs[0].get_text(strip=True)
                m_state = re.search(r',\s*([A-Z]{2})\b', txt)
                if m_state:
                    state = m_state.group(1).upper()
            
            # Parse credential
            cred = ""
            if re.search(r'\bDO\b|\bD\.O\.\b', name.upper()) or re.search(r'\bDO\b|\bD\.O\.\b', title.upper()):
                cred = "DO"
            elif re.search(r'\bMD\b|\bM\.D\.\b', name.upper()) or re.search(r'\bMD\b|\bM\.D\.\b', title.upper()):
                cred = "MD"
                
            parsed_providers.append({
                "raw_name": f"{name}, {cred}" if cred else name,
                "name": name_clean,
                "credentials": cred,
                "state": state,
                "platform": "Kindbody",
                "pe_owner": "Perceptive, JPMorgan, GV",
                "acq_year": "2018",
                "source": "kindbody.com/our-doctors/"
            })
            count += 1
    print(f"Parsed {count} providers from Kindbody")

# 11. Women's Care Enterprises (BC Partners)
file_9 = os.path.join(output_dir, "9_womens_care.html")
if os.path.exists(file_9):
    with open(file_9, "r", encoding="utf-8") as f:
        soup = BeautifulSoup(f.read(), 'html.parser')
    app_div = soup.find('div', id='app')
    if app_div and app_div.get('data-page'):
        try:
            data = json.loads(app_div.get('data-page'))
            stores = data.get("props", {}).get("content", {}).get("section_0", {}).get("storeLocator", {}).get("stores", [])
            count = 0
            for s in stores:
                full_name = s.get("full_name", "")
                raw_name = s.get("name", "")
                last_name = s.get("last_name", "")
                
                # Check degree/credential
                cred = ""
                if re.search(r'\bDO\b|\bD\.O\.\b', raw_name.upper()):
                    cred = "DO"
                elif re.search(r'\bMD\b|\bM\.D\.\b', raw_name.upper()):
                    cred = "MD"
                elif any(x in raw_name.upper() for x in ["CNM", "APRN", "NP", "PA"]):
                    continue # Exclude mid-levels
                    
                parsed_providers.append({
                    "raw_name": raw_name,
                    "name": full_name.strip(),
                    "credentials": cred,
                    "state": "FL",
                    "platform": "Women's Care Enterprises",
                    "pe_owner": "BC Partners",
                    "acq_year": "2020",
                    "source": "womenscareobgyn.com/providers"
                })
                count += 1
            print(f"Parsed {count} providers from Women's Care Enterprises")
        except Exception as e:
            print(f"Error parsing Women's Care JSON: {e}")

# 12. Axia Women's Health
file_10 = os.path.join(output_dir, "10_axia.html")
if os.path.exists(file_10):
    with open(file_10, "r", encoding="utf-8") as f:
        soup = BeautifulSoup(f.read(), 'html.parser')
    options = soup.find_all('option')
    count = 0
    for opt in options:
        text = opt.get_text(strip=True)
        # check if it represents a provider name (typically has MD, DO, NP, PA, CNM, etc.)
        if any(cred in text for cred in ["MD", "DO", "NP", "PA", "CNM", "M.D.", "D.O."]):
            # Exclude mid-levels
            if any(m in text.upper() for m in ["CNM", "NP", "PA", "WHNP", "APN", "CRNP", "PAC"]):
                continue
                
            m = re.match(r'^([^,\n\-]+),\s*(MD|DO|M\.D\.|D\.O\.)(?:\s*,.*)?$', text, re.IGNORECASE)
            if m:
                name, cred = m.groups()
                parsed_providers.append({
                    "raw_name": text,
                    "name": name.strip(),
                    "credentials": cred.upper().replace(".", ""),
                    "state": "NJ", # Default to NJ, matcher will check PA/IN/OH/KY too
                    "platform": "Axia Women's Health",
                    "pe_owner": "Partners Group",
                    "acq_year": "2021",
                    "source": "axiawh.com/providers"
                })
                count += 1
    print(f"Parsed {count} providers from Axia")

# 13. OB Hospitalist Group (OBHG)
file_11 = os.path.join(output_dir, "11_obhg.txt")
if os.path.exists(file_11):
    with open(file_11, "r", encoding="utf-8") as f:
        text = f.read()
    count = 0
    lines = [l.strip() for l in text.split('\n') if l.strip()]
    
    # We found that lines 119 to 153 contain the names, but let's just find all lines starting with "Dr. "
    for line in lines:
        if line.startswith("Dr. ") and len(line) < 50:
            name = re.sub(r'^(Dr\.|Doctor|Dr)\s+', '', line, flags=re.IGNORECASE).strip()
            # If line mentions multiple positions, ignore
            if "Market" in name or "Hospitalist" in name or "Physician" in name:
                continue
                
            # Parse state
            state = "IL" # default, matcher will check TX/other states as well
            if "Mankus" in name:
                state = "TX"
                
            parsed_providers.append({
                "raw_name": line,
                "name": name,
                "credentials": "", # Default to empty for OBHG hospitalists, matcher will verify
                "state": state,
                "platform": "OB Hospitalist Group",
                "pe_owner": "Kohlberg & Company",
                "acq_year": "2021",
                "source": "obhg.com/clinician-profiles"
            })
            count += 1
    print(f"Parsed {count} providers from OBHG")

# Deduplicate parsed providers by name + platform
unique_providers = []
seen_provs = set()
for p in parsed_providers:
    key = (p['name'].lower(), p['platform'].lower())
    if key not in seen_provs:
        seen_provs.add(key)
        unique_providers.append(p)

print(f"\nTotal unique providers parsed: {len(unique_providers)}")

# Save to discovered_providers.json
with open("discovered_providers.json", "w") as f:
    json.dump(unique_providers, f, indent=2)
print("Saved parsed providers to discovered_providers.json")
