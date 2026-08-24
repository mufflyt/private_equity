# Cycle 15 -- 3 BVA, 3 semantic, 4 adversarial.
# Targets the covariate defaults the propensity model applies before matching, and the time
# zone the caller uses to decide when to dial. Both are quiet: neither produces an error, and
# both change who is matched to whom or whether the phone is answered.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)
rd <- function(f) utils::read.csv(f, colClasses = "character", check.names = FALSE)

sheet <- rd(p("pe_obgyn_final_calling_sheet_200_dedup.csv"))
db    <- rd(p("pe_obgyn_study_database.csv"))
psm   <- readLines(p("build_matched_control_group_psm.R"))

db$k <- npi_key(db$NPI)
i    <- match(npi_key(sheet$NPI), db$k)
gcol <- function(col) trimws(ifelse(is.na(db[[col]][i]), "", db[[col]][i]))
sheet$gender <- gcol("Gender")

tz <- trimws(sheet[["Time Zone"]])
st <- trimws(sheet$State)

ZONE_STATES <- list(
  Eastern  = c("CT","DC","DE","FL","GA","IN","MA","MD","MI","NC","NJ","NY","OH","PA","VA","KY","SC","VT","NH","ME","RI","WV"),
  Central  = c("AL","IL","MN","MO","TN","TX","AR","IA","KS","LA","MS","NE","OK","SD","ND","WI"),
  Mountain = c("AZ","CO","UT","ID","MT","NM","WY"),
  Pacific  = c("CA","NV","OR","WA")
)
VALID_ZONES <- c(names(ZONE_STATES), "Alaska", "Hawaii")

# ---------------------------------------------------------------- BVA (3)

test_that("BVA: every time zone is one of the recognised US zones", {
  present <- unique(tz[nzchar(tz) & !is.na(tz)])
  expect_true(length(present) > 0L)
  expect_true(all(present %in% VALID_ZONES),
              info = sprintf("unrecognised zones: %s", paste(setdiff(present, VALID_ZONES), collapse = ", ")))
})

test_that("BVA: gender takes exactly the two recorded categories, or is absent", {
  present <- unique(sheet$gender[nzchar(sheet$gender)])
  expect_true(all(present %in% c("Female", "Male")),
              info = sprintf("unexpected gender values: %s", paste(setdiff(present, c("Female","Male")), collapse = ", ")))
})

test_that("BVA: zero Open Payments years is a legitimate observed value", {
  op <- suppressWarnings(as.numeric(gcol("Open Payments Years")))
  expect_true(any(!is.na(op)))
  expect_true(all(op >= 0, na.rm = TRUE))
  # Because zero is legitimate, an imputed zero is indistinguishable from an observed one.
  # That is what makes the asymmetric imputation below undetectable downstream.
  expect_true(any(op == 0, na.rm = TRUE) || all(op > 0, na.rm = TRUE))
})

# ---------------------------------------------------------------- semantic (3)

test_that("semantic: the caller's time zone matches the clinic's state", {
  ok <- mapply(function(z, s) {
    if (is.na(z) || !nzchar(z) || !(z %in% names(ZONE_STATES))) return(NA)
    s %in% ZONE_STATES[[z]]
  }, tz, st)
  bad <- data.frame(state = st, zone = tz)[which(!ok), , drop = FALSE]
  expect_equal(nrow(bad), 0L,
               info = sprintf("%d clinics carry a time zone their state does not use: %s",
                              nrow(bad), paste(unique(paste0(bad$state, "->", bad$zone)), collapse = ", ")))
})

test_that("semantic: missing covariates are imputed the same way in both arms", {
  # The PE arm's missing Open Payments years are filled with the PE median; the control
  # candidates' are filled with 0. Open Payments is a matching covariate, so a systematic
  # difference in how it is filled biases the propensity score between arms.
  pe_line  <- grep("pe_matched_all\\$Open_Payments_Years\\[is.na", psm, value = TRUE)
  ctl_line <- grep("candidates_df\\$Open_Payments_Years\\[is.na", psm, value = TRUE)
  expect_length(pe_line, 1L); expect_length(ctl_line, 1L)
  pe_fill  <- sub(".*<- *", "", pe_line)
  ctl_fill <- sub(".*<- *", "", ctl_line)
  expect_equal(pe_fill, ctl_fill,
               info = sprintf("PE missing values are filled with '%s', controls with '%s'", pe_fill, ctl_fill))
})

test_that("semantic: a categorical covariate is not defaulted to one of its levels", {
  # Gender is an exact-match covariate. Filling missing gender with "Female" does not merely
  # add noise: it forces those clinicians into the female stratum for matching.
  g_lines <- grep("Gender_clean <- ifelse\\(is.na", psm, value = TRUE)
  expect_true(length(g_lines) > 0L)
  defaults_to_level <- any(grepl('"Female"|"Male"', g_lines))
  expect_false(defaults_to_level,
               info = "missing gender is defaulted to Female in both arms rather than left missing")
})

# ---------------------------------------------------------------- adversarial (4)

test_that("adversarial: no clinic is fielded without a calling window", {
  n <- sum(!nzchar(tz) | is.na(tz))
  expect_equal(n, 0L,
               info = sprintf("%d fielded clinics have no time zone, so the 0800-1700 local instruction cannot be followed", n))
})

test_that("adversarial: credential is not defaulted to MD when unknown", {
  # This is the same default that stamped a CNM as MD in cycle 12, seen here as a covariate
  # rather than an eligibility question.
  # Strengthened: the first version matched '"MD")' and so missed '"MD",', passing while the
  # default was present. Third such false negative in my own suite this run.
  lines <- grep("MD_vs_DO <- ifelse", psm, value = TRUE)
  expect_true(length(lines) > 0L)
  expect_false(any(grepl('"MD"', lines, fixed = TRUE)),
               info = sprintf("unknown credentials become MD: %s", trimws(lines[1])))
})

test_that("adversarial: imputed values are distinguishable from observed ones", {
  # Nothing marks which values were filled, so Table 1 and the balance claim cannot exclude
  # them, and a reader cannot tell an observed zero from a filled one.
  expect_true(any(grepl("_imputed|is_imputed|imputed_flag", psm)),
              info = "no flag records which covariate values were imputed")
})

test_that("adversarial: median imputation is computed within arm, not across the pool", {
  # Imputing the PE arm from the PE median and the control arm from the control median is
  # defensible; imputing one from a pooled median would leak the other arm's distribution.
  expect_true(any(grepl("pe_years_med <- median\\(pe_matched_all", psm)))
  expect_true(any(grepl("cand_years_med <- median\\(candidates_df", psm)))
})
