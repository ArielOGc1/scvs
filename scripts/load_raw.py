"""Load raw data from local CSV files into the PostgreSQL database."""

import csv
import os
from pathlib import Path

import psycopg
from dotenv import load_dotenv

# Path to the directory containing the CSV files
CSV_DIRECTORY = Path(__file__).resolve().parents[1] / "data" / "raw"
# List of expected CSV files
TABLES_NAME = [
    "bi_segmento",
    "bi_ciiu",
    "bi_compania",
    "bi_ranking",
]


def read_header(path):
    """Read the header of a CSV file."""
    with open(path, "r", newline="", encoding="utf-8-sig") as f:
        reader = csv.reader(f)
        header = next(reader)
        new_header = [h.strip() for h in header]
    return new_header


for tables in TABLES_NAME:
    csv_path = CSV_DIRECTORY / f"{tables}.csv"
    if not csv_path.exists():
        raise FileNotFoundError(f"Expected CSV file not found: {csv_path}")
    header = read_header(csv_path)
    print(f"{tables} header: {header} and length: {len(header)}")


load_dotenv()
try:
    with psycopg.connect(
        dbname=os.environ["POSTGRES_DB"],
        user=os.environ["POSTGRES_USER"],
        password=os.environ["POSTGRES_PASSWORD"],
        host=os.getenv("POSTGRES_HOST", "localhost"),
        port=os.getenv("POSTGRES_PORT", "5432"),
    ) as conn:
        db_version = conn.execute("SELECT version();").fetchone()
        if db_version is None:
            raise ValueError("Failed to retrieve database version.")
        else:
            print(f"Database version: {db_version[0]}")
        # Create the 'raw' schema if it doesn't exist
        conn.execute("CREATE SCHEMA IF NOT EXISTS raw;")
        verify = conn.execute(
            "SELECT schema_name FROM information_schema.schemata WHERE schema_name = %s",
            ("raw",),
        ).fetchone()
        if verify is None:
            raise ValueError("Failed to create schema 'raw'.")
        conn.commit()

    print("Connection to the database established successfully.")
except KeyError as e:
    print(f"Environment variable not found: {e.args[0]}")
except psycopg.OperationalError as e:
    print(f"Operational error connecting to the database: {e}")
except Exception as e:
    print(f"Unexpected error: {e}")
