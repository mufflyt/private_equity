# Every figure the README shows must exist, and must not be older than the artifact it plots.
#
# A README figure is a publication-facing object in the same sense as a manuscript figure: it
# is what a reader looks at first. The two simulated outcome figures that prompted
# docs/MANUSCRIPT_PROVENANCE_AUDIT.md were exactly this kind of object. A stale README figure
# is the softer version of the same failure -- it shows a number that was true once.

testthat::local_edition(3)
ROOT <- testthat::test_path("..", "..")
readme <- paste(readLines(file.path(ROOT, "README.md"), warn = FALSE), collapse = "\n")

refs <- unique(regmatches(readme, gregexpr("figures/[A-Za-z0-9_.-]+\\.png", readme))[[1]])

test_that("POSITIVE CONTROL: the README actually references figures", {
  # Without this, a README whose images had all been deleted would pass every check below.
  expect_true(length(refs) >= 5L,
              info = paste("expected at least five README figures, found", length(refs)))
})

test_that("LAW: every figure the README references exists", {
  missing <- refs[!file.exists(file.path(ROOT, refs))]
  expect_true(length(missing) == 0L,
              info = paste("README references missing figure(s):",
                           paste(missing, collapse = ", ")))
})

test_that("LAW: comparator figures are not older than the artifact they plot", {
  # These two are drawn from comparator_adjudication.csv. If that table is rebuilt and the
  # figures are not, the README reports superseded counts -- which is how the earlier "61"
  # would have survived on the front page after the table said 59.
  src <- file.path(ROOT, "data", "comparator", "comparator_adjudication.csv")
  expect_true(file.exists(src), info = "the comparator artifact must be committed")
  for (f in c("figures/fig_readme_comparator_status.png",
              "figures/fig_readme_practice_scale.png")) {
    p <- file.path(ROOT, f)
    expect_true(file.exists(p), info = paste(f, "is missing"))
    expect_true(file.mtime(p) >= file.mtime(src),
                info = paste(f, "is older than comparator_adjudication.csv; rerun",
                             "make_readme_figures.py"))
  }
})

test_that("LAW: the README's headline contamination figure matches the artifact", {
  # The one number on the front page that a reader will quote.
  adj <- read.csv(file.path(ROOT, "data", "comparator", "comparator_adjudication.csv"),
                  colClasses = "character", check.names = FALSE)
  ctl <- adj[adj$arm != "PE" & grepl("fielded", adj$frame), , drop = FALSE]
  n <- sum(nzchar(ctl$pe_platform_link))
  expect_true(grepl(paste0("**", n, " of 200 fielded controls (", sprintf("%.1f", 100 * n / 200),
                           "%)**"), readme, fixed = TRUE),
              info = paste("README must state", n, "contaminated fielded controls"))
  ind <- sum(ctl$comparator_class == "independent_supported")
  expect_true(grepl(paste0("**", ind, " of 200**"), readme, fixed = TRUE),
              info = paste("README must state", ind, "controls with affirmative independence"))
})
