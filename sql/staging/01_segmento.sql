-- =============================================================
-- Staging: segmento
-- Source: raw.bi_segmento -> Target: staging.segmento
--
-- Cleans the company size catalog:
--   - TRIM on key and label (profiling 2.4: fixed-width padding)
--   - Drops sentinel code '0' = NO DEFINIDO (profiling 2.7:
--     not used by any 2025 company)
--   - Key kept as text to match ranking.cod_segmento
--
-- Idempotent: drops and recreates the table on every run.
-- Run: docker compose exec -T db psql -U scvs -d scvs
--      -v ON_ERROR_STOP=1 < sql/staging/01_segmento.sql
-- =============================================================

-- Single transaction: any error rolls back the whole script
BEGIN;
-- Create schema on first run; no-op afterwards
CREATE SCHEMA IF NOT EXISTS staging;

-- Drop previous version so the script can be re-run
DROP TABLE IF EXISTS staging.segmento;

-- Clean copy of the catalog without the sentinel
CREATE TABLE staging.segmento AS
    SELECT TRIM(id_segmento) AS id_segmento, TRIM(segmento) AS segmento
    FROM raw.bi_segmento
    WHERE TRIM(id_segmento) <> '0';

-- CREATE TABLE AS copies no constraints; enforce the grain
-- (one row per id_segmento, profiling 2.3)
ALTER TABLE staging.segmento
    ADD PRIMARY KEY (id_segmento);

-- Fail fast: 5 source rows minus the sentinel = 4
DO $$
BEGIN
    IF (SELECT COUNT(*) FROM staging.segmento) <> 4 THEN
        RAISE EXCEPTION 'Expected 4 rows in staging.segmento';
    END IF;
END $$;
COMMIT;
