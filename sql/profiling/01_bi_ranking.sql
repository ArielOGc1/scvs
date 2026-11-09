SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema= 'raw' AND table_name= 'bi_ranking'
ORDER BY ordinal_position;

-- =============================================================
-- 1.1 RESULTADO (09-nov-2026)
-- 54 columnas, todas de tipo text (esperado: raw guarda el CSV
-- tal cual; el tipado se hace en staging).
--
-- ALCANCE V1 — columnas que entran a staging:
--   anio            -> filtro anio = 2024
--   expediente      -> llave de la empresa (join con bi_compania, a confirmar en 1.7)
--   ingresos_ventas -> ingreso operativo; base de concentración y margen (P1, P2, P3)
--   utilidad_neta   -> numerador del margen neto (P1, P3)
--   ciiu_n1         -> sector a nivel sección (P1, P3)
--   cod_segmento    -> tamaño de empresa (join con bi_segmento)
--   n_empleados     -> contexto de tamaño y actividad (P4)
--
-- EN OBSERVACIÓN — solo se perfilan:
--   id_estado_financiero -> verificar grano: ¿más de un estado financiero
--                           por empresa en 2024? Si sí, se duplicarían ingresos.
--   ingresos_totales     -> comparado contra ingresos_ventas.
--   ciiu_n6              -> CIIU detallado; solo si se hace drill-down de un sector.
--
-- FUERA DE V1:
--   29 ratios precalculados (liquidez, solvencia, gestión, rentabilidad):
--     el margen neto se calcula a partir de los montos para controlar
--     división por cero e ingresos negativos; liquidez/solvencia vuelven
--     en V1.1 (modelo de riesgo crediticio).
--   13 montos y 2 identificadores: ninguna de las 4 preguntas los usa.
--
-- DECISIÓN: ingresos = ingresos_ventas (no ingresos_totales), porque
--   refleja la actividad principal y excluye ingresos puntuales
--   (intereses, venta de activos) que distorsionan tamaño y margen.
-- =============================================================