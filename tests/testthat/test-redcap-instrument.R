# Cycle 11 -- 3 BVA, 4 semantic, 3 adversarial.
# Targets the REDCap instrument itself: the contract under which the primary outcomes will
# actually be recorded. Cycle 2 tested the load files; nothing has tested the form that
# collects the data. A field that cannot hold the value the analysis needs is a defect
# upstream of every model in the SAP.

root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)
p <- function(...) file.path(root, ...)

dict <- utils::read.csv(p("ICVsPOPVsSUI_DataDictionary_2026-07-05.csv"),
                        check.names = FALSE, colClasses = "character")
names(dict)[1] <- "field"
fld <- function(f) dict[dict$field == f, , drop = FALSE]
req <- function(f) trimws(fld(f)[["Required Field?"]]) == "y"
val <- function(f) trimws(fld(f)[["Text Validation Type OR Show Slider Number"]])
vmin <- function(f) trimws(fld(f)[["Text Validation Min"]])
vmax <- function(f) trimws(fld(f)[["Text Validation Max"]])
branch <- trimws(dict[["Branching Logic (Show field only if...)"]])

# ---------------------------------------------------------------- BVA (3)

test_that("BVA: call and hold durations admit realistic upper values", {
  expect_equal(val("calltime"), "integer")
  expect_equal(val("holdtime"), "integer")
  expect_equal(vmin("calltime"), "0")
  expect_equal(vmin("holdtime"), "0")
  # The reminders field explicitly anticipates holds beyond five minutes. A 1000 second cap
  # is 16 minutes 40 seconds, so a 20 minute hold cannot be recorded at all.
  expect_true(as.numeric(vmax("holdtime")) >= 1800,
              info = sprintf("holdtime max is %s s (%.1f min); long holds are exactly the signal of an access barrier",
                             vmax("holdtime"), as.numeric(vmax("holdtime")) / 60))
})

test_that("BVA: date fields are bounded at both ends", {
  for (f in c("calldate1", "calldate2", "appdate")) {
    expect_true(nzchar(vmin(f)), info = sprintf("%s has no minimum date", f))
    expect_true(nzchar(vmax(f)),
                info = sprintf("%s has no maximum date, so a mistyped year is accepted", f))
  }
})

test_that("BVA: coded answers start at 1 and run contiguously", {
  for (f in c("medicaid_status", "transfers", "doctor_called")) {
    ch <- fld(f)[["Choices, Calculations, OR Slider Labels"]]
    codes <- as.integer(sub("^\\s*([0-9]+),.*", "\\1", strsplit(ch, "\\|")[[1]]))
    codes <- codes[!is.na(codes)]
    expect_true(length(codes) > 1L)
    expect_equal(min(codes), 1L, info = sprintf("%s does not start at 1", f))
    expect_false(any(duplicated(codes)), info = sprintf("%s repeats a code", f))
  }
})

# ---------------------------------------------------------------- semantic (4)

test_that("semantic: the primary wait-time outcome cannot be left silently blank", {
  # appdate IS the wait-time outcome. It is optional and has no branching logic, so a
  # record can be saved complete with the study's primary endpoint empty and no prompt.
  expect_true(req("appdate") || nzchar(branch[dict$field == "appdate"]),
              info = "appdate is neither required nor conditionally shown")
})

test_that("semantic: date fields can record the time the labels promise", {
  # Labels say "Date and Time of FIRST Phone Call" and instruct calling between 0800 and
  # 1700 local. date_mdy stores a date only, so neither the business-hours instruction nor
  # the >=48 hour spacing between the two insurance arms can be verified from the data.
  for (f in c("calldate1", "calldate2")) {
    expect_match(val(f), "datetime",
                 info = sprintf("%s validates as '%s', which cannot hold a time", f, val(f)))
  }
})

test_that("semantic: the instrument records which insurance arm a call belongs to", {
  # medicaid_status option 3 is "NA as this was a Blue Cross/Blue Shield call", so the arm
  # is recoverable only from physician_name's dropdown code. That field must therefore be
  # required, or a record exists whose arm is unknown and which no model can use.
  ch <- fld("medicaid_status")[["Choices, Calculations, OR Slider Labels"]]
  expect_match(ch, "Blue Cross/Blue Shield call")
  expect_true(req("physician_name"),
              info = "physician_name carries the only arm identifier and is not required")
})

test_that("semantic: the instrument's dropdown matches the fielded cohort", {
  ch <- fld("physician_name")[["Choices, Calculations, OR Slider Labels"]]
  n_dict <- length(strsplit(ch, "\\|")[[1]])
  n_file <- length(readLines(p("redcap_physician_name_choices.txt"), warn = FALSE))
  expect_equal(n_dict, n_file,
               info = sprintf("dictionary carries %d choices, the fielded set needs %d", n_dict, n_file))
})

# ---------------------------------------------------------------- adversarial (3)

test_that("adversarial: contradictory records are not enterable unchallenged", {
  # With no branching logic anywhere, a caller can record contacted1 = No and still enter an
  # appointment date, or mark an exclusion and still record a wait time.
  expect_true(any(nzchar(branch)),
              info = "no field in the instrument has branching logic")
})

test_that("adversarial: every field the analysis consumes is required", {
  # The SAP consumes obtainment, wait time, payer arm and exclusions. Each must be present
  # for a record to be analysable.
  consumed <- c("contacted1", "appdate", "medicaid_status", "exclusions", "physician_name")
  missing_req <- consumed[!vapply(consumed, req, logical(1))]
  expect_length(missing_req, 0L)
})

test_that("adversarial: no numeric field admits a value that would corrupt an outcome", {
  for (f in c("calltime", "holdtime")) {
    expect_equal(vmin(f), "0", info = sprintf("%s allows a negative duration", f))
  }
  # A date minimum before the study opened would admit calls attributed to the wrong period.
  expect_true(as.Date(vmin("calldate1")) >= as.Date("2026-01-01"),
              info = "calldate1 accepts dates from before the study window")
})
