# Real demographic covariates

Seven columns in `pe_obgyn_final_calling_sheet_300.csv` were previously filled
with `rnorm()` placeholders (see `apply_demographic_covariates.R`, `set.seed(1978)`).
They have been replaced with real, geocoded data.

## Pipeline (all reproducible, run in order)

| Step | Script | Output |
|---|---|---|
| 1 | `R/fetch_npi_geography.R` | `data/covariates/npi_geography.csv` — NPI → practice tract + county (NPPES + Census geocoder) |
| 1b | `R/fetch_npi_geography_fallback.R` | backfills addresses the Census geocoder missed via Nominatim → Census coordinates endpoint (same tract geography) |
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

## `CDC_SVI` is still simulated

`CDC_SVI` was **not** among the seven columns replaced above. It remains the
`Normal(0.434, 0.193)` draw truncated to [0.01, 0.99] that
`apply_demographic_covariates.R` produced, and it is measurable as such: over the
600 fielded rows the column tests KS p = 0.90 against a fitted Normal and
p < 1e-6 against Uniform(0, 1). A CDC SVI percentile rank is uniform by
construction, so normality is disqualifying.

It has therefore been renamed **`SIMULATED_CDC_SVI`** in the calling sheet, matching
the convention `analysis_manifest.csv` and `tests/testthat/test-svi-provenance.R`
already apply to the fielded 200 sheet: no column name in a fielded artifact may
assert a measurement that was not made. The values are untouched — only the header
changed — so nothing downstream changes meaning. No script that reads
`pe_obgyn_final_calling_sheet_300.csv` referenced the column.

The real replacement, `CDC_SVI_real`, is built by `build_svi_covariate.R` from the
CDC/ATSDR tract-level SVI and exists only on the 200 sheet. Until that runs against
the 300 sheet, `SIMULATED_CDC_SVI` is provenance only and is never analytic.

## Coverage & missingness

Addresses that did not geocode to a tract keep **NA** (honest missingness, not a
random fill). After the Nominatim fallback (step 1b) tract coverage is **95.7%**
(590/600 NPIs geocoded; 8 un-geocodable + 2 with no NPPES address remain NA) and
county columns are **97–99.7%**. County values were recovered from ZIP where the
precise tract geocode failed.

## Validation

`tests/testthat/test-real-covariates.R` (33 assertions, all passing):

- **Adversarial** — values no longer equal the seed-1978 `rnorm` vectors; county
  columns are now identical for all NPIs in the same county (the placeholder drew
  per row, so 63/115 shared counties disagreed before; 0/115 now); tract columns
  identical within a tract.
- **Semantic** — tract ⊂ county ⊂ state and state matches the NPPES record;
  percentages are valid proportions; Medicaid share moves opposite to private;
  OB/GYN supply and Medicare enrollment scale together.
