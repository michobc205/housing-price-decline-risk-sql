-- 003_phase2_split.sql
--
-- SQL version of Phase 2's chronological Train/Embargo/Test split, applied
-- directly to county_month_joined (built by 002_join_check.sql). Same three
-- cutoffs as the pandas pipeline's phase2_split.ipynb:
--   Train:   through 2021-09-30
--   Embargo: 2021-10-01 to 2021-12-31 (excluded from both Train and Test)
--   Test:    2022-01-01 to 2026-03-31
-- Rows outside all three (the 2026 Q2/Q3 tail) get 'unassigned' rather than
-- being silently dropped -- same reasoning as the pandas version.
--
-- Unlike the pandas notebook, which builds three separate DataFrames, this
-- assigns a single `split` column via CASE WHEN. Since the three conditions
-- are mutually exclusive by construction, a leakage check here is really just
-- confirming the CASE logic was written correctly -- there's no way for SQL to
-- accidentally put one row in two buckets the way a pandas boolean-mask bug
-- theoretically could.

DROP TABLE IF EXISTS monthly_split;

CREATE TABLE monthly_split AS
SELECT
    *,
    CASE
        WHEN month <= DATE '2021-09-30' THEN 'train'
        WHEN month >= DATE '2021-10-01' AND month <= DATE '2021-12-31' THEN 'embargo'
        WHEN month >= DATE '2022-01-01' AND month <= DATE '2026-03-31' THEN 'test'
        ELSE 'unassigned'
    END AS split
FROM county_month_joined;

-- Convenience views, one per window -- mirrors having train_df/embargo_df/test_df
-- as separate objects in the pandas version, without duplicating the data.
DROP VIEW IF EXISTS train_monthly;
DROP VIEW IF EXISTS embargo_monthly;
DROP VIEW IF EXISTS test_monthly;

CREATE VIEW train_monthly AS SELECT * FROM monthly_split WHERE split = 'train';
CREATE VIEW embargo_monthly AS SELECT * FROM monthly_split WHERE split = 'embargo';
CREATE VIEW test_monthly AS SELECT * FROM monthly_split WHERE split = 'test';

-- Row-count check per split, for the notebook to read back and compare against
-- the pandas pipeline's known figures (Train 528,174 / Embargo 9,063 /
-- Test 156,361 / Unassigned 15,355 at monthly grain).
SELECT split, COUNT(*) AS n_rows
FROM monthly_split
GROUP BY split
ORDER BY split;
