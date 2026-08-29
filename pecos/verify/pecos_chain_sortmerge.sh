#!/bin/sh
# IMPLEMENTATION 2 of the PECOS relational chain, for independent verification.
#
# pecos/pecos_chain.py resolves the chain with in-memory hash tables and row-wise accumulation.
# This resolves the same chain with external sort-merge relational joins. Different algorithm,
# different memory model, different language, no shared code. If both agree exactly, a mistake
# would have to have been made twice in two different idioms.
#
# Only fields 1-3 of ppefenrol (npi, pecos_asct_cntl_id, enrlmt_id) are read. Every later field
# is free text that may contain an embedded comma, which naive splitting would mis-parse; these
# three cannot. That constraint is why this implementation reads no organisation names.
#
# Usage: sh pecos/verify/pecos_chain_sortmerge.sh <workdir> <pecos_data_dir>
set -e
W="$1"; D="$2"; T="$W/sm"; mkdir -p "$T"
export LC_ALL=C

tail -n +2 "$W/cohort_key_union.csv" | awk -F, '{print $1}' | sort -u > "$T/npis.txt"

# enrlmt_id -> PAC ID, for every enrolment in the file
tr -d '"' < "$D/ppefenrol.csv" | awk -F, 'NR>1{print $3"\t"$2}' | sort -u > "$T/enr_pac.tsv"

# cohort NPI -> its individual (I-prefixed) enrolments
tr -d '"' < "$D/ppefenrol.csv" \
  | awk -F, 'NR>1 && substr($3,1,1)=="I"{print $1"\t"$3}' | sort -u > "$T/all_ind.tsv"
join -t "$(printf '\t')" -1 1 -2 1 "$T/npis.txt" \
     "$(printf '%s' "$T/all_ind.tsv")" 2>/dev/null \
  || join -t "$(printf '\t')" -1 1 -2 1 "$T/npis.txt" "$T/all_ind.tsv" \
  | awk -F'\t' '{print $2"\t"$1}' | sort -u > "$T/cohort_enr.tsv"

# reassignment, organisation-receiving only. I->I rows are excluded: the receiving party is a
# person, not a practice entity.
tr -d '"' < "$D/ppefreassign.csv" \
  | awk -F, 'NR>1 && substr($2,1,1)=="O"{print $1"\t"$2}' | sort -u > "$T/reassign.tsv"

join -t "$(printf '\t')" -1 1 -2 1 "$T/cohort_enr.tsv" "$T/reassign.tsv" \
  | awk -F'\t' '{print $2"\t"$3}' | sort -u > "$T/npi_rcv.tsv"

# PAC-level membership: distinct individual PACs reassigning into each organisation PAC
join -t "$(printf '\t')" -1 1 -2 1 "$T/reassign.tsv" "$T/enr_pac.tsv" \
  | awk -F'\t' '{print $2"\t"$3}' | sort -u > "$T/rcv_ipac.tsv"
join -t "$(printf '\t')" -1 1 -2 1 "$T/rcv_ipac.tsv" "$T/enr_pac.tsv" \
  | awk -F'\t' '{print $3"\t"$2}' | sort -u \
  | awk -F'\t' '{c[$1]++} END{for (k in c) print k"\t"c[k]}' \
  | sort -t "$(printf '\t')" -k1,1 > "$T/pac_members.tsv"

echo "cohort NPI -> receiving enrolment : $(wc -l < "$T/npi_rcv.tsv")"
echo "organisation PACs with members    : $(wc -l < "$T/pac_members.tsv")"
echo "distinct cohort NPIs reassigning  : $(cut -f1 "$T/npi_rcv.tsv" | sort -u | wc -l)"
