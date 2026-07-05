#!/usr/bin/env Rscript
# Trim the 300-pair calling sheet to a geographically balanced 200-pair / 800-call
# set (round-robin across states -> minimum Florida share), then build the REDCap
# import for that fielded set. Uses mysterycall::parse_redcap_labels for codes.
suppressMessages({library(mysterycall); library(readr); library(dplyr); library(stringr)})

DICT  <- "ICVsPOPVsSUI_DataDictionary_2026-07-05.csv"
SHEET <- "pe_obgyn_final_calling_sheet_300.csv"
FORM  <- "acost_three_dx_urogyn_2"
N_TARGET <- 200L
set.seed(1978)

cs <- read_csv(SHEET, show_col_types = FALSE)

# 1. Round-robin pair selection across states (fills small states first, caps big ones)
pair_state <- cs %>% distinct(pair = `Matched Pair ID`, State)
selected <- pair_state %>%
  group_by(State) %>% slice_sample(prop = 1) %>% mutate(rank = row_number()) %>% ungroup() %>%
  arrange(rank, State) %>% slice_head(n = N_TARGET)

sheet200 <- cs %>% filter(`Matched Pair ID` %in% selected$pair)
write_csv(sheet200, "pe_obgyn_final_calling_sheet_200.csv")
cat(sprintf("Selected %d pairs (%d clinicians) across %d states\n",
            n_distinct(sheet200$`Matched Pair ID`), nrow(sheet200), n_distinct(sheet200$State)))
cat("Pairs per state (fielded 200):\n")
print(selected %>% count(State, sort = TRUE), n = 30)

# 2. Map the fielded physicians to their REDCap dropdown codes
choices <- read.csv(DICT, check.names = FALSE) %>%
  {.[.[[1]] == "physician_name", "Choices, Calculations, OR Slider Labels"]}
lab <- as.data.frame(mysterycall_parse_redcap_labels(choices))
lab$code <- as.integer(str_trim(lab$code))
lab$npi  <- str_match(lab$label, "NPI:\\s*(\\d+)")[, 2]

fielded_npi <- as.character(sheet200$NPI)
code_by_npi <- lab %>% transmute(npi, code)

# physician_name is a human-readable calling string built from the calling sheet:
# "Dr. Name, City, State, Phone: <phone>, NPI: <npi>". record_id stays the REDCap
# dropdown code (mapped by NPI) so records remain traceable to the instrument.
imp <- sheet200 %>%
  transmute(
    npi            = as.character(NPI),
    physician_name = sprintf("%s, %s, %s, Phone: %s, NPI: %s",
                             `Provider Name`, City, State, Phone, NPI)
  ) %>%
  left_join(code_by_npi, by = "npi") %>%
  arrange(code) %>%
  transmute(record_id = row_number(), physician_name)  # fresh contiguous ids 1..N (no gaps)
imp[[paste0(FORM, "_complete")]] <- 0L

matched <- sum(fielded_npi %in% lab$npi)
cat(sprintf("\nFielded physicians: %d | matched to dropdown code: %d | import records: %d\n",
            length(fielded_npi), matched, nrow(imp)))
if (nrow(imp) != length(fielded_npi) || any(is.na(imp$record_id)))
  cat("  WARNING: some fielded physicians did not map to a dropdown code.\n")

write_csv(imp, "redcap_import_ready_200.csv")

# REDCap dropdown CHOICES for the physician_name field: one "code, label" line per
# physician, to copy/paste into the "Choices (one choice per line)" box in the
# Online Designer. REDCap splits each line on the first comma only, so the label's
# internal commas (city, state, phone, NPI) are preserved.
# 800 physician x insurance choices: ids 1..400 = Medicaid, 401..800 = Blue Cross/
# Blue Shield (the same 400 physicians, same order, in each block). id 1 and id 401
# are the same physician (Medicaid vs BCBS). Each line is REDCap "code, label".
phys  <- imp$physician_name
n     <- nrow(imp)
combo <- rbind(
  data.frame(id = seq_len(n),     name = phys, ins = "Medicaid",               stringsAsFactors = FALSE),
  data.frame(id = n + seq_len(n), name = phys, ins = "Blue Cross/Blue Shield", stringsAsFactors = FALSE)
)
choice_lines <- sprintf("%d, id: %d, %s, Insurance: %s, id: %d",
                        combo$id, combo$id, combo$name, combo$ins, combo$id)
writeLines(choice_lines, "redcap_physician_name_choices.txt")
cat("Wrote pe_obgyn_final_calling_sheet_200.csv, redcap_import_ready_200.csv, and redcap_physician_name_choices.txt\n")
cat(sprintf("Calls implied: %d records x 2 calls = %d (<= 800 ceiling: %s)\n",
            nrow(imp), nrow(imp) * 2, ifelse(nrow(imp) * 2 <= 800, "YES", "NO")))
