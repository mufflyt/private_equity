# Row-level data contract.
#
# Sourcing this file has no side effects.
#
# WHY THIS EXISTS ALONGSIDE analysis_manifest.csv. That manifest is a COLUMN contract: what each
# column means, where it came from, what distribution it should have. It cannot express anything
# about ROWS -- how many there should be, which of them must be unique, that every matched pair
# holds exactly one PE and one non-PE clinician, that the 800 call slots cover 1..800 once each,
# or that two artifacts describe the same 400 people.
#
# Those are the invariants that carry the design. A calling sheet that silently gained a row, a
# pair that lost its control, a record id issued twice: none of them is a column-level defect,
# none would fail gate_provenance(), and each one quietly changes what the study is.
#
# The tracked calling artifacts are committed, so unlike most of this repository's data checks
# these run in CI against the real files rather than being confined to a machine that happens to
# have the cohort.

ROW_CONTRACT <- "config/row_contract.yml"

read_row_contract <- function(path = ROW_CONTRACT) {
  if (!file.exists(path)) stop("No row contract at ", path, call. = FALSE)
  yaml::read_yaml(path)
}

# Read as character throughout, and do not let read.csv invent missingness. na.strings is
# emptied because a literal "NA" in a data column is a value someone wrote, and blankness is
# tested explicitly below rather than inferred.
read_dataset <- function(path) {
  utils::read.csv(path, colClasses = "character", check.names = FALSE,
                  na.strings = character(0))
}

blank_col <- function(v) is.na(v) | !nzchar(trimws(v))

# ---- the rule engine --------------------------------------------------------
#
# Every rule returns character(0) when satisfied, or one message per violation. Rules are
# deliberately small and total: a rule that cannot evaluate (missing column, unreadable file)
# reports that rather than skipping, because a silently skipped rule is a green check that
# means nothing.

rule_rows <- function(df, n) {
  if (nrow(df) == n) character(0)
  else sprintf("row count is %d, contract says %d", nrow(df), n)
}

rule_unique <- function(df, cols) {
  out <- character(0)
  for (cn in cols) {
    if (!cn %in% names(df)) { out <- c(out, sprintf("unique: no column '%s'", cn)); next }
    d <- sum(duplicated(df[[cn]]))
    if (d) out <- c(out, sprintf("'%s' has %d duplicate value(s)", cn, d))
  }
  out
}

rule_non_empty <- function(df, cols) {
  out <- character(0)
  for (cn in cols) {
    if (!cn %in% names(df)) { out <- c(out, sprintf("non_empty: no column '%s'", cn)); next }
    b <- sum(blank_col(df[[cn]]))
    if (b) out <- c(out, sprintf("'%s' is blank in %d row(s)", cn, b))
  }
  out
}

rule_domains <- function(df, domains) {
  out <- character(0)
  for (cn in names(domains)) {
    if (!cn %in% names(df)) { out <- c(out, sprintf("domains: no column '%s'", cn)); next }
    bad <- setdiff(unique(trimws(df[[cn]])), unlist(domains[[cn]]))
    if (length(bad)) {
      out <- c(out, sprintf("'%s' has value(s) outside its domain: %s", cn,
                            paste(utils::head(bad, 5), collapse = ", ")))
    }
  }
  out
}

rule_group_size <- function(df, spec) {
  cn <- spec$column
  if (!cn %in% names(df)) return(sprintf("group_size: no column '%s'", cn))
  tb <- table(df[[cn]])
  bad <- names(tb)[tb != spec$size]
  if (!length(bad)) return(character(0))
  sprintf("%d group(s) in '%s' are not size %d (e.g. %s)", length(bad), cn, spec$size,
          paste(utils::head(bad, 5), collapse = ", "))
}

# Every group holds exactly one row per arm value. This is the invariant that makes a matched
# pair a matched pair; a pair with two PE members is not a comparison.
rule_balanced_groups <- function(df, spec) {
  g <- spec$group; a <- spec$arm
  if (!all(c(g, a) %in% names(df))) return(sprintf("balanced_groups: missing '%s' or '%s'", g, a))
  tb <- table(df[[g]], df[[a]])
  bad <- rownames(tb)[apply(tb, 1, function(r) any(r != 1L))]
  if (!length(bad)) return(character(0))
  sprintf("%d group(s) in '%s' do not hold exactly one row per '%s' (e.g. %s)",
          length(bad), g, a, paste(utils::head(bad, 5), collapse = ", "))
}

# The union of the named id columns must cover 1..n exactly once. An id issued twice double-books
# a call; an id never issued means a planned call has no slot.
rule_id_coverage <- function(df, spec) {
  cols <- unlist(spec$columns)
  if (!all(cols %in% names(df))) {
    return(sprintf("id_coverage: missing column(s) %s",
                   paste(setdiff(cols, names(df)), collapse = ", ")))
  }
  ids <- suppressWarnings(as.integer(unlist(df[cols], use.names = FALSE)))
  if (any(is.na(ids))) return("id_coverage: non-integer id present")
  want <- seq_len(spec$max)
  got <- sort(ids)
  if (identical(got, want)) return(character(0))
  c(if (length(got) != length(want))
      sprintf("id_coverage: %d ids for a range of %d", length(got), length(want)),
    if (anyDuplicated(got))
      sprintf("id_coverage: %d duplicate id(s)", sum(duplicated(got))),
    if (length(setdiff(want, got)))
      sprintf("id_coverage: %d id(s) never issued", length(setdiff(want, got))))
}

rule_columns_differ <- function(df, cols) {
  cols <- unlist(cols)
  if (!all(cols %in% names(df))) return("columns_differ: missing column(s)")
  n <- sum(df[[cols[1]]] == df[[cols[2]]])
  if (n) sprintf("'%s' equals '%s' in %d row(s)", cols[1], cols[2], n) else character(0)
}

# A `<form>_complete` column must name a form that actually exists in the project's data
# dictionary. This is not pedantry: REDCap silently ignores a completion column for a form it
# does not have, so the records import and none of them is marked complete.
rule_complete_form <- function(df, spec, root) {
  cc <- grep("_complete$", names(df), value = TRUE)
  if (!length(cc)) return("complete_form: no *_complete column present")
  dict <- file.path(root, spec$dictionary)
  if (!file.exists(dict)) return(sprintf("complete_form: dictionary not found: %s", spec$dictionary))
  d <- utils::read.csv(dict, colClasses = "character", check.names = FALSE)
  forms <- unique(trimws(d[[spec$form_column]]))
  named <- sub("_complete$", "", cc)
  bad <- setdiff(named, forms)
  if (!length(bad)) return(character(0))
  sprintf("completion column names form '%s', which is not in %s (forms: %s)",
          paste(bad, collapse = ", "), basename(spec$dictionary), paste(forms, collapse = ", "))
}

# Two artifacts must describe the same set of people.
rule_key_agreement <- function(spec, root) {
  a <- file.path(root, spec$left$path); b <- file.path(root, spec$right$path)
  if (!file.exists(a) || !file.exists(b)) return("key_agreement: a dataset is missing")
  A <- read_dataset(a); B <- read_dataset(b)
  if (!spec$left$column %in% names(A) || !spec$right$column %in% names(B)) {
    return("key_agreement: a key column is missing")
  }
  ka <- unique(trimws(A[[spec$left$column]])); kb <- unique(trimws(B[[spec$right$column]]))
  only_a <- setdiff(ka, kb); only_b <- setdiff(kb, ka)
  if (!length(only_a) && !length(only_b)) return(character(0))
  sprintf("%s and %s disagree: %d only in the first, %d only in the second",
          basename(a), basename(b), length(only_a), length(only_b))
}

#' Validate every dataset in the contract. Returns one row per violation.
validate_row_contract <- function(contract = read_row_contract(), root = ".") {
  findings <- list()
  note <- function(ds, msgs) {
    for (m in msgs) findings[[length(findings) + 1L]] <<-
      data.frame(dataset = ds, violation = m, stringsAsFactors = FALSE)
  }

  for (nm in names(contract$datasets)) {
    spec <- contract$datasets[[nm]]
    path <- file.path(root, spec$path)
    if (!file.exists(path)) { note(nm, sprintf("file not found: %s", spec$path)); next }
    df <- tryCatch(read_dataset(path), error = function(e) NULL)
    if (is.null(df)) { note(nm, "file could not be parsed as CSV"); next }

    if (!is.null(spec$rows))            note(nm, rule_rows(df, spec$rows))
    if (!is.null(spec$unique))          note(nm, rule_unique(df, unlist(spec$unique)))
    if (!is.null(spec$non_empty))       note(nm, rule_non_empty(df, unlist(spec$non_empty)))
    if (!is.null(spec$domains))         note(nm, rule_domains(df, spec$domains))
    if (!is.null(spec$group_size))      note(nm, rule_group_size(df, spec$group_size))
    if (!is.null(spec$balanced_groups)) note(nm, rule_balanced_groups(df, spec$balanced_groups))
    if (!is.null(spec$id_coverage))     note(nm, rule_id_coverage(df, spec$id_coverage))
    if (!is.null(spec$columns_differ))  note(nm, rule_columns_differ(df, spec$columns_differ))
    if (!is.null(spec$complete_form))   note(nm, rule_complete_form(df, spec$complete_form, root))
  }

  for (nm in names(contract$cross_dataset)) {
    note(nm, rule_key_agreement(contract$cross_dataset[[nm]], root))
  }

  if (!length(findings)) {
    data.frame(dataset = character(0), violation = character(0), stringsAsFactors = FALSE)
  } else do.call(rbind, findings)
}

if (sys.nframe() == 0L) {
  v <- validate_row_contract()
  if (!nrow(v)) cat("Row contract satisfied: no violations.\n")
  else { cat(sprintf("%d violation(s):\n", nrow(v))); print(v, row.names = FALSE) }
  quit(status = if (nrow(v)) 1L else 0L)
}
