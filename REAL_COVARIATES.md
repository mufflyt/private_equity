# Real demographic covariates

Seven columns in `pe_obgyn_final_calling_sheet_300.csv` were previously filled
with `rnorm()` placeholders (see `apply_demographic_covariates.R`, `set.seed(1978)`).
They have been replaced with real, geocoded data.

## Pipeline (all reproducible, run in order)

| Step | Script | Output |
|---|---|---|
| 1 | `R/fetch_npi_geography.R` | `data/covariates/npi_geography.csv` — NPI → practice tract + county (NPPES + Census geocoder) |
| 2 | `R/fetch_acs_female_insurance.R` | `data/covariates/tract_female_insurance.csv` — female coverage % by tract (ACS 2022 5-yr) |
| 3 | `R/fetch_county_enrollment.R` | `data/covariates/county_enrollment.csv` — county Medicare + Medicaid |
| 4 | `R/replace_fake_covariates.R` | rewrites the calling sheet (backs up original to `*.ORIGINAL_FAKE.csv`) |

`R/fetch_county_obgyn_count.R` documents the CMS National Downloadable File step
producing `data/covariates/county_obgyn_count.csv`.

Steps 2–4 require `CENSUS_API_KEY` (in `~/.Renviron`).

## Column sources

| Column | Source | Notes |
|---|---|---|
| `Tract_Pct_Female_Private` | ACS **B27002** (female, with private) | true female-specific |
| `Tract_Pct_Female_Medicaid` | ACS **C27007** (female, with Medicaid/means-tested) | true female-specific |
| `Tract_Pct_Female_Medicare` | ACS **C27006** (female, with Medicare) | true female-specific |
| `Tract_Pct_Female_Uninsured` | ACS **B27001** (female, no coverage) | true female-specific |
| `County_OBGYN_Count` | CMS Doctors & Clinicians National Downloadable File | distinct OB/GYN + Gyn-Onc NPIs whose practice ZIP is in the county |
| `County_Medicare_Enrollment` | CMS Medicare Monthly Enrollment (latest annual, `TOT_BENES`) | |
| `County_Medicaid_Enrollment` | ACS **C27007** county total "With Medicaid/means-tested" | |

## Coverage & missingness

Addresses that did not geocode to a tract keep **NA** (honest missingness, not a
random fill): tract columns ~89%, county columns ~97–99.7%. County values were
recovered from ZIP where the precise tract geocode failed.

## Validation

`tests/testthat/test-real-covariates.R` (33 assertions, all passing):

- **Adversarial** — values no longer equal the seed-1978 `rnorm` vectors; county
  columns are now identical for all NPIs in the same county (the placeholder drew
  per row, so 63/115 shared counties disagreed before; 0/115 now); tract columns
  identical within a tract.
- **Semantic** — tract ⊂ county ⊂ state and state matches the NPPES record;
  percentages are valid proportions; Medicaid share moves opposite to private;
  OB/GYN supply and Medicare enrollment scale together.
