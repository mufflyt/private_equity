# Cycle 2 -- 3 BVA, 4 semantic, 3 adversarial.
# Targets the REDCap load structure and the artifact contracts that carry the protocol's
# "each clinic is contacted two times" guarantee. Cycle 1 tested the key builders in
# isolation; this cycle tests the shipped artifacts those keys produced.

repo <- normalizePath(file.path(dirname(attr(body(function() NULL), "srcfile")$filename %||% "."), "..", ".."),
                      mustWork = FALSE)
if (!dir.exists(file.path(repo, "R"))) repo <- normalizePath(".", mustWork = FALSE)
while (!file.exists(file.path(repo, "R", "pe_helpers.R")) && dirname(repo) != repo) repo <- dirname(repo)

p <- function(...) file.path(repo, ...)
read_csv_q <- function(f) utils::read.csv(f, check.names = FALSE, colClasses = "character")

SHEET   <- p("pe_obgyn_final_calling_sheet_200.csv")
IMPORT  <- p("redcap_import_ready_200.csv")
CHOICES <- p("redcap_physician_name_choices.txt")
SCHED   <- p("redcap_call_schedule_800.csv")

sheet   <- read_csv_q(SHEET)
imp     <- read_csv_q(IMPORT)
choices <- readLines(CHOICES, warn = FALSE)
sched   <- read_csv_q(SCHED)

choice_npi  <- sub(".*NPI:\\s*(\\d+).*", "\\1", choices)
choice_code <- as.integer(sub("^(\\d+),.*", "\\1", choices))
choice_arm  <- ifelse(grepl("Insurance: Medicaid", choices, fixed = TRUE), "Medicaid", "BCBS")
N_CLIN <- 400L

# ---------------------------------------------------------------- BVA (3)

test_that("BVA: dropdown codes span exactly 1..800 with no gaps or duplicates", {
  expect_equal(length(choices), 2L * N_CLIN)
  expect_equal(sort(choice_code), seq_len(2L * N_CLIN),
               info = "a gap or duplicate in the code sequence silently drops or double-books a call")
  expect_equal(min(choice_code), 1L)
  expect_equal(max(choice_code), 2L * N_CLIN)
})

test_that("BVA: the arm boundary falls exactly between code 400 and 401", {
  expect_equal(choice_arm[choice_code == 1L], "Medicaid")
  expect_equal(choice_arm[choice_code == N_CLIN], "Medicaid",
               info = "code 400 is the last Medicaid call")
  expect_equal(choice_arm[choice_code == N_CLIN + 1L], "BCBS",
               info = "code 401 is the first commercial call")
  expect_equal(choice_arm[choice_code == 2L * N_CLIN], "BCBS")
  expect_equal(sum(choice_arm == "Medicaid"), N_CLIN)
  expect_equal(sum(choice_arm == "BCBS"), N_CLIN)
})

test_that("BVA: every matched pair contributes exactly two clinicians, never one or three", {
  tb <- table(sheet[["Matched Pair ID"]])
  expect_true(all(tb == 2L),
              info = sprintf("pairs with wrong size: %s",
                             paste(names(tb)[tb != 2L], collapse = ", ")))
  expect_equal(length(tb), 200L)
})

# ---------------------------------------------------------------- semantic (4)

test_that("semantic: code i and code i+400 are the same physician, not merely the same position", {
  lo <- choice_npi[order(choice_code)][seq_len(N_CLIN)]
  hi <- choice_npi[order(choice_code)][N_CLIN + seq_len(N_CLIN)]
  expect_equal(lo, hi,
               info = "the two arms must address the identical physician list in identical order")
  expect_equal(length(unique(choice_npi)), N_CLIN,
               info = "800 codes must resolve to exactly 400 distinct physicians")
})

test_that("semantic: every office receives exactly two calls, as the protocol promises", {
  key <- phone_key(sheet$Phone)
  expect_false(any(is.na(key)), info = "an unusable phone cannot be called at all")
  calls <- table(key[match(choice_npi, sheet$NPI)])
  expect_true(all(calls == 2L),
              info = sprintf("offices receiving other than 2 calls: %d",
                             sum(calls != 2L)))
  expect_equal(length(calls), N_CLIN,
               info = "400 distinct offices, one per fielded clinician")
})

test_that("semantic: the import file addresses the same physicians as the fielded sheet", {
  expect_equal(nrow(imp), 2L * N_CLIN,
               info = "one record per physician per arm; 400 records cannot hold 800 calls")
  expect_equal(as.integer(imp$record_id), seq_len(2L * N_CLIN))
  expect_equal(as.integer(imp$physician_name), as.integer(imp$record_id),
               info = "physician_name must carry the dropdown code, not a label string")
})

test_that("semantic: ownership arms stay balanced through to the call list", {
  expect_equal(sum(sheet$PE_or_Not == "PE"), 200L)
  expect_equal(sum(sheet$PE_or_Not == "Non-PE"), 200L)
  arm_by_call <- sheet$PE_or_Not[match(choice_npi, sheet$NPI)]
  expect_equal(as.integer(table(arm_by_call, choice_arm)), rep(200L, 4L),
               info = "the 2x2 of ownership by payer must be exactly 200 calls per cell")
})

# ---------------------------------------------------------------- adversarial (3)

test_that("adversarial: REDCap artifacts are not stale relative to the calling sheet", {
  expect_setequal(unique(choice_npi), sheet$NPI)
  expect_setequal(unique(sched$Phone), sheet$Phone)
  expect_equal(nrow(sched), N_CLIN)
})

test_that("adversarial: the call schedule covers all 800 records exactly once", {
  ids <- sort(c(as.integer(sched$first_record_id), as.integer(sched$second_record_id)))
  expect_equal(ids, seq_len(2L * N_CLIN),
               info = "a record scheduled twice or not at all breaks the crossover design")
  expect_true(all(sched$first_arm != sched$second_arm),
              info = "each clinician must be called once under each payer")
  expect_true(all(as.integer(sched$min_hours_between_calls) >= 48L))
})

test_that("adversarial: row order of the fielded sheet does not determine office identity", {
  shuffled <- sheet[rev(seq_len(nrow(sheet))), , drop = FALSE]
  expect_setequal(phone_key(shuffled$Phone), phone_key(sheet$Phone))
  expect_equal(sort(phone_key(shuffled$Phone)), sort(phone_key(sheet$Phone)),
               info = "keys must be a function of content, not of position")
})
