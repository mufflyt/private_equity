import pandas as pd

df = pd.read_csv("pe_obgyn_final_calling_sheet_300.csv")

print("Total rows:", len(df))
print("Missing Phone count:", df['Phone'].isna().sum())
print("N/A Phone count:", (df['Phone'] == 'N/A').sum())
print("Empty Phone count:", (df['Phone'] == '').sum())

print("\nFirst few rows:")
print(df[['Provider Name', 'Phone', 'PE_or_Not', 'Matched Pair ID']].head(10))
