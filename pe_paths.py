"""Resolve data paths on the removable drive without guessing.

The Python counterpart to R/pe_warehouse.R, which uses
github.com/mufflyt/researchpaths. Same contract, because the failure it prevents
is the same one:

macOS leaves a stale mount point in /Volumes after an unclean unmount and
remounts the same physical disk as "Name 1". Code holding the old literal reads
nothing. With DuckDB that is not a "file not found" -- duckdb.connect() creates a
database at a path that does not exist, so the pipeline runs to completion
against zero rows and reports a clean result having measured nothing.

Rules, matching researchpaths:
  1. Discovery is a glob over the volume name, never a literal.
  2. Discovery never creates, opens or modifies a candidate.
  3. A candidate must clear a size floor before it is accepted.
  4. Zero candidates is an error; several plausible candidates is an error.
  5. An environment override is honoured but still validated.
  6. Connections are read-only unless a caller deliberately asks otherwise.
"""

import glob
import os

NBER_WAREHOUSE = "DuckDB/nber_my_duckdb.duckdb"
NBER_VOLUME = "MufflySamsung*"
NBER_ENV_VAR = "PE_NBER_DUCKDB"
MIN_BYTES = 1_000_000_000


def _plausible(path, min_bytes):
    try:
        return os.path.isfile(path) and os.path.getsize(path) >= min_bytes
    except OSError:
        return False


def resolve_on_volume(relative_path, volume_pattern=NBER_VOLUME,
                      min_bytes=MIN_BYTES, mount_root="/Volumes", env_var=None):
    """Return the one plausible path, or raise. Never creates anything."""
    if env_var:
        override = os.environ.get(env_var)
        if override:
            if not _plausible(override, min_bytes):
                raise FileNotFoundError(
                    f"{env_var}={override!r} does not point at a file of at least "
                    f"{min_bytes:,} bytes. A typo here must fail, not create a "
                    f"database somewhere new.")
            return override

    candidates = [p for p in glob.glob(os.path.join(mount_root, volume_pattern,
                                                    relative_path))
                  if _plausible(p, min_bytes)]

    if not candidates:
        mounted = sorted(glob.glob(os.path.join(mount_root, volume_pattern)))
        raise FileNotFoundError(
            f"No file matching {volume_pattern}/{relative_path} of at least "
            f"{min_bytes:,} bytes under {mount_root}.\n"
            f"  Mount points matching {volume_pattern!r}: "
            f"{mounted if mounted else 'none'}\n"
            f"  Set {env_var or NBER_ENV_VAR} to override.")
    if len(candidates) > 1:
        joined = "\n    ".join(candidates)
        raise RuntimeError(
            f"{len(candidates)} plausible candidates for {relative_path}:\n"
            f"    {joined}\n"
            f"  Refusing to guess -- that would silently decide which data the "
            f"analysis ran on. Set {env_var or NBER_ENV_VAR} to choose.")
    return candidates[0]


def nber_warehouse_path():
    """Path to the NPPES/NBER DuckDB warehouse on the removable drive."""
    return resolve_on_volume(NBER_WAREHOUSE, NBER_VOLUME, env_var=NBER_ENV_VAR)


def open_nber_warehouse(required_tables=(), read_only=True):
    """Open the warehouse read-only, asserting required tables exist and are non-empty.

    An empty required table is treated as a missing one: a caller that proceeds
    from an empty table produces a confident answer about nothing.
    """
    import duckdb

    path = nber_warehouse_path()
    if not os.path.exists(path):
        raise FileNotFoundError(
            f"refusing to open a warehouse that does not exist: {path}")

    con = duckdb.connect(path, read_only=read_only)
    try:
        have = {r[0] for r in con.execute("SHOW TABLES").fetchall()}
        missing = [t for t in required_tables if t not in have]
        if missing:
            raise RuntimeError(
                f"{path} has {len(have)} table(s) but not: {', '.join(missing)}\n"
                f"  This is the wrong database.")
        for table in required_tables:
            n = con.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
            if not n:
                raise RuntimeError(
                    f"{table} in {path} is EMPTY. An empty table is treated as a "
                    f"missing one: a run over it reports zero findings and looks "
                    f"like a clean result.")
    except Exception:
        con.close()
        raise
    return con
