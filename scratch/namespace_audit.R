# Enumerate the exported namespace of every canonical Muffly package and intersect it with the
# functions written inline in private_equity.
#
# All seven repositories are clean and on main with GitHub remotes, so the local checkouts are
# byte-identical to what `remotes::install_github()` would fetch. Exports are read from
# NAMESPACE rather than from an installed namespace so that packages which are not currently
# installed are still enumerated.

HOME <- Sys.getenv("HOME")
PKGS <- c("isochrones", "twostep", "mysterycall", "mysterymaps", "cliff", "mufflyaccess",
          "simulation")

exports_of <- function(p) {
  ns <- file.path(HOME, p, "NAMESPACE")
  if (!file.exists(ns)) return(character(0))
  ln <- readLines(ns, warn = FALSE)
  e <- grep("^export\\(", ln, value = TRUE)
  nm <- gsub('^export\\(|\\)$|"', "", e)
  if (any(grepl("exportPattern", ln))) {
    # Project-style package: enumerate top-level function definitions instead.
    fs <- list.files(file.path(HOME, p, "R"), pattern = "\\.R$", full.names = TRUE)
    defs <- unlist(lapply(fs, function(f) {
      src <- readLines(f, warn = FALSE)
      d <- grep("^\\s*[A-Za-z._][A-Za-z0-9._]*\\s*(<-|=)\\s*function", src, value = TRUE)
      trimws(sub("\\s*(<-|=)\\s*function.*$", "", d))
    }))
    nm <- unique(c(nm, defs))
  }
  sort(unique(nm[nzchar(nm)]))
}

ex <- lapply(PKGS, exports_of)
names(ex) <- PKGS

cat("=== exported / defined function counts ===\n")
for (p in PKGS) cat(sprintf("  %-14s %5d\n", p, length(ex[[p]])))

# ---------------------------------------------------------------- overlap between packages
cat("\n=== names defined in more than one package ===\n")
all_nm <- unlist(ex, use.names = FALSE)
dupes <- sort(unique(all_nm[duplicated(all_nm)]))
for (d in dupes) {
  where <- PKGS[vapply(ex, function(v) d %in% v, logical(1))]
  cat(sprintf("  %-42s %s\n", d, paste(where, collapse = ", ")))
}
cat(sprintf("  (%d name(s))\n", length(dupes)))

# ---------------------------------------------------------------- what private_equity defines
PE <- "."
pe_files <- c(list.files(file.path(PE, "R"), pattern = "\\.R$", full.names = TRUE),
              list.files(PE, pattern = "\\.R$", full.names = TRUE))
pe_defs <- unlist(lapply(pe_files, function(f) {
  src <- readLines(f, warn = FALSE)
  d <- grep("^\\s*[A-Za-z._][A-Za-z0-9._]*\\s*<-\\s*function", src, value = TRUE)
  stats::setNames(rep(basename(f), length(d)), trimws(sub("\\s*<-\\s*function.*$", "", d)))
}))

cat(sprintf("\n=== private_equity defines %d top-level functions in %d files ===\n",
            length(pe_defs), length(unique(pe_defs))))

# ---------------------------------------------------------------- candidate canonical matches
# Match on the informative stem, ignoring package prefixes and common verbs, so that
# npi_key <-> mysterycall_clean_npi style pairs surface.
stem <- function(x) {
  s <- tolower(x)
  s <- sub("^(mysterycall|mysterymaps|mufflyaccess|isochrones|twostep|cliff|urpssim|sim)_", "", s)
  s <- gsub("[^a-z0-9]", "", s)
  s
}

cat("\n=== private_equity function -> candidate canonical equivalents ===\n")
lookup <- do.call(rbind, lapply(PKGS, function(p)
  if (length(ex[[p]])) data.frame(pkg = p, fn = ex[[p]], stem = stem(ex[[p]]),
                                  stringsAsFactors = FALSE) else NULL))

for (i in seq_along(pe_defs)) {
  nm <- names(pe_defs)[i]
  st <- stem(nm)
  if (nchar(st) < 4) next
  hit <- lookup[lookup$stem == st | grepl(st, lookup$stem, fixed = TRUE) |
                  vapply(lookup$stem, function(z) grepl(z, st, fixed = TRUE) && nchar(z) >= 5,
                         logical(1)), ]
  if (nrow(hit)) {
    cat(sprintf("\n  %s  (%s)\n", nm, pe_defs[[i]]))
    for (j in seq_len(min(nrow(hit), 6))) cat(sprintf("      -> %s::%s\n", hit$pkg[j], hit$fn[j]))
  }
}

# ---------------------------------------------------------------- concept search
cat("\n=== concept search across all packages ===\n")
concepts <- c(npi = "npi", phone = "phone", address = "address|street|suite",
              geocode = "geocod|lat_?long|coordinate", distance = "haversine|distance|miles",
              join = "join|merge|key", missing = "missing|mcar|mar\\b|impute",
              power = "power|sample_size|mde", psm = "match|propensity|caliper|smd",
              svi = "svi|vulnerab|deprivation|tract", redcap = "redcap",
              strobe = "strobe|consort|flow", zip = "zip|zcta|fips",
              provenance = "provenance|manifest|audit|validate|assert|gate")
for (cn in names(concepts)) {
  hits <- lookup[grepl(concepts[[cn]], lookup$fn, ignore.case = TRUE), ]
  if (!nrow(hits)) next
  cat(sprintf("\n-- %s (%d)\n", cn, nrow(hits)))
  by <- split(hits$fn, hits$pkg)
  for (p in names(by)) cat(sprintf("   %-14s %s\n", p, paste(utils::head(by[[p]], 14), collapse = ", ")))
}
