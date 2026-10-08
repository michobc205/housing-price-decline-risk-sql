-- 006_checks.sql
--
-- A test suite written in SQL. Run it after 001 to 005b (or at any time, to see whether
-- the database is still in a healthy state). HARD checks stop the script with an error:
-- they are invariants that must hold whatever Zillow or FRED publish next. SOFT checks only
-- print figures to compare with the README, because those drift slightly as data arrives.
--
--   psql "$DATABASE_URL" -f sql/006_checks.sql
-- or paste it into DBeaver's SQL editor (run it as a script).

-- 1. Source tables ------------------------------------------------------------------------
DO $$
DECLARE
    n_dup INTEGER;
    n_bad_z INTEGER;
    n_bad_m INTEGER;
BEGIN
    SELECT COUNT(*) INTO n_dup FROM (
        SELECT county_fips, month FROM zhvi_monthly GROUP BY county_fips, month HAVING COUNT(*) > 1
    ) d;
    IF n_dup > 0 THEN
        RAISE EXCEPTION 'CHECK FAILED: % duplicate (county_fips, month) pairs in zhvi_monthly', n_dup;
    END IF;

    -- Every stored date must be a month-END date: the day after it is the 1st of a month.
    SELECT COUNT(*) INTO n_bad_z FROM zhvi_monthly WHERE EXTRACT(DAY FROM (month + INTERVAL '1 day')) <> 1;
    SELECT COUNT(*) INTO n_bad_m FROM mortgage_monthly WHERE EXTRACT(DAY FROM (month + INTERVAL '1 day')) <> 1;
    IF n_bad_z > 0 OR n_bad_m > 0 THEN
        RAISE EXCEPTION 'CHECK FAILED: month-end convention broken (% zhvi rows, % mortgage rows)', n_bad_z, n_bad_m;
    END IF;
    RAISE NOTICE 'PASS: no duplicate months, and every month is a month-end date';
END $$;

-- 2. Join integrity -----------------------------------------------------------------------
DO $$
DECLARE
    n_z INTEGER; n_j INTEGER; n_lost_counties INTEGER; n_null_rate INTEGER;
BEGIN
    SELECT COUNT(*) INTO n_z FROM zhvi_monthly;
    SELECT COUNT(*) INTO n_j FROM county_month_joined;
    SELECT COUNT(*) INTO n_lost_counties FROM (
        SELECT county_fips FROM zhvi_monthly EXCEPT SELECT county_fips FROM county_month_joined
    ) d;
    SELECT COUNT(*) INTO n_null_rate FROM county_month_joined WHERE mortgage_rate IS NULL;
    IF n_z <> n_j THEN
        RAISE EXCEPTION 'CHECK FAILED: the join changed the row count (% before, % after)', n_z, n_j;
    END IF;
    IF n_lost_counties > 0 THEN
        RAISE EXCEPTION 'CHECK FAILED: % counties lost in the join', n_lost_counties;
    END IF;
    IF n_null_rate > 0 THEN
        RAISE EXCEPTION 'CHECK FAILED: % joined rows have no mortgage rate', n_null_rate;
    END IF;
    RAISE NOTICE 'PASS: join kept all % rows and all counties, with no missing rate', n_j;
END $$;

-- 3. Split and folds ----------------------------------------------------------------------
DO $$
DECLARE
    n_null_split INTEGER; n_fold_leak INTEGER; min_val_pos INTEGER;
BEGIN
    SELECT COUNT(*) INTO n_null_split FROM monthly_split WHERE split IS NULL;
    IF n_null_split > 0 THEN
        RAISE EXCEPTION 'CHECK FAILED: % rows without a split label', n_null_split;
    END IF;

    SELECT COUNT(*) INTO n_fold_leak FROM cv_fold_rows WHERE split <> 'train';
    IF n_fold_leak > 0 THEN
        RAISE EXCEPTION 'CHECK FAILED: % fold rows come from Embargo or Test', n_fold_leak;
    END IF;

    -- Every validation fold needs enough positives for its AUC to be trusted.
    SELECT MIN(pos) INTO min_val_pos FROM (
        SELECT fold_id, SUM(decline_label) AS pos FROM cv_fold_rows WHERE fold_role = 'val' GROUP BY fold_id
    ) s;
    IF min_val_pos < 20 THEN
        RAISE EXCEPTION 'CHECK FAILED: a validation fold has only % positives (minimum 20)', min_val_pos;
    END IF;
    RAISE NOTICE 'PASS: every row has a split, no fold row leaves Train, lowest validation fold has % positives', min_val_pos;
END $$;

-- 4. Labels -------------------------------------------------------------------------------
DO $$
DECLARE
    n_gap INTEGER; n_null INTEGER; n_bad_label INTEGER;
BEGIN
    SELECT COUNT(*) INTO n_gap FROM train_quarterly_labeled
    WHERE prev_quarter <> (quarter - INTERVAL '3 months')::date;
    SELECT COUNT(*) INTO n_null FROM train_quarterly_labeled WHERE pct_change IS NULL;
    SELECT COUNT(*) INTO n_bad_label FROM train_quarterly_labeled WHERE decline_label NOT IN (0, 1);
    IF n_gap > 0 OR n_null > 0 OR n_bad_label > 0 THEN
        RAISE EXCEPTION 'CHECK FAILED: labels (% spanning more than a quarter, % empty changes, % invalid labels)',
            n_gap, n_null, n_bad_label;
    END IF;
    RAISE NOTICE 'PASS: every label is a true quarter-to-quarter change';
END $$;

-- 5. Modeling table -----------------------------------------------------------------------
DO $$
DECLARE
    n_null INTEGER; n_dup INTEGER; n_align INTEGER; n_inter INTEGER; n_month INTEGER;
BEGIN
    SELECT COUNT(*) INTO n_null FROM quarterly_modeling_table
    WHERE momentum_1m IS NULL OR momentum_3m IS NULL OR momentum_6m IS NULL
       OR rate_level IS NULL OR rate_roc_12m IS NULL OR rate_momentum_interaction IS NULL;
    SELECT COUNT(*) INTO n_dup FROM (
        SELECT county_fips, quarter FROM quarterly_modeling_table GROUP BY county_fips, quarter HAVING COUNT(*) > 1
    ) d;
    -- Features are measured on the last day before the label quarter starts.
    SELECT COUNT(*) INTO n_align FROM quarterly_modeling_table
    WHERE feature_quarter_end <> (quarter - INTERVAL '1 day')::date;
    SELECT COUNT(*) INTO n_month FROM quarterly_modeling_table
    WHERE EXTRACT(MONTH FROM feature_quarter_end) NOT IN (3, 6, 9, 12);
    SELECT COUNT(*) INTO n_inter FROM quarterly_modeling_table
    WHERE ABS(rate_momentum_interaction - rate_roc_12m * momentum_3m) > 1e-9;
    IF n_null > 0 OR n_dup > 0 OR n_align > 0 OR n_month > 0 OR n_inter > 0 THEN
        RAISE EXCEPTION 'CHECK FAILED: modeling table (% missing, % duplicates, % misaligned, % not at a quarter end, % wrong interaction)',
            n_null, n_dup, n_align, n_month, n_inter;
    END IF;
    RAISE NOTICE 'PASS: no missing features, one row per county and quarter, features from the preceding quarter end';
END $$;

-- 6. Soft checks: figures to compare with the README ----------------------------------------
-- 6a. Decline labels per window, computed in SQL. They must equal the figures printed by
-- Section 8 of notebook 01, which computes the same thing in pandas. With the Zillow file
-- downloaded on 2026-09-23: Full history 231,453 rows / 5.55 percent, Train 173,277 / 4.88,
-- Embargo 3,020 / 0.96, Test 52,085 / 8.15. Full history also holds the 3,071 rows of
-- 2026-Q2, which belong to no split.
SELECT 'Full history' AS window, COUNT(*) AS n_rows,
       ROUND(100.0 * AVG(decline_label), 2) AS positive_rate_pct
FROM quarterly_labeled_full
UNION ALL
SELECT 'Train', COUNT(*), ROUND(100.0 * AVG(decline_label), 2)
FROM quarterly_labeled_full WHERE split = 'train'
UNION ALL
SELECT 'Embargo', COUNT(*), ROUND(100.0 * AVG(decline_label), 2)
FROM quarterly_labeled_full WHERE split = 'embargo'
UNION ALL
SELECT 'Test', COUNT(*), ROUND(100.0 * AVG(decline_label), 2)
FROM quarterly_labeled_full WHERE split = 'test';

-- 6b. The modeling table, which drops each county's earliest quarters (no 6-month momentum
-- or 12-month rate history yet) and any row with a missing feature.
-- Expected with the Zillow file downloaded on 2026-09-23 (they drift slightly as new months arrive):
--   Train 164,460 rows / 4.85 percent, Embargo 3,020 / 0.96, Test 51,980 / 8.11, Unassigned 3,070 / 4.27
SELECT split, COUNT(*) AS n_rows, COUNT(DISTINCT county_fips) AS n_counties,
       ROUND(100.0 * AVG(decline_label), 2) AS positive_rate_pct
FROM quarterly_modeling_table
GROUP BY split
ORDER BY split;
