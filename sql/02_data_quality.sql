-- data quality checks, run before analysis

CREATE OR REPLACE VIEW dq_report AS

-- ACS: earnings suppressed for small groups
SELECT 'Missing female or male median earnings' AS check_name,
       'jobs_gender (ACS)' AS dataset,
       COUNT(*) AS issue_rows,
       'Excluded from pay-gap ranking (is_reliable = FALSE)' AS action_taken
FROM raw_jobs_gender
WHERE total_earnings_female IS NULL OR total_earnings_male IS NULL

UNION ALL
-- ACS: tiny groups give unstable medians
SELECT 'Fewer than 10k men or women in occupation',
       'jobs_gender (ACS)',
       COUNT(*),
       'Excluded from pay-gap ranking (is_reliable = FALSE)'
FROM raw_jobs_gender
WHERE total_earnings_female IS NOT NULL AND total_earnings_male IS NOT NULL
  AND (workers_male < 10000 OR workers_female < 10000)

UNION ALL
-- ACS: male + female should equal total
SELECT 'Male + female workers <> total workers',
       'jobs_gender (ACS)',
       COUNT(*),
       'Logged only (reconciliation check)'
FROM raw_jobs_gender
WHERE workers_male + workers_female <> total_workers

UNION ALL
-- ACS: duplicate keys
SELECT 'Duplicate year + occupation keys',
       'jobs_gender (ACS)',
       COUNT(*) - COUNT(DISTINCT year || '|' || occupation),
       'Logged only'
FROM raw_jobs_gender

UNION ALL
-- CPS earnings: completeness of the quarterly series
SELECT 'Missing quarters in 2010-2020 series',
       'earn (BLS CPS)',
       44 - COUNT(DISTINCT year * 10 + quarter),
       'Logged only (expect 0)'
FROM raw_earn

UNION ALL
SELECT 'NULL median weekly earnings',
       'earn (BLS CPS)',
       COUNT(*),
       'Logged only (expect 0)'
FROM raw_earn
WHERE median_weekly_earn IS NULL

UNION ALL
-- Employment file: NULL industry
SELECT 'NULL industry name',
       'employed (BLS CPS)',
       COUNT(*),
       'Dropped in staging'
FROM raw_employed
WHERE industry IS NULL

UNION ALL
-- Employment file: demographic labels shifted into industry column
SELECT 'Demographic label in industry column (shifted rows)',
       'employed (BLS CPS)',
       COUNT(*),
       'Dropped in staging'
FROM raw_employed
WHERE industry IN ('Women', 'Men', 'White', 'Asian', 'Black or African American')

UNION ALL
-- Employment file: embedded line breaks in names
SELECT 'Line breaks inside industry name',
       'employed (BLS CPS)',
       COUNT(*),
       'Whitespace normalized in staging'
FROM raw_employed
WHERE industry LIKE '%' || CHR(10) || '%' OR industry LIKE '%' || CHR(13) || '%'

UNION ALL
-- Employment file: sub-industries that would double count
SELECT 'Sub-industry rows (would double count parent sector)',
       'employed (BLS CPS)',
       COUNT(*),
       'Excluded; analysis uses 13 top-level sectors'
FROM raw_employed
WHERE industry IN ('Durable goods', 'Nondurable goods', 'Wholesale trade', 'Retail trade',
                   'Other services, except private households', 'Private households');


-- Reconciliation: 13 cleaned sectors must sum to published BLS total employment
-- (BLS CPS annual average, employed persons 16+: ~157.5M in 2019, ~147.8M in 2020)
CREATE OR REPLACE VIEW dq_employment_reconciliation AS
SELECT year,
       SUM(employed) FILTER (WHERE demographic = 'TOTAL') AS total_employed,
       SUM(employed) FILTER (WHERE demographic = 'Men')
     + SUM(employed) FILTER (WHERE demographic = 'Women') AS men_plus_women,
       COUNT(DISTINCT industry) AS sectors
FROM stg_industry_employment
GROUP BY year
ORDER BY year;
