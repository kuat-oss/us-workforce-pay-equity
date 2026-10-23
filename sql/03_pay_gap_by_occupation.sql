-- gender pay gap by occupation (ACS 2013-2016, full-time year-round)

-- Balanced panel: only occupations reliable in ALL four years, so trends
-- compare the same set of jobs (no composition drift from suppression)
CREATE OR REPLACE VIEW occ_panel AS
SELECT p.*
FROM stg_occupation_pay p
JOIN (
    SELECT occupation
    FROM stg_occupation_pay
    WHERE is_reliable
    GROUP BY occupation
    HAVING COUNT(DISTINCT year) = 4
) keep USING (occupation);


-- 1) Workforce-weighted pay ratio by year (balanced panel)
CREATE OR REPLACE VIEW a_pay_ratio_by_year AS
SELECT
    year,
    COUNT(*)                                                        AS occupations,
    SUM(total_workers)                                              AS workers,
    ROUND(SUM(median_earnings_female * workers_female) / SUM(workers_female), 0) AS wavg_female_earnings,
    ROUND(SUM(median_earnings_male   * workers_male)   / SUM(workers_male),   0) AS wavg_male_earnings,
    ROUND(100.0 * (SUM(median_earnings_female * workers_female) / SUM(workers_female))
                / (SUM(median_earnings_male   * workers_male)   / SUM(workers_male)), 1) AS overall_pay_ratio,
    -- "like-for-like" ratio: average gap INSIDE the same occupation, weighted by headcount
    ROUND(SUM(pay_ratio * total_workers) / SUM(total_workers), 1)    AS within_occupation_pay_ratio
FROM occ_panel
GROUP BY year
ORDER BY year;


-- 2) Pay ratio by major category, 2013 vs 2016 (is the gap closing?)
CREATE OR REPLACE VIEW a_pay_ratio_by_category AS
WITH cat AS (
    SELECT
        major_category,
        year,
        SUM(total_workers)                                      AS workers,
        ROUND(100.0 * SUM(workers_female) / SUM(total_workers), 1) AS pct_female,
        ROUND(SUM(pay_ratio * total_workers) / SUM(total_workers), 1) AS pay_ratio
    FROM occ_panel
    GROUP BY major_category, year
)
SELECT
    major_category,
    MAX(workers)    FILTER (WHERE year = 2016) AS workers_2016,
    MAX(pct_female) FILTER (WHERE year = 2016) AS pct_female_2016,
    MAX(pay_ratio)  FILTER (WHERE year = 2013) AS pay_ratio_2013,
    MAX(pay_ratio)  FILTER (WHERE year = 2016) AS pay_ratio_2016,
    ROUND(MAX(pay_ratio) FILTER (WHERE year = 2016)
        - MAX(pay_ratio) FILTER (WHERE year = 2013), 1) AS change_pts
FROM cat
GROUP BY major_category
ORDER BY pay_ratio_2016;


-- 3) Occupations with the widest and narrowest gaps (2016, 50k+ workers)
CREATE OR REPLACE VIEW a_occupation_gap_ranking AS
WITH ranked AS (
    SELECT
        occupation,
        major_category,
        total_workers,
        percent_female,
        median_earnings_male,
        median_earnings_female,
        pay_ratio,
        median_earnings_male - median_earnings_female AS annual_gap_usd,
        RANK() OVER (ORDER BY pay_ratio ASC)  AS rank_widest,
        RANK() OVER (ORDER BY pay_ratio DESC) AS rank_narrowest
    FROM stg_occupation_pay
    WHERE year = 2016 AND is_reliable AND total_workers >= 50000
)
SELECT 'Widest gap' AS list, * EXCLUDE (rank_widest, rank_narrowest), rank_widest AS rnk
FROM ranked WHERE rank_widest <= 10
UNION ALL
SELECT 'Narrowest gap', * EXCLUDE (rank_widest, rank_narrowest), rank_narrowest
FROM ranked WHERE rank_narrowest <= 10
ORDER BY list DESC, rnk;


-- 4) Does occupational segregation drive pay? Female share bands vs earnings
CREATE OR REPLACE VIEW a_female_share_bands AS
SELECT
    CASE
        WHEN percent_female < 25 THEN '1. <25% female'
        WHEN percent_female < 50 THEN '2. 25-50% female'
        WHEN percent_female < 75 THEN '3. 50-75% female'
        ELSE                          '4. 75%+ female'
    END                                                                  AS female_share_band,
    COUNT(*)                                                             AS occupations,
    SUM(total_workers)                                                   AS workers,
    ROUND(SUM(median_earnings_all * total_workers) / SUM(total_workers), 0) AS wavg_median_earnings,
    ROUND(SUM(pay_ratio * total_workers) / SUM(total_workers), 1)        AS within_occ_pay_ratio
FROM stg_occupation_pay
WHERE year = 2016 AND is_reliable
GROUP BY 1
ORDER BY 1;


-- 5) Occupation-level scatter data for the dashboard (2016)
CREATE OR REPLACE VIEW a_occupation_scatter AS
SELECT occupation, major_category, total_workers, percent_female, median_earnings_all, pay_ratio
FROM stg_occupation_pay
WHERE year = 2016 AND is_reliable;
