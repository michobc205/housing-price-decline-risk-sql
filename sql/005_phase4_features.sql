-- 005_phase4_features.sql
--
-- Builds quarterly_modeling_table: one row per county and label quarter, with the decline
-- label and six features measured one quarter earlier.
--
-- Fixed feature set
--   momentum_1m, momentum_3m, momentum_6m   ZHVI change over 1, 3 and 6 months
--   rate_level                              30-year mortgage rate at the quarter end
--   rate_roc_12m                            12-month change of that rate, in percentage points
--   rate_momentum_interaction               rate_roc_12m x momentum_3m (3 months is one quarter,
--                                           the horizon being predicted)
--
-- Rules
--   * Quarter-end month only: the label and the features of a quarter are read at its
--     quarter-end month (Mar, Jun, Sep, Dec). A quarter whose end month is empty gets no
--     row, and a label is kept only when the previous row is the calendar quarter before
--     it. So both quarter-end months must have a value.
--   * No look-ahead: every feature attached to a label is measured at the end of the
--     quarter BEFORE the one being predicted. Rows are dated by their label quarter.
--   * Any missing feature drops the row, so no model input is ever empty.
--   * This file runs on ALL splits (Train, Embargo, Test): Test rows need real feature
--     values too. What must never happen is a Test row informing a modeling DECISION.
--
-- Rebuilding this table drops the view cv_fold_rows (it depends on it), so re-run
-- 005b_cv_fold_rows.sql afterwards.

-- 1. Monthly ZHVI momentum per county. Empty internal-gap months stay as rows, so counting
-- rows back is the same as counting calendar months back.
DROP TABLE IF EXISTS county_monthly_momentum;
CREATE TABLE county_monthly_momentum AS
SELECT
    county_fips,
    month,
    date_trunc('quarter', month)::date AS quarter,
    zhvi,
    zhvi / NULLIF(LAG(zhvi, 1) OVER w, 0) - 1 AS momentum_1m,
    zhvi / NULLIF(LAG(zhvi, 3) OVER w, 0) - 1 AS momentum_3m,
    zhvi / NULLIF(LAG(zhvi, 6) OVER w, 0) - 1 AS momentum_6m
FROM monthly_split
WINDOW w AS (PARTITION BY county_fips ORDER BY month);

-- 2. Momentum at each county's quarter-end month.
DROP TABLE IF EXISTS county_quarterly_momentum;
CREATE TABLE county_quarterly_momentum AS
SELECT county_fips, quarter, momentum_1m, momentum_3m, momentum_6m
FROM county_monthly_momentum
WHERE zhvi IS NOT NULL
  AND month = (quarter + INTERVAL '3 months' - INTERVAL '1 day')::date;

-- 3. National mortgage rate: level and 12-month change in percentage points.
DROP TABLE IF EXISTS national_monthly_rate_full;
CREATE TABLE national_monthly_rate_full AS
SELECT DISTINCT month, mortgage_rate, date_trunc('quarter', month)::date AS quarter
FROM monthly_split
ORDER BY month;

DROP TABLE IF EXISTS national_rate_roc_full;
CREATE TABLE national_rate_roc_full AS
SELECT
    month, quarter, mortgage_rate,
    mortgage_rate - LAG(mortgage_rate, 12) OVER (ORDER BY month) AS rate_roc_12m
FROM national_monthly_rate_full;

-- 4. Rate features at the quarter-end month.
DROP TABLE IF EXISTS quarter_end_rate_features;
CREATE TABLE quarter_end_rate_features AS
SELECT quarter, mortgage_rate AS rate_level, rate_roc_12m
FROM national_rate_roc_full
WHERE month = (quarter + INTERVAL '3 months' - INTERVAL '1 day')::date;

-- 5. Quarterly decline label across all splits (same rule as 004, which is Train only).
DROP TABLE IF EXISTS quarterly_labeled_full;
CREATE TABLE quarterly_labeled_full AS
SELECT
    county_fips,
    quarter,
    split,
    zhvi,
    LAG(zhvi)    OVER w AS prev_zhvi,
    LAG(quarter) OVER w AS prev_quarter,
    CASE WHEN zhvi / NULLIF(LAG(zhvi) OVER w, 0) - 1 < -0.02 THEN 1 ELSE 0 END AS decline_label
FROM (
    SELECT county_fips,
           date_trunc('quarter', month)::date AS quarter,
           zhvi,
           split
    FROM monthly_split
    WHERE zhvi IS NOT NULL
      AND month = (date_trunc('quarter', month) + INTERVAL '3 months' - INTERVAL '1 day')::date
) q
WINDOW w AS (PARTITION BY county_fips ORDER BY quarter);

DELETE FROM quarterly_labeled_full
WHERE prev_zhvi IS NULL
   OR prev_quarter <> (quarter - INTERVAL '3 months')::date;

-- 6. Modeling table: each label joined to the PRECEDING quarter's features.
DROP TABLE IF EXISTS quarterly_modeling_table CASCADE;
CREATE TABLE quarterly_modeling_table AS
SELECT
    l.county_fips,
    l.quarter,
    (l.quarter + INTERVAL '3 months' - INTERVAL '1 day')::date AS label_quarter_end,
    (l.quarter - INTERVAL '1 day')::date AS feature_quarter_end,
    l.split,
    l.decline_label,
    m.momentum_1m,
    m.momentum_3m,
    m.momentum_6m,
    r.rate_level,
    r.rate_roc_12m,
    r.rate_roc_12m * m.momentum_3m AS rate_momentum_interaction
FROM quarterly_labeled_full l
JOIN county_quarterly_momentum m
    ON m.county_fips = l.county_fips
   AND m.quarter + INTERVAL '3 months' = l.quarter
JOIN quarter_end_rate_features r
    ON r.quarter + INTERVAL '3 months' = l.quarter;

-- 7. Drop rows with any missing feature: the earliest quarters of each county and of the
-- rate series, and any quarter touched by an empty ZHVI month inside the look-back window.
DELETE FROM quarterly_modeling_table
WHERE momentum_1m IS NULL OR momentum_3m IS NULL OR momentum_6m IS NULL
   OR rate_level IS NULL OR rate_roc_12m IS NULL OR rate_momentum_interaction IS NULL;

-- Rows, counties and decline rate per split.
SELECT split, COUNT(1) AS n_rows, COUNT(DISTINCT county_fips) AS n_counties,
       ROUND(100.0 * AVG(decline_label), 2) AS positive_rate_pct
FROM quarterly_modeling_table
GROUP BY split
ORDER BY split;
