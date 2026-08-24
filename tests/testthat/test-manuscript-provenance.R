# Manuscript provenance.
#
# Prompted by two figures in manuscript/ that depicted the study's primary outcomes from
# numbers typed into the script -- appointment obtainment of 41.0% against 72.5% with
# confidence intervals, and a wait-time distribution from rlnorm() around typed medians --
# before any call was placed, with no REDCap outcome export in existence and SAP.lock never
# having been run. Nothing was broken, so nothing failed. The artifacts were simply plausible.
#
# The contract below is scientific rather than mechanical. It does not check that code works;
# it checks that no publication-facing object asserts a quantity nobody measured. See
# docs/MANUSCRIPT_PROVENANCE_AUDIT.md for the full audit this was built from.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p    <- function(...) file.path(root, ...)
rd   <- function(f) utils::read.csv(f, colClasses = "character", check.names = FALSE)

sheet <- rd(p("pe_obgyn_final_calling_sheet_200_dedup.csv"))
pool  <- rd(p("pe_obgyn_matched_calling_list.csv"))
ms    <- paste(readLines(p("manuscript", "manuscript_cite.md"), warn = FALSE), collapse = "\n")
prov  <- paste(readLines(p("manuscript", "appendix_data_provenance.md"), warn = FALSE), collapse = "\n")
gen   <- readLines(p("manuscript", "generate_figures.R"), warn = FALSE)
strb  <- readLines(p("manuscript", "strobe_diagram.R"), warn = FALSE)

# A real outcome export is the thing whose absence makes an outcome claim unsupportable.
outcome_export <- length(list.files(root, pattern = "^redcap_export.*[.]csv$")) > 0L

T <- function(x) trimws(ifelse(is.na(x), "", x))
n_states  <- length(unique(T(sheet$State)))
n_pairs   <- length(unique(T(sheet[["Matched Pair ID"]])))
n_clin    <- nrow(sheet)
n_lines   <- length(unique(T(sheet$phone_id)))

# ---------------------------------------------------------------- no unlabelled simulation

test_that("no unlabelled simulated outcome artifact exists in a publication directory", {
  figs <- list.files(p("manuscript"), pattern = "[.]png$")
  outcome_like <- grep("obtain|wait|outcome|result", figs, ignore.case = TRUE, value = TRUE)
  if (!outcome_export) {
    for (f in outcome_like) {
      expect_true(grepl("^SIMULATED_", f),
                  info = sprintf("manuscript/%s depicts an outcome and no outcome export exists", f))
    }
  }
  # And the unmarked names must not reappear beside the marked ones.
  expect_false(file.exists(p("manuscript", "figure1.png")))
  expect_false(file.exists(p("manuscript", "figure2.png")))
})

test_that("an outcome figure declares itself in its title, not only in its filename", {
  if (outcome_export) skip("real outcomes exist; the marking requirement is lifted")
  titles <- grep("title *=", gen, value = TRUE)
  titles <- grep("Obtainment Rates|Wait Times", titles, value = TRUE)
  expect_true(length(titles) >= 2L)
  expect_true(all(grepl("SIMULATED", titles)),
              info = "a filename prefix is stripped by anyone who inserts the image")
})

test_that("adversarial: reintroducing an unmarked outcome figure is detectable", {
  # The guard must key on the OUTPUT NAME, not on a comment, or it is defeated by deleting a
  # comment. This reconstructs the defect: an ggsave to an unmarked outcome filename.
  outputs <- gsub('"', "", regmatches(gen, regexpr('"[A-Za-z0-9_]+[.]png"', gen)))
  outcome_outputs <- grep("obtain|wait", outputs, ignore.case = TRUE, value = TRUE)
  expect_true(length(outcome_outputs) >= 2L)
  if (!outcome_export) {
    expect_false(any(!grepl("^SIMULATED_", outcome_outputs)),
                 info = sprintf("unmarked outcome output(s): %s",
                                paste(outcome_outputs[!grepl("^SIMULATED_", outcome_outputs)],
                                      collapse = ", ")))
  }
})

# ---------------------------------------------------------------- outcomes stay unfilled

test_that("no outcome result is stated in prose while no outcome export exists", {
  if (outcome_export) skip("real outcomes exist; placeholders may be filled")
  # The Abstract's convention is square brackets for values awaiting data. That convention is
  # what kept the prose honest while the figures were not: the figures rendered the same
  # numbers with the brackets stripped. The brackets must survive.
  # Written with perl lookarounds and \Q..\E quoting. The first version used a POSIX bracket
  # class -- "[\\[]?%s[\\]]?" -- which never matched anything, so this test ran zero
  # expectations and testthat reported it as an EMPTY TEST while showing a green tick. It was
  # caught by reintroducing the defect and watching nothing fail. A contract that cannot fail
  # is the thing this whole file exists to prevent, one level up.
  # Scoped to the headline and Abstract, where the outcome placeholders live. Searching the
  # whole document collides with Table 1: 63 of 200 male clinicians is 31.5%, which is also the
  # placeholder for the obtainment difference. A guard that fires on a true baseline statistic
  # trains people to ignore it.
  abstract <- sub("(?s)\n## Introduction.*", "", ms, perl = TRUE)
  CLAIMS <- c("41.0", "72.5", "0.26", "1.31", "98.5", "99.0", "22.3", "11.3", "31.5")
  checked <- 0L
  for (claim in CLAIMS) {
    bracketed <- gregexpr(sprintf("\\[\\Q%s\\E\\]", claim), abstract, perl = TRUE)[[1]]
    bare      <- gregexpr(sprintf("(?<!\\[)\\Q%s\\E(?!\\])", claim), abstract, perl = TRUE)[[1]]
    n_brack <- if (bracketed[1] == -1L) 0L else length(bracketed)
    n_bare  <- if (bare[1] == -1L) 0L else length(bare)
    if (n_brack + n_bare == 0L) next
    checked <- checked + 1L
    expect_equal(n_bare, 0L,
                 info = sprintf("outcome value %s appears %d time(s) unbracketed in the prose; it is a placeholder, not a result",
                                claim, n_bare))
  }
  expect_gt(checked, 3L)
})

# ---------------------------------------------------------------- counts trace to the cohort

test_that("manuscript state and sample counts equal the frozen cohort artifacts", {
  for (txt in list(ms, prov)) {
    stated <- regmatches(txt, gregexpr("[0-9]+ (?:U[.]?S[.]? )?states", txt))[[1]]
    stated <- unique(as.integer(sub("[^0-9]*([0-9]+).*", "\\1", stated)))
    expect_true(length(stated) > 0L)
    expect_true(all(stated == n_states),
                info = sprintf("manuscript states %s; the cohort spans %d",
                               paste(stated, collapse = "/"), n_states))
  }
  expect_true(grepl(sprintf("\\[?%d\\]? matched clinician pairs", n_pairs), ms) ||
              grepl(sprintf("\\[?%d\\]? matched", n_pairs), ms),
              info = sprintf("the Abstract must state %d pairs", n_pairs))
  expect_true(grepl(sprintf("\\[?%d\\]? clinicians", n_clin), ms),
              info = sprintf("the Abstract must state %d clinicians", n_clin))
})

test_that("sensitivity-analysis counts in the Methods equal the cohort's own", {
  # Each of these was stale: 385 clustering units against 387, two shared-line pairs against
  # three, 154 address-linked pairs against 195. They read as design decisions, so a reader
  # cannot tell them from parameters, and nothing recomputed them.
  expect_true(grepl(sprintf("\\(%d units rather than %d\\)", n_lines, n_clin), ms),
              info = sprintf("Methods must state %d clustering units", n_lines))
  shared <- sum(toupper(T(sheet$same_phone_within_pair)) == "TRUE") / 2L
  word <- c("one", "two", "three", "four", "five")[shared]
  expect_true(grepl(sprintf("%s matched pairs in which", word), ms),
              info = sprintf("Methods must state %s shared-line pairs", word))
  addr <- tapply(grepl("address", T(sheet$SVI_geocode_via), ignore.case = TRUE),
                 T(sheet[["Matched Pair ID"]]), all)
  expect_true(grepl(sprintf("the %d pairs in which both members", sum(addr)), ms),
              info = sprintf("Methods must state %d address-linked pairs", sum(addr)))
})

# ---------------------------------------------------------------- STROBE

test_that("STROBE counts come from the pipeline and keep one unit of analysis", {
  stage <- function(name) {
    ln <- grep(paste0('"', name, '"'), strb, value = TRUE, fixed = TRUE)
    ln <- grep("=", ln, value = TRUE)[1]
    if (is.na(ln)) return(NA_character_)
    trimws(sub(".*= *([^,]*).*", "\\1", ln))
  }
  expect_equal(as.integer(stage("Initial Scraped PE Roster")), 1537L)
  expect_equal(as.integer(stage("Geographically Matched")), nrow(pool))
  expect_equal(as.integer(stage("Fielded Cohort")), n_clin)
  # Units: every stage that is resolved is in clinicians. The figure previously ended in pairs.
  expect_gt(as.integer(stage("Fielded Cohort")), n_pairs)
})

test_that("adversarial: an unresolved STROBE stage stops the figure rather than guessing", {
  # 544 matched nothing in the pipeline. A plausible-but-unproven cohort count is the same
  # class of error as a simulated figure, and harder to notice. The stage is NA and the script
  # must refuse to run rather than let a reader infer it from the stages around it.
  expect_true(any(grepl("NA_integer_", strb)),
              info = "the unresolved stage must be NA, not a plausible number")
  expect_true(any(grepl("^\\s*stop\\(", strb)),
              info = "the script must fail closed on an unresolved stage")
  res <- system2("Rscript", shQuote(p("manuscript", "strobe_diagram.R")),
                 stdout = TRUE, stderr = TRUE)
  expect_true(any(grepl("unresolved", res, ignore.case = TRUE)),
              info = "strobe_diagram.R should have refused to generate")
})

# ---------------------------------------------------------------- hard-coded constants

test_that("hard-coded quantities in the manuscript are external, design, or bracketed", {
  # Not every literal is a defect. A published comparator and a pre-specified effect size are
  # correctly typed. The rule is that anything else asserting a study result must be bracketed
  # until the analysis produces it.
  sap <- read_sap(p("SAP.lock"))
  for (k in c("effect_primary_irr", "effect_conservative_irr", "effect_larger_irr")) {
    expect_true(nzchar(T(sap[[paste0(k, "_source")]])),
                info = sprintf("%s is hard-coded and must name its source", k))
  }
  # The Nie et al. comparator must remain attributed wherever its numbers appear.
  if (grepl("17[.]5 days", ms)) {
    expect_true(grepl("nie2022urology", ms),
                info = "the published comparator's values appear without their citation")
  }
})
