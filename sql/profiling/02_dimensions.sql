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

-- 2.3a Does each dimension have exactly one row per key?
SELECT 'bi_segmento' AS table_name,
    COUNT(*) AS total,
    COUNT(DISTINCT id_segmento) AS distinct_keys,
    COUNT(DISTINCT TRIM(id_segmento)) AS distinct_trimmed_keys,
    COUNT(*) FILTER (WHERE id_segmento IS NULL OR TRIM(id_segmento)= '') AS empty_keys
FROM raw.bi_segmento
UNION ALL
SELECT 'bi_ciiu' AS table_name,
    COUNT(*) AS total,
    COUNT(DISTINCT ciiu) AS distinct_keys,
    COUNT(DISTINCT TRIM(ciiu)) AS distinct_trimmed_keys,
    COUNT(*) FILTER (WHERE ciiu IS NULL OR TRIM(ciiu) = '') AS empty_keys
FROM raw.bi_ciiu
UNION ALL
SELECT 'bi_compania' AS table_name,
    COUNT(*) AS total,
    COUNT(DISTINCT expediente) AS distinct_keys,
    COUNT(DISTINCT TRIM(expediente)) AS distinct_trimmed_keys,
    COUNT(*) FILTER (WHERE expediente IS NULL OR TRIM(expediente)= '') AS empty_keys
FROM raw.bi_compania;
-- 2.3 Result:
--   All three dimensions: total_rows = distinct_keys = distinct_trimmed_keys,
--   and empty_keys = 0.
--     bi_segmento:      5 rows
--     bi_ciiu:      3,058 rows
--     bi_compania: 345,819 rows
--
-- Conclusion:
--   Grain is clean: one row per join key, no hidden duplicates caused by
--   padding, no NULL or blank keys. Joining the fact table to these
--   dimensions will not duplicate companies or inflate totals.
--
-- Staging decision:
--   No deduplication needed (no DISTINCT ON). Keys are trimmed only for
--   consistency with the fact table.

-- 2.4 Do text attributes carry pading, and does it split categories?
SELECT 'bi_compania.provincia' AS column_name,
    COUNT(*) FILTER (WHERE provincia <> TRIM(provincia)) AS padded_rows,
    COUNT(DISTINCT provincia) AS distinct_raw,
    COUNT(DISTINCT TRIM(provincia)) AS distinct_trimmed,
    COUNT(DISTINCT UPPER(TRIM(provincia))) AS distinct_normalized
FROM raw.bi_compania
UNION ALL
SELECT 'bi_compania.tipo' AS column_name,
    COUNT(*) FILTER (WHERE tipo <> TRIM(tipo)) AS padded_rows,
    COUNT(DISTINCT tipo) AS distinct_raw,
    COUNT(DISTINCT TRIM(tipo)) AS distinct_trimmed,
    COUNT(DISTINCT UPPER(TRIM(tipo))) AS distinct_normalized
FROM raw.bi_compania
UNION ALL
SELECT 'bi_segmento.segmento' AS column_name,
    COUNT(*) FILTER (WHERE segmento <> TRIM(segmento)) AS padded_rows,
    COUNT(DISTINCT segmento) AS distinct_raw,
    COUNT(DISTINCT TRIM(segmento)) AS distinct_trimmed,
    COUNT(DISTINCT UPPER(TRIM(segmento))) AS distinct_normalized
FROM raw.bi_segmento
UNION ALL
SELECT 'bi_ciiu.descripcion' AS column_name,
    COUNT(*) FILTER (WHERE descripcion <> TRIM(descripcion)) AS padded_rows,
    COUNT(DISTINCT descripcion) AS distinct_raw,
    COUNT(DISTINCT TRIM(descripcion)) AS distinct_trimmed,
    COUNT(DISTINCT UPPER(TRIM(descripcion))) AS distinct_normalized 
FROM raw.bi_ciiu;
-- 2.4 Result:
--   bi_compania.tipo and bi_compania.provincia: padding in 100% of rows
--   (345,819) -> fixed-width export, not random noise.
--   bi_segmento.segmento: padding in all 5 rows.
--   bi_ciiu.descripcion: padding in only 2 rows.
--   In every column distinct_raw = distinct_trimmed = distinct_normalized:
--   padding does not split categories and there are no case variants.
--
-- Conclusion:
--   Totals would not change, but equality filters (e.g. provincia = 'X')
--   would silently fail and dashboard labels would carry trailing spaces.
--
-- Staging decision:
--   TRIM all text attributes. No UPPER/INITCAP needed.
--
-- Note for 2.6 (CIIU sections):
--   2,533 distinct descriptions for 3,058 codes -> some descriptions are
--   shared across codes (likely across hierarchy levels). Irrelevant for
--   V1 only if the ~21 section descriptions are unique among themselves.

-- 2.5a Are there companies with a missing province code or name?
SELECT
    COUNT(*) FILTER (WHERE provincia IS NULL OR TRIM(provincia) = '') AS empty_provincia,
    COUNT(*) FILTER (WHERE pro_codigo IS NULL OR TRIM(pro_codigo) = '') AS empty_pro_codigo
FROM raw.bi_compania;

-- 2.5b Does any province code map to more than one province name?
SELECT
    TRIM(pro_codigo) AS pro_codigo,
    COUNT(DISTINCT TRIM(provincia)) AS n_names,
    STRING_AGG(DISTINCT TRIM(provincia), ', ') AS names
FROM raw.bi_compania
GROUP BY TRIM(pro_codigo)
HAVING COUNT(DISTINCT TRIM(provincia)) > 1;

-- 2.5c Does any province name map to more than one province code?
SELECT
    TRIM(provincia) AS provincia,
    COUNT(DISTINCT TRIM(pro_codigo)) AS n_codes,
    STRING_AGG(DISTINCT TRIM(pro_codigo), ', ') AS codes
FROM raw.bi_compania
GROUP BY TRIM(provincia)
HAVING COUNT(DISTINCT TRIM(pro_codigo)) > 1;

-- 2.5d FUll list of code-name pairs
SELECT DISTINCT
    TRIM(pro_codigo) AS pro_codigo,
    TRIM(provincia) AS provincia
FROM raw.bi_compania
ORDER BY pro_codigo, provincia;
-- 2.5 Result:
--   0 missing values in pro_codigo and provincia.
--   No code maps to more than one name and no name maps to more than one
--   code -> strict 1:1 relationship, 24 pairs = Ecuador's 24 provinces.
--   No sentinel values (no 'EXTERIOR', 'NO DEFINIDO' or code 90).
--
-- Staging decision:
--   Keep both columns: provincia (TRIM) for labels, pro_codigo as text
--   (two-digit, zero-padded; casting to integer would turn '01' into 1).
--
-- Risk for the Power BI phase:
--   Province names have no accents (BOLIVAR, MANABI, GALAPAGOS...) and
--   BOLIVAR is ambiguous worldwide. Map geocoding needs the country added
--   (e.g. provincia || ', Ecuador') and the State/Province data category.

-- 2.6 How many CIIU are there, and their descriptions unique?
SELECT 
    COUNT(*) AS n_codes,
    COUNT(DISTINCT TRIM(ciiu)) AS n_distinct_codes,
    COUNT(DISTINCT TRIM(descripcion)) AS n_distinct_descriptions
FROM raw.bi_ciiu
WHERE LENGTH(TRIM(ciiu)) = 1;

-- 2.6b List of CIIU sections and their descriptions
SELECT 
    TRIM(ciiu) AS section_code,
    TRIM(descripcion) AS section_description
FROM raw.bi_ciiu
WHERE LENGTH(TRIM(ciiu)) = 1
ORDER BY section_code;

-- 2.6c How are 2025 companies distributed across ciiu_n1 values?
SELECT 
    TRIM(ciiu_n1) AS ciiu_n1,
    COUNT(*) AS n_companies
FROM raw.bi_ranking
WHERE anio= '2025'
GROUP BY TRIM(ciiu_n1)
ORDER BY ciiu_n1;
-- 2.6 Result:
--   bi_ciiu has 22 one-character codes: sections A-U (CIIU Rev. 4) plus
--   'Z' = 'DEPURAR', an SCVS sentinel for activities pending review.
--   All 22 descriptions are unique -> no sectors merge when grouping.
--   In 2025: no company uses 'Z'; no commas or stray values in ciiu_n1;
--   21 sections + 1 NULL (see 1.x) = 154,343 companies (matches the fact grain).
--
-- Staging decisions:
--   - Section dimension excludes 'Z' (unused; would show as an empty
--     'DEPURAR' option in Power BI filters).
--   - Descriptions: strip trailing period and collapse double spaces.
--   - Add a short label per section (some descriptions exceed 140 chars).
--
-- Risk for Phase 4 (Q3, margin by sector):
--   Sections O (9 companies), T (3) and U (1) are too small for a reliable
--   sector margin. Apply a minimum company count before ranking sectors.

-- 2.7a Complete list of segment codes and descriptions
SELECT
    TRIM(id_segmento) AS id_segmento,
    TRIM(segmento) AS segmento
FROM raw.bi_segmento
ORDER BY id_segmento;

-- 2.7b How are 2025 companies distributed across segments?
SELECT
    TRIM(cod_segmento) AS cod_segmento,
    COUNT(*) AS n_companies
FROM raw.bi_ranking
WHERE anio= '2025'
GROUP BY TRIM(cod_segmento)
ORDER BY cod_segmento;
-- 2.7 Result:
--   bi_segmento: 0 = NO DEFINIDO (sentinel), 1-4 = MICROEMPRESA, PEQUEÑA,
--   MEDIANA, GRANDE.
--   In 2025: no company uses code 0; 1 company has NULL cod_segmento.
--   106,749 + 33,178 + 10,075 + 4,340 + 1 = 154,343 (matches the fact grain).
--   69% of companies are micro; only 2.8% are large.
--
-- Staging decisions:
--   - Segment dimension excludes code 0 (same treatment as CIIU 'Z').
--   - NULL cod_segmento stays NULL (source did not report it; not mapped to 0).
--   - Keep id_segmento: needed as "Sort by" column in Power BI, since
--     segment names sort alphabetically in a meaningless order.

-- 2.8 Company names: padding, NULLs, empty strings and duplicates?
   SELECT
       COUNT(*)                                             AS total,
       COUNT(*) FILTER (WHERE nombre <> TRIM(nombre))       AS con_relleno,
       COUNT(*) FILTER (WHERE nombre IS NULL)               AS nulos,
       COUNT(*) FILTER (WHERE TRIM(nombre) = '')            AS vacios,
       COUNT(DISTINCT TRIM(nombre))                         AS distintos
   FROM raw.bi_compania;
   --   - 2.8 nombre: 11 padded, 0 NULL/empty -> TRIM. 398 duplicate names
--     (key is expediente, not nombre); disambiguate in top-10 if needed

-- =====================================================================
-- Summary: staging decisions for dimensions
-- =====================================================================
-- All dims : grain clean (1 row per key) -> no dedup; TRIM keys and text.
-- Province : keep provincia (TRIM) + pro_codigo as text ('01'-'24'), 1:1.
-- CIIU     : sections only (LENGTH(TRIM(ciiu)) = 1), exclude 'Z';
--            strip trailing period, collapse double spaces; add short label.
-- Segment  : exclude code 0; keep id_segmento for sort order.
-- NULLs    : 2025 companies with NULL ciiu_n1 / cod_segmento kept as NULL.
-- Phase 4  : sections O, T, U too small for reliable sector margin.
-- Power BI : add ', Ecuador' for map geocoding; sort segment by id.