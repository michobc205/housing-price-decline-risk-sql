# Housing Price Decline Risk: a SQL-first pipeline in PostgreSQL

Which US counties will see their home values fall by more than 2% in the next quarter, and
how much do mortgage rates add once a county's own price momentum is already known?

This project answers that question with a pipeline that runs **in SQL**. Loading, joining,
splitting in time, building the validation folds, labelling, feature engineering and the
data checks all run inside PostgreSQL. Python is used only to download the data, to fit the
models and to draw the plots.

It is one half of a two-person capstone. The [team repository](https://github.com/michobc205/capstone-housing-risk-team)
holds the merged pipeline, where this SQL build was compared row by row with an independent
pandas build of the same pipeline.

## Status

| Phase | What | Status |
|---|---|---|
| 1 | Ingest, month-end join, coverage audit | Done and verified |
| 2 | Split in time and 11 validation folds, generated in SQL | Done and verified |
| 3 | Exploratory analysis: lag sweep, quarter-level re-test, rate definition | Done and verified |
| 3b | Reverse-causation check with a block bootstrap | Done and verified |
| 4 | Modeling table with six features | Done and verified |
| 5 | Modeling on the validation folds: 3 families, 3 feature steps, quarter bootstrap | Done and verified |
| 6 | Evaluation on the test period | In progress |
| 7 | Dashboard | In progress |

Phase 5 was run on the corrected pipeline below and never reads the test period. The results
of phases 6 and 7 are added here only after they have been re-run the same way.

## The data

| Source | Grain | Used for |
|---|---|---|
| [Zillow ZHVI](https://www.zillow.com/research/data/): county, middle tier (33rd to 67th percentile), single-family and condo, smoothed and seasonally adjusted | County, monthly | The decline label and the price-momentum features |
| [FRED MORTGAGE30US](https://fred.stlouisfed.org/series/MORTGAGE30US): 30-year fixed mortgage rate | National, weekly | Rate level, rate change and their interaction with momentum |

The data files are **not** included in this repository. The notebook downloads them, and both
sources have their own terms of use. The weekly rate is averaged to one value per month
(`.mean()`), dated at month-end like Zillow's columns.

## Verified results so far

| What | Result |
|---|---|
| Zillow after cleaning | 709,996 county-months, 3,071 counties, of which 1,043 are internal gaps kept as empty rows |
| Join (in SQL) | All 709,996 rows and all counties kept, no missing mortgage rate |
| Decline labels, Train (through 2021-09-30) | 173,277 rows, 4.88% declines |
| Embargo (2021-Q4) | 3,020 rows, 0.96% |
| Test (2022-Q1 to 2026-Q1) | 52,085 rows, 8.15% |
| Modeling table, Train | 164,460 rows, 3,009 counties, 4.85% declines |
| Validation folds | 11 expanding-window folds, validation years 2010 to 2020. Pooled: 112,734 rows, 4,252 declines (3.77%). Lowest fold: 71 declines (2020). Fold decline rates run from 0.59% to 13.62% |
| Features recomputed independently | 2,000 random rows of the modeling table recomputed in pandas from the raw monthly tables: largest difference 0 for all six features, 0 label mismatches |
| Rate change vs decline, 12-month lag, quarter level | r = -0.145 on 82 quarters, 95% interval -0.351 to +0.074 (it includes zero) |
| Does price momentum lead rate changes? | At most weak evidence. With rate data only through Train, the correlation is about 0.12 at leads of 4 and 14 months (12-month block-bootstrap 95% intervals 0.005 to 0.222 and 0.009 to 0.236). It is 0.26 at 14 months when rate data after Train are included, and the difference comes from the latest 14 months. |

The label counts are computed twice, in pandas (notebook 01, Section 8) and in SQL
(`sql/006_checks.sql`, check 6a), and the two agree exactly. An independent pandas
implementation of the same pipeline in the team repository produces the same 164,460
Train rows, with identical features and labels.

## Phase 5: modeling on the validation folds

Notebook 05 compares three model families on three feature steps, using only the 11
validation folds that `sql/003b` and `sql/005b` build in SQL. The test period is never read.
Everything below was fixed before the first result.

| Item | Choice |
|---|---|
| Families | Logistic regression (inputs standardized inside each fold), random forest (200 trees, min leaf 5, max depth 12), histogram gradient boosting (150 iterations). Fixed settings, no tuning |
| Feature steps | **Baseline:** 1, 3 and 6-month momentum. **+ rate level:** adds the mortgage rate. **+ rate change and interaction:** adds the 12-month rate change (percentage points) and its product with 3-month momentum |
| Fits | 3 families x 3 steps x 11 folds = 99 fits, about 7 minutes in total (the random forest takes most of it) |
| Metrics | ROC-AUC (main) and PR-AUC, per fold, next to each fold's own base rate |
| Baseline lock | The baseline scores are written to `outputs/phase5_baseline_lock.json` before the rate features are fitted. A re-run must reproduce them or the notebook stops |
| Uncertainty | A bootstrap that resamples the 44 validation quarters (2,000 draws), because counties in one quarter share the same rate and market conditions |
| A step "helps" | Its 95% interval excludes zero **and** the gain is at least +0.01 ROC-AUC |
| A step is "robust" | It helps in at least 2 of the 3 families |
| Recommended model | Highest average ROC-AUC across the 11 folds, with PR-AUC shown next to it |

### Result in one sentence

Once a county's own price momentum is known, the mortgage rate adds nothing measurable on the
validation folds. No step passes the rule in any family. For logistic regression the gains are
+0.0005 to +0.0008 and the upper ends of the intervals (at most +0.0024) rule out a gain of
+0.01. For both tree families, adding the rate lowers ROC-AUC.

### Scores averaged over the 11 folds

| Family | Feature step | Mean ROC-AUC | Std across folds | Mean PR-AUC | Std across folds |
|---|---|---|---|---|---|
| Logistic regression | Baseline (momentum only) | 0.8364 | 0.0630 | 0.3290 | 0.1399 |
| Logistic regression | + rate level | 0.8368 | 0.0621 | 0.3288 | 0.1385 |
| Logistic regression | + rate change and interaction | 0.8372 | 0.0618 | 0.3288 | 0.1387 |
| Random forest | Baseline (momentum only) | 0.8680 | 0.0351 | 0.3120 | 0.1305 |
| Random forest | + rate level | 0.8564 | 0.0387 | 0.3066 | 0.1115 |
| Random forest | + rate change and interaction | 0.8462 | 0.0496 | 0.3142 | 0.1243 |
| Histogram gradient boosting | Baseline (momentum only) | 0.8666 | 0.0359 | 0.3139 | 0.1342 |
| Histogram gradient boosting | + rate level | 0.8525 | 0.0407 | 0.2972 | 0.1206 |
| Histogram gradient boosting | + rate change and interaction | 0.8511 | 0.0438 | 0.2987 | 0.1214 |

The average base rate of the 11 folds is 4.21%. It differs from the pooled 3.77% because each
fold counts once in the average and by its size in the pooled figure.

### Does the rate help? Bootstrap over whole quarters

Each difference is the change in average ROC-AUC across the folds. The interval comes from
2,000 resamples of the 44 validation quarters.

| Family | Comparison | Change in ROC-AUC | 95% interval | Verdict |
|---|---|---|---|---|
| Logistic regression | + rate level minus baseline | +0.0005 | -0.0008 to +0.0017 | no significant effect |
| Logistic regression | + rate change and interaction minus + rate level | +0.0004 | -0.0008 to +0.0020 | no significant effect |
| Logistic regression | + rate change and interaction minus baseline | +0.0008 | -0.0006 to +0.0024 | no significant effect |
| Random forest | + rate level minus baseline | -0.0116 | -0.0173 to -0.0002 | hurts |
| Random forest | + rate change and interaction minus + rate level | -0.0101 | -0.0193 to +0.0016 | no significant effect |
| Random forest | + rate change and interaction minus baseline | -0.0217 | -0.0295 to -0.0071 | hurts |
| Histogram gradient boosting | + rate level minus baseline | -0.0141 | -0.0206 to -0.0042 | hurts |
| Histogram gradient boosting | + rate change and interaction minus + rate level | -0.0013 | -0.0079 to +0.0074 | no significant effect |
| Histogram gradient boosting | + rate change and interaction minus baseline | -0.0155 | -0.0199 to -0.0045 | hurts |

| Comparison | Families that help | Families that hurt | Overall |
|---|---|---|---|
| + rate level minus baseline | 0 | 2 | No gain, hurts in 2 families |
| + rate change and interaction minus + rate level | 0 | 0 | No family shows a gain that clears the rule |
| + rate change and interaction minus baseline | 0 | 2 | No gain, hurts in 2 families |

- **Logistic regression:** the three changes are +0.0005, +0.0004 and +0.0008, all with
  intervals that include zero. Because the upper ends are +0.0017, +0.0020 and +0.0024, a gain
  as large as +0.01 is ruled out on these folds.
- **Random forest:** adding the rate level lowers ROC-AUC by 0.0116 (interval -0.0173 to
  -0.0002, so only just below zero). Adding the rate change as well brings the total to
  -0.0217. The step from + rate level to + rate change alone is -0.0101 with an interval that
  includes zero (-0.0193 to +0.0016).
- **Histogram gradient boosting:** adding the rate level lowers ROC-AUC by 0.0141 (-0.0206 to
  -0.0042) and the second step changes nothing significant (-0.0013).
- **Folds where a step lowers the score** (of 11, from the three-decimal table below): adding
  the rate level lowers it in 9 folds for both random forest and gradient boosting, but only
  in 3 for logistic regression.

### ROC-AUC per fold

LR is logistic regression, RF random forest, GB histogram gradient boosting. "Base rate" is the
share of declines in that fold's validation year.

| Fold (year) | Base rate | LR base | LR + level | LR + change | RF base | RF + level | RF + change | GB base | GB + level | GB + change |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 (2010) | 11.18% | 0.801 | 0.796 | 0.793 | 0.812 | 0.811 | 0.804 | 0.811 | 0.801 | 0.785 |
| 1 (2011) | 13.62% | 0.868 | 0.868 | 0.869 | 0.870 | 0.846 | 0.858 | 0.870 | 0.843 | 0.845 |
| 2 (2012) | 3.32% | 0.817 | 0.814 | 0.812 | 0.816 | 0.828 | 0.818 | 0.818 | 0.836 | 0.823 |
| 3 (2013) | 3.11% | 0.861 | 0.859 | 0.860 | 0.864 | 0.828 | 0.791 | 0.868 | 0.834 | 0.840 |
| 4 (2014) | 3.29% | 0.882 | 0.882 | 0.889 | 0.899 | 0.895 | 0.885 | 0.906 | 0.893 | 0.896 |
| 5 (2015) | 1.62% | 0.854 | 0.854 | 0.856 | 0.896 | 0.895 | 0.882 | 0.897 | 0.890 | 0.885 |
| 6 (2016) | 3.22% | 0.874 | 0.874 | 0.876 | 0.892 | 0.879 | 0.877 | 0.889 | 0.866 | 0.878 |
| 7 (2017) | 2.62% | 0.889 | 0.891 | 0.892 | 0.894 | 0.896 | 0.846 | 0.896 | 0.893 | 0.886 |
| 8 (2018) | 2.06% | 0.889 | 0.890 | 0.885 | 0.912 | 0.909 | 0.915 | 0.907 | 0.909 | 0.916 |
| 9 (2019) | 1.70% | 0.785 | 0.795 | 0.788 | 0.830 | 0.824 | 0.750 | 0.834 | 0.825 | 0.796 |
| 10 (2020) | 0.59% | 0.680 | 0.683 | 0.690 | 0.864 | 0.809 | 0.880 | 0.837 | 0.787 | 0.813 |

- **Fold 10 (2020)** has only 71 declines. Logistic regression scores 0.680 there, against
  0.864 (random forest) and 0.837 (gradient boosting). Without fold 10, the baseline averages
  are about 0.852, 0.8685 and 0.8696, so the gap between logistic regression and the trees
  shrinks but stays, and gradient boosting edges ahead of the random forest.
- **Fold 9 (2019)** is one of the weaker folds for all three families at baseline (0.785,
  0.830, 0.834).
- In fold 10 the random forest goes 0.864, 0.809, 0.880 across the three steps: down 0.055, then
  up 0.071, on 71 declines. That shows how noisy a single small fold is.

<details>
<summary>PR-AUC per fold (compare each value with the base rate in column 2)</summary>

| Fold (year) | Base rate | LR base | LR + level | LR + change | RF base | RF + level | RF + change | GB base | GB + level | GB + change |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 (2010) | 11.18% | 0.437 | 0.426 | 0.416 | 0.414 | 0.377 | 0.371 | 0.420 | 0.373 | 0.359 |
| 1 (2011) | 13.62% | 0.592 | 0.593 | 0.594 | 0.579 | 0.494 | 0.542 | 0.583 | 0.504 | 0.515 |
| 2 (2012) | 3.32% | 0.277 | 0.273 | 0.269 | 0.277 | 0.267 | 0.270 | 0.299 | 0.287 | 0.290 |
| 3 (2013) | 3.11% | 0.302 | 0.300 | 0.303 | 0.285 | 0.247 | 0.278 | 0.281 | 0.247 | 0.227 |
| 4 (2014) | 3.29% | 0.360 | 0.359 | 0.379 | 0.330 | 0.317 | 0.377 | 0.346 | 0.323 | 0.328 |
| 5 (2015) | 1.62% | 0.201 | 0.202 | 0.202 | 0.186 | 0.223 | 0.223 | 0.187 | 0.199 | 0.198 |
| 6 (2016) | 3.22% | 0.445 | 0.445 | 0.449 | 0.386 | 0.421 | 0.436 | 0.399 | 0.399 | 0.416 |
| 7 (2017) | 2.62% | 0.368 | 0.370 | 0.370 | 0.334 | 0.360 | 0.339 | 0.341 | 0.350 | 0.351 |
| 8 (2018) | 2.06% | 0.365 | 0.370 | 0.356 | 0.365 | 0.373 | 0.356 | 0.339 | 0.359 | 0.350 |
| 9 (2019) | 1.70% | 0.177 | 0.180 | 0.176 | 0.160 | 0.160 | 0.139 | 0.158 | 0.125 | 0.154 |
| 10 (2020) | 0.59% | 0.095 | 0.099 | 0.102 | 0.115 | 0.132 | 0.125 | 0.100 | 0.104 | 0.097 |

PR-AUC depends on the base rate, so it is read against it: for the baseline random forest, fold
10 reaches 0.115 against a base rate of 0.59% (about 19 times), and fold 1 reaches 0.579 against
13.62% (about 4 times).
</details>

### The recommended model

By the rule above, the recommended model is **random forest on the baseline (momentum only)**:
mean ROC-AUC 0.8680, mean PR-AUC 0.3120. The best family within each step:

| Step | Best family | Mean ROC-AUC | Mean PR-AUC |
|---|---|---|---|
| Baseline | Random forest | 0.8680 | 0.3120 |
| + rate level | Random forest | 0.8564 | 0.3066 |
| + rate change and interaction | Histogram gradient boosting | 0.8511 | 0.2987 |

The choice between families is not strong:

- Histogram gradient boosting on the baseline is 0.0014 behind (0.8666), and ahead of the
  random forest once fold 10 is left out.
- **PR-AUC ranks the families the other way round.** Logistic regression has the highest mean
  PR-AUC at every step (0.3290 at baseline, against 0.3139 and 0.3120), although its ROC-AUC
  is lowest. The trees order counties better over the whole list, while logistic regression does
  slightly better on PR-AUC, which puts more weight on the highest-ranked counties. This matters
  for the top-X% thresholds of phase 6.
- **For the random forest the two metrics disagree about the rate.** Its ROC-AUC falls with each
  step (0.8680, 0.8564, 0.8462) while its PR-AUC is about unchanged (0.3120, 0.3066, 0.3142).
  A possible reading is that the rate features disturb the ordering of the lower-risk counties
  more than the top of the list. This is a reading and not a tested explanation.

### Why do the tree models get worse? Two diagnostics

**Rates outside the training range.** Tree models cannot predict beyond the values they saw in
training. The share of validation rows whose rate lies outside the range of that fold's training
rows:

| Fold (year) | Rate level outside training range | 12-month rate change outside training range |
|---|---|---|
| 0 (2010) | 100.0% | 0.0% |
| 1 (2011) | 25.3% | 0.0% |
| 2 (2012) | 100.0% | 0.0% |
| 3 (2013) | 24.7% | 0.0% |
| 4 (2014) | 0.0% | 24.8% |
| 5 (2015) | 0.0% | 0.0% |
| 6 (2016) | 0.0% | 0.0% |
| 7 (2017) | 0.0% | 0.0% |
| 8 (2018) | 0.0% | 0.0% |
| 9 (2019) | 0.0% | 0.0% |
| 10 (2020) | 50.0% | 0.0% |

This may contribute, but it does not explain everything:

- The three largest random-forest drops when the rate level is added are in fold 10 (-0.055),
  fold 3 (-0.036) and fold 1 (-0.024), which have 50%, 24.7% and 25.3% of rows out of range.
- Folds 0 and 2 are 100% out of range, yet the random forest barely changes there (-0.001 and
  +0.012).
- Adding the rate change drops the random forest sharply in folds 9 (-0.074) and 7 (-0.050),
  where nothing is out of range. The one fold with the rate change out of range (fold 4) shows
  no damage (-0.010 for the random forest, +0.003 and +0.007 for the other two families).

**Logistic regression coefficients.** Fitted on all 164,460 Train rows (never Embargo or Test)
with the full six features and standardized inputs, so the sizes can be compared:

| Feature | Standardized coefficient |
|---|---|
| `momentum_1m` | -3.0145 |
| `momentum_3m` | +1.9007 |
| `momentum_6m` | -1.0919 |
| `rate_level` | +0.2981 |
| `rate_roc_12m` | -0.0744 |
| `rate_momentum_interaction` | +0.2275 |

The three momentum measures overlap (the 6-month change contains the 3-month change, which
contains the 1-month change), so their coefficients are read together and not one by one. The
rate coefficients are small. A coefficient that is not zero inside Train does not mean the
feature helps on new data: the validation folds above show a gain of at most +0.0008.

### Compared with the earlier version of this phase

| | Earlier version | This version |
|---|---|---|
| Data used to compare models and choose the recommended one | The test period | The 11 validation folds |
| Test period read | Yes | No |
| Independent units for the bootstrap | 17 test quarters | 44 validation quarters |
| Rate level | Null or negative in all three families | No gain in any family, and it lowers both tree families |
| Rate change and interaction | Helped in one family only (gradient boosting), so not robust | No gain in any family |
| Recommended model | Random forest on the baseline | Random forest on the baseline |

The recommended model is the same, but it is now reached without looking at the test period.
The older numbers came from an older table and from the test period, so they are retired and
not compared with these. The gradient boosting gain seen on the test period does not appear on
the validation folds. The test period will be scored once, in phase 6, with frozen models, and
this phase says nothing yet about how the models do there.

### How the phase was checked

- The folds are checked before any model is fitted: 11 folds, 44 separate validation quarters,
  no missing feature, no fold row outside Train, every training window ends before its
  validation window, lowest fold 71 declines.
- The bootstrap uses a tie-aware AUC written in NumPy. With equal weights it matches
  scikit-learn to 2.2e-16 on every model and fold, and it also matched scikit-learn with random
  integer weights and many tied scores on test data.
- The notebook was first run end to end on synthetic fold data. A changed baseline stops it, as
  designed.
- Results are saved to four Postgres tables (`phase5_fold_scores` 99 rows, `phase5_step_summary`
  9, `phase5_bootstrap_deltas` 9, `phase5_validation_predictions` 112,734). Phase 6 reads them.

## How the pipeline works

```
notebook 01  download, clean, load     -> zhvi_monthly, mortgage_monthly
sql/002      join in SQL               -> county_month_joined
sql/003      split in time             -> monthly_split (+ train, embargo, test views)
sql/003b     validation folds          -> cv_folds
sql/004      label + lag analysis      -> train_quarterly_labeled, lag_correlation_*
sql/004b     reverse causation         -> national_momentum, reverse_causation_*
sql/005      features                  -> quarterly_modeling_table
sql/005b     fold membership           -> cv_fold_rows
sql/006      checks                    -> 5 hard checks and soft figures
notebook 04  features, checked in pandas -> quarterly_modeling_table, cv_fold_rows verified
notebook 05  modeling on the folds     -> phase5_* tables, outputs/phase5_baseline_lock.json
```

Three rules shape everything downstream:

- **Month-end dates everywhere.** Zillow publishes month-end columns and the rate is dated
  at month-end, so the join is a plain equality. Mixing month-start and month-end dates in
  SQL silently gives zero matches.
- **Both quarter-end months must have a value.** A county-quarter is represented by its
  quarter-end month, and a decline label is built only between two consecutive quarter-end
  months. A quarter with an empty end month gets no label, and neither does the quarter after
  it. Every label is therefore a true quarter-to-quarter change.
- **Features look backward only.** Every feature attached to a label is measured at the end
  of the quarter before the one being predicted.

### What the SQL looks like

The quarter-end rule (`sql/004_phase3_eda.sql`):

```sql
CREATE TABLE train_quarterly AS
SELECT county_fips, date_trunc('quarter', month)::date AS quarter, zhvi, mortgage_rate
FROM train_monthly
WHERE zhvi IS NOT NULL
  AND month = (date_trunc('quarter', month) + INTERVAL '3 months' - INTERVAL '1 day')::date;

-- a label is kept only when the previous row is the calendar quarter before it
DELETE FROM train_quarterly_labeled
WHERE prev_zhvi IS NULL
   OR prev_quarter <> (quarter - INTERVAL '3 months')::date;
```

The 11 folds, generated and checked in SQL (`sql/003b_cv_folds.sql`):

```sql
SELECT g.fold_id, ... AS train_end, ... AS val_start, ... AS val_end
FROM params p
CROSS JOIN LATERAL generate_series(0, p.n_folds - 1) AS g(fold_id);
```

The data checks (`sql/006_checks.sql`) are `DO` blocks that stop the script with an error:
no duplicate months, month-end dates, join integrity, no fold row outside Train, at least
20 positives in every validation fold, no label spanning more than a quarter, and no missing
feature in the modeling table.

## Pitfalls found along the way

- **A join that silently matched nothing.** Zillow months stored at month-start and FRED
  months at month-end gave zero matches and no error. Both are now month-end.
- **A gap turned into "no decline".** Taking each quarter's last month with `DISTINCT ON`
  picked an empty month, and its label silently became 0.
- **Labels that spanned more than a quarter.** Taking "the last month with a value" fixed the
  first problem but let a label span two, or four to five, months when a quarter-end month
  was empty. In a row-by-row comparison, 448 modeling rows were built that way, and about 25%
  of them were declines against 4.9% overall. Requiring both quarter-end months removes them.
- **A change that spanned six months.** After a fully empty quarter, the next quarter's change
  covered six months. 91 counties have such a quarter.
- **A claim that was reasoned and not measured.** Intervals that assume independent months were first described as too narrow. A block bootstrap showed they are of similar width, so the conclusion on reverse causation is worded as "at most weak evidence" and not as "no evidence".
- **Choosing the model on the test period.** An earlier version of this phase compared
  the families and chose its thresholds on the test period. Phase 5 now chooses everything
  on the validation folds and leaves the test period for one scoring with frozen models.
- **An explanation checked and only partly confirmed.** The tree models get worse when the
  rate is added, and rates outside the training range were an obvious suspect. The check shows
  it fits some folds and not others, so it is reported as a possible contribution only.
- **A script splitter broken by prose.** Splitting a SQL file on `;` breaks on semicolons
  inside comments and `DO` blocks. The notebooks now send each file to the database whole.

## Limits

- The rate change is one national number per quarter, shared by about 3,000 counties, so the
  170,000 county-quarter rows are **not** independent evidence. The honest sample size for the
  rate link is the number of quarters, about 82.
- Zillow revises past values in each new file, so figures drift slightly with the data version.
- Counties with no Train history are scored using what the model learned from other counties.
- Phase 5 chose everything on the validation folds and has not scored the test period.
  Phase 6 scores it once, with frozen models. An earlier version of this project compared
  models on the test period directly. That is not repeated here.
- The validation years (2010 to 2020) do not include the 2022-23 rate-hiking cycle, which is
  in the test period, so the rate result above is about the validation years only.
- Model settings were fixed and not tuned, so a tuned model could use the rate differently.
- The rate is one national number per quarter, so the evidence about it rests on 44 validation
  quarters and not on 112,734 rows. The random forest result at the first rate step is only just
  below zero.
- Fold 10 (2020) has 71 declines, so its scores are noisy and the choice between random
  forest and gradient boosting depends on whether it is included.

## Repository layout

```
sql/                   001 to 006 plus 003b, 004b and 005b, each safe to re-run
notebooks/             01 ingest, 02 split and folds, 03 and 03b analysis, 04 features, 05 modeling
                       (06 and 07 are being rebuilt on the corrected pipeline)
outputs/               figures, feature summary, phase5_baseline_lock.json
.env.example           the database settings to copy into .env
requirements.txt       Python packages
```

## Setup

Requires PostgreSQL 15 or newer. Create a database, then copy `.env.example` to `.env`
(never commit it) and fill in your settings:

```
PGUSER=postgres
PGPASSWORD=your_password_here
PGHOST=localhost
PGPORT=5432
PGDATABASE=housing_risk_sql
```

```bash
python -m venv .venv
source .venv/Scripts/activate        # Git Bash on Windows
pip install -r requirements.txt
psql -U postgres -d housing_risk_sql -f sql/001_schema.sql
```

Run `notebooks/01_phase1_ingest_sql.ipynb` first. It downloads the data, loads it and runs
the join. Then run the remaining SQL files in order, from the repo root:

```bash
for f in 003_phase2_split 003b_cv_folds 004_phase3_eda 004b_reverse_causation 005_phase4_features 005b_cv_fold_rows 006_checks; do
  psql -v ON_ERROR_STOP=1 -U postgres -d housing_risk_sql -f sql/$f.sql
done
```

Expected figures are printed by `006_checks.sql` and match the table above. Re-run `005b`
after every run of `005`, because rebuilding the modeling table drops the fold view.

Then run `notebooks/04_phase4_features_sql.ipynb` (it re-runs `005` and `005b` and checks the
result against an independent pandas recomputation) and `notebooks/05_phase5_modeling_sql.ipynb`
(about 7 minutes of fitting plus 1 minute of bootstrap).

## License

MIT. See the [LICENSE](LICENSE) file. The data files are not covered by it: Zillow and FRED
have their own terms of use.
