-- 005b_cv_fold_rows.sql
-- Run AFTER 005_phase4_features.sql (it needs quarterly_modeling_table).
--
-- One row per fold and county-quarter, with fold_role 'train' or 'val'. Only Train-split
-- rows are eligible, so Embargo and Test rows can never enter a fold. Rows are assigned by
-- their LABEL quarter end, compared with the quarter-end dates stored in cv_folds.
--
-- 005 drops this view whenever it rebuilds the modeling table, so re-run this file after 005.

DROP VIEW IF EXISTS cv_fold_rows;

CREATE VIEW cv_fold_rows AS
SELECT f.fold_id, 'train'::text AS fold_role, m.*
FROM cv_folds f
JOIN quarterly_modeling_table m
    ON m.split = 'train'
   AND m.label_quarter_end BETWEEN f.train_start AND f.train_end
UNION ALL
SELECT f.fold_id, 'val'::text AS fold_role, m.*
FROM cv_folds f
JOIN quarterly_modeling_table m
    ON m.split = 'train'
   AND m.label_quarter_end BETWEEN f.val_start AND f.val_end;

-- Rows and positives per fold and role.
SELECT fold_id, fold_role,
       COUNT(*) AS n_rows,
       SUM(decline_label) AS n_positives,
       ROUND(100.0 * AVG(decline_label), 2) AS positive_rate_pct
FROM cv_fold_rows
GROUP BY fold_id, fold_role
ORDER BY fold_id, fold_role;
