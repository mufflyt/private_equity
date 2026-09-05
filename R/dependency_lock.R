# Read, scan and diff the dependency lockfile.
#
# Sourcing this file has no side effects: it defines functions and nothing else.
#
# WHAT THE LOCKFILE IS FOR, and what it deliberately is not. config/dependencies.lock records
# the exact versions the analysis was last run against, so a result can be tied to an
# environment. It is a PROVENANCE RECORD and a COMPLETENESS CONTRACT, not an installer.
#
# It does NOT pin what CI installs. That question was already decided and reverted in this
# repository (79e1ced pinned gates.yml to known-good SHAs, 9844370 reverted it), so re-deciding
# it as a side effect of adding a lockfile would be relitigating someone else's call. gates.yml
# is untouched here; see docs/APPENDIX_DEPENDENCIES.md for the tradeoff and who owns it.
#
# The one thing the lockfile DOES gate is completeness: every package the code actually loads
# must be recorded. That check is environment-independent -- it compares the code against the
# lockfile, not against whatever happens to be installed -- so it is safe to run in CI, where
# the installed versions legitimately differ from a developer's machine.

LOCK_DEFAULT <- "config/dependencies.lock"

# Base and recommended packages ship with R itself and are never installed separately, so they
# are not lockfile entries. Hardcoded rather than read from installed.packages(priority=...)
# because that call answers "what is on THIS machine", which is exactly the environment
# dependence this file exists to avoid.
R_BUNDLED <- c("base", "compiler", "datasets", "grDevices", "graphics", "grid", "methods",
               "parallel", "splines", "stats", "stats4", "tcltk", "tools", "utils",
               "boot", "class", "cluster", "codetools", "foreign", "KernSmooth", "lattice",
               "MASS", "Matrix", "mgcv", "nlme", "nnet", "rpart", "spatial", "survival")

#' Parse config/dependencies.lock into a data frame.
#'
#' Format is one record per line: `<source> <name> <version> [sha]`. Blank lines and lines
#' beginning with `#` are ignored. `key = value` lines carry the interpreter versions.
read_lockfile <- function(path = LOCK_DEFAULT) {
  if (!file.exists(path)) stop("No dependency lockfile at ", path, call. = FALSE)
  ln <- readLines(path, warn = FALSE)
  ln <- ln[!grepl("^\\s*#", ln) & nzchar(trimws(ln))]

  is_kv <- grepl("=", ln) & !grepl("^\\s*(cran|github|pypi)\\s", ln)
  meta <- list()
  if (any(is_kv)) {
    kv <- ln[is_kv]
    meta <- stats::setNames(as.list(trimws(sub("^[^=]*=", "", kv))),
                            trimws(sub("=.*$", "", kv)))
  }

  rec <- ln[!is_kv]
  parts <- strsplit(trimws(rec), "\\s+")
  bad <- which(lengths(parts) < 3L)
  if (length(bad)) {
    stop("Malformed lockfile record(s) at: ", paste(rec[bad], collapse = " | "), call. = FALSE)
  }
  df <- data.frame(
    source  = vapply(parts, `[`, character(1), 1L),
    name    = vapply(parts, `[`, character(1), 2L),
    version = vapply(parts, `[`, character(1), 3L),
    sha     = vapply(parts, function(p) if (length(p) >= 4L) p[4L] else NA_character_, character(1)),
    stringsAsFactors = FALSE)
  list(meta = meta, deps = df)
}

#' Every R package the tracked source actually loads.
#'
#' Matches the four ways this codebase reaches a package: library(), require(),
#' requireNamespace("x") and x::fn. Bundled packages are dropped, because they are not
#' installable dependencies.
scan_r_dependencies <- function(root = ".") {
  files <- list.files(root, pattern = "\\.(R|r|Rmd|qmd)$", recursive = TRUE, full.names = TRUE)
  files <- files[!grepl("/(\\.git|\\.venv|__pycache__|renv)/", files)]
  hits <- character(0)
  for (f in files) {
    txt <- readLines(f, warn = FALSE)
    # A file may opt out by carrying the marker below. The only legitimate reason is that the
    # file contains package names as FIXTURE DATA rather than as its own imports -- the
    # scanner's own test writes `library(alpha)` into a temp file to prove the scanner sees
    # it, and would otherwise report `alpha` as an unrecorded dependency of this repository.
    # Opting out is deliberately a visible line in the file, not a path list living somewhere
    # else that no one reads.
    if (any(grepl("DEPENDENCY-SCAN:\\s*ignore", txt))) next
    txt <- txt[!grepl("^\\s*#", txt)]          # a package named only in a comment is not a dep
    one <- paste(txt, collapse = "\n")
    hits <- c(hits,
      # library(pkg) / require(pkg), quoted or bare
      sub(".*\\(\\s*['\"]?([A-Za-z][A-Za-z0-9._]*).*", "\\1",
          regmatches(one, gregexpr("(?:library|require)\\(\\s*['\"]?[A-Za-z][A-Za-z0-9._]*",
                                   one))[[1]]),
      sub(".*\\(\\s*['\"]([A-Za-z][A-Za-z0-9._]*).*", "\\1",
          regmatches(one, gregexpr("requireNamespace\\(\\s*['\"][A-Za-z][A-Za-z0-9._]*",
                                   one))[[1]]),
      # Lookbehind excludes two real false positives: a sprintf format string ("%s::%s"
      # matched as package "s"), and the tail of a longer identifier. perl = TRUE is required
      # for the lookbehind; TRE does not support one.
      sub("::$", "",
          regmatches(one, gregexpr("(?<![A-Za-z0-9._%])[A-Za-z][A-Za-z0-9._]*::",
                                   one, perl = TRUE))[[1]]))
  }
  setdiff(sort(unique(hits)), R_BUNDLED)
}

#' Every Python package declared in requirements.txt.
scan_py_dependencies <- function(path = "requirements.txt") {
  if (!file.exists(path)) return(character(0))
  ln <- readLines(path, warn = FALSE)
  ln <- trimws(ln[!grepl("^\\s*#", ln) & nzchar(trimws(ln))])
  sort(unique(tolower(sub("[<>=!~;\\[].*$", "", ln))))
}

#' Packages the code loads that the lockfile does not record.
#'
#' This is the gated direction. The reverse (recorded but unused) is reported for tidiness but
#' is not a defect: a package can legitimately be needed to render the manuscript or to run a
#' script that lives outside the scanned extensions.
lockfile_missing <- function(lock = read_lockfile(), root = ".") {
  r_used  <- scan_r_dependencies(root)
  py_used <- scan_py_dependencies(file.path(root, "requirements.txt"))
  r_have  <- lock$deps$name[lock$deps$source %in% c("cran", "github")]
  py_have <- tolower(lock$deps$name[lock$deps$source == "pypi"])
  list(r = setdiff(r_used, r_have), python = setdiff(py_used, py_have))
}

#' Compare the lockfile against the packages actually installed here.
#'
#' A report, never a gate: CI installs from RSPM and will legitimately differ from a
#' developer's machine. Use it to decide when to regenerate, not to fail a build.
lockfile_drift <- function(lock = read_lockfile()) {
  rows <- lock$deps[lock$deps$source %in% c("cran", "github"), , drop = FALSE]
  rows$installed <- vapply(rows$name, function(p) {
    tryCatch(as.character(utils::packageVersion(p)), error = function(e) NA_character_)
  }, character(1))
  rows$status <- ifelse(is.na(rows$installed), "NOT INSTALLED",
                 ifelse(rows$installed == rows$version, "match", "DRIFTED"))
  rows[, c("source", "name", "version", "installed", "status")]
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if ("--drift" %in% args) {
    d <- lockfile_drift()
    print(d[d$status != "match", , drop = FALSE], row.names = FALSE)
    cat(sprintf("\n%d of %d recorded R package(s) differ from this environment.\n",
                sum(d$status != "match"), nrow(d)))
  } else {
    m <- lockfile_missing()
    cat(sprintf("R packages used but not locked    : %s\n",
                if (length(m$r)) paste(m$r, collapse = ", ") else "(none)"))
    cat(sprintf("Python packages used but not locked: %s\n",
                if (length(m$python)) paste(m$python, collapse = ", ") else "(none)"))
  }
}
