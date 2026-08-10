# Cycle 21 -- 3 BVA, 3 semantic, 4 adversarial.
# Targets whether the cohort is still current. The Methods calls this an "active clinician
# roster". Two independent signals bear on that: when the platform directories were scraped,
# and the last year each clinician was observed practising. Neither had been tested, and a
# clinician who has left is recorded as a failure to contact, which enters the primary
# obtainment outcome as if it were a refusal.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)
rd <- function(f) utils::read.csv(f, colClasses = "character", check.names = FALSE)

roster <- rd(p("pe_obgyn_providers_active.csv"))
sheet  <- rd(p("pe_obgyn_final_calling_sheet_200.csv"))
db     <- rd(p("pe_obgyn_study_database.csv"))
ms     <- paste(readLines(p("manuscript", "manuscript_cite.md")), collapse = "\n")

g <- function(d, col) trimws(ifelse(is.na(d[[col]]), "", d[[col]]))
scrape <- g(roster, "Scrape Run Time")
src    <- g(roster, "Source of Information")
last_r <- suppressWarnings(as.numeric(g(roster, "Last Active Year")))

db$k <- npi_key(db$NPI)
i    <- match(npi_key(sheet$NPI), db$k)
last_f <- suppressWarnings(as.numeric(trimws(ifelse(is.na(db[["Last Active Year"]][i]), "",
                                                    db[["Last Active Year"]][i]))))
CALL_YEAR <- 2026

# ---------------------------------------------------------------- BVA (3)

test_that("BVA: every roster row records when it was scraped", {
  n_missing <- sum(!nzchar(scrape))
  expect_equal(n_missing, 0L,
               info = sprintf("%d roster rows have no scrape timestamp, so their currency is unknown",
                              n_missing))
})

test_that("BVA: scrape timestamps fall inside a plausible window", {
  yr <- suppressWarnings(as.numeric(substr(scrape[nzchar(scrape)], 1, 4)))
  expect_true(length(yr) > 0L)
  expect_true(all(yr >= 2020 & yr <= CALL_YEAR, na.rm = TRUE),
              info = "a scrape dated outside 2020 to the calling year is not usable provenance")
})

test_that("BVA: the activity year never post-dates the data it comes from", {
  v <- last_r[!is.na(last_r)]
  expect_true(length(v) > 0L)
  expect_true(all(v <= CALL_YEAR), info = "a future activity year is impossible")
  expect_true(all(v >= 2000))
})

# ---------------------------------------------------------------- semantic (3)

test_that("semantic: the activity signal is current enough to support an 'active roster' claim", {
  # The maximum observed value IS the source's last year, so the signal stops there.
  newest <- max(last_r, na.rm = TRUE)
  expect_true(CALL_YEAR - newest <= 2,
              info = sprintf("the newest activity year anywhere in the roster is %d, %d years before the calling window; the Methods calls this an active clinician roster",
                             newest, CALL_YEAR - newest))
})

test_that("semantic: every roster clinician traces to a named source", {
  n_missing <- sum(!nzchar(src))
  expect_equal(n_missing, 0L,
               info = sprintf("%d roster rows have no Source of Information", n_missing))
})

test_that("semantic: provenance is recorded in one consistent form", {
  # Most rows carry a URL; some carry a platform name instead, so provenance cannot be
  # resolved to a page uniformly.
  # Premise correction: the first version required the domain to end the string, so
  # "togetherwomenshealth.com (Eastside)" counted as a non-URL. Those are URLs with a
  # practice annotation. The real contract is that provenance resolves to a page at all.
  have <- src[nzchar(src)]
  has_domain <- grepl("[.](com|org|net|health)\\b", have)
  expect_true(all(has_domain),
              info = sprintf("%d of %d sources carry no domain, e.g. %s",
                             sum(!has_domain), length(have),
                             paste(utils::head(unique(have[!has_domain]), 2), collapse = "; ")))
})

# ---------------------------------------------------------------- adversarial (4)

test_that("adversarial: no fielded clinician was last observed practising long ago", {
  stale <- sum(last_f <= CALL_YEAR - 7, na.rm = TRUE)
  expect_equal(stale, 0L,
               info = sprintf("%d of %d fielded clinicians were last observed active in %d or earlier",
                              stale, nrow(sheet), CALL_YEAR - 7))
})

test_that("adversarial: activity is known for every fielded clinician", {
  n_unknown <- sum(is.na(last_f))
  expect_equal(n_unknown, 0L,
               info = sprintf("%d of %d fielded clinicians have no activity year at all",
                              n_unknown, nrow(sheet)))
})

test_that("adversarial: the scrape covers every platform in the fielded cohort", {
  stats_file <- p("scraping_stats.json")
  expect_true(file.exists(stats_file))
  txt <- paste(readLines(stats_file, warn = FALSE), collapse = " ")
  # Premise correction: the stats keys are slugs, not platform names ("1_uwh_michigan" is
  # Unified Women's Healthcare). Matching on the first characters of the display name was
  # wrong. Use the documented slug mapping instead.
  SLUG <- c("Unified Women's Healthcare" = "uwh", "Together Women's Health" = "together",
            "Nova Women's Health Partners" = "nova", "Axia Women's Health" = "axia",
            "Women's Care Enterprises" = "womens_care", "Femwell Group Health" = "topline",
            "Advantia Health" = "advantia",
            "Unified Women's Healthcare / Genesis OBGYN" = "uwh")
  plat <- unique(trimws(ifelse(is.na(db[["Platform/Practice"]][i]), "", db[["Platform/Practice"]][i])))
  plat <- plat[nzchar(plat) & plat != "Control Group"]
  known <- plat[plat %in% names(SLUG)]
  expect_true(length(known) > 0L)
  covered <- vapply(SLUG[known], function(k) grepl(k, tolower(txt), fixed = TRUE), logical(1))
  expect_true(all(covered),
              info = sprintf("platforms absent from scraping_stats.json: %s",
                             paste(known[!covered], collapse = ", ")))
})

test_that("adversarial: an attrition mechanism exists given the roster's age", {
  # The backup-physician protocol was cut from the manuscript, so the only remaining
  # mechanism is the replacement pool. With the activity signal five years stale, some
  # attrition is expected and the study needs a stated way to absorb it.
  weeks_old <- as.numeric(difftime(as.Date(sprintf("%d-08-10", CALL_YEAR)),
                                   as.Date(substr(max(scrape[nzchar(scrape)]), 1, 10)),
                                   units = "weeks"))
  has_mechanism <- grepl("replacement pool|backup", ms, ignore.case = TRUE)
  expect_true(weeks_old < 4 || has_mechanism,
              info = sprintf("the roster is %.0f weeks old and the manuscript states no attrition mechanism",
                             weeks_old))
})
