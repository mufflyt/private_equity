#!/usr/bin/env python3
import pandas as pd
import re
import os

def clean_company_name(text):
    if not isinstance(text, str):
        return ""
    # Remove row number prefix like "29 | " or "1,270 | "
    text = re.sub(r'^\d[\d,]*\s*\|\s*', '', text)
    return text.strip()

# List of strings to flag false positives in Company Name (case-insensitive)
FALSE_POSITIVE_NAMES = [
    "creamery", "yogurt", "dairy", "tennis", "physical therapy", 
    "physiotherapy", "limestone", "calcium products", "soil amendment", 
    "onlinemeded", "touchmd", "laborie", "hamilton thorne", "htl holdings",
    "wta"
]

def is_false_positive(row_dict):
    name = row_dict.get('Company Name', '')
    if not isinstance(name, str):
        return False
    name_lower = name.lower()
    for fp in FALSE_POSITIVE_NAMES:
        if fp in name_lower:
            return True
    return False

def clean_file(input_path, output_path, label):
    if not os.path.exists(input_path):
        print(f"File {input_path} does not exist.")
        return
        
    df = pd.read_csv(input_path)
    
    # Rename the first column to "Company Name" and clean its content
    first_col = df.columns[0]
    
    # Extract original row numbers and clean company names
    df['Original Row'] = df[first_col].apply(lambda x: re.match(r'^(\d[\d,]*)\s*\|', str(x)).group(1) if re.match(r'^(\d[\d,]*)\s*\|', str(x)) else "")
    df['Company Name'] = df[first_col].apply(clean_company_name)
    
    # Reorder columns to put Company Name first
    cols = list(df.columns)
    cols.remove('Company Name')
    cols.remove('Original Row')
    # Put Company Name first, and remove the original first column which had the raw name
    cols = ['Company Name', 'Original Row'] + cols[1:]
    df = df[cols]
    
    # Filter out false positives
    cleaned_rows = []
    removed_count = 0
    for idx, row in df.iterrows():
        row_dict = row.to_dict()
        if is_false_positive(row_dict):
            removed_count += 1
            print(f"  Removed false positive: {row_dict['Company Name']}")
        else:
            cleaned_rows.append(row_dict)
            
    cleaned_df = pd.DataFrame(cleaned_rows)
    cleaned_df.to_csv(output_path, index=False)
    
    print(f"✓ Cleaned {label}: {len(cleaned_df)} rows saved to {output_path} (removed {removed_count} false positives)")
    return cleaned_df

if __name__ == "__main__":
    base_dir = "/Users/tylermuffly/private_equity"
    
    # Clean Companies
    clean_file(
        os.path.join(base_dir, "pe_obgyn_companies_filtered.csv"),
        os.path.join(base_dir, "pe_obgyn_companies_clean.csv"),
        "COMPANIES"
    )
    
    # Clean Deals
    clean_file(
        os.path.join(base_dir, "pe_obgyn_deals_filtered.csv"),
        os.path.join(base_dir, "pe_obgyn_deals_clean.csv"),
        "DEALS"
    )
