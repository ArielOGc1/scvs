-- =============================================================
-- Profiling: dimension tables (raw.bi_compania, raw.bi_ciiu, raw.bi_segmento)
-- SCVS snapshot 2026-10-11
-- Purpose: inspect raw dimensions before building the staging layer.
-- Read-only: no table is created or modified.
-- Run from the repo root:
--   docker compose exec -T db psql -U scvs -d scvs < sql/profiling/02_dimensions.sql
-- =============================================================


-- 2.1 Column map: which columns does each dimension have, and of what type?
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'raw' AND table_name IN ('bi_compania', 'bi_ciiu', 'bi_segmento')
ORDER BY table_name, ordinal_position;
-- =============================================================
-- 2.1 RESULT (2026-11-09)
-- bi_ciiu: ciiu, descripcion | bi_compania: expediente, ruc, nombre,
--   tipo, pro_codigo, provincia | bi_segmento: id_segmento, segmento.
-- All columns are text. Join keys: expediente, ciiu, id_segmento.
-- Region is not available (province only); a province -> region
--   mapping is an optional extra for later.
-- =============================================================


-- 2.2a CIIU code format: what lengths do the catalog codes have?
SELECT LENGTH(ciiu) AS code_length,
    COUNT(*) AS codes
FROM raw.bi_ciiu
GROUP BY LENGTH(ciiu)
ORDER BY code_length;

-- 2.2b CIIU code format: what do the codes starting with G look like?
SELECT ciiu, LENGTH(ciiu) AS code_length, descripcion
FROM raw.bi_ciiu
WHERE ciiu LIKE 'G%'
ORDER BY ciiu
LIMIT 15;
-- =============================================================
-- 2.2 RESULT (2026-11-09)
-- bi_ciiu has no level column; all 3,058 codes have length 15 (fixed
--   width, right-padded). This is why the CIIU join in 1.7 failed
--   without TRIM.
-- Level is derived from LENGTH(TRIM(ciiu)):
--   1 = section (G), 3 = division (G45), 4 = group (G451),
--   5 = class (G4510), 7-8 = subclass/activity (G4510.0, G4510.01).
-- V1 sector dimension: rows where LENGTH(TRIM(ciiu)) = 1 (sections).
-- =============================================================