#!/usr/bin/env python3
import pandas as pd
import re
import os

KEYWORDS = [
    r'\bobstetrics\b', r'\bgynecology\b', r'\bob/gyn\b', r'\bobgyn\b',
    r"women's health", r"women's healthcare", r'\burogynecology\b',
    r'maternal fetal medicine', r'reproductive endocrinology',
    r'\bfertility\b', r'\bivf\b'
]

# Compile regular expressions for case-insensitive search
pattern = re.compile('|'.join(KEYWORDS), re.IGNORECASE)

def matches_keywords(text):
    if not isinstance(text, str):
        return False
    return bool(pattern.search(text))

def filter_csv(input_path, output_path, label):
    if not os.path.exists(input_path) or os.path.getsize(input_path) == 0:
        print(f"Skipping {label}: file is empty or does not exist.")
        return 0

    print(f"Filtering {label} ({input_path})...")
    df = pd.read_csv(input_path)
    
    # We will search for keywords in all text columns
    mask = df.map(lambda x: matches_keywords(str(x))).any(axis=1)
    filtered_df = df[mask]
    
    # Save the filtered results
    filtered_df.to_csv(output_path, index=False)
    print(f"✓ Saved {len(filtered_df)} matching rows to {output_path} (out of {len(df)} total rows)")
    return len(filtered_df)

if __name__ == "__main__":
    import sys
    
    base_dir = "."
    
    companies_in = os.path.join(base_dir, "companies_export.csv")
    companies_out = os.path.join(base_dir, "pe_obgyn_companies_filtered.csv")
    
    deals_in = os.path.join(base_dir, "deals_export.csv")
    deals_out = os.path.join(base_dir, "pe_obgyn_deals_filtered.csv")
    
    print("=== PE OB/GYN Data Filter ===")
    
    comp_count = filter_csv(companies_in, companies_out, "COMPANIES")
    deals_count = filter_csv(deals_in, deals_out, "DEALS")
    
    print("\nComplete!")
    print(f"Filtered Companies: {comp_count} rows")
    print(f"Filtered Deals: {deals_count} rows")
