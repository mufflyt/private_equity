# PECOS / DAC comparator validation

Scripts behind `docs/COMPARATOR_ADJUDICATION.md` and
`manuscript/appendix_comparator_validation.md`.

## What this answers

`SAP.lock` names the exposure contrast "PE vs **independent**" and the COMIRB protocol
restricts controls to **independent private practices**. Nothing in the pipeline tested that.
These scripts reconstruct each clinician's organisational affiliation from Medicare enrollment
records and adjudicate the comparator.

## External dependency

Every extraction step reads an archive on a removable drive:

```
/Volumes/MufflySamsung/pecos_data/            PPEF enrolment, reassignment, address, specialty
/Volumes/MufflySamsung/PPEF_Data/             historical PPEF snapshots
/Volumes/MufflySamsung/facility_affiliation/  CMS Doctors and Clinicians + facility affiliation
```

**The outputs in `data/comparator/` are committed**, so nothing downstream — the appendix, the
blocking tests, the manuscript ledger — needs the drive. The drive is needed only to rebuild.

Two vintage facts govern which files may be used, both established by
`hashcount.py` and recorded in `data/comparator/pecos_source_manifest.csv`:

- `pecos_data/` **is a 2019 snapshot**, not a current one. Its zip members are dated
  2019-04-15 and its CSVs are byte-identical to the 2019 vintage after normalising quoting;
  the later filesystem timestamps are extraction dates.
- PPEF carries enrolment through 2025 but **reassignment only for 2016, 2017 and 2019**. The
  affiliation chain needs reassignment, so PECOS alone cannot reach past 2019. The primary
  measurement is therefore the **DAC National Downloadable File of 05/2024**, itself
  PECOS-derived, which is the most recent source carrying organisation identity *and* practice
  location *and* a date preceding cohort construction.

## Run order

```sh
W=/tmp/pecos && mkdir -p $W
DACDIR=/Volumes/MufflySamsung/facility_affiliation
DAC=$DACDIR/unzipped_files/doctors_and_clinicians_05_2024_DAC_NationalDownloadableFile.csv

python pecos/hashcount.py            $W/source_manifest.json          # 0. freeze inputs
python pecos/build_cohort_key.py     $W .                             # 1. union key
python pecos/dac_extract.py          $W                               # 2. DAC org + sizes
python pecos/pecos_chain.py          $W 2019 \
    /Volumes/MufflySamsung/pecos_data/ppefenrol.csv \
    /Volumes/MufflySamsung/pecos_data/ppefreassign.csv \
    /Volumes/MufflySamsung/pecos_data/ppefaddr.csv                    # 3. PECOS 2019 chain
python pecos/extract_facility_affiliation.py $W \
    $DACDIR/doctors_and_clinicians_2026_06/Facility_Affiliation_2026-06.csv   # 4. affiliations
python pecos/orgspec.py              $W                               # 5. specialty mix
python pecos/build_comparator_adjudication.py $W .                    # 6. adjudication table
```

Step 6 writes `data/comparator/comparator_adjudication.csv`, the artifact the appendix and
`tests/testthat/test-comparator-adjudication.R` are checked against.

## Independent verification

The linkage decides everything downstream, so it is implemented twice, by methods sharing no
code — hash tables and row-wise accumulation, against external sort-merge relational joins —
and compared exactly.

```sh
sh   pecos/verify/pecos_chain_sortmerge.sh $W /Volumes/MufflySamsung/pecos_data
perl pecos/verify/dac_parse.pl $W/sm/npis.txt $DAC | sort -u > $W/v2/npi_org.tsv
python pecos/verify/compare_implementations.py $W        # non-zero exit on any disagreement
```

At the vintages above this reports 472 clinician-to-receiving-enrolment relations, 463
clinician-to-organisation relations, 311 organisations and 345 DAC relations, with **zero**
disagreements. The Perl parser also confirms the DAC row count exactly (2,563,744), which is
what rules out embedded record separators shifting field positions.

## Rules the classification obeys

Enforced by `tests/testthat/test-comparator-adjudication.R`, each mutation-tested:

- missing enrollment evidence never implies independence;
- hospital admitting affiliation never implies employment — obstetrician-gynecologists need
  privileges to deliver, so the relation is near-universal and says nothing about ownership;
- organisation size never decides ownership independence, and national and local practice size
  are kept as separate measurements rather than collapsed;
- a row carrying no organisation identifier is never treated as a resolved organisation;
- the sampled office is resolved rather than aggregated — `max()` across all of a clinician's
  affiliations was considered and rejected;
- any definitive classification must retain affirmative evidence;
- neither contamination measure may be removed from the released table.

`classify.py` was removed in favour of `build_comparator_adjudication.py`: it carried the
blank-organisation selection defect, and two live implementations of one classification is the
race condition `docs/CANONICAL_SOURCES_AUDIT.md` exists to prevent.
