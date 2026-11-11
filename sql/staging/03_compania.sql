-- =============================================================
-- Staging: compania
-- Source: raw.bi_compania -> Target: staging.compania
--
-- Cleans the company dimension:
--   - TRIM on all columns (profiling 2.4: tipo and provincia
--     padded in 100% of rows; 2.8: 11 padded nombre)
--   - pro_codigo kept as text ('01'-'24'), 1:1 with provincia
--     (profiling 2.5)
--   - All 345,819 companies kept, not filtered to 2025: the year
--     filter belongs to the fact table
--   - ruc out of V1 scope (not used, not profiled)
--   - 398 duplicate names are valid (key is expediente)
--
-- Idempotent: drops and recreates the table on every run.
-- Run: docker compose exec -T db psql -U scvs -d scvs
--      -v ON_ERROR_STOP=1 < sql/staging/03_compania.sql
-- =============================================================
BEGIN;
CREATE SCHEMA IF NOT EXISTS staging;

DROP TABLE IF EXISTS staging.compania;

-- Clean copy of all companies; no row filter
CREATE TABLE staging.compania AS
    SELECT
        TRIM(expediente) AS expediente,
        TRIM(nombre) AS nombre,
        TRIM(tipo) AS tipo,
        TRIM(pro_codigo) AS pro_codigo,
        TRIM(provincia) AS provincia
    FROM raw.bi_compania;

-- Enforce the grain: one row per expediente (profiling 2.3)
ALTER TABLE staging.compania
    ADD PRIMARY KEY (expediente);

-- Fail fast: exact row count, names present, 24 provinces
-- and code <-> province mapping still 1:1
DO $$
BEGIN
    IF (SELECT COUNT(*) FROM staging.compania) <> 345819 THEN
        RAISE EXCEPTION 'Expected 345819 rows in staging.compania';
    END IF;
    IF (SELECT COUNT(*) FROM staging.compania WHERE nombre IS NULL) > 0 THEN
        RAISE EXCEPTION 'Unexpected NULL nombre';
    END IF;
    IF (SELECT COUNT(DISTINCT provincia) FROM staging.compania) <> 24 THEN
        RAISE EXCEPTION 'Expected 24 distinct provincias in staging.compania';
    END IF;
    IF (SELECT COUNT(DISTINCT (pro_codigo, provincia)) FROM staging.compania) <> 24 THEN
        RAISE EXCEPTION 'Expected 24 distinct (pro_codigo, provincia) pairs in staging.compania';
    END IF;
END $$;
COMMIT;