# Resolving the NPPES/NBER warehouse on the removable drive.
#
# The path used to be hardcoded as "/Volumes/MufflySamsung 1/DuckDB/nber_my_duckdb.duckdb".
# macOS leaves a stale mount point behind after an unclean unmount and remounts the same
# physical disk one suffix along, so that literal now points at a mount that is present but
# unreadable while the 79 GB warehouse sits at "/Volumes/MufflySamsung 1 1/...".
#
# That would be an ordinary "file not found" were it not for DuckDB: dbConnect() CREATES a
# database when the path does not exist. The churn pipeline would then run to completion
# against zero rows and report a clean result having measured nothing.
#
# researchpaths resolves the volume by glob, validates a size floor, refuses to guess between
# two plausible mounts, and asserts the required tables exist AND are non-empty before handing
# back a connection. See github.com/mufflyt/researchpaths.

NBER_WAREHOUSE  <- "DuckDB/nber_my_duckdb.duckdb"
NBER_VOLUME     <- "MufflySamsung*"

pe_nber_warehouse <- function(required_tables = character(), read_only = TRUE) {
  if (!requireNamespace("researchpaths", quietly = TRUE))
    stop("researchpaths is not installed. ",
         'remotes::install_github("mufflyt/researchpaths")', call. = FALSE)

  researchpaths::open_duckdb_checked(
    relative_path   = NBER_WAREHOUSE,
    volume_pattern  = NBER_VOLUME,
    required_tables = required_tables,
    read_only       = read_only,
    env_var         = "PE_NBER_DUCKDB"
  )
}

pe_nber_warehouse_path <- function() {
  researchpaths::resolve_duckdb(NBER_WAREHOUSE, NBER_VOLUME, env_var = "PE_NBER_DUCKDB")
}
