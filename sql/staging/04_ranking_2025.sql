-- =============================================================
-- Staging: ranking_2025 (fact table)
-- Source: raw.bi_ranking -> Target: staging.ranking_2025
--
-- One row per company for fiscal year 2025 (154,343 companies):
--   - Filter anio = 2025; grain = expediente (profiling 1.3)
--   - V1 scope: 7 columns (profiling 1.1); revenue = ingresos_ventas
--   - Amounts cast to numeric (exact, safe for sums); empty
--     strings -> NULL via NULLIF before casting
--   - n_empleados > 100,000 -> NULL: 2 values were national ID
--     numbers loaded by mistake at the source (profiling 1.6);
--     rows kept
--   - Codes kept as text to match dimension keys
--   - 2 companies with NULL ciiu_n1 / cod_segmento kept as NULL
--
-- No foreign keys on purpose: they would block the DROP in the
-- dimension scripts. Orphans are checked below instead.
--
-- Known limitation: 2 implausible sales-per-employee cases
-- kept as-is (profiling 1.6).
--
-- Idempotent: drops and recreates the table on every run.
-- Run: docker compose exec -T db psql -U scvs -d scvs
--      -v ON_ERROR_STOP=1 < sql/staging/04_ranking_2025.sql
-- =============================================================
BEGIN;

CREATE SCHEMA IF NOT EXISTS staging;

DROP TABLE IF EXISTS staging.ranking_2025;

CREATE TABLE staging.ranking_2025 AS
    SELECT
        TRIM(anio)::integer AS anio,
        TRIM(expediente) AS expediente,
        NULLIF(TRIM(ingresos_ventas), '')::numeric AS ingresos_ventas,
        NULLIF(TRIM(utilidad_neta), '')::numeric AS utilidad_neta,
        TRIM(ciiu_n1) AS ciiu_n1,
        TRIM(cod_segmento) AS cod_segmento,
        -- Double cast: values may come as '12.0', which fails as integer
        CASE
            WHEN NULLIF(TRIM(n_empleados), '')::numeric > 100000 THEN NULL
            ELSE NULLIF(TRIM(n_empleados), '')::numeric::integer
        END AS n_empleados
    FROM raw.bi_ranking
    WHERE TRIM(anio) = '2025';

-- Enforce the grain: one row per company in 2025 (profiling 1.3)
ALTER TABLE staging.ranking_2025
    ADD PRIMARY KEY (expediente);

-- Fail fast: row count, no orphans against any dimension
-- (NULL keys excluded: missing data, not missing match),
-- ID-number cleanup applied, NULL count matches profiling
DO $$
BEGIN
    IF (SELECT COUNT(*) FROM staging.ranking_2025) <> 154343 THEN
        RAISE EXCEPTION 'Expected 154343 rows in staging.ranking_2025';
    END IF;
    IF (SELECT COUNT(*)
        FROM staging.ranking_2025 r
        LEFT JOIN staging.compania c ON r.expediente = c.expediente
        WHERE c.expediente IS NULL) > 0 THEN
        RAISE EXCEPTION 'Orphan expediente: not found in staging.compania';
    END IF;
    IF (SELECT COUNT(*)
        FROM staging.ranking_2025 r
        LEFT JOIN staging.ciiu_seccion s ON r.ciiu_n1 = s.ciiu
        WHERE r.ciiu_n1 IS NOT NULL AND s.ciiu IS NULL) > 0 THEN
        RAISE EXCEPTION 'Orphan ciiu_n1: not found in staging.ciiu_seccion';
    END IF;
    IF (SELECT COUNT(*)
        FROM staging.ranking_2025 r
        LEFT JOIN staging.segmento seg ON r.cod_segmento = seg.id_segmento
        WHERE r.cod_segmento IS NOT NULL AND seg.id_segmento IS NULL) > 0 THEN
        RAISE EXCEPTION 'Orphan cod_segmento: not found in staging.segmento';
    END IF;
    IF (SELECT COUNT(*) FROM staging.ranking_2025 WHERE n_empleados > 100000) > 0 THEN
        RAISE EXCEPTION 'Unexpected n_empleados > 100000';
    END IF;
    IF (SELECT COUNT(*) FROM staging.ranking_2025 WHERE ciiu_n1 IS NULL) <> 1 THEN
        RAISE EXCEPTION 'Expected exactly 1 NULL ciiu_n1 (profiling 2.6)';
    END IF;
END $$;
COMMIT;