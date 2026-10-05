-- 004_phase3_eda.sql
--
-- Quarterly decline label and lag-correlation analysis on the TRAIN window only.
-- Everything here reads train_monthly (from 003_phase2_split.sql) and never touches
-- the Embargo or Test months, so no decision made from this file can be test-informed.
--
-- Definitions
--   Label:    1 when a county's ZHVI fell by MORE than 2 percent from the previous
--             quarter end to this quarter end, otherwise 0.
--   Quarter:  each county-quarter is represented by its QUARTER-END month (Mar, Jun,
--             Sep, Dec). A quarter whose end month has no ZHVI value gets no row, and a
--             label is only kept when the previous row is the calendar quarter right
--             before it. So BOTH quarter-end months must have a value, and every label is
--             a true quarter-to-quarter change.
--   Rate change: percentage-point difference, rate(t) minus rate(t - lag months).
--             A relative-change version at 12 months is kept for comparison only.
--   Alignment: each label quarter is paired with the rate change measured at the end of
--             the quarter BEFORE it, which is the information available one quarter ahead.

-- 1. Quarterly ZHVI per county: the quarter-end month's value.
DROP TABLE IF EXISTS train_quarterly CASCADE;
CREATE TABLE train_quarterly AS
SELECT
    county_fips,
    date_trunc('quarter', month)::date AS quarter,
    zhvi,
    mortgage_rate
FROM train_monthly
WHERE zhvi IS NOT NULL
  AND month = (date_trunc('quarter', month) + INTERVAL '3 months' - INTERVAL '1 day')::date;

-- 2. Quarter-over-quarter change and decline label.
DROP TABLE IF EXISTS train_quarterly_labeled CASCADE;
CREATE TABLE train_quarterly_labeled AS
SELECT
    county_fips,
    quarter,
    zhvi,
    mortgage_rate,
    LAG(zhvi)    OVER w AS prev_zhvi,
    LAG(quarter) OVER w AS prev_quarter,
    zhvi / NULLIF(LAG(zhvi) OVER w, 0) - 1 AS pct_change,
    CASE WHEN zhvi / NULLIF(LAG(zhvi) OVER w, 0) - 1 < -0.02 THEN 1 ELSE 0 END AS decline_label
FROM train_quarterly
WINDOW w AS (PARTITION BY county_fips ORDER BY quarter);

-- A county's first quarter has nothing to compare with, and a label whose previous row
-- is not the calendar quarter before it would span more than one quarter.
DELETE FROM train_quarterly_labeled
WHERE prev_zhvi IS NULL
   OR prev_quarter <> (quarter - INTERVAL '3 months')::date;

-- 3. National monthly mortgage rate (one value per month, identical for all counties).
DROP TABLE IF EXISTS national_monthly_rate CASCADE;
CREATE TABLE national_monthly_rate AS
SELECT DISTINCT month, mortgage_rate
FROM train_monthly
ORDER BY month;

-- 4. Rate change at each candidate lag, in percentage points. The column roc_12m_rel
-- is the relative change at 12 months, used only in the comparison further down.
DROP TABLE IF EXISTS national_rate_roc CASCADE;
CREATE TABLE national_rate_roc AS
SELECT
    month,
    date_trunc('quarter', month)::date AS quarter,
    mortgage_rate,
    mortgage_rate - LAG(mortgage_rate, 1)  OVER w AS roc_1m,
    mortgage_rate - LAG(mortgage_rate, 2)  OVER w AS roc_2m,
    mortgage_rate - LAG(mortgage_rate, 3)  OVER w AS roc_3m,
    mortgage_rate - LAG(mortgage_rate, 6)  OVER w AS roc_6m,
    mortgage_rate - LAG(mortgage_rate, 9)  OVER w AS roc_9m,
    mortgage_rate - LAG(mortgage_rate, 12) OVER w AS roc_12m,
    mortgage_rate / NULLIF(LAG(mortgage_rate, 12) OVER w, 0) - 1 AS roc_12m_rel
FROM national_monthly_rate
WINDOW w AS (ORDER BY month);

-- 5. Quarter-end snapshot of the rate changes.
DROP TABLE IF EXISTS quarter_end_rates CASCADE;
CREATE TABLE quarter_end_rates AS
SELECT DISTINCT ON (quarter)
    quarter, roc_1m, roc_2m, roc_3m, roc_6m, roc_9m, roc_12m, roc_12m_rel
FROM national_rate_roc
ORDER BY quarter, month DESC;

-- 6. Labels paired with the PRECEDING quarter's rate change.
DROP TABLE IF EXISTS lag_correlation_input CASCADE;
CREATE TABLE lag_correlation_input AS
SELECT
    t.county_fips,
    t.quarter,
    t.decline_label,
    q.roc_1m, q.roc_2m, q.roc_3m, q.roc_6m, q.roc_9m, q.roc_12m, q.roc_12m_rel
FROM train_quarterly_labeled t
JOIN quarter_end_rates q
    ON q.quarter + INTERVAL '3 months' = t.quarter;

-- 7. Row-level correlation of the label with each lag, computed on the server.
-- Each row is one county-quarter, so these rows are NOT independent: the rate change is
-- one national number per quarter, shared by about 3,000 counties.
DROP TABLE IF EXISTS lag_correlation_results CASCADE;
CREATE TABLE lag_correlation_results AS
SELECT
    v.definition,
    v.lag_months,
    corr(a.decline_label, v.roc) AS correlation,
    COUNT(v.roc) AS n_rows
FROM lag_correlation_input a
CROSS JOIN LATERAL (VALUES
    ('percentage points', 1,  a.roc_1m),
    ('percentage points', 2,  a.roc_2m),
    ('percentage points', 3,  a.roc_3m),
    ('percentage points', 6,  a.roc_6m),
    ('percentage points', 9,  a.roc_9m),
    ('percentage points', 12, a.roc_12m),
    ('relative change',   12, a.roc_12m_rel)
) AS v(definition, lag_months, roc)
GROUP BY v.definition, v.lag_months;

-- 8. Quarter-level correlation: one data point per quarter (its share of counties with a
-- decline against that quarter's rate change). The sample size is the number of quarters,
-- about 80, which is the honest amount of independent information about the rate.
DROP TABLE IF EXISTS lag_correlation_quarterly CASCADE;
CREATE TABLE lag_correlation_quarterly AS
WITH per_quarter AS (
    SELECT
        quarter,
        AVG(decline_label) AS decline_share,
        AVG(roc_1m)  AS roc_1m,  AVG(roc_2m)  AS roc_2m,  AVG(roc_3m) AS roc_3m,
        AVG(roc_6m)  AS roc_6m,  AVG(roc_9m)  AS roc_9m,  AVG(roc_12m) AS roc_12m
    FROM lag_correlation_input
    GROUP BY quarter
)
SELECT
    v.lag_months,
    corr(p.decline_share, v.roc) AS correlation,
    COUNT(v.roc) AS n_quarters
FROM per_quarter p
CROSS JOIN LATERAL (VALUES
    (1, p.roc_1m), (2, p.roc_2m), (3, p.roc_3m),
    (6, p.roc_6m), (9, p.roc_9m), (12, p.roc_12m)
) AS v(lag_months, roc)
GROUP BY v.lag_months;

-- Results for DBeaver (the notebook reads the same tables back).
SELECT definition, lag_months, correlation, n_rows
FROM lag_correlation_results
ORDER BY definition, lag_months;

SELECT lag_months, correlation, n_quarters
FROM lag_correlation_quarterly
ORDER BY lag_months;
