-- 004b_reverse_causation.sql
--
-- Reverse-causation check: does national price momentum LEAD future changes of the
-- mortgage rate? The lag sweep in 004 found that the rate change is, if anything,
-- negatively related to later declines, the opposite of the hypothesis. One possible
-- explanation is that the arrow runs the other way: a cooling housing market may
-- influence later rate decisions. If that were true, past price momentum should
-- correlate with the rate change that comes LATER.
--
-- Definitions
--   National momentum at month t: the 3-month change of the MEDIAN county ZHVI, using
--       Train months only.
--   Rate step at month t + k:     the 1-month change of the mortgage rate in percentage points.
--   Leads:                        k = 1 to 18 months.
--
-- Two variants
--   A  all rate months: the rate step may fall after the end of Train for the latest t.
--   B  rates through the end of Train only: no Embargo or Test period rate enters the check.
--
-- Months are matched through a whole-number month index (year x 12 + month), so there is
-- no month-end date arithmetic to get wrong.
--
-- Caution: neighbouring months are NOT independent. A 3-month change overlaps its
-- neighbours by two months, and both series are strongly autocorrelated. Intervals that
-- treat each month as independent may be too narrow, so notebook 03b checks them with a
-- block bootstrap.
--
-- Safe to re-run.

-- 1. National momentum per month (Train months only).
DROP TABLE IF EXISTS national_momentum CASCADE;
CREATE TABLE national_momentum AS
SELECT
    month,
    (EXTRACT(YEAR FROM month) * 12 + EXTRACT(MONTH FROM month))::int AS month_idx,
    national_zhvi,
    national_zhvi / NULLIF(LAG(national_zhvi, 3) OVER w, 0) - 1 AS mom_3m
FROM (
    SELECT month, percentile_cont(0.5) WITHIN GROUP (ORDER BY zhvi) AS national_zhvi
    FROM train_monthly
    GROUP BY month
) z
WINDOW w AS (ORDER BY month);

-- 2. Monthly change of the mortgage rate, in percentage points (full FRED history).
DROP TABLE IF EXISTS national_rate_step CASCADE;
CREATE TABLE national_rate_step AS
SELECT
    month,
    (EXTRACT(YEAR FROM month) * 12 + EXTRACT(MONTH FROM month))::int AS month_idx,
    mortgage_rate - LAG(mortgage_rate) OVER (ORDER BY month) AS rate_step_1m
FROM mortgage_monthly;

-- 3. Every pair (momentum at t, rate step at t + k), for both variants.
DROP TABLE IF EXISTS reverse_causation_pairs CASCADE;
CREATE TABLE reverse_causation_pairs AS
SELECT
    v.variant,
    k.lag_months,
    m.month AS momentum_month,
    f.month AS rate_month,
    m.mom_3m,
    f.rate_step_1m
FROM national_momentum m
CROSS JOIN generate_series(1, 18) AS k(lag_months)
JOIN national_rate_step f
    ON f.month_idx = m.month_idx + k.lag_months
CROSS JOIN (VALUES ('A: all rate months'), ('B: rates through the end of Train')) AS v(variant)
WHERE m.mom_3m IS NOT NULL
  AND f.rate_step_1m IS NOT NULL
  AND (v.variant LIKE 'A%' OR f.month <= (SELECT MAX(month) FROM train_monthly));

-- 4. Correlation per variant and lead, computed on the server.
DROP TABLE IF EXISTS reverse_causation_sweep CASCADE;
CREATE TABLE reverse_causation_sweep AS
SELECT variant, lag_months, corr(mom_3m, rate_step_1m) AS correlation, COUNT(*) AS n_rows
FROM reverse_causation_pairs
GROUP BY variant, lag_months;

-- Results for DBeaver (the notebook reads the same tables back).
SELECT variant, lag_months, correlation, n_rows
FROM reverse_causation_sweep
ORDER BY variant, lag_months;
