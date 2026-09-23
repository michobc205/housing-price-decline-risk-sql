-- 002_join_check.sql
--
-- Joins zhvi_monthly (county-month) with mortgage_monthly (national-month) on
-- month. Zillow is the spine (LEFT JOIN): a month missing from mortgage_monthly
-- should surface as a NULL mortgage_rate, never as a silently dropped
-- county-month row. This mirrors the join logic used in the pandas pipeline
-- (zillow_slim.merge(fred_slim, on="month", how="left")), just expressed in SQL
-- instead of pandas.
--
-- Run this directly in DBeaver against capstone_sql_variant, or via the
-- notebook's exec_driver_sql call in 01_phase1_ingest_sql.ipynb.

CREATE TABLE IF NOT EXISTS county_month_joined AS
SELECT
    z.county_fips,
    z.month,
    z.zhvi,
    z.region_name,
    z.state,
    m.mortgage_rate
FROM zhvi_monthly AS z
LEFT JOIN mortgage_monthly AS m
    ON date_trunc('month', m.month) = date_trunc('month', z.month);

-- Re-running this file re-creates the table from scratch rather than silently
-- accumulating duplicate rows on each run (the exact bug that produced the
-- 708,953-vs-709,996 mismatch in the other repo). CREATE TABLE ... AS fails if
-- the table already exists, so drop it first for idempotent re-runs:
--
--   DROP TABLE IF EXISTS county_month_joined;
--
-- (kept as a separate manual step rather than baked into this file, so a
-- careless re-run can't silently wipe a table you meant to keep)
