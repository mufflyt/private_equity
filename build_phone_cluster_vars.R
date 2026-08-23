# Make the shared-scheduler structure of the fielded sample explicit and analysable.
#
# WHY TWO KEYS. The number a caller will actually dial is the sheet's Phone column, which is
# the NPPES registered number, and all 400 of those are distinct -- no clinician is dialed
# twice. But a distinct registered number does not make a distinct scheduler. The practice
# number carried in the study database (Scraped Phone, falling back to NPPES then CMS DAC)
# collapses the same 400 clinicians onto 385 numbers, and one of those numbers covers four
# fielded clinicians across Edina, Minneapolis and Saint Paul. Where several clinicians route
# through one central line, calls to them are not independent observations, whatever their
# registered numbers say.
#
# So both keys are emitted. phone_dialed is operational: it answers "what do we dial". The
# clustering variables are built on phone_practice, because that is the one that plausibly
# corresponds to a shared scheduler, and address_key is emitted alongside it as the strongest
# same-physical-office signal.
#
# Nothing here changes the sample. It adds columns.

ROOT <- "/Users/tylermuffly/private_equity"
source(file.path(ROOT, "R", "pe_helpers.R"))

SHEET <- file.path(ROOT, "pe_obgyn_final_calling_sheet_200.csv")
sheet <- read.csv(SHEET, colClasses = "character", check.names = FALSE)
db    <- read.csv(file.path(ROOT, "pe_obgyn_study_database.csv"),
                  colClasses = "character", check.names = FALSE)

idx <- match(npi_key(sheet$NPI), npi_key(db$NPI))
stopifnot(!anyNA(idx))
dbf <- db[idx, , drop = FALSE]

# ---------------------------------------------------------------- keys

phone_dialed <- phone_key(sheet$Phone)
phone_pract  <- phone_key(coalesce_cols(dbf, c("Scraped Phone", "NPPES Phone", "DAC Phone")))
addr         <- address_key(dbf)

stopifnot(!anyNA(phone_dialed))

# A clinician with no usable practice number must not collide with any other clinician who
# also has none, so unresolved rows get their own singleton key rather than a shared NA.
pract_key <- ifelse(!is.na(phone_pract), paste0("P:", phone_pract),
                    ifelse(!is.na(addr), paste0("A:", addr),
                           paste0("R:", npi_key(sheet$NPI))))

# Stable, order-independent ids: name them by the key's first appearance in NPI order so the
# same input always produces the same labels.
lvl <- unique(pract_key[order(npi_key(sheet$NPI))])
sheet$phone_dialed   <- phone_dialed
sheet$phone_practice <- ifelse(is.na(phone_pract), NA_character_, phone_pract)
sheet$phone_id       <- sprintf("line_%03d", match(pract_key, lvl))
sheet$office_addr_key <- addr

# ---------------------------------------------------------------- cluster sizes

n_clin  <- table(pract_key)
sheet$clinicians_per_phone <- as.integer(n_clin[pract_key])
sheet$calls_per_phone      <- 2L * sheet$clinicians_per_phone   # one Medicaid, one commercial

pair <- sheet[["Matched Pair ID"]]
pairs_on_key <- tapply(pair, pract_key, function(x) length(unique(x)))
sheet$pairs_per_phone <- as.integer(pairs_on_key[pract_key])

# ---------------------------------------------------------------- within-pair contamination

by_pair <- tapply(pract_key, pair, function(k) length(unique(k)) == 1L)
sheet$same_phone_within_pair <- unname(by_pair[pair])

shared_addr <- tapply(addr, pair, function(a) !anyNA(a) && length(unique(a)) == 1L)
sheet$same_address_within_pair <- unname(shared_addr[pair])

# ---------------------------------------------------------------- report

cat(sprintf("dialed numbers, distinct:   %d of %d clinicians\n",
            length(unique(phone_dialed)), nrow(sheet)))
cat(sprintf("practice lines, distinct:   %d\n", length(unique(pract_key))))
cat(sprintf("lines serving >1 clinician: %d (covering %d clinicians)\n",
            sum(n_clin > 1L), sum(n_clin[n_clin > 1L])))
cat(sprintf("largest line:               %d clinicians, %d calls\n",
            max(sheet$clinicians_per_phone), max(sheet$calls_per_phone)))

cat("\npairs whose two arms share a practice line:\n")
bad <- unique(pair[sheet$same_phone_within_pair])
if (length(bad)) {
  for (b in bad) {
    r <- sheet[pair == b, ]
    cat(sprintf("  %-10s %s | %s | %s\n", b, unique(pract_key[pair == b]),
                paste(r$PE_or_Not, collapse = "+"), paste(r$`Provider Name`, collapse = " / ")))
  }
} else cat("  none\n")

cat("\npairs whose two arms share a normalised address:\n")
bada <- unique(pair[sheet$same_address_within_pair])
cat(sprintf("  %s\n", if (length(bada)) paste(bada, collapse = ", ") else "none"))

cat("\nclinicians per line, distribution:\n")
print(table(sheet$clinicians_per_phone))

cat(sprintf("\nEffective independent units if the practice line is the cluster: %d (of 400 clinicians)\n",
            length(unique(pract_key))))

write.csv(sheet, SHEET, row.names = FALSE, na = "")
cat(sprintf("\nWrote %s with phone_id, phone_dialed, phone_practice, office_addr_key,\n", basename(SHEET)))
cat("clinicians_per_phone, calls_per_phone, pairs_per_phone, same_phone_within_pair,\n")
cat("same_address_within_pair.\n")
