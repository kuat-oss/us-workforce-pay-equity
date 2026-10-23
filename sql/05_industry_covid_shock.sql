-- 2020 job losses by sector (BLS CPS annual averages)

-- 1) Employment change 2019 -> 2020 by sector, with gender split
CREATE OR REPLACE VIEW a_industry_shock AS
WITH pivoted AS (
    SELECT
        industry,
        MAX(employed) FILTER (WHERE year = 2015 AND demographic = 'TOTAL') AS total_2015,
        MAX(employed) FILTER (WHERE year = 2019 AND demographic = 'TOTAL') AS total_2019,
        MAX(employed) FILTER (WHERE year = 2020 AND demographic = 'TOTAL') AS total_2020,
        MAX(employed) FILTER (WHERE year = 2019 AND demographic = 'Women') AS women_2019,
        MAX(employed) FILTER (WHERE year = 2020 AND demographic = 'Women') AS women_2020,
        MAX(employed) FILTER (WHERE year = 2019 AND demographic = 'Men')   AS men_2019,
        MAX(employed) FILTER (WHERE year = 2020 AND demographic = 'Men')   AS men_2020
    FROM stg_industry_employment
    GROUP BY industry
)
SELECT
    industry,
    total_2019,
    total_2020,
    total_2020 - total_2019                                         AS jobs_change,
    ROUND(100.0 * (total_2020::DOUBLE / total_2019 - 1), 1)         AS pct_change_2020,
    ROUND(100.0 * (total_2019::DOUBLE / total_2015 - 1), 1)         AS pct_growth_2015_2019,
    ROUND(100.0 * women_2019 / total_2019, 1)                       AS pct_women_2019,
    ROUND(100.0 * (women_2020::DOUBLE / women_2019 - 1), 1)         AS women_pct_change,
    ROUND(100.0 * (men_2020::DOUBLE   / men_2019   - 1), 1)         AS men_pct_change,
    -- share of all 2020 job losses carried by this sector
    ROUND(100.0 * (total_2020 - total_2019)
        / SUM(total_2020 - total_2019) OVER (), 1)                  AS share_of_total_loss_pct
FROM pivoted
ORDER BY pct_change_2020;


-- 2) Total employment trend 2015-2020 by gender
CREATE OR REPLACE VIEW a_employment_trend AS
SELECT
    year,
    SUM(employed) FILTER (WHERE demographic = 'TOTAL') AS total,
    SUM(employed) FILTER (WHERE demographic = 'Women') AS women,
    SUM(employed) FILTER (WHERE demographic = 'Men')   AS men,
    ROUND(100.0 * SUM(employed) FILTER (WHERE demographic = 'Women')
                / SUM(employed) FILTER (WHERE demographic = 'TOTAL'), 1) AS pct_women
FROM stg_industry_employment
GROUP BY year
ORDER BY year;
