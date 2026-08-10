# Cycle 19 -- 4 BVA, 3 semantic, 3 adversarial.
# Follows the manual verification: the roster name "Cindy Joslyn, MD" contradicted her own
# CNM credential, and that appended "MD" is how she passed the MD/DO derivation. This cycle
# asks how far that parsing failure extends.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)
rd <- function(f) utils::read.csv(f, colClasses = "character", check.names = FALSE)

roster <- rd(p("pe_obgyn_providers_active.csv"))
g <- function(col) trimws(ifelse(is.na(roster[[col]]), "", roster[[col]]))

name  <- g("Provider Name")
npc   <- toupper(g("NPPES Credentials"))
first <- g("Parsed First Name")
last  <- g("Parsed Last Name")

# The token appended after the comma in the name, stripped to letters.
tok  <- toupper(trimws(sub("^[^,]*, *", "", ifelse(grepl(",", name), name, ""))))
tok  <- gsub("[^A-Z]", "", tok)
npcc <- gsub("[^A-Z]", "", npc)

MIDLEVEL <- c("CNM", "NP", "PA", "PAC", "RN", "APRN", "WHNP", "DNP", "FNP",
              "ARNP", "CRNP", "APN", "MSN", "LPN")
# Board memberships and degrees that legitimately follow a physician credential.
HONORIFIC <- c("FACOG", "FACS", "FACOOG", "MPH", "PHD", "MSCE", "MS", "MBA", "FACP")

strip_honorific <- function(x) {
  for (h in HONORIFIC) x <- gsub(h, "", x, fixed = TRUE)
  x
}

# ---------------------------------------------------------------- BVA (4)

test_that("BVA: every roster row has a non-empty provider name", {
  expect_equal(sum(!nzchar(name)), 0L)
  expect_true(nrow(roster) > 0L)
})

test_that("BVA: a name-embedded credential without MD or DO never reaches the cohort", {
  # Premise correction: enumerating every legitimate extra degree (MDJD, MDMIGS, MDFPMRS,
  # DOESQ ...) is unbounded and not the contract. What matters is that a name claiming ONLY
  # a non-physician credential must not enter the study. Three such rows exist in the roster
  # (embryology lab director, genetic counsellor, dietitian) and all three carry no NPI, so
  # the NPI requirement excludes them before matching.
  core <- strip_honorific(tok)
  nonphys_only <- nzchar(core) & !grepl("MD|DO", core)
  expect_true(all(!nzchar(npi_key(roster$NPI[nonphys_only]))),
              info = sprintf("%d non-physician-only names carry an NPI and could enter the cohort",
                             sum(nonphys_only & nzchar(npi_key(roster$NPI)))))
})

test_that("BVA: a generational suffix is not absorbed into the credential token", {
  # "Name, Jr, MD" collapses to the token JRMD, so the suffix and the credential are no
  # longer separable and the credential no longer compares equal to NPPES.
  suffixed <- grep("^(JR|SR|II|III|IV)", tok, value = TRUE)
  expect_length(suffixed, 0L)
})

test_that("BVA: parsed first and last names are populated wherever a name exists", {
  have_name <- nzchar(name)
  expect_true(sum(have_name) > 0L)
  expect_equal(sum(have_name & !nzchar(last)), 0L)
  expect_equal(sum(have_name & !nzchar(first)), 0L)
})

# ---------------------------------------------------------------- semantic (3)

test_that("semantic: a name claiming MD or DO never contradicts a mid-level credential", {
  # This is the defect that let a certified nurse midwife into a physician cohort. It is a
  # narrow test on purpose: only a physician claim against a non-physician credential.
  bad <- which(strip_honorific(tok) %in% c("MD", "DO") & npcc %in% MIDLEVEL)
  expect_length(bad, 0L)
})

test_that("semantic: board memberships are not treated as credential conflicts", {
  # MDFACOG against NPPES MD is the same credential plus a board membership, not a conflict.
  both <- nzchar(tok) & nzchar(npcc)
  raw_conflict <- sum(both & tok != npcc)
  real_conflict <- sum(both & strip_honorific(tok) != strip_honorific(npcc))
  expect_true(real_conflict < raw_conflict,
              info = sprintf("%d raw mismatches reduce to %d once board suffixes are stripped",
                             raw_conflict, real_conflict))
})

test_that("semantic: the parsed surname appears in the source name", {
  ok <- nzchar(name) & nzchar(last)
  matched <- mapply(function(n, l) grepl(l, n, fixed = TRUE, useBytes = TRUE),
                    toupper(name[ok]), toupper(last[ok]))
  expect_true(mean(matched) > 0.95,
              info = sprintf("%.1f%% of parsed surnames appear in their source name",
                             100 * mean(matched)))
})

# ---------------------------------------------------------------- adversarial (3)

test_that("adversarial: the roster stores NPI without a float suffix", {
  expect_false(any(grepl("\\.", g("NPI"))),
               info = "a float NPI in the roster propagates the join hazard to every consumer")
})

test_that("adversarial: no clinician appears twice under different NPIs", {
  # Premise correction: rows with a blank NPI must be excluded first. The apparent
  # duplicates were a named clinician paired with their own unmatched, NPI-less row, which
  # is one person, not two NPIs.
  key <- paste(toupper(first), toupper(last))
  ok <- nzchar(first) & nzchar(last) & nzchar(npi_key(roster$NPI))
  dup_names <- names(which(table(key[ok]) > 1))
  same_person <- vapply(dup_names, function(k) {
    length(unique(npi_key(roster$NPI[ok][key[ok] == k]))) > 1L
  }, logical(1))
  expect_equal(sum(same_person), 0L,
               info = sprintf("%d names map to more than one NPI", sum(same_person)))
})

test_that("adversarial: credential conflicts are bounded and enumerable, not open-ended", {
  # A pipeline cannot be audited if the number of contradictory records is unknown. Pin it.
  both <- nzchar(tok) & nzchar(npcc)
  real_conflict <- which(both & strip_honorific(tok) != strip_honorific(npcc))
  expect_true(length(real_conflict) < 0.05 * nrow(roster),
              info = sprintf("%d of %d roster rows carry a genuine credential conflict",
                             length(real_conflict), nrow(roster)))
})
