-- 7.1 Companies, active companies and sales by province (registered domicile)
SELECT
    co.provincia,
    COUNT(*) AS n_companies,
    COUNT(*) FILTER (WHERE r.ingresos_ventas > 0) AS n_active,
    ROUND(100.0 * COUNT(*) FILTER (WHERE r.ingresos_ventas > 0) / COUNT(*), 2) AS active_rate_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE r.ingresos_ventas > 0) / SUM(COUNT(*) FILTER (WHERE r.ingresos_ventas > 0)) OVER (), 2) AS active_share_pct,
    SUM(r.ingresos_ventas) AS total_sales,
    ROUND(100.0 * SUM(r.ingresos_ventas) / SUM(SUM(r.ingresos_ventas)) OVER(), 2) AS sales_share_pct
FROM staging.ranking_2025 AS r
LEFT JOIN staging.compania AS co ON co.expediente = r.expediente
GROUP BY co.provincia
ORDER BY total_sales DESC;
-- Findings (7.1):
-- - Province = registered domicile, not where the company operates. Companies
--   headquartered in Guayas/Pichincha report their nationwide sales there.
-- - Guayas + Pichincha hold 70.56% of active companies and 79.20% of sales.
-- - Guayas sells more than its share of companies (43.64% of sales vs 36.35%
--   of active companies): its companies are larger on average.
-- - Zamora Chinchipe is the 5th province by sales (2.26%) with only 0.59% of
--   active companies (~USD 7.1M average sales per active company vs ~1.85M
--   nationally), driven by two mining companies (see 7.3).
-- - Activity rate ranges from 44.83% (Napo) to 67.48% (Azuay). Amazon provinces
--   and Esmeraldas have the lowest rates: more than half of their registered
--   companies reported no sales.

-- 7.2 Reconciliation: expected 24 provinces, 154.343 companies,
-- 95.601 active companies and total sales matching staging
WITH by_province AS (
    SELECT
        co.provincia,
        COUNT(*) AS n_companies,
        COUNT(*) FILTER (WHERE r.ingresos_ventas > 0) AS n_active,
        ROUND(100.0 * COUNT(*) FILTER (WHERE r.ingresos_ventas > 0) / COUNT(*), 2) AS active_rate_pct,
        ROUND(100.0 * COUNT(*) FILTER (WHERE r.ingresos_ventas > 0) / SUM(COUNT(*) FILTER (WHERE r.ingresos_ventas > 0)) OVER (), 2) AS active_share_pct,
        SUM(r.ingresos_ventas) AS total_sales,
        ROUND(100.0 * SUM(r.ingresos_ventas) / SUM(SUM(r.ingresos_ventas)) OVER(), 2) AS sales_share_pct
    FROM staging.ranking_2025 AS r
    LEFT JOIN staging.compania AS co ON co.expediente = r.expediente
    GROUP BY co.provincia
)
SELECT
    COUNT(*) AS n_provinces,
    SUM(n_companies) AS total_companies,
    SUM(n_active) AS total_active,
    SUM(total_sales) AS total_sales
FROM by_province;
-- 7.2 Result: 24 provinces, 154,343 companies, 95,601 active,
-- total sales 177,020,766,391.00. Matches staging, Q1 and 6.1. OK.

-- 7.3 Which companies explain Zamora Chinchipe's sales? (top 5 by sales)
SELECT
    r.expediente,
    co.nombre AS company_name,
    COALESCE(c.sector, 'Sin sector') AS sector,
    r.ingresos_ventas AS sales,
    ROUND(100.0 * r.ingresos_ventas / SUM(r.ingresos_ventas) OVER (), 2) AS province_share_pct
FROM staging.ranking_2025 AS r
LEFT JOIN staging.compania AS co ON co.expediente = r.expediente
LEFT JOIN staging.ciiu_seccion AS c ON c.ciiu = r.ciiu_n1
WHERE co.provincia = 'ZAMORA CHINCHIPE'
ORDER BY r.ingresos_ventas DESC, expediente
LIMIT 5;
-- Findings (7.3):
-- - Two mining companies explain Zamora Chinchipe's sales: Aurelian Ecuador
--   (43.55%) and Ecuacorriente (41.62%), together 85.17% of the province.
-- - Both are domiciled in Zamora, where they operate, so the domicile caveat
--   does not distort this result.
-- - The next three companies (construction and manufacturing) appear linked
--   to the mining supply chain (hypothesis based on company names, not tested).
-- - The top 5 companies hold ~93.3% of the province's sales: Zamora's economic
--   weight in the ranking depends almost entirely on mining.