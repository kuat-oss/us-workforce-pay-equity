-- load raw csvs + clean staging views
-- run from repo root (relative paths)

-- RAW LAYER (as published, no changes)
CREATE OR REPLACE TABLE raw_jobs_gender AS
SELECT * FROM read_csv_auto('data/raw/jobs_gender.csv', nullstr = 'NA');

CREATE OR REPLACE TABLE raw_earn AS
SELECT * FROM read_csv_auto('data/raw/earn.csv', nullstr = 'NA');

CREATE OR REPLACE TABLE raw_employed AS
SELECT * FROM read_csv_auto('data/raw/employed.csv', nullstr = 'NA');


-- STAGING: occupation-level pay by gender (Census ACS, 2013-2016)
-- One row per year x detailed occupation.
-- pay_ratio = women's median earnings as % of men's (100 = parity).
CREATE OR REPLACE VIEW stg_occupation_pay AS
SELECT
    year,
    TRIM(occupation)                                   AS occupation,
    TRIM(major_category)                               AS major_category,
    TRIM(minor_category)                               AS minor_category,
    total_workers,
    workers_male,
    workers_female,
    percent_female,
    total_earnings                                     AS median_earnings_all,
    total_earnings_male                                AS median_earnings_male,
    total_earnings_female                              AS median_earnings_female,
    ROUND(100.0 * total_earnings_female / total_earnings_male, 1) AS pay_ratio,
    -- ACS suppresses estimates for small groups; flag rows that are reliable
    (total_earnings_male IS NOT NULL
        AND total_earnings_female IS NOT NULL
        AND workers_male   >= 10000
        AND workers_female >= 10000)                  AS is_reliable
FROM raw_jobs_gender;


-- STAGING: quarterly median weekly earnings (BLS CPS, 2010-2020)
CREATE OR REPLACE VIEW stg_weekly_earnings AS
SELECT
    sex,
    race,
    ethnic_origin,
    age,
    year,
    quarter,
    MAKE_DATE(year, (quarter - 1) * 3 + 1, 1)          AS quarter_start,
    year || '-Q' || quarter                            AS period,
    n_persons,
    median_weekly_earn
FROM raw_earn;


-- STAGING: employment by top-level industry (BLS CPS, 2015-2020)
-- Data issues found in raw file and handled here (see 02_data_quality.sql):
--   1. Industry names containing line breaks ("Mining, quarrying, and\r\noil...")
--   2. Malformed rows where demographic labels shifted into the industry column
--      ("Women", "Men", "Asian", ...) with NULL counts
--   3. Rows with NULL industry
--   4. Nested sub-industries (Durable goods, Retail trade, ...) that would
--      double-count if summed with their parent sector
CREATE OR REPLACE VIEW stg_industry_employment AS
WITH cleaned AS (
    SELECT
        REGEXP_REPLACE(TRIM(industry), '\s+', ' ', 'g') AS industry,
        race_gender,
        industry_total,
        year
    FROM raw_employed
    WHERE industry IS NOT NULL
      AND industry_total IS NOT NULL
)
SELECT DISTINCT
    industry,
    year,
    race_gender AS demographic,
    industry_total AS employed
FROM cleaned
WHERE industry IN (
    'Agriculture and related',
    'Mining, quarrying, and oil and gas extraction',
    'Construction',
    'Manufacturing',
    'Wholesale and retail trade',
    'Transportation and utilities',
    'Information',
    'Financial activities',
    'Professional and business services',
    'Education and health services',
    'Leisure and hospitality',
    'Other services',
    'Public administration'
);
