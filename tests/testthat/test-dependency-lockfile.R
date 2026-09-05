# Dependency lockfile: 3 BVA, 3 semantic, 3 adversarial.
#
# WHAT THIS GOVERNS. config/dependencies.lock records the versions the analysis was last run
# against. A result that cannot name its environment cannot be reproduced, and this repository
# had no such record: gates.yml installed two GitHub packages from a floating branch head, and
# nothing anywhere wrote down what that head was on the day a number was produced.
#
# WHAT IS GATED, and why only this. The gated contract is COMPLETENESS: every package the code
# actually loads must be recorded. That compares the CODE against the LOCKFILE and never
# touches the installed library, so it means the same thing on a developer's laptop and on a CI
# runner that installed different versions from RSPM.
#
# Version EQUALITY is deliberately not gated. CI installs current CRAN; a developer has
# whatever they have. A test demanding they match would be red on every machine except the one
# that last regenerated the file, which is a gate people learn to bypass -- the exact failure
# tests/BLOCKING warns about. lockfile_drift() reports that comparison for humans instead.
#
# Pinning gates.yml is likewise NOT done here. It was decided and reverted already (79e1ced,
# then 9844370); re-deciding it as a side effect of adding a lockfile would be relitigating
# someone else's call. See docs/APPENDIX_DEPENDENCIES.md.
#
# MUTATION EVIDENCE (Law 1, docs/SCIENTIFIC_CI_LAWS.md). Both controls run live, because a
# scanner that stops matching is the failure mode here and a comment cannot detect it:
#   negative control  a package present in synthetic source but absent from a synthetic lock
#                     must be reported missing (test 4).
#   positive control  the same comparison with the package recorded must report nothing, so a
#                     pass cannot come from a scanner that finds nothing in anything (test 5).
#   end-to-end        2026-09-05: appending `library(zzfakepkg)` to a tracked .R file made
#                     "adversarial: every package the code loads is recorded" fail naming
#                     zzfakepkg, and only that test. Reverting returned the file to green.

# DEPENDENCY-SCAN: ignore -- this file writes package names (alpha, bravo, ...) into temp
# files as fixture data to prove the scanner sees them. Without this marker the scanner reads
# its own fixtures back as unrecorded dependencies of the repository.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
source(file.path(root, "R", "dependency_lock.R"))
LOCK <- file.path(root, "config", "dependencies.lock")

lock <- read_lockfile(LOCK)

# ---------------------------------------------------------------- BVA (3)

test_that("BVA: the lockfile parses and carries both interpreter versions", {
  expect_true(file.exists(LOCK))
  expect_true(nrow(lock$deps) > 0L)
  for (k in c("r_version", "python_version", "recorded_on")) {
    expect_true(k %in% names(lock$meta), info = sprintf("lockfile has no %s", k))
    expect_true(nzchar(lock$meta[[k]]))
  }
  expect_match(lock$meta$r_version, "^[0-9]+\\.[0-9]+\\.[0-9]+$")
  expect_match(lock$meta$recorded_on, "^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
})

test_that("BVA: every record has a known source and a non-empty version", {
  expect_true(all(lock$deps$source %in% c("cran", "github", "pypi")),
              info = paste("unknown source(s):",
                           paste(setdiff(lock$deps$source, c("cran", "github", "pypi")),
                                 collapse = ", ")))
  expect_true(all(nzchar(lock$deps$version)))
  expect_false(any(duplicated(paste(lock$deps$source, lock$deps$name))),
               info = "a package recorded twice can carry two different versions")
})

test_that("BVA: github records carry a full 40-character commit sha, cran records carry none", {
  gh <- lock$deps[lock$deps$source == "github", , drop = FALSE]
  expect_true(nrow(gh) > 0L, info = "no github dependencies recorded; mysterycall is one")
  expect_true(all(grepl("^[0-9a-f]{40}$", gh$sha)),
              info = "an abbreviated sha is ambiguous across a repository's lifetime")
  cran <- lock$deps[lock$deps$source == "cran", , drop = FALSE]
  expect_true(all(is.na(cran$sha)),
              info = "a cran record with a sha is a mis-parsed line, not extra information")
})

# ---------------------------------------------------------------- semantic (3)

test_that("semantic: the R scanner finds each of the four ways this codebase loads a package", {
  tmp <- tempfile(fileext = ".R"); on.exit(unlink(tmp), add = TRUE)
  writeLines(c("library(alpha)", "require(bravo)", 'requireNamespace("charlie")',
               "delta::fn()", "# echo::commented_out()"), tmp)
  found <- scan_r_dependencies(dirname(tmp))
  for (p in c("alpha", "bravo", "charlie", "delta")) {
    expect_true(p %in% found, info = sprintf("scanner missed %s", p))
  }
  expect_false("echo" %in% found,
               info = "a package named only in a comment is not a dependency")
})

test_that("semantic: the scanner is not fooled by a sprintf format string", {
  # Real false positive found while writing this: scratch/namespace_audit.R contains
  # sprintf("%s::%s"), which a naive [A-Za-z]+:: pattern reads as a package called "s".
  tmp <- tempfile(fileext = ".R"); on.exit(unlink(tmp), add = TRUE)
  writeLines('cat(sprintf("  -> %s::%s\\n", pkg, fn))', tmp)
  expect_false("s" %in% scan_r_dependencies(dirname(tmp)))
})

test_that("semantic: bundled R packages are not treated as installable dependencies", {
  tmp <- tempfile(fileext = ".R"); on.exit(unlink(tmp), add = TRUE)
  writeLines(c("stats::median(1)", "utils::read.csv('x')", "MASS::glm.nb"), tmp)
  found <- scan_r_dependencies(dirname(tmp))
  expect_false(any(c("stats", "utils", "MASS") %in% found),
               info = "base and recommended packages ship with R and are never installed")
})

# ---------------------------------------------------------------- adversarial (3)

test_that("adversarial: NEGATIVE and POSITIVE control on the completeness comparison", {
  tmp <- file.path(tempdir(), "lockctl"); dir.create(tmp, showWarnings = FALSE)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  writeLines("library(zzsynthetic)", file.path(tmp, "src.R"))
  writeLines("requirements.txt", file.path(tmp, "requirements.txt"))

  bare <- list(meta = list(), deps = data.frame(source = "cran", name = "other",
                                                version = "1.0", sha = NA_character_,
                                                stringsAsFactors = FALSE))
  # negative control: an unrecorded package MUST be reported
  expect_true("zzsynthetic" %in% lockfile_missing(bare, root = tmp)$r,
              info = "the completeness check failed to notice an unrecorded package")

  # positive control: once recorded, nothing is reported -- so a pass is not vacuous
  full <- bare
  full$deps <- rbind(full$deps, data.frame(source = "cran", name = "zzsynthetic",
                                           version = "1.0", sha = NA_character_,
                                           stringsAsFactors = FALSE))
  expect_length(lockfile_missing(full, root = tmp)$r, 0L)
})

test_that("adversarial: every package the code loads is recorded in the lockfile", {
  miss <- lockfile_missing(lock, root = root)
  expect_length(miss$r, 0L)
  expect_length(miss$python, 0L)
})

test_that("adversarial: the two GitHub dependencies CI installs are both recorded", {
  # gates.yml installs these from a floating branch head. If one is ever added to CI and not
  # here, the lockfile silently stops describing the environment CI actually builds.
  ci <- readLines(file.path(root, ".github", "workflows", "gates.yml"), warn = FALSE)
  installed <- sub(".*github::[^/]+/([A-Za-z0-9._-]+).*", "\\1",
                   grep("github::", ci, value = TRUE))
  installed <- unique(trimws(installed))
  expect_true(length(installed) > 0L, info = "no github:: install found in gates.yml")
  expect_true(all(installed %in% lock$deps$name[lock$deps$source == "github"]),
              info = paste("in gates.yml but not the lockfile:",
                           paste(setdiff(installed, lock$deps$name), collapse = ", ")))
})
