-- 6.1 How many companies have positive sales (base for margin analysis)?
SELECT
    COUNT(*) AS total_companies,
    COUNT(*) FILTER (WHERE r.ingresos_ventas > 0) AS with_sales,
    ROUND(100.0 * COUNT(*) FILTER (WHERE r.ingresos_ventas > 0) / COUNT(*), 2) AS with_sales_pct
FROM staging.ranking_2025 AS r;
-- Findings (6.1):
-- - Only 95,601 of 154,343 companies (61.94%) reported positive sales in 2025;
--   38% reported zero sales (likely dormant or shell companies).
-- - Margin analysis (6.2) uses only companies with sales > 0.
-- - This also defines "active company" for Q4: ingresos_ventas > 0.

-- 6.2 Net margin by sector: aggregate (size-weighted) vs median (typical company)
SELECT
    c.sector,
    COUNT(*) AS n_companies,
    ROUND(100.0 * SUM(r.utilidad_neta) / SUM(r.ingresos_ventas), 2) AS aggregate_margin_pct,
    ROUND((100.0 * PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY r.utilidad_neta / r.ingresos_ventas))::numeric, 2) AS median_margin_pct
FROM staging.ranking_2025 AS r
JOIN staging.ciiu_seccion AS c ON c.ciiu = r.ciiu_n1
WHERE r.ingresos_ventas > 0
GROUP BY c.sector
HAVING COUNT(*) >= 30
ORDER BY aggregate_margin_pct DESC;
-- Findings (6.2):
-- - Base: companies with sales > 0, sectors with >= 30 such companies (18 sectors).
-- - Aggregate margin (size-weighted) exceeds the median margin (typical company)
--   in 17 of 18 sectors: large companies earn higher margins than typical ones.
-- - Mineria shows the widest gap (19.84% aggregate vs 2.20% median, ~9x):
--   profitability is concentrated in a few large miners, consistent with its
--   high sales concentration (CR4 = 51.03%, 5.3).
-- - Finanzas y seguros leads on both measures (55.76% aggregate, 13.30% median).
--   The aggregate is likely inflated by holding companies (profit ~= sales), but
--   the median confirms the typical financial company is also more profitable.
-- - Agua y saneamiento is the only sector where the median (1.91%) exceeds the
--   aggregate (1.52%): its large companies are less profitable than typical ones
--   (possible regulated tariffs; hypothesis, not tested).
-- - Typical margins are thin: outside Finanzas, all medians are between 0.50% and 3.25%.
--   Comercio, the largest sector by sales, has a 2.50% aggregate margin (volume business).
-- - The ranking depends on the metric (e.g., Mineria is 2nd by aggregate, 5th by
--   median); both must be reported together.
-- - Limitation: holding companies are not identified or separated in V1.