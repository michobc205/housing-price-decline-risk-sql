-- 002_join_check.sql
--
-- Joins zhvi_monthly (county by month) with mortgage_monthly (national, by month).
-- Zillow is the spine (LEFT JOIN), so a month missing from mortgage_monthly shows up
-- as an empty mortgage_rate and never as a silently dropped county-month row.
--
-- Plain equality join. Both tables store month-END dates: Zillow publishes month-end
-- column headers, and the FRED resample is aligned to month-end as well, so no date
-- truncation is needed. An earlier version stored Zillow months at month-start and had
-- to truncate both sides to make them match. Raw SQL date joins fail silently when the
-- two conventions differ: zero matches and no error message.
--
-- Safe to re-run. The table is dropped and rebuilt, because CREATE TABLE AS has no
-- OR REPLACE form and would otherwise fail on a second run or keep stale rows.

DROP TABLE IF EXISTS county_month_joined;

CREATE TABLE county_month_joined AS
SELECT
    z.county_fips,
    z.month,
    z.zhvi,
    z.region_name,
    z.state,
    m.mortgage_rate
FROM zhvi_monthly AS z
LEFT JOIN mortgage_monthly AS m
    ON m.month = z.month;
