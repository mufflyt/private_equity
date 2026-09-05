# Manuscript render contract: 3 BVA, 3 semantic, 3 adversarial.
#
# WHAT THIS GOVERNS. .github/workflows/manuscript.yml renders what CAN be rendered in CI. Two
# documents cannot be: private_equity_manuscript.qmd and private_equity_title_page.qmd read
# primary_analysis_results.rds and pe_obgyn_study_database.csv, both gitignored and neither
# present on a runner. --no-execute does not rescue them -- it skips chunks but still evaluates
# INLINE R, so `r wc_body` fails on a variable the skipped chunk would have defined.
#
# So the checks that need no pandoc and no data live here instead, and cover ALL manuscript
# sources including those two: every citation key resolves, and every YAML header parses.
#
# WHY AN UNRESOLVED CITATION IS THE CHECK WORTH HAVING. Pandoc does not fail on one. It renders
# the key as a literal "**smith2020?**" and exits 0. A broken reference therefore reaches a
# submitted manuscript behind a green build unless something asks the question directly.
#
# MUTATION EVIDENCE (Law 1, docs/SCIENTIFIC_CI_LAWS.md):
#   negative control  a synthetic source citing a key absent from a synthetic bibliography must
#                     be reported (test 4). Runs live.
#   positive control  the same source against a bibliography containing the key must report
#                     nothing, so a pass is not the scanner failing to find anything (test 4).
#   end-to-end        2026-09-05, two mutations, each producing exactly one failure and
#                     exactly the right one:
#                       [@zhu2020specialties] -> [@zhu2020specialtiestypo] in manuscript_cite.md
#                         -> "adversarial: every citation in every manuscript source resolves"
#                       manuscript.yml told to render some_other.md instead
#                         -> "semantic: the workflow renders the documents that can be
#                            rendered, and no others"
#                     Both reverted clean to 36 passed / 0 failed.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
MS <- file.path(root, "manuscript")

bib_keys <- function(path = file.path(MS, "references.bib")) {
  txt <- readLines(path, warn = FALSE)
  trimws(sub("^@\\w+\\{\\s*([^,]+),.*$", "\\1", grep("^@\\w+\\{", txt, value = TRUE)))
}

manuscript_sources <- function() {
  f <- list.files(MS, pattern = "\\.(qmd|md)$", full.names = TRUE)
  # README.md documents the render command; it is not a manuscript source.
  f[basename(f) != "README.md"]
}

# Citation keys actually cited. Pandoc accepts both bracketed [@key] and in-text @key forms;
# reading only the bracketed one would miss half the citations and pass vacuously.
cited_keys <- function(txt) {
  one <- paste(txt, collapse = "\n")
  bracketed <- unlist(regmatches(one, gregexpr("\\[[^]]*@[^]]*\\]", one)))
  keys <- unlist(regmatches(bracketed,
                            gregexpr("@[A-Za-z][A-Za-z0-9_:.#$%&+?<>~/-]*", bracketed)))
  intext <- unlist(regmatches(one,
              gregexpr("(?<![\\[\\w@])@[A-Za-z][A-Za-z0-9_:.-]*[0-9]{4}[A-Za-z0-9_:.-]*",
                       one, perl = TRUE)))
  unique(sub("^@", "", c(keys, intext)))
}

unresolved <- function(txt, keys) setdiff(cited_keys(txt), keys)

KEYS <- bib_keys()

# ---------------------------------------------------------------- BVA (3)

test_that("BVA: the bibliography exists, parses, and has unique keys", {
  expect_true(file.exists(file.path(MS, "references.bib")))
  expect_true(length(KEYS) > 0L, info = "no @entry{key parsed out of references.bib")
  expect_false(any(duplicated(KEYS)),
               info = paste("duplicate bib key(s):",
                            paste(unique(KEYS[duplicated(KEYS)]), collapse = ", ")))
  expect_true(all(nzchar(KEYS)))
})

test_that("BVA: the render toolchain files the workflow depends on are present", {
  for (f in c("references.bib", "ama.csl", "pandoc-reference.docx", "manuscript_cite.md")) {
    expect_true(file.exists(file.path(MS, f)),
                info = sprintf("manuscript/%s is referenced by the render and is missing", f))
  }
})

test_that("BVA: there is at least one manuscript source to check", {
  # Guards against the whole file passing because a glob stopped matching.
  expect_true(length(manuscript_sources()) >= 4L,
              info = "fewer manuscript sources than expected; the checks below may be vacuous")
})

# ---------------------------------------------------------------- semantic (3)

test_that("semantic: the citation scanner reads both pandoc citation forms", {
  expect_true("smith2020" %in% cited_keys("as shown [@smith2020]"))
  expect_true("jones2019" %in% cited_keys("@jones2019 showed that"))
  expect_true(all(c("a2020", "b2021") %in% cited_keys("[@a2020; @b2021]")))
  expect_false("notacite" %in% cited_keys("email me at name@notacite.org"),
               info = "an email address is not a citation")
})

test_that("semantic: every YAML header in every manuscript source parses", {
  for (f in manuscript_sources()) {
    txt <- readLines(f, warn = FALSE)
    if (!length(txt) || !grepl("^---\\s*$", txt[1])) next   # no front matter is legitimate
    close_at <- grep("^---\\s*$", txt)[2]
    expect_false(is.na(close_at),
                 info = sprintf("%s opens a YAML header that is never closed", basename(f)))
    hdr <- txt[2:(close_at - 1)]
    ok <- tryCatch({ yaml::yaml.load(paste(hdr, collapse = "\n")); TRUE },
                   error = function(e) conditionMessage(e))
    expect_true(isTRUE(ok),
                info = sprintf("%s has an unparseable YAML header: %s", basename(f), ok))
  }
})

test_that("semantic: the workflow renders the documents that can be rendered, and no others", {
  wf <- readLines(file.path(root, ".github", "workflows", "manuscript.yml"), warn = FALSE)
  one <- paste(wf, collapse = "\n")
  expect_true(grepl("manuscript_cite.md", one, fixed = TRUE),
              info = "CI no longer renders the one document that renders completely")
  # These two need gitignored analysis output. Asking CI to render them yields a failing job
  # that everyone learns to ignore, which is worse than not checking.
  for (f in c("private_equity_manuscript.qmd", "private_equity_title_page.qmd")) {
    rendered <- grepl(sprintf("quarto render[^\n]*%s", f), one)
    expect_false(rendered,
                 info = sprintf("CI tries to render %s, which needs data CI does not have", f))
  }
})

# ---------------------------------------------------------------- adversarial (3)

test_that("adversarial: NEGATIVE and POSITIVE control on the citation resolver", {
  src <- "Prior work [@present2020; @absent1999] showed."
  expect_equal(unresolved(src, c("present2020")), "absent1999",
               info = "the resolver missed a citation that is not in the bibliography")
  expect_length(unresolved(src, c("present2020", "absent1999")), 0L)
  expect_length(unresolved("no citations here", KEYS), 0L)
})

test_that("adversarial: every citation in every manuscript source resolves", {
  bad <- list()
  for (f in manuscript_sources()) {
    u <- unresolved(readLines(f, warn = FALSE), KEYS)
    if (length(u)) bad[[basename(f)]] <- u
  }
  # expect_length() takes no `info`, and an unresolved key is useless without its file name,
  # so report through expect_true() where the message survives.
  detail <- if (length(bad)) {
    paste(mapply(function(f, k) sprintf("%s: %s", f, paste(k, collapse = ", ")),
                 names(bad), bad), collapse = " | ")
  } else "none"
  expect_true(length(bad) == 0L,
              info = paste("unresolved citation(s) ->", detail))
})

test_that("adversarial: the render command in manuscript/README.md matches what CI runs", {
  # Two places document how to build this manuscript. When they disagree, whichever a person
  # follows by hand stops matching what the pipeline produced.
  readme <- paste(readLines(file.path(MS, "README.md"), warn = FALSE), collapse = "\n")
  wf <- paste(readLines(file.path(root, ".github", "workflows", "manuscript.yml"), warn = FALSE),
              collapse = "\n")
  for (flag in c("--citeproc", "--bibliography=references.bib", "--csl=ama.csl",
                 "--reference-doc=pandoc-reference.docx")) {
    expect_true(grepl(flag, readme, fixed = TRUE),
                info = sprintf("manuscript/README.md no longer documents %s", flag))
    expect_true(grepl(flag, wf, fixed = TRUE),
                info = sprintf("the CI render no longer passes %s", flag))
  }
})
