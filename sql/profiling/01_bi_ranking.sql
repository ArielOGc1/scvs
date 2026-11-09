SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema= 'raw' AND table_name= 'bi_ranking'
ORDER BY ordinal_position;

-- =============================================================
-- 1.1 RESULT (2026-11-09)
-- 54 columns, all of type text (expected: raw stores the CSV
-- as-is; typing happens in staging).
--
-- V1 SCOPE — columns that go into staging:
--   anio            -> filter anio = 2024
--   expediente      -> company key (join with bi_compania, to confirm in 1.7)
--   ingresos_ventas -> operating revenue; basis for concentration and margin (Q1, Q2, Q3)
--   utilidad_neta   -> net margin numerator (Q1, Q3)
--   ciiu_n1         -> sector at section level (Q1, Q3)
--   cod_segmento    -> company size (join with bi_segmento)
--   n_empleados     -> size and activity context (Q4)
--
-- UNDER REVIEW — profiled only:
--   id_estado_financiero -> check grain: more than one financial statement
--                           per company in 2024? If so, revenue would be duplicated.
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