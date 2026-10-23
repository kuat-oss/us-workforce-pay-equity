-- weekly earnings trends (BLS CPS 2010-2020, full-time wage & salary)

-- 1) Quarterly median weekly earnings: men vs women, all workers 16+
CREATE OR REPLACE VIEW a_earnings_by_sex_quarterly AS
SELECT
    period,
    quarter_start,
    MAX(median_weekly_earn) FILTER (WHERE sex = 'Both Sexes') AS all_workers,
    MAX(median_weekly_earn) FILTER (WHERE sex = 'Men')        AS men,
    MAX(median_weekly_earn) FILTER (WHERE sex = 'Women')      AS women,
    ROUND(100.0 * MAX(median_weekly_earn) FILTER (WHERE sex = 'Women')
                / MAX(median_weekly_earn) FILTER (WHERE sex = 'Men'), 1) AS women_to_men_pct,
    MAX(n_persons) FILTER (WHERE sex = 'Both Sexes')          AS ft_workers
FROM stg_weekly_earnings
WHERE race = 'All Races' AND ethnic_origin = 'All Origins' AND age = '16 years and over'
GROUP BY period, quarter_start
ORDER BY quarter_start;


-- 2) Year-over-year change using window functions (same quarter prior year)
CREATE OR REPLACE VIEW a_earnings_yoy AS
SELECT
    period,
    all_workers,
    LAG(all_workers, 4) OVER (ORDER BY quarter_start)                        AS all_workers_prev_year,
    ROUND(100.0 * (all_workers / LAG(all_workers, 4) OVER (ORDER BY quarter_start) - 1), 1) AS yoy_pct,
    ft_workers,
    ROUND(100.0 * (ft_workers::DOUBLE / LAG(ft_workers, 4) OVER (ORDER BY quarter_start) - 1), 1) AS ft_workers_yoy_pct
FROM a_earnings_by_sex_quarterly
ORDER BY quarter_start;


-- 3) Annual earnings by race (all origins) and Hispanic origin, 2010 vs 2020
CREATE OR REPLACE VIEW a_earnings_by_race AS
WITH yearly AS (
    SELECT
        CASE WHEN ethnic_origin = 'Hispanic or Latino' THEN 'Hispanic or Latino' ELSE race END AS group_name,
        year,
        AVG(median_weekly_earn) AS avg_weekly
    FROM stg_weekly_earnings
    WHERE sex = 'Both Sexes' AND age = '16 years and over'
      AND (ethnic_origin = 'Hispanic or Latino' OR (ethnic_origin = 'All Origins'))
    GROUP BY 1, 2
)
SELECT
    group_name,
    ROUND(MAX(avg_weekly) FILTER (WHERE year = 2010), 0) AS weekly_2010,
    ROUND(MAX(avg_weekly) FILTER (WHERE year = 2020), 0) AS weekly_2020,
    ROUND(100.0 * (MAX(avg_weekly) FILTER (WHERE year = 2020)
                 / MAX(avg_weekly) FILTER (WHERE year = 2010) - 1), 1) AS growth_pct,
    -- CAGR over 10 years
    ROUND(100.0 * (POWER(MAX(avg_weekly) FILTER (WHERE year = 2020)
                       / MAX(avg_weekly) FILTER (WHERE year = 2010), 1.0 / 10) - 1), 2) AS cagr_pct
FROM yearly
GROUP BY group_name
ORDER BY weekly_2020 DESC;


-- 4) Gender pay ratio by age group, 2020 annual average
CREATE OR REPLACE VIEW a_gender_ratio_by_age AS
WITH y AS (
    SELECT age, sex, AVG(median_weekly_earn) AS w
    FROM stg_weekly_earnings
    WHERE year = 2020 AND race = 'All Races' AND ethnic_origin = 'All Origins'
      AND age IN ('16 to 19 years', '20 to 24 years', '25 to 34 years', '35 to 44 years',
                  '45 to 54 years', '55 to 64 years', '65 years and over')
    GROUP BY age, sex
)
SELECT
    age,
    ROUND(MAX(w) FILTER (WHERE sex = 'Men'), 0)   AS men_weekly,
    ROUND(MAX(w) FILTER (WHERE sex = 'Women'), 0) AS women_weekly,
    ROUND(100.0 * MAX(w) FILTER (WHERE sex = 'Women') / MAX(w) FILTER (WHERE sex = 'Men'), 1) AS women_to_men_pct
FROM y
GROUP BY age
ORDER BY age;
