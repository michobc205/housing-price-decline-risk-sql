-- 003_phase2_split.sql
--
-- Chronological split of county_month_joined into Train, Embargo and Test:
--   Train:   through 2021-09-30
--   Embargo: 2021-10-01 to 2021-12-31 (excluded from both Train and Test)
--   Test:    2022-01-01 to 2026-03-31
-- Months after 2026-03-31 are labelled 'unassigned' instead of being dropped silently.
--
-- Why an embargo: momentum features look back several months, so rows right after the
-- Train cutoff share information with the last Train rows. One quarter is left out of
-- both sides to keep Train and Test apart.
--
-- A single CASE expression assigns the split, so every row lands in exactly one bucket
-- by construction. The count at the bottom confirms that there are no gaps.
--
-- Safe to re-run: dropping the table with CASCADE also drops the three views below.

DROP TABLE IF EXISTS monthly_split CASCADE;

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

CREATE VIEW train_monthly   AS SELECT * FROM monthly_split WHERE split = 'train';
CREATE VIEW embargo_monthly AS SELECT * FROM monthly_split WHERE split = 'embargo';
CREATE VIEW test_monthly    AS SELECT * FROM monthly_split WHERE split = 'test';

-- Monthly row counts per split. With the Zillow file of October 2026 the expected
-- figures are Train 529,214 / Embargo 9,063 / Test 156,364 / Unassigned 15,355
-- (709,996 in total, including the empty internal-gap months).
SELECT split, COUNT(*) AS n_rows
FROM monthly_split
GROUP BY split
ORDER BY split;
