# Laws governing the PECOS/DAC comparator adjudication.
#
# The protocol restricts controls to "independent private practices" and SAP.lock names the
# contrast "PE vs independent". Nothing in the pipeline ever tested that. This file holds the
# rules the adjudication must obey -- above all, the rule that absence of evidence is not
# evidence of independence.

testthat::local_edition(3)
ROOT <- testthat::test_path("..", "..")
adj  <- read.csv(file.path(ROOT, "data", "comparator", "comparator_adjudication.csv"),
                 colClasses = "character", check.names = FALSE)
man  <- read.csv(file.path(ROOT, "data", "comparator", "pecos_source_manifest.csv"),
                 colClasses = "character")
ctl  <- adj[adj$arm != "PE" & grepl("fielded", adj$frame), , drop = FALSE]
STATES <- c("independent_supported", "not_independent_supported", "independence_unresolved")

test_that("POSITIVE CONTROL: the adjudication table is present and shaped as expected", {
  # Without this, every law below could pass vacuously on an empty table.
  expect_true(nrow(adj) > 1000, info = "adjudication must cover the union of frames")
  expect_true(nrow(ctl) == 200L, info = "exactly the 200 fielded controls must be adjudicated")
  expect_true(all(adj$comparator_class %in% STATES),
              info = "only the three prespecified states may appear")
  expect_true(all(c("external_source", "evidence_date", "adjudicator",
                    "adjudication_confidence") %in% names(adj)),
              info = "manual adjudication fields must exist even when unfilled")
})

test_that("LAW: every frozen PECOS input carries a sha256 and a row count", {
  # The archive lives on a removable drive. Without hashes there is no way to prove which
  # snapshot a classification was built from, and PECOS public files are current-state
  # snapshots that get overwritten.
  expect_true(nrow(man) >= 20, info = "the source manifest must cover the archive")
  expect_true(all(nchar(man$sha256) == 64L), info = "every input needs a full sha256")
  used <- man[man$used_as_input == "TRUE", , drop = FALSE]
  expect_true(all(as.numeric(used$data_rows) > 0), info = "every input actually read needs a row count")
  # A file carried in the manifest but not read must say so, rather than being quietly dropped:
  # the archive contains a 10-byte stub, and hiding it would misstate what was inventoried.
  unused <- man[man$used_as_input != "TRUE", , drop = FALSE]
  expect_true(all(nzchar(unused$note)), info = "an unused input must record why it is unused")
})

test_that("LAW: missing PECOS evidence can never imply independence", {
  # The single most dangerous failure mode. A clinician absent from PECOS, or whose sampled
  # office cannot be resolved, is UNKNOWN -- not a solo independent practitioner. Reading
  # absence as independence would manufacture exactly the comparator the protocol promised.
  bad <- adj[adj$pecos_status != "location_resolved" &
             adj$comparator_class == "independent_supported", , drop = FALSE]
  expect_true(nrow(bad) == 0L,
              info = paste("unresolved PECOS status classified as independent for NPIs:",
                           paste(utils::head(bad$npi, 5), collapse = ", ")))
})

test_that("LAW: hospital admitting affiliation alone cannot imply employment", {
  # An OB/GYN needs privileges to deliver. CMS Facility Affiliation records privileges, not
  # ownership, so it must never be the reason a control is called non-independent.
  reasons <- unique(adj$classification_reason[adj$comparator_class == "not_independent_supported"])
  # Anchored on word boundaries: an unanchored absence assertion on source-like text can match
  # something adjacent and certify the very bug it was written to catch, which is what
  # test-enrichment-covariates.R's adversarial meta-check exists to prevent -- and it caught
  # this line on its first run.
  expect_false(any(grepl("\\bhospital affiliation\\b|\\badmitting\\b|\\bprivileg",
                         reasons, ignore.case = TRUE)),
               info = "affiliation alone was used as evidence of employment")
  # POSITIVE CONTROL: clinicians WITH a hospital affiliation still appear as independent or
  # unresolved, proving the field is not silently driving the classification.
  withaff <- adj[nzchar(adj$hospital_affiliation), , drop = FALSE]
  expect_true(any(withaff$comparator_class != "not_independent_supported"),
              info = "every hospital-affiliated clinician was called non-independent")
})

test_that("LAW: organisation size alone cannot decide ownership independence", {
  # The protocol says independent private practice; it never prespecified a headcount. A
  # 30-physician physician-owned group can be independent; a 4-physician hospital clinic is not.
  ok <- adj[adj$comparator_class == "independent_supported", , drop = FALSE]
  expect_false(any(grepl("^size|only.*clinicians$|fewer than [0-9]+ clinicians$",
                         ok$classification_reason)),
               info = "size alone was used to affirm independence")
  # NEGATIVE CONTROL: small organisations must be able to be non-independent.
  small_ni <- adj[adj$comparator_class == "not_independent_supported" &
                  suppressWarnings(as.numeric(adj$dac_national_clinicians)) <= 50, , drop = FALSE]
  expect_true(nrow(small_ni) > 0,
              info = "no small organisation was ever called non-independent, so size is deciding")
  # NEGATIVE CONTROL the other way: large organisations must be able to be unresolved rather
  # than automatically condemned.
  big_un <- adj[adj$comparator_class == "independence_unresolved" &
                suppressWarnings(as.numeric(adj$dac_national_clinicians)) >= 500, , drop = FALSE]
  expect_true(nrow(big_un) > 0, info = "large organisations are being classified by size alone")
})

test_that("LAW: a definitive classification must retain affirmative evidence", {
  # Neither definitive state may be asserted without a recorded reason. Unresolved is the
  # honest default and is allowed to say so.
  d <- adj[adj$comparator_class != "independence_unresolved", , drop = FALSE]
  expect_true(all(nzchar(trimws(d$classification_reason))),
              info = "a definitive classification with no stated evidence")
  expect_true(all(nchar(d$classification_reason) > 20L),
              info = "evidence strings must be substantive, not a token")
})

test_that("LAW: classification is a function of its inputs, not of row order", {
  # Same NPI and same organisation inputs must give the same class wherever the row sits.
  k <- paste(adj$npi, adj$dac_org_pac_id, adj$pecos_status)
  tab <- tapply(adj$comparator_class, k, function(x) length(unique(x)))
  expect_true(all(tab == 1L),
              info = "identical inputs produced more than one classification")
  # And an NPI appearing in both frames must classify identically.
  dup <- adj$npi[duplicated(adj$npi)]
  expect_true(length(dup) == 0L, info = "the adjudication must hold one row per NPI")
})

test_that("LAW: PE-platform contamination of the control arm is recorded, not silently dropped", {
  # Controls sharing a CMS organisation with a clinician on the study's own PE roster are
  # exposure-misclassified, which is a different and more serious defect than non-independence.
  # This law exists so the count cannot quietly disappear from the artifact.
  expect_true("pe_platform_link" %in% names(adj),
              info = "the PE-platform link column must be retained")
  n <- sum(nzchar(ctl$pe_platform_link))
  expect_true(n > 0, info = "the recorded contamination count must not be zeroed out")
  # The true invariant is one-sided. Where the sampled office is ambiguous, a PE-platform link
  # is suggestive but does not pin which organisation was actually called, so `unresolved` is
  # the honest state. What is NEVER permissible is calling such a clinician independent.
  expect_true(all(adj$comparator_class[nzchar(adj$pe_platform_link)] != "independent_supported"),
              info = "a clinician in a PE-platform organisation was called independent")
  resolved_pe <- adj[nzchar(adj$pe_platform_link) & adj$pecos_status == "location_resolved", ]
  expect_true(all(resolved_pe$comparator_class == "not_independent_supported"),
              info = "a resolved office inside a PE-platform organisation must be non-independent")
})

test_that("LAW: a blank organisation is never treated as a resolved organisation", {
  # A DAC row with an empty org_pac_id records NO organisational affiliation for that row.
  # Selecting one reports "organisation = nothing", which is a different claim, and it discards
  # the organisation-bearing rows at the same office. The first version of the builder did
  # exactly that for 74 clinicians, one of whose only organisation was a PE platform -- so the
  # contamination count was understated and the evidence silently vanished.
  bad <- adj[adj$pecos_status == "location_resolved" & !nzchar(adj$dac_org_pac_id), , drop = FALSE]
  expect_true(nrow(bad) == 0L,
              info = paste("resolved to a blank organisation for NPIs:",
                           paste(utils::head(bad$npi, 5), collapse = ", ")))
  # POSITIVE CONTROL: the honest status must actually be in use, or the rule was implemented by
  # deleting the affected rows rather than by classifying them.
  expect_true(sum(adj$pecos_status == "no_organisation_on_sampled_row") > 0,
              info = "no clinician carries the blank-organisation status; check it is reachable")
  expect_true(all(adj$comparator_class[adj$pecos_status == "no_organisation_on_sampled_row"] ==
                    "independence_unresolved"),
              info = "a blank-organisation match is unresolved, never a definitive state")
})

test_that("LAW: the any-affiliation sensitivity view is retained beside the primary figure", {
  # Sampled-office resolution is the primary rule, deliberately: max() across every affiliation
  # was rejected. But the broader view must remain visible, because dropping it would hide that
  # 61 fielded controls have SOME PE-platform affiliation while 59 have one at the office called.
  expect_true("pe_platform_any_affiliation" %in% names(adj),
              info = "the any-affiliation column must be retained")
  n_any <- sum(nzchar(ctl$pe_platform_any_affiliation))
  n_smp <- sum(nzchar(ctl$pe_platform_link))
  expect_true(n_any >= n_smp,
              info = "any-affiliation can never be narrower than the sampled-office measure")
  expect_true(n_smp > 0 && n_any > 0, info = "neither contamination measure may be zeroed out")
})

# ------------------------------------- the appendix must not carry numbers nobody can recompute

test_that("LAW: every count in Supplementary Appendix S3 is recomputable from the artifact", {
  # This repository exists partly because two publication-shaped figures were once built from
  # numbers typed into a script. An appendix full of hand-copied counts is the same object with
  # better prose. Each figure below is recomputed from comparator_adjudication.csv and required
  # to appear in the appendix; a figure that drifts fails here rather than reaching a journal.
  ap <- paste(readLines(testthat::test_path("..", "..", "manuscript",
                                            "appendix_comparator_validation.md"), warn = FALSE),
              collapse = "\n")
  uni <- adj[grepl("universe", adj$frame) & adj$arm != "PE", , drop = FALSE]
  has <- function(x) grepl(x, ap, fixed = TRUE)

  n_smp  <- sum(nzchar(ctl$pe_platform_link))
  n_any  <- sum(nzchar(ctl$pe_platform_any_affiliation))
  n_pair <- length(unique(ctl$pair[nzchar(ctl$pe_platform_link) & nzchar(ctl$pair)]))
  u_smp  <- sum(nzchar(uni$pe_platform_link))
  u_any  <- sum(nzchar(uni$pe_platform_any_affiliation))
  u_cln  <- sum(!nzchar(uni$pe_platform_link))

  expect_true(has(paste0("**", n_smp, " (29.5%)**")),
              info = paste("appendix must report", n_smp, "contaminated fielded controls"))
  expect_true(has(as.character(n_pair)), info = "affected pair count must appear")
  expect_true(has(paste0(u_smp, " (47.9%)")), info = "universe contamination must appear")
  expect_true(has(paste0("are ", n_any, " and ", u_any)),
              info = "the any-affiliation sensitivity figures must both appear")
  expect_true(has(paste0(u_cln, " of 459")), info = "clean-universe count must appear")

  for (st in c("not_independent_supported", "independent_supported", "independence_unresolved")) {
    n <- sum(ctl$comparator_class == st)
    expect_true(has(as.character(n)),
                info = paste("appendix must report", n, "fielded controls as", st))
  }
  expect_true(has(paste0("**", sum(ctl$comparator_class == "independent_supported"), " of 200**")),
              info = "the headline independence count must be stated as a fraction of 200")

  res <- sum(ctl$pecos_status == "location_resolved")
  noorg <- sum(ctl$pecos_status == "no_organisation_on_sampled_row")
  expect_true(has(paste0(res, " resolved")) && has(paste0(noorg, " matched only")),
              info = "office-resolution breakdown must match the artifact")
  # The appendix uses journal thousands separators, so accept either rendering of the same
  # integer rather than forcing the prose to be written for the test's convenience.
  n_rows <- nrow(adj)
  expect_true(has(as.character(n_rows)) || has(formatC(n_rows, big.mark = ",", format = "d")),
              info = "the adjudication row count must appear")

  # POSITIVE CONTROL: the appendix must actually be the comparator appendix, not any file that
  # happens to contain these integers.
  expect_true(has("Supplementary Appendix S3") && has("PECOS Associate Control"),
              info = "wrong document; these contracts would be vacuous")
})

test_that("LAW: the appendix states the vintage limits rather than implying currency", {
  # The archive's enrolment extract reads as current and is April 2019; reassignment stops at
  # 2019 entirely. An appendix that omitted this would describe a 2026 comparator using a 2019
  # relation without saying so.
  ap <- paste(readLines(testthat::test_path("..", "..", "manuscript",
                                            "appendix_comparator_validation.md"), warn = FALSE),
              collapse = "\n")
  expect_true(grepl("April 15, 2019", ap, fixed = TRUE),
              info = "the archive's true internal date must be disclosed")
  expect_true(grepl("2016, 2017, and 2019", ap, fixed = TRUE),
              info = "the reassignment vintages available must be stated")
  expect_true(grepl("May 2024", ap, fixed = TRUE),
              info = "the primary measurement vintage must be named")
})
