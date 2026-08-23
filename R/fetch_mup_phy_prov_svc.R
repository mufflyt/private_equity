#!/usr/bin/env Rscript
# =============================================================================
# Download CMS "Medicare Physician & Other Practitioners - by Provider and
# Service" annual files (NPI x HCPCS x place of service, utilization/payment)
# to the external drive, and record a provenance manifest.
#
# Source: https://catalog.data.gov/dataset/medicare-physician-other-practitioners-by-provider-and-service
# CMS dataset id: 92396110-2aed-4d63-a6a2-5d6207d46a29
#
# Files are 2.2-3.0 GB each (2013-2024, ~30 GB total) and are downloaded
# directly to the removable drive, never into the repo or Downloads. This
# script only fetches the raw CSVs and writes the manifest (source url, file
# size, SHA-256, download date). Filtering to the pelvic-floor HCPCS basket
# and loading into DuckDB is a separate step (see ingest_mup_phy_prov_svc.R)
# so partial/large-file failures don't block re-running the filter.
# =============================================================================

suppressPackageStartupMessages({
  library(curl)
  library(digest)
})

source("R/pe_warehouse.R")  # for NBER_VOLUME

CMS_DATASET_ID <- "92396110-2aed-4d63-a6a2-5d6207d46a29"

MUP_PHY_URLS <- c(
  "2013" = "https://data.cms.gov/sites/default/files/2025-11/bf4231f9-ec7f-4189-afc3-ba5d53b8bd12/MUP_PHY_R25_P04_V20_D13_Prov_Svc.csv",
  "2014" = "https://data.cms.gov/sites/default/files/2025-11/6700f86d-d2e5-4f2d-9dcb-8c30412768ff/MUP_PHY_R25_P04_V20_D14_Prov_Svc.csv",
  "2015" = "https://data.cms.gov/sites/default/files/2025-11/14954ce3-4c43-43df-97e9-2c0437d7b43c/MUP_PHY_R25_P04_V20_D15_Prov_Svc.csv",
  "2016" = "https://data.cms.gov/sites/default/files/2025-11/426bf97a-4cb8-47ca-9727-a535d9e8c298/MUP_PHY_R25_P04_V20_D16_Prov_Svc.csv",
  "2017" = "https://data.cms.gov/sites/default/files/2025-11/4623fb40-781e-4eef-860e-b851cd5d10ea/MUP_PHY_R25_P04_V20_D17_Prov_Svc.csv",
  "2018" = "https://data.cms.gov/sites/default/files/2025-11/5669eafb-f0b3-4dc5-be6d-abc09b480c2e/MUP_PHY_R25_P04_V20_D18_Prov_Svc.csv",
  "2019" = "https://data.cms.gov/sites/default/files/2025-11/7befba27-752e-47a8-a76c-6c6d4f74f2e3/MUP_PHY_R25_P04_V20_D19_Prov_Svc.csv",
  "2020" = "https://data.cms.gov/sites/default/files/2025-11/d22b18cd-7726-4bf5-8e9c-3e4587c589a1/MUP_PHY_R25_P05_V20_D20_Prov_Svc.csv",
  "2021" = "https://data.cms.gov/sites/default/files/2025-11/bffaf97a-c2ab-4fd7-8718-be90742e3485/MUP_PHY_R25_P05_V20_D21_Prov_Svc.csv",
  "2022" = "https://data.cms.gov/sites/default/files/2025-11/53fb2bae-4913-48dc-a6d4-d8c025906567/MUP_PHY_R25_P05_V20_D22_Prov_Svc.csv",
  "2023" = "https://data.cms.gov/sites/default/files/2025-04/e3f823f8-db5b-4cc7-ba04-e7ae92b99757/MUP_PHY_R25_P05_V20_D23_Prov_Svc.csv",
  "2024" = "https://data.cms.gov/sites/default/files/2026-05/b5ebab5a-f490-418a-9bce-4b9f31419356/PHY_R26_P05_V10_D24_Prov_Svc.csv"
)

MIN_EXPECTED_BYTES <- 1.5e9  # files run 2.2-3.0 GB; guard against a truncated/HTML-error download

#' Download every year's MUP_PHY Provider & Service CSV to the external
#' drive and (re)build the provenance manifest. Already-downloaded files
#' that pass the size floor are skipped; re-run to resume interrupted ones.
fetch_mup_phy_prov_svc <- function(years = names(MUP_PHY_URLS)) {
  volume <- researchpaths::resolve_volume(NBER_VOLUME)
  raw_dir <- file.path(volume, "data-raw", "cms", "physician_provider_service")

  urls <- MUP_PHY_URLS[years]
  stopifnot(!anyNA(urls))

  dests <- vapply(years, function(y) {
    d <- file.path(raw_dir, y)
    dir.create(d, showWarnings = FALSE, recursive = TRUE)
    file.path(d, basename(urls[[y]]))
  }, character(1))

  sizes <- file.size(dests)  # NA (not an error) for files that don't exist yet
  todo <- is.na(sizes) | sizes < MIN_EXPECTED_BYTES

  if (any(todo)) {
    cat(sprintf("Downloading %d of %d files to %s\n", sum(todo), length(todo), raw_dir))
    res <- curl::multi_download(urls[todo], dests[todo], resume = TRUE, progress = TRUE)
    bad <- res$status_code != 200 & res$status_code != 206
    if (any(bad)) {
      stop("Download failed (non-2xx) for: ", paste(dests[todo][bad], collapse = ", "))
    }
  } else {
    cat("All requested years already downloaded and pass the size floor.\n")
  }

  small <- file.size(dests) < MIN_EXPECTED_BYTES
  if (any(small)) {
    stop("File(s) below expected size floor (", MIN_EXPECTED_BYTES, " bytes) -- ",
         "likely a truncated download or an HTML error page saved as .csv: ",
         paste(dests[small], collapse = ", "))
  }

  manifest <- data.frame(
    year = years,
    cms_dataset_id = CMS_DATASET_ID,
    file_name = basename(urls),
    source_url = unname(urls),
    file_size_bytes = file.size(dests),
    sha256 = vapply(dests, function(f) digest::digest(f, algo = "sha256", file = TRUE), character(1)),
    download_date_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    local_path = dests,
    stringsAsFactors = FALSE
  )

  manifest_path <- file.path(raw_dir, "manifest.csv")
  if (file.exists(manifest_path)) {
    prior <- read.csv(manifest_path, colClasses = "character", stringsAsFactors = FALSE)
    prior <- prior[!(prior$year %in% manifest$year), , drop = FALSE]
    manifest <- rbind(prior[names(manifest)], manifest)
  }
  manifest <- manifest[order(manifest$year), ]
  write.csv(manifest, manifest_path, row.names = FALSE)

  dir.create("data/manifests", showWarnings = FALSE, recursive = TRUE)
  write.csv(manifest, "data/manifests/mup_phy_prov_svc_manifest.csv", row.names = FALSE)

  cat(sprintf("Manifest written: %s (%d years)\n", manifest_path, nrow(manifest)))
  invisible(manifest)
}

fetch_mup_phy_prov_svc()
