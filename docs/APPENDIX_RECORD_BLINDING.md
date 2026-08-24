# Appendix: Record numbering and caller blinding

**Status:** resolved 2026-08-24. Fix in `bbd427d`, merged as PR #4.
**Applies to:** the fielded 200-pair / 800-call REDCap instrument `taylor_private_equity`.

---

## S1. Summary

The fielded REDCap dictionary numbered its records in a way that encoded the exposure. Record
parity predicted private-equity ownership perfectly across all 400 clinicians, and the two
members of every matched pair sat on consecutive record ids. A mystery-caller design that
depends on the caller not knowing which practices are PE-backed was therefore unblinded by its
own record ids, before any call was placed.

The ownership variable had been added as a `@HIDDEN` field, which was ineffective: hiding a
field does not hide a pattern in the primary key.

The numbering was regenerated under an allocator with two guaranteed properties, the artifacts
were rebuilt, and the invariants are now enforced by a test that runs in continuous
integration.

## S2. The defect

`build_200_redcap_import.R` assigned dropdown codes with:

```r
phys <- sheet %>%
  arrange(as.numeric(str_remove(`Matched Pair ID`, "pair_")), PE_or_Not) %>%
  mutate(slot = row_number())
```

`PE_or_Not` takes the values `"Non-PE"` and `"PE"`. `"Non-PE"` sorts first. Sorting by
`(pair, PE_or_Not)` therefore emits every matched pair as control-then-PE, and `row_number()`
turns that into consecutive integers. Two regularities follow, neither of them intended:

| Regularity | Extent |
|---|---|
| Odd record id ⇒ control; even record id ⇒ PE | 400 of 400 clinicians, no exceptions |
| Members of a matched pair on consecutive ids | 200 of 200 pairs |

Records 1–400 are the Medicaid calls and 401–800 the commercial calls for the same clinicians
in the same order, so the pattern repeated identically in both arms.

Anyone reading the caller's dropdown could recover the exposure for the whole sample from the
record numbers alone. No data was required, and no access beyond the instrument itself.

## S3. How it was found

Not by a test. The pattern was noticed while reconstructing which physicians were fielded: the
per-state counts in the dropdown were all even, which is not what an unconstrained sample looks
like. That prompted a check of parity against ownership, which came back 400 of 400.

Independently, `recover_fielded_400_from_redcap.py` had already documented the same ordering
contract and used it, correctly, to reconstruct the cohort from the live dropdown. The
contract was known and relied upon; that it also leaked the exposure was not noticed.

The lesson recorded here is narrow: a deterministic ordering that is useful for recovery is the
same property that makes it useful for inference. If an ordering can be inverted to recover the
design, it can be inverted by the caller.

## S4. The fix

`assign_blinded_slots()` in `R/pe_helpers.R` replaces the sort. Given the pair labels and the
arm labels it returns a permutation of the slots with two guarantees:

- **Exact parity balance.** Each arm occupies exactly half the odd slots and exactly half the
  even slots. Parity carries zero information about the arm, not merely little. On the fielded
  cohort: 100 of 200 PE clinicians on odd record ids.
- **No pair adjacency.** The two members of a matched pair never occupy consecutive slots. On
  the fielded cohort: 0 of 200 pairs adjacent.

Both are constructed rather than sampled-and-hoped-for: the allocator splits each arm into
parity halves, shuffles within each half so the arms are not merely block-ordered instead, and
rejects and redraws if any pair lands adjacent.

Properties deliberately preserved:

- Codes 1–400 remain the Medicaid arm and 401–800 the commercial arm.
- Code *i* and code *i+400* remain the two calls to one clinician.
- Pair membership is unchanged. Only the numbering moved.

Checked for residual signal beyond parity: PE clinicians are 96 of 200 in the low half of the
id range, and distribute evenly across id modulo 3, 4 and 5.

## S5. Consequence: the mapping is no longer derivable

The old numbering could be reconstructed from the calling sheet by repeating the sort. The new
one cannot: it is seeded (`SLOT_SEED = 20260824L`) and reproducible from that seed, but not
recoverable from the sheet alone.

`build_200_redcap_import.R` therefore writes a crosswalk, and that file is now the only record
of which record id is which clinician. It is committed here for that reason. It is also the
only artifact that pairs a record id with an ownership label, so it is restricted — see S8.

The build asserts both invariants on its own output and exits non-zero if either fails, so a
future run cannot quietly reintroduce the defect.

## S6. Verification

`tests/testthat/test-blinded-slot-assignment.R`, registered `nodata` in `tests/BLOCKING` so
continuous integration runs it. 101 assertions. It:

1. reconstructs the shipped ordering and asserts that it leaks — 200 of 200 controls odd, 200
   of 200 pairs adjacent — so the test would fail if the defect were ever reintroduced;
2. asserts exact parity balance and zero pair adjacency on the new allocator;
3. asserts the arms are not blocked into low and high slots instead;
4. repeats 2 and 3 across 40 seeds, so the guarantee is not a property of the one seed chosen;
5. asserts reproducibility from a seed and variation between seeds;
6. asserts the allocator refuses inputs it cannot balance — mismatched lengths, an odd number
   of records, an arm of odd size, or a single arm.

Spot-check of the rebuilt artifacts, new id → clinician → pair:

| New id | Clinician | Pair |
|---|---|---|
| 1 / 401 | Dr. Wendy Cervi | 490 |
| 2 | Dr. Joanna Dalton Ayoung | 233 |
| 400 / 800 | Dr. Caroline Mecker | 294 |

Records 1 and 2 are adjacent ids belonging to different pairs, which is the adjacency property.
Ids 1 and 401 are one clinician's two insurance calls, which is the preserved arm structure.

## S7. Deployment

The renumbering lives in the **data dictionary**, not in the record data. `physician_name` is a
dropdown; which clinician a record refers to is the dropdown *code*, and the code-to-clinician
mapping is the dictionary's choices column. Confirmed by diffing the two dictionaries: exactly
one field changed, `physician_name`, exactly one column, `choices`. The record import file is
`record_id == physician_name` for all 800 rows and is byte-identical before and after.

Order of operations:

1. Confirm the project holds no call data. **This is a precondition, not a formality.** A
   record's stored `physician_name` does not change, but its meaning does: record 1 still holds
   code 1, and code 1 now resolves to a different clinician. Any call already entered would be
   silently reattributed, with no error and no warning.
2. Upload `redcap/PrivateVsPublicDoesEquityOwner_DataDictionary_2026-08-24_blinded.csv` as the
   data dictionary. This carries the new numbering and also adds the `ownership` and `pair_id`
   fields, both `@HIDDEN`.
3. Import `redcap/redcap_import_ownership_pair.csv` — 800 rows, 798 of which changed value.
4. Send the caller the rebuilt materials only, and have the previous copies destroyed.
5. Verify a handful of records: same new id → same clinician → same pair, across the caller's
   sheet and REDCap.

If call data does exist, do not upload. `redcap/redcap_record_id_old_to_new.csv` maps all 800
old ids to new and allows the existing records to be migrated instead.

## S8. Artifact inventory

Everything below is under `redcap/`.

| File | Role | Distribution |
|---|---|---|
| `PrivateVsPublicDoesEquityOwner_DataDictionary_2026-08-24_blinded.csv` | The fix. Upload as data dictionary | Study team |
| `redcap_import_ownership_pair.csv` | Record import, `ownership` + `pair_id`, 800 rows | Study team |
| `Taylor_PE_Call_Tracker_400_Physicians.xlsx` | Caller's working tracker, 800 call rows | **Caller** |
| `pe_mystery_caller_call_sheet_400.csv` | Flat equivalent of the tracker | **Caller** |
| `redcap_record_id_old_to_new.csv` | Migration and audit | Study team |
| `redcap_slot_crosswalk_400.csv` | **Carries ownership.** Only record of id → clinician | **Restricted** |
| `redcap_call_schedule_800.csv` | **Carries `PE_or_Not`.** Arm order and 48-hour spacing | **Restricted** |
| `obsolete/OBSOLETE_DO_NOT_USE_*` | Superseded, retained for audit | Do not use |

The two restricted files are the reason this directory is worth stating a rule about: they
contain the exposure. This repository is private and single-owner, which is what makes
committing them appropriate. If a caller is ever granted access, move them out first — a
caller with repository access re-creates exactly the leak this appendix documents.

The caller's two files carry no ownership, pair, or PE column. Verified against the tracker's
header rather than assumed.

## S9. Related findings

**Two offices are reached by two clinicians each.** `(305) 665-1133` serves pairs 124 and 128;
`(609) 926-8353` serves pairs 457 and 501. All four clinicians are PE-arm, so those offices
receive four calls rather than two. This was masked until two corrupt NPPES telephone numbers
were corrected — the sample never had 400 distinct practice lines, it has 398. Both duplicates
cross pairs rather than sitting within one, so the plan's `same_phone_within_pair` sensitivity
does not detect them; clustering on `phone_id` does.

**A provider-data ignore rule matched by exact filename.** `.gitignore` excluded
`redcap_physician_name_choices.txt`, but the builder writes that name with a `--suffix`, so
suffixed runs produced unignored files containing 800 clinician names and phone numbers. The
rule is now globbed. Nothing of the sort was ever committed; this closed a hole rather than
cleaning up a spill.
