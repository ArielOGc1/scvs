-- =============================================================
-- Staging: ciiu_seccion
-- Source: raw.bi_ciiu -> Target: staging.ciiu_seccion
--
-- Builds the CIIU sections dimension (V1 sector = section):
--   - Keeps only sections: LENGTH(TRIM(ciiu)) = 1 (profiling 2.6)
--   - Drops sentinel 'Z' = DEPURAR (profiling 2.6: not used by
--     any 2025 company)
--   - TRIM on key; descripcion cleaned: trailing period removed,
--     repeated spaces collapsed (profiling 2.4, 2.6)
--   - Adds sector: short business-friendly label per section
--     for Power BI axes
--
-- Known source issues, kept as-is (official SCVS text):
--   - E, Q: words glued together (YACTIVIDADES, ASISTENCIASOCIAL)
--   - E, G: missing punctuation between activities
--
-- Idempotent: drops and recreates the table on every run.
-- Run: docker compose exec -T db psql -U scvs -d scvs
--      -v ON_ERROR_STOP=1 < sql/staging/02_ciiu_seccion.sql
-- =============================================================
BEGIN;
CREATE SCHEMA IF NOT EXISTS staging;

DROP TABLE IF EXISTS staging.ciiu_seccion;

-- Sections only, without sentinel; nested cleaning runs inside-out:
-- TRIM -> drop trailing '.' -> TRIM -> collapse spaces
CREATE TABLE staging.ciiu_seccion AS
    SELECT
        TRIM(ciiu) AS ciiu,
        REGEXP_REPLACE(TRIM(RTRIM(TRIM(descripcion), '.')), '\s+', ' ', 'g') AS descripcion,
        -- No ELSE on purpose: a missing WHEN yields NULL, caught below
        CASE TRIM(ciiu)
            WHEN 'A' THEN 'Agricultura y pesca'
            WHEN 'B' THEN 'Minería'
            WHEN 'C' THEN 'Manufactura'
            WHEN 'D' THEN 'Electricidad y gas'
            WHEN 'E' THEN 'Agua y saneamiento'
            WHEN 'F' THEN 'Construcción'
            WHEN 'G' THEN 'Comercio'
            WHEN 'H' THEN 'Transporte'
            WHEN 'I' THEN 'Alojamiento y comida'
            WHEN 'J' THEN 'Información y TIC'
            WHEN 'K' THEN 'Finanzas y seguros'
            WHEN 'L' THEN 'Inmobiliario'
            WHEN 'M' THEN 'Profesional y técnico'
            WHEN 'N' THEN 'Apoyo administrativo'
            WHEN 'O' THEN 'Sector público'
            WHEN 'P' THEN 'Educación'
            WHEN 'Q' THEN 'Salud y asistencia'
            WHEN 'R' THEN 'Arte y recreación'
            WHEN 'S' THEN 'Otros servicios'
            WHEN 'T' THEN 'Hogares empleadores'
            WHEN 'U' THEN 'Org. internacionales'
            END AS sector
    FROM raw.bi_ciiu
    WHERE LENGTH(TRIM(ciiu)) = 1 AND TRIM(ciiu) <> 'Z';

-- CREATE TABLE AS copies no constraints; enforce one row per section
ALTER TABLE staging.ciiu_seccion
    ADD PRIMARY KEY (ciiu);

-- Fail fast on count AND content: 21 sections (A-U), every section
-- labeled, labels unique, descriptions fully cleaned
DO $$
BEGIN
    IF (SELECT COUNT(*) FROM staging.ciiu_seccion) <> 21 THEN
        RAISE EXCEPTION 'Expected 21 rows in staging.ciiu_seccion';
    END IF;
    IF (SELECT COUNT(*) FROM staging.ciiu_seccion WHERE sector IS NULL) > 0 THEN
        RAISE EXCEPTION 'Unexpected NULL sector';
    END IF;
    IF (SELECT COUNT(DISTINCT sector) FROM staging.ciiu_seccion) <> 21 THEN
        RAISE EXCEPTION 'Expected 21 distinct sectors in staging.ciiu_seccion';
    END IF;
    IF (SELECT COUNT(*) FROM staging.ciiu_seccion WHERE descripcion LIKE '%.') > 0 THEN
        RAISE EXCEPTION 'Unexpected periods on descripcion';
    END IF;
    IF (SELECT COUNT(*) FROM staging.ciiu_seccion WHERE descripcion LIKE '%  %') > 0 THEN
        RAISE EXCEPTION 'Unexpected double spaces on descripcion';
    END IF;
END $$;
COMMIT;