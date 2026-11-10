-- =============================================================
-- Profiling: raw.bi_ranking (SCVS snapshot 2026-10-11)
-- Purpose: inspect raw data before building the staging layer.
-- Read-only: no table is created or modified.
-- Run from the repo root:
--   docker compose exec -T db psql -U scvs -d scvs < sql/profiling/01_bi_ranking.sql
-- =============================================================


-- 1.1 Column map: which columns does raw.bi_ranking have, and of what type?
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'raw' AND table_name = 'bi_ranking'
ORDER BY ordinal_position;
-- =============================================================
-- 1.1 RESULT (2026-11-09)
-- 54 columns, all of type text (expected: raw stores the CSV
-- as-is; typing happens in staging).
--
-- V1 SCOPE — columns that go into staging:
--   anio            -> filter anio = 2025 (see 1.2 decision)
--   expediente      -> company key (join with bi_compania, confirmed in 1.7)
--   ingresos_ventas -> operating revenue; basis for concentration and margin (Q1, Q2, Q3)
--   utilidad_neta   -> net margin numerator (Q1, Q3)
--   ciiu_n1         -> sector at section level (Q1, Q3)
--   cod_segmento    -> company size (join with bi_segmento)
--   n_empleados     -> size and activity context (Q4)
--
-- UNDER REVIEW — profiled only:
--   id_estado_financiero -> check grain: more than one financial statement
--                           per company in 2025? If so, revenue would be duplicated.
--   ingresos_totales     -> compared against ingresos_ventas.
--   ciiu_n6              -> detailed CIIU; only for a sector drill-down.
--
-- OUT OF V1:
--   29 precomputed ratios (liquidity, solvency, efficiency, profitability):
--     net margin is computed from the amounts to control division by
--     zero and negative revenue; liquidity/solvency return in V1.1
--     (credit-risk model).
--   13 amounts and 2 identifiers: none of the 4 questions use them.
--
-- DECISION: revenue = ingresos_ventas (not ingresos_totales), because
--   it reflects core activity and excludes one-off income
--   (interest, asset sales) that distorts size and margin.
-- =============================================================


-- 1.2a Year distribution: how many rows per year?
SELECT anio, COUNT(*) AS row_count
FROM raw.bi_ranking
GROUP BY anio
ORDER BY anio;

-- 1.2b Year format: does every anio value have length 4 (no padding, no malformed values)?
SELECT LENGTH(anio) AS anio_length, COUNT(*) AS row_count
FROM raw.bi_ranking
GROUP BY LENGTH(anio)
ORDER BY anio_length;
-- =============================================================
-- 1.2 RESULT (2026-11-09)
-- 18 years (2008-2025); sum = 1,676,639 rows (matches raw load count).
-- All anio values have length 4 and none are NULL: no padding or
-- malformed values, so anio = '<year>' is a safe filter and anio
-- needs no TRIM in staging.
-- 2024: 142,521 rows | 2025: 154,343 rows.
-- 2025 follows the normal growth trend (+11,822 vs +8,331 the year
-- before), so it does not look truncated by late filers.
-- DECISION: V1 uses anio = '2025' (changed from the initial 2024 plan)
--   because it is the most recent exercise and shows no sign of
--   truncation. Limitation to note in the README: late filers may
--   still be missing from 2025.
-- =============================================================


-- 1.3 Grain: is there exactly one row per company in 2025?
SELECT COUNT(*) AS rows_2025,
    COUNT(DISTINCT expediente) AS distinct_companies,
    COUNT(*) - COUNT(expediente) AS expediente_nulls,
    COUNT(*) FILTER (WHERE expediente <> TRIM(expediente)) AS expediente_padded,
    COUNT(DISTINCT id_estado_financiero) AS distinct_id_estado_financiero
FROM raw.bi_ranking
WHERE anio = '2025';
-- =============================================================
-- 1.3 RESULT (2026-11-09) — grain check, anio = '2025'
-- rows_2025 = distinct_companies = 154,343; expediente has no NULLs
-- and no padding.
-- Grain confirmed: one row = one company in 2025 (no duplicated revenue).
-- id_estado_financiero is unique per row (154,343 distinct): it is a
-- statement ID that adds nothing beyond expediente -> dropped from scope.
-- STAGING: expediente can be the PRIMARY KEY, so a duplicate would make
--   the build fail instead of silently inflating totals.
-- =============================================================


-- 1.4a Missing values: NULLs, blanks and padding per scope column in 2025.
SELECT 'ingresos_ventas' AS column_name,
    COUNT(*) - COUNT(ingresos_ventas) AS nulls,
    COUNT(*) FILTER (WHERE TRIM(ingresos_ventas) = '') AS blanks,
    COUNT(*) FILTER (WHERE ingresos_ventas <> TRIM(ingresos_ventas)) AS padded
FROM raw.bi_ranking
WHERE anio = '2025'
UNION ALL
SELECT 'utilidad_neta' AS column_name,
    COUNT(*) - COUNT(utilidad_neta) AS nulls,
    COUNT(*) FILTER (WHERE TRIM(utilidad_neta) = '') AS blanks,
    COUNT(*) FILTER (WHERE utilidad_neta <> TRIM(utilidad_neta)) AS padded
FROM raw.bi_ranking
WHERE anio = '2025'
UNION ALL
SELECT 'n_empleados' AS column_name,
    COUNT(*) - COUNT(n_empleados) AS nulls,
    COUNT(*) FILTER (WHERE TRIM(n_empleados) = '') AS blanks,
    COUNT(*) FILTER (WHERE n_empleados <> TRIM(n_empleados)) AS padded
FROM raw.bi_ranking
WHERE anio = '2025'
UNION ALL
SELECT 'ciiu_n1' AS column_name,
    COUNT(*) - COUNT(ciiu_n1) AS nulls,
    COUNT(*) FILTER (WHERE TRIM(ciiu_n1) = '') AS blanks,
    COUNT(*) FILTER (WHERE ciiu_n1 <> TRIM(ciiu_n1)) AS padded
FROM raw.bi_ranking
WHERE anio = '2025'
UNION ALL
SELECT 'cod_segmento' AS column_name,
    COUNT(*) - COUNT(cod_segmento) AS nulls,
    COUNT(*) FILTER (WHERE TRIM(cod_segmento) = '') AS blanks,
    COUNT(*) FILTER (WHERE cod_segmento <> TRIM(cod_segmento)) AS padded
FROM raw.bi_ranking
WHERE anio = '2025'
UNION ALL
SELECT 'ingresos_totales' AS column_name,
    COUNT(*) - COUNT(ingresos_totales) AS nulls,
    COUNT(*) FILTER (WHERE TRIM(ingresos_totales) = '') AS blanks,
    COUNT(*) FILTER (WHERE ingresos_totales <> TRIM(ingresos_totales)) AS padded
FROM raw.bi_ranking
WHERE anio = '2025';

-- 1.4b Which companies have a NULL sector or segment, and how much do they sell?
SELECT expediente, ciiu_n1, cod_segmento, ingresos_ventas, n_empleados
FROM raw.bi_ranking
WHERE (ciiu_n1 IS NULL OR cod_segmento IS NULL) AND anio = '2025';
-- =============================================================
-- 1.4 RESULT (2026-11-09) — NULLs, blanks and padding, anio = '2025'
-- ingresos_ventas, utilidad_neta, n_empleados, ingresos_totales:
--   0 NULLs, 0 blanks, 0 padded.
-- ciiu_n1: 1 NULL | cod_segmento: 1 NULL (two different companies):
--   171277 -> sector G, no segment, revenue 100,000.23, 3 employees
--   309374 -> no sector, segment 1, revenue 0.00, 2 employees
-- DECISION: keep both rows with their NULLs; their weight in totals is
--   negligible and dropping companies without need would bias the data.
-- NOTE: cod_segmento has no padding here; the padding found in the raw
--   layer is in the bi_segmento dimension, so TRIM goes there.
-- NOTE: ~136k rows in earlier years have NULL ciiu_n1 -> historical
--   sector gap. Irrelevant for V1 (2025 only); matters if V1.1 uses
--   several years.
-- FOR 1.5: n_empleados comes as '3.00' (a direct ::integer cast fails);
--   revenue = 0.00 exists -> division by zero when computing net margin.
-- NOTE: 0 NULLs does not mean valid values; formats are checked in 1.5.
-- =============================================================


-- 1.5a Castability: how many values do not look like a number?
SELECT 'ingresos_ventas' AS column_name,
    COUNT(*) FILTER (WHERE ingresos_ventas !~ '^-?[0-9]+(\.[0-9]+)?$') AS non_numeric
FROM raw.bi_ranking
WHERE anio = '2025'
UNION ALL
SELECT 'utilidad_neta' AS column_name,
    COUNT(*) FILTER (WHERE utilidad_neta !~ '^-?[0-9]+(\.[0-9]+)?$') AS non_numeric
FROM raw.bi_ranking
WHERE anio = '2025'
UNION ALL
SELECT 'n_empleados' AS column_name,
    COUNT(*) FILTER (WHERE n_empleados !~ '^-?[0-9]+(\.[0-9]+)?$') AS non_numeric
FROM raw.bi_ranking
WHERE anio = '2025'
UNION ALL
SELECT 'cod_segmento' AS column_name,
    COUNT(*) FILTER (WHERE cod_segmento !~ '^-?[0-9]+(\.[0-9]+)?$') AS non_numeric
FROM raw.bi_ranking
WHERE anio = '2025'
UNION ALL
SELECT 'ingresos_totales' AS column_name,
    COUNT(*) FILTER (WHERE ingresos_totales !~ '^-?[0-9]+(\.[0-9]+)?$') AS non_numeric
FROM raw.bi_ranking
WHERE anio = '2025';

-- 1.5b Employees: do all values end in '.00' (safe to cast to integer)?
SELECT 'n_empleados' AS column_name,
    COUNT(*) FILTER (WHERE n_empleados !~ '\.0+$') AS nonzero_decimals
FROM raw.bi_ranking
WHERE anio = '2025';
-- =============================================================
-- 1.5 RESULT (2026-11-09) — castability, anio = '2025'
-- Pattern for numbers: ^-?[0-9]+(\.[0-9]+)?$ (optional minus sign,
-- digits, optional decimal part with a dot).
-- ingresos_ventas, utilidad_neta, ingresos_totales, n_empleados:
--   0 non-numeric values -> casting to NUMERIC is safe.
-- cod_segmento: 0 non-numeric -> numeric code, but it stays text in
--   staging (identifier, no arithmetic; its type must match the
--   bi_segmento key for the join).
-- ciiu_n1: excluded from this check (section-level CIIU is a letter);
--   its validity is checked in 1.7 against the bi_ciiu catalog.
-- n_empleados: 0 values with nonzero decimals (all are 'X.00') ->
--   two-step cast ::numeric::integer loses no information.
-- =============================================================


-- 1.6a Ranges: min, max, negatives, zeros and median per numeric column.
-- Casting inside the query is safe here because 1.5 found no non-numeric values.
SELECT 'ingresos_ventas' AS column_name,
    MIN(ingresos_ventas::numeric) AS min_value,
    MAX(ingresos_ventas::numeric) AS max_value,
    COUNT(*) FILTER (WHERE ingresos_ventas::numeric < 0) AS negatives,
    COUNT(*) FILTER (WHERE ingresos_ventas::numeric = 0) AS zeros,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ingresos_ventas::numeric) AS median_value
FROM raw.bi_ranking
WHERE anio = '2025'
UNION ALL
SELECT 'utilidad_neta' AS column_name,
    MIN(utilidad_neta::numeric) AS min_value,
    MAX(utilidad_neta::numeric) AS max_value,
    COUNT(*) FILTER (WHERE utilidad_neta::numeric < 0) AS negatives,
    COUNT(*) FILTER (WHERE utilidad_neta::numeric = 0) AS zeros,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY utilidad_neta::numeric) AS median_value
FROM raw.bi_ranking
WHERE anio = '2025'
UNION ALL
SELECT 'n_empleados' AS column_name,
    MIN(n_empleados::numeric) AS min_value,
    MAX(n_empleados::numeric) AS max_value,
    COUNT(*) FILTER (WHERE n_empleados::numeric < 0) AS negatives,
    COUNT(*) FILTER (WHERE n_empleados::numeric = 0) AS zeros,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY n_empleados::numeric) AS median_value
FROM raw.bi_ranking
WHERE anio = '2025'
UNION ALL
SELECT 'ingresos_totales' AS column_name,
    MIN(ingresos_totales::numeric) AS min_value,
    MAX(ingresos_totales::numeric) AS max_value,
    COUNT(*) FILTER (WHERE ingresos_totales::numeric < 0) AS negatives,
    COUNT(*) FILTER (WHERE ingresos_totales::numeric = 0) AS zeros,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ingresos_totales::numeric) AS median_value
FROM raw.bi_ranking
WHERE anio = '2025';

-- 1.6b Outliers: the 20 largest employee counts (numeric order, not text order).
SELECT expediente, n_empleados, ingresos_ventas, ciiu_n1
FROM raw.bi_ranking
WHERE anio = '2025'
ORDER BY n_empleados::numeric DESC
LIMIT 20;
-- =============================================================
-- 1.6 RESULT (2026-11-09) — ranges, anio = '2025'
-- ingresos_ventas: min 0, max 2,690,137,857.78, median 9,020;
--   0 negatives, 58,742 zeros (38% of companies -> likely dormant).
--   Max is ~300,000x the median -> strong market concentration (Q2).
-- utilidad_neta: min -32,021,211.35, max 515,905,137.29, median 0;
--   30,753 negatives (losses, expected), 53,351 zeros.
-- n_empleados: min 1, 0 zeros (even among zero-revenue companies ->
--   1 is likely a default value, not a real headcount).
--
-- INVALID n_empleados: 2 values are Ecuadorian ID numbers (cedulas):
--   390015 -> 1722151868 (10 digits, starts with 17 = Pichincha)
--   105507 -> 928267662  (leading 0 lost: 0928267662, 09 = Guayas)
--   Source data error, not a load error (load_raw copies text as-is;
--   the rest of each row is consistent).
--   VERIFIED in the source CSV: yes (row "2025,390015,..." has
--   1722151868.00 in the n_empleados position).
-- DECISION (staging): n_empleados > 100,000 -> NULL. The rule is robust:
--   the largest plausible value is 36,935 and the next one is 928M,
--   so any threshold in between flags the same 2 rows. Rows are kept
--   because their revenue is valid.
-- SUSPICIOUS, kept as-is (implausible but not provably wrong):
--   731839 -> 36,935 employees, revenue 1.07M (~USD 29/employee/year)
--   727682 -> 4,150 employees, revenue 16,573 (~USD 4/employee/year)
--   Documented as a README limitation; check their weight in Q4.
-- ANALYSIS NOTES: net margin only where ingresos_ventas > 0; Q4 must
--   decide whether "active company" means ingresos_ventas > 0.
-- =============================================================


-- 1.7 Join coverage: how many 2025 companies find no match in each dimension?
-- Anti-join: LEFT JOIN keeps every ranking row; rows whose dimension key
-- comes back NULL are the orphans.
SELECT 'bi_compania' AS dimension,
    COUNT(*) AS orphans
FROM raw.bi_ranking r
LEFT JOIN raw.bi_compania c ON r.expediente = c.expediente
WHERE r.anio = '2025' AND c.expediente IS NULL
UNION ALL
SELECT 'bi_ciiu' AS dimension,
    COUNT(*) AS orphans
FROM raw.bi_ranking r
LEFT JOIN raw.bi_ciiu ci ON r.ciiu_n1 = TRIM(ci.ciiu)
WHERE r.anio = '2025' AND ci.ciiu IS NULL
UNION ALL
SELECT 'bi_segmento' AS dimension,
    COUNT(*) AS orphans
FROM raw.bi_ranking r
LEFT JOIN raw.bi_segmento s ON r.cod_segmento = s.id_segmento
WHERE r.anio = '2025' AND s.id_segmento IS NULL;
-- =============================================================
-- 1.7 RESULT (2026-11-09) — join coverage, anio = '2025'
-- Orphans per dimension:
--   bi_compania (expediente = expediente):        0
--   bi_segmento (cod_segmento = id_segmento):     1 -> company 171277,
--                                                   NULL segment (see 1.4)
--   bi_ciiu (ciiu_n1 = ciiu):               154,343 -> ALL rows. Cause:
--     every bi_ciiu.ciiu value is padded to 15 characters ('G' + 14
--     spaces; see 02_dimensions.sql, 2.2). With TRIM(ci.ciiu) in the
--     join: 1 orphan -> company 309374, NULL sector (see 1.4).
-- STAGING: store the CIIU dimension already trimmed, so joins (phase 4)
--   and Power BI relationships are plain equalities, with no TRIM in
--   every query.
-- =============================================================