-- 5.1 Top-10 companies by sales, with share and cumulative share of national total
SELECT
    r.expediente, 
    co.nombre AS company_name,
    COALESCE(c.sector, 'Sin sector') AS sector,
    r.ingresos_ventas AS sales,
    ROUND(100.0 * r.ingresos_ventas / SUM(r.ingresos_ventas) OVER(), 2) AS sales_share_pct,
    ROUND(100.0 * SUM(r.ingresos_ventas) OVER (ORDER BY r.ingresos_ventas DESC, r.expediente) 
    / SUM(r.ingresos_ventas) OVER(), 2) AS cumulative_share_pct
FROM staging.ranking_2025 AS r
LEFT JOIN staging.compania AS co ON r.expediente = co.expediente
LEFT JOIN staging.ciiu_seccion AS c ON c.ciiu = r.ciiu_n1
ORDER BY r.ingresos_ventas DESC, r.expediente
LIMIT 10;
-- Findings (5.1):
-- - The top-10 companies hold 8.53% of national sales (10 out of 154,343 companies).
-- - 5 of the top 10 are in Comercio (Favorita, El Rosado, Primax, Dinadec, Tuti),
--   consistent with Comercio holding 40.82% of sales in Q1.
-- - Corporacion Favorita is the largest company by sales (1.52% of national total).
-- - Caveat: a national top-10 mixes unrelated markets, so a low national share does
--   not mean low concentration. Concentration within each sector is measured in 5.3.

-- 5.2 Join check: joins must not drop/duplicate rows nor leave names empty
SELECT
    COUNT(*) AS n_rows,
    COUNT(*) FILTER (WHERE co.nombre IS NULL) AS missing_names
FROM staging.ranking_2025 AS r
LEFT JOIN staging.compania AS co on co.expediente = r.expediente;
-- and leave no company without a name. Result: 154,343 rows, 0 missing. OK.

-- 5.3 Concentration within sectors: share of sector sales held by its top-4 companies
WITH ranked AS(
    SELECT
        c.sector,
        r.ingresos_ventas,
        ROW_NUMBER() OVER(
            PARTITION BY r.ciiu_n1 
            ORDER BY r.ingresos_ventas DESC, r.expediente
        ) AS rank_in_sector,
        SUM(r.ingresos_ventas) OVER (PARTITION BY r.ciiu_n1) AS sector_sales,
        COUNT(*) OVER (PARTITION BY r.ciiu_n1) AS n_companies
    FROM staging.ranking_2025 AS r
    LEFT JOIN staging.ciiu_seccion AS c on c.ciiu = r.ciiu_n1
    WHERE r.ciiu_n1 IS NOT NULL
)
SELECT 
    sector,
    n_companies,
    sector_sales,
    SUM(ingresos_ventas) AS top4_sales,
    ROUND(100.0 * SUM(ingresos_ventas) / sector_sales, 2) AS top3_share_pct
FROM ranked
WHERE rank_in_sector <= 4
GROUP BY sector, n_companies, sector_sales
ORDER BY top3_share_pct DESC;
-- Findings (5.3):
-- - Metric: CR4 = share of sector sales held by the sector's 4 largest companies.
-- - Most concentrated sectors (>= 30 companies): Electricidad y gas (70.70%),
--   Mineria (51.03%), Agua y saneamiento (45.12%), Informacion y TIC (44.07%).
--   All are capital- or infrastructure-intensive (hypothesis, not tested here).
-- - Paradox: Comercio places 5 companies in the national top 10 (5.1), yet it is
--   one of the least concentrated sectors (CR4 = 9.50% across 37,114 companies).
-- - Sectors with fewer than 30 companies (Sector publico, Hogares empleadores,
--   Org. internacionales) show CR4 near or at 100% by construction; excluded
--   from conclusions (same threshold applies in Q3).
-- - Checks: Mineria CR4 > share of its top 2 (~36.8%); Comercio sector_sales
--   matches Q1 (72,262,510,700.81).