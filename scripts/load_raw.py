"""Load raw data from local CSV files into the PostgreSQL database."""

import os
from dotenv import load_dotenv
import psycopg

load_dotenv()
try:
    with psycopg.connect(
        dbname=os.environ["POSTGRES_DB"],
        user=os.environ["POSTGRES_USER"],
        password=os.environ["POSTGRES_PASSWORD"],
        host=os.getenv("POSTGRES_HOST", "localhost"),
        port=os.getenv("POSTGRES_PORT", 5432),
    ) as conn:
        with conn.cursor() as cursor:
            cursor.execute("SELECT version();")
            db_version = cursor.fetchone()
            print(f"Database version: {db_version[0]}")
    print("Connection to the database established successfully.")
except KeyError as e:
    print(f"Environment variable not found: {e.args[0]}")
except psycopg.OperationalError as e:
    print(f"Operational error connecting to the database: {e}")
except Exception as e:
    print(f"Error connecting to the database: {e}")
