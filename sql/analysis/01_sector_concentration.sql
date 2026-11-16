-- 4.1 Sales and net profit by sector, with share of total
SELECT
    COALESCE(c.sector, 'Sin sector') AS sector,
    COUNT(*) AS n_companies,
    SUM(r.ingresos_ventas) AS total_sales,
    SUM(r.utilidad_neta) AS total_net_profit,
    ROUND(100.0 * SUM(r.ingresos_ventas) / SUM(SUM(r.ingresos_ventas)) OVER(), 2) AS sales_share_pct,
    ROUND(100.0 * SUM(r.utilidad_neta) / SUM(SUM(r.utilidad_neta)) OVER(), 2) AS profit_share_pct
FROM staging.ranking_2025 AS r
LEFT JOIN staging.ciiu_seccion AS c ON r.ciiu_n1 = c.ciiu
GROUP BY sector
ORDER BY total_sales DESC;
-- Findings (4.1):
-- - Sales are highly concentrated: Comercio alone holds 40.82% of total sales;
--   the top 3 sectors (Comercio, Manufactura, Agricultura y pesca) hold ~70.8%.
-- - Sales and profit do not move together: Finanzas y seguros (2.85% of sales)
--   and Mineria (5.24% of sales) together capture ~43.4% of total net profit,
--   while the top 3 sales sectors capture only ~36.6%.
-- - Finanzas y seguros likely includes holding companies whose operating revenue
--   is mostly dividends (one company shows net profit ~= sales). This may inflate
--   the sector margin; to be reviewed in Q3.
-- - All sectors show positive aggregate net profit, so profit_share_pct is a
--   valid share (no negative or >100% values).
-- - Sector publico (9), Hogares empleadores (3) and Org. internacionales (1)
--   have too few companies to support conclusions; a minimum-companies threshold
--   will be applied in Q3.
-- - 'Sin sector' = 1 company with NULL ciiu_n1 and zero sales; kept for reconciliation.

-- 4.2 Reconciliation: totals by sector must match staging totals
-- Expected: 154343 companies and total sales matching staging.ranking_2025. Result: OK.
WITH by_sector AS(
    SELECT
        COALESCE(c.sector, 'Sin sector') AS sector,
        COUNT(*) AS n_companies,
        SUM(r.ingresos_ventas) AS total_sales,
        SUM(r.utilidad_neta) AS total_net_profit,
        ROUND(100.0 * SUM(r.ingresos_ventas) / SUM(SUM(r.ingresos_ventas)) OVER(), 2) AS sales_share_pct,
        ROUND(100.0 * SUM(r.utilidad_neta) / SUM(SUM(r.utilidad_neta)) OVER(), 2) AS profit_share_pct
    FROM staging.ranking_2025 AS r
    LEFT JOIN staging.ciiu_seccion AS c ON r.ciiu_n1 = c.ciiu
    GROUP BY sector
    ORDER BY total_sales DESC
)
SELECT
    SUM(n_companies) AS total_companies,
    SUM(total_sales) AS total_sales
FROM by_sector;

