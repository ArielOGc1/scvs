"""Load raw SCVS CSV files into the `raw` schema of PostgreSQL.

Raw layer = faithful copy of the source files:
  - every column is TEXT (no typing, no cleaning),
  - typing, TRIM and casts happen later, in SQL staging.

Usage (venv active and `docker compose up -d` running):
    python scripts/load_raw.py
"""

import csv
import os
import sys
import time
from pathlib import Path

import psycopg
from dotenv import load_dotenv
from psycopg import sql

# --- Configuration -----------------------------------------------------------
# Each name is written ONCE here; the rest of the script only uses the constants.
ROOT = Path(__file__).resolve().parents[1]
CSV_DIRECTORY = ROOT / "data" / "raw"
RAW_SCHEMA = "raw"
CHUNK_SIZE = 1 << 20  # 1 MB, for COPY streaming

# Smallest first: if something breaks, you find out in seconds, not minutes.
EXPECTED_CSV = ["bi_segmento", "bi_ciiu", "bi_compania", "bi_ranking"]


# Files
def csv_path(table: str) -> Path:
    """Return the CSV path for a table name (the only place that adds '.csv')."""
    return CSV_DIRECTORY / f"{table}.csv"


def validate_csv_files(tables: list[str]) -> None:
    """Fail before touching the database if any expected CSV is missing."""
    missing = [str(csv_path(t)) for t in tables if not csv_path(t).exists()]
    if missing:
        raise FileNotFoundError(f"Expected CSV files not found: {', '.join(missing)}")


def read_header(path: Path) -> list[str]:
    """Read the first row of a CSV and strip whitespace from each column name."""
    with open(path, newline="", encoding="utf-8-sig") as f:
        header = next(csv.reader(f))
    return [col.strip() for col in header]


def count_csv_rows(path: Path) -> int:
    """Count the number of rows in a CSV file (excluding the header)."""
    with open(path, newline="", encoding="utf-8-sig") as f:
        reader = csv.reader(f)
        next(reader)  # Skip header
        return sum(1 for _ in reader)


# Database
def get_connection() -> psycopg.Connection:
    """Open a connection using the .env variables (required ones fail fast)."""
    return psycopg.connect(
        dbname=os.environ["POSTGRES_DB"],
        user=os.environ["POSTGRES_USER"],
        password=os.environ["POSTGRES_PASSWORD"],
        host=os.getenv("POSTGRES_HOST", "localhost"),
        port=os.getenv("POSTGRES_PORT", "5432"),
    )


def create_schema(conn: psycopg.Connection, schema: str) -> None:
    """Create the schema if missing and verify it exists. Does NOT commit."""
    conn.execute(
        sql.SQL("CREATE SCHEMA IF NOT EXISTS {}").format(sql.Identifier(schema))
    )
    row = conn.execute(
        "SELECT 1 FROM information_schema.schemata WHERE schema_name = %s",
        (schema,),
    ).fetchone()
    if row is None:
        raise RuntimeError(f"Failed to create schema '{schema}'.")


def recreate_table(
    conn: psycopg.Connection, schema: str, table: str, header: list[str]
) -> None:
    """Drop and recreate schema.table with one TEXT column per header entry.
    Does NOT commit."""
    table_id = sql.Identifier(schema, table)
    columns = sql.SQL(", ").join(
        sql.SQL("{} TEXT").format(sql.Identifier(col)) for col in header
    )
    drop_stmt = sql.SQL("DROP TABLE IF EXISTS {}").format(table_id)
    create_stmt = sql.SQL("CREATE TABLE {} ({})").format(table_id, columns)
    conn.execute(drop_stmt)
    conn.execute(create_stmt)


def verify_table(
    conn: psycopg.Connection, schema: str, table: str, expected_columns: int
) -> None:
    """Check that schema.table exists and has the expected number of columns."""
    table_row = conn.execute(
        "SELECT 1 FROM information_schema.tables "
        "WHERE table_schema = %s AND table_name = %s",
        (schema, table),
    ).fetchone()
    if table_row is None:
        raise RuntimeError(f"Table '{schema}.{table}' was not created.")

    count_row = conn.execute(
        "SELECT count(*) FROM information_schema.columns "
        "WHERE table_schema = %s AND table_name = %s",
        (schema, table),
    ).fetchone()
    n_columns = count_row[0] if count_row is not None else 0
    if n_columns != expected_columns:
        raise RuntimeError(
            f"Column count mismatch for '{schema}.{table}': "
            f"expected {expected_columns}, got {n_columns}."
        )


def load_table(conn: psycopg.Connection, schema: str, table: str, path: Path) -> None:
    """Load a CSV file into schema.table using COPY. Does NOT commit."""

    copy_stmt = sql.SQL(
        "COPY {} FROM STDIN WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')"
    ).format(sql.Identifier(schema, table))

    with conn.cursor() as cur, open(path, "rb") as f, cur.copy(copy_stmt) as copy:
        while data := f.read(CHUNK_SIZE):
            copy.write(data)


def verify_row_count(
    conn: psycopg.Connection, schema: str, table: str, expected_rows: int
) -> None:
    """Check that schema.table has the expected number of rows."""

    query_count_row = sql.SQL("SELECT COUNT(*) FROM {}").format(
        sql.Identifier(schema, table)
    )
    count_row = conn.execute(query_count_row).fetchone()
    actual_rows = count_row[0] if count_row is not None else 0
    if actual_rows != expected_rows:
        raise RuntimeError(
            f"Row count mismatch for '{schema}.{table}': "
            f"expected {expected_rows}, got {actual_rows}."
        )


# Entry point
def main() -> int:
    """Run the load. Returns 0 on success, 1 on error (exit code for the shell)."""
    load_dotenv()

    load_plan = []
    try:
        # Everything that can fail without the database is checked first.
        validate_csv_files(EXPECTED_CSV)
        for table in EXPECTED_CSV:
            header = read_header(csv_path(table))
            expected_rows = count_csv_rows(csv_path(table))
            load_plan.append((table, header, expected_rows))

        with get_connection() as conn:
            version_row = conn.execute("SELECT version()").fetchone()
            if version_row is None:
                raise RuntimeError("Failed to retrieve database version.")
            print(f"Connected: {version_row[0]}")

            create_schema(conn, RAW_SCHEMA)
            for table, header, expected_rows in load_plan:
                start_time = time.perf_counter()
                print(f"Loading {RAW_SCHEMA}.{table}...")
                recreate_table(conn, RAW_SCHEMA, table, header)
                verify_table(conn, RAW_SCHEMA, table, len(header))
                load_table(conn, RAW_SCHEMA, table, csv_path(table))
                verify_row_count(conn, RAW_SCHEMA, table, expected_rows)
                conn.commit()  # Per table: loaded tables stay saved. Safe because the snapshot is frozen.
                elapsed_time = time.perf_counter() - start_time
                print(
                    f"Loaded {RAW_SCHEMA}.{table} {expected_rows:,} rows, "
                    f"{len(header)} columns in {elapsed_time:.2f} seconds."
                )

            # Single commit point: main decides when everything is saved
    except KeyError as e:
        print(f"Environment variable not found: {e.args[0]}", file=sys.stderr)
        return 1
    except FileNotFoundError as e:
        print(e, file=sys.stderr)
        return 1
    except psycopg.OperationalError as e:
        print(f"Could not connect to the database: {e}", file=sys.stderr)
        return 1
    except Exception as e:  # noqa: BLE001 — last-resort handler, on purpose
        print(f"Unexpected error: {e}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
