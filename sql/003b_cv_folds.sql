-- 003b_cv_folds.sql
--
-- Expanding-window cross-validation folds, generated in SQL.
--
--   first training quarter:    2000-Q1
--   first fold trains on:      40 quarters (2000-Q1 to 2009-Q4)
--   every fold validates on:   the next 4 quarters (one calendar year)
--   every later fold:          adds the previous validation year to its training window
--   number of folds:           11 (validation years 2010 to 2020)
--
-- All validation windows end inside Train, so a fold can never reach the Embargo or Test
-- periods. Training always ends the quarter before validation starts. There is no extra
-- gap: every training label is already known when the validation features are measured,
-- and the features only look backward.
--
-- Fold dates are QUARTER-END dates. Rows are assigned by the quarter whose decline they
-- describe (the label quarter), see 005b_cv_fold_rows.sql.
--
-- The parameters in the first CTE are the only numbers to change for a different design.

DROP TABLE IF EXISTS cv_folds CASCADE;

CREATE TABLE cv_folds AS
WITH params AS (
    SELECT DATE '2000-01-01' AS first_quarter_start,
           40 AS initial_train_quarters,
           4  AS validation_quarters,
           11 AS n_folds
)
SELECT
    g.fold_id,
    (p.first_quarter_start + INTERVAL '3 months' - INTERVAL '1 day')::date AS train_start,
    (p.first_quarter_start
        + (p.initial_train_quarters + g.fold_id * p.validation_quarters) * INTERVAL '3 months'
        - INTERVAL '1 day')::date AS train_end,
    (p.first_quarter_start
        + (p.initial_train_quarters + g.fold_id * p.validation_quarters + 1) * INTERVAL '3 months'
        - INTERVAL '1 day')::date AS val_start,
    (p.first_quarter_start
        + (p.initial_train_quarters + g.fold_id * p.validation_quarters + p.validation_quarters) * INTERVAL '3 months'
        - INTERVAL '1 day')::date AS val_end,
    p.initial_train_quarters + g.fold_id * p.validation_quarters AS n_train_quarters,
    p.validation_quarters AS n_val_quarters
FROM params p
CROSS JOIN LATERAL generate_series(0, p.n_folds - 1) AS g(fold_id);

ALTER TABLE cv_folds ADD PRIMARY KEY (fold_id);

-- Consistency checks: any failure stops the script with an error.
DO $$
DECLARE
    n_folds INTEGER;
    bad INTEGER;
    last_train DATE;
BEGIN
    SELECT COUNT(*) INTO n_folds FROM cv_folds;
    IF n_folds <> 11 THEN
        RAISE EXCEPTION 'Fold check failed: expected 11 folds, found %', n_folds;
    END IF;

    SELECT MAX(month) INTO last_train FROM monthly_split WHERE split = 'train';
    IF (SELECT MAX(val_end) FROM cv_folds) > last_train THEN
        RAISE EXCEPTION 'Fold check failed: a validation window reaches past the Train window';
    END IF;

    -- Validation starts at the end of the quarter right after training ends.
    SELECT COUNT(*) INTO bad FROM cv_folds
    WHERE (date_trunc('quarter', train_end + INTERVAL '1 day') + INTERVAL '3 months' - INTERVAL '1 day')::date <> val_start;
    IF bad > 0 THEN
        RAISE EXCEPTION 'Fold check failed: % fold(s) do not validate on the quarters right after training', bad;
    END IF;

    -- Every validation window covers exactly 4 quarters.
    SELECT COUNT(*) INTO bad FROM cv_folds
    WHERE (date_trunc('quarter', val_start) + INTERVAL '12 months' - INTERVAL '1 day')::date <> val_end;
    IF bad > 0 THEN
        RAISE EXCEPTION 'Fold check failed: % validation window(s) are not 4 quarters long', bad;
    END IF;

    -- Expanding window: same start, and each training window is exactly one validation year longer.
    SELECT COUNT(*) INTO bad FROM (
        SELECT train_start, train_end,
               LAG(train_end) OVER (ORDER BY fold_id) AS prev_end,
               FIRST_VALUE(train_start) OVER (ORDER BY fold_id) AS first_start
        FROM cv_folds
    ) t
    WHERE train_start <> first_start
       OR (prev_end IS NOT NULL AND (prev_end + INTERVAL '1 day' + INTERVAL '12 months' - INTERVAL '1 day')::date <> train_end);
    IF bad > 0 THEN
        RAISE EXCEPTION 'Fold check failed: folds are not a clean expanding window';
    END IF;

    RAISE NOTICE 'Fold checks passed: % folds, validation years % to %, last Train month %',
        n_folds, EXTRACT(YEAR FROM (SELECT MIN(val_start) FROM cv_folds)),
        EXTRACT(YEAR FROM (SELECT MAX(val_end) FROM cv_folds)), last_train;
END $$;

SELECT * FROM cv_folds ORDER BY fold_id;
