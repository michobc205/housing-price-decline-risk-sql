# Results in detail

[Back to the README](../README.md)

This page holds the full results of phases 5, 6 and 7 of the SQL-first housing price decline
project: the model comparison on the validation folds, the evaluation on the test period and the
dashboard. The README has the summary.

Contents:

- [Phase 5: modeling on the validation folds](#phase-5-modeling-on-the-validation-folds)
- [Phase 6: the Test period, scored once with frozen models](#phase-6-the-test-period-scored-once-with-frozen-models)
- [Phase 7: the dashboard](#phase-7-the-dashboard)

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
the validation folds. The test period is scored once, in phase 6 (next section), with frozen models.
This phase on its own says nothing about how the models do there.

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

## Phase 6: the Test period, scored once with frozen models

Notebook 06 scores the nine models of phase 5 on the Test period (2022-Q1 to 2026-Q1) once, with
the settings frozen in phase 5. Nothing in it changes a model, a setting or a decision rule
after Test has been seen. The one cut-off it needs (the F1 threshold) is found on the saved
validation predictions and written to a file **before** Test is scored.

| Item | Choice |
|---|---|
| Models | All 9 of phase 5 (3 families x 3 feature steps), same fixed settings, refit once on **all** 164,460 Train rows |
| Test scoring | Once, with frozen models. The scores are locked in `outputs/phase6_test_lock.json`. A re-run must reproduce them or the notebook stops |
| Does the rate help on Test? | Same rule as phase 5: the interval of the change excludes zero **and** the gain is at least +0.01 ROC-AUC. Robust means it helps in at least 2 of 3 families. Bootstrap over the 17 Test quarters, 2,000 draws |
| Decision rules | Flag the riskiest 5%, 10% or 20% of counties **in each quarter**, or flag every county at or above the F1-maximizing threshold found on validation. No rule is picked: all four are reported side by side |
| Reference | The same rules on the saved validation predictions, so that Test can be compared with validation |
| Calibration | Reported on Test and on validation, with no recalibration |

### Result in one sentence

On Test, as on validation, the mortgage rate adds nothing robust once momentum is known: no step
passes the rule in any family, and adding the rate level lowers ROC-AUC for both tree families.
The recommended model (random forest on momentum alone) reaches ROC-AUC 0.8857 and PR-AUC 0.4665
against a base rate of 8.11%, and flagging the riskiest 10% of counties each quarter catches
48.6% of the declines. Its probabilities are too low on Test in every decile, while its ranking
holds up.

### Data and checks

| | Rows | Counties | Declines | Label quarters |
|---|---|---|---|---|
| Train (all of it, including 2021-Q1 to Q3, which sit in no fold) | 164,460 | 3,009 | 4.85% | 2001-06-30 to 2021-09-30 |
| Test | 51,980 | 3,071 | 8.11% (4,214 declines) | 17 quarters, 2022-03-31 to 2026-03-31 |

The notebook checks before any fit that no feature is missing, that Train ends before Test
starts, and that Test has exactly 17 quarters. The first Train label is the quarter ending
2001-06-30, because earlier quarters lack the history that the 6-month momentum and the 12-month
rate change need, so fold 0 of phase 5 effectively trains on 35 quarters, not the nominal 40.

### Decision rules chosen on validation, before Test

The F1-maximizing probability threshold of each model, found on the pooled validation predictions
of phase 5 and written to `outputs/phase6_thresholds_lock.json` before any Test prediction exists:

| Family | Feature step | Threshold | Validation precision | Validation recall | Validation F1 |
|---|---|---|---|---|---|
| Logistic regression | Baseline | 0.2805 | 0.4103 | 0.4929 | 0.4479 |
| Logistic regression | + rate level | 0.2573 | 0.4178 | 0.4847 | 0.4488 |
| Logistic regression | + rate change and interaction | 0.2379 | 0.3983 | 0.4960 | 0.4418 |
| Random forest | Baseline | 0.3386 | 0.4039 | 0.4937 | 0.4443 |
| Random forest | + rate level | 0.3327 | 0.3802 | 0.4650 | 0.4183 |
| Random forest | + rate change and interaction | 0.3309 | 0.3956 | 0.4436 | 0.4182 |
| Histogram gradient boosting | Baseline | 0.3895 | 0.4359 | 0.4506 | 0.4432 |
| Histogram gradient boosting | + rate level | 0.2784 | 0.3285 | 0.5200 | 0.4027 |
| Histogram gradient boosting | + rate change and interaction | 0.2753 | 0.3314 | 0.4737 | 0.3900 |

### Test scores

Interval = 95% interval of the ROC-AUC from the bootstrap over the 17 Test quarters. "Mean
predicted" is the average predicted probability, to be compared with the actual 8.11%. "Gap" is
Test ROC-AUC minus the phase 5 validation average.

| Family | Feature step | ROC-AUC (95% interval) | PR-AUC | Brier | Mean predicted | Validation mean ROC-AUC | Gap |
|---|---|---|---|---|---|---|---|
| Logistic regression | Baseline | 0.8668 (0.8088 to 0.9065) | 0.5069 | 0.0545 | 6.47% | 0.8364 | +0.0304 |
| Logistic regression | + rate level | 0.8677 (0.8074 to 0.9081) | 0.5128 | 0.0537 | 8.48% | 0.8368 | +0.0308 |
| Logistic regression | + rate change and interaction | 0.8648 (0.8184 to 0.9022) | 0.4777 | 0.0563 | 6.75% | 0.8372 | +0.0276 |
| Random forest | Baseline | 0.8857 (0.8502 to 0.9139) | 0.4665 | 0.0549 | 6.91% | 0.8680 | +0.0177 |
| Random forest | + rate level | 0.8779 (0.8422 to 0.9069) | 0.4330 | 0.0587 | 9.65% | 0.8564 | +0.0216 |
| Random forest | + rate change and interaction | 0.8802 (0.8466 to 0.9074) | 0.4441 | 0.0558 | 9.02% | 0.8462 | +0.0340 |
| Histogram gradient boosting | Baseline | 0.8915 (0.8594 to 0.9175) | 0.4759 | 0.0545 | 6.93% | 0.8666 | +0.0249 |
| Histogram gradient boosting | + rate level | 0.8692 (0.8344 to 0.9000) | 0.4176 | 0.0608 | 8.57% | 0.8525 | +0.0167 |
| Histogram gradient boosting | + rate change and interaction | 0.8689 (0.8330 to 0.9007) | 0.4234 | 0.0588 | 8.17% | 0.8511 | +0.0177 |

- All nine models score higher on Test than their validation average, by 0.017 to 0.034 ROC-AUC.
  Test is pooled over 17 quarters while validation is scored year by year, so the two are not
  like for like.
- A model that always predicted the Test base rate would have a Brier score of about 0.0745. The
  recommended model reaches 0.0549, about 26% better. On validation the same comparison gives
  0.0297 against 0.0363, about 18% better.
- The intervals are wide (about +/-0.03 to 0.05) because Test has only 17 quarters.
- Logistic regression has the highest PR-AUC at every step. The recommended model's PR-AUC is
  0.4665 with a 95% interval of 0.3379 to 0.5738.

### Does the rate help on Test?

| Family | Comparison | Change in ROC-AUC | 95% interval | Verdict |
|---|---|---|---|---|
| Logistic regression | + rate level minus baseline | +0.0009 | -0.0021 to +0.0035 | no significant effect |
| Logistic regression | + rate change and interaction minus + rate level | -0.0028 | -0.0205 to +0.0188 | no significant effect |
| Logistic regression | + rate change and interaction minus baseline | -0.0020 | -0.0195 to +0.0179 | no significant effect |
| Random forest | + rate level minus baseline | -0.0077 | -0.0118 to -0.0044 | hurts |
| Random forest | + rate change and interaction minus + rate level | +0.0023 | -0.0087 to +0.0143 | no significant effect |
| Random forest | + rate change and interaction minus baseline | -0.0054 | -0.0175 to +0.0066 | no significant effect |
| Histogram gradient boosting | + rate level minus baseline | -0.0223 | -0.0414 to -0.0084 | hurts |
| Histogram gradient boosting | + rate change and interaction minus + rate level | -0.0003 | -0.0124 to +0.0123 | no significant effect |
| Histogram gradient boosting | + rate change and interaction minus baseline | -0.0226 | -0.0361 to -0.0093 | hurts |

| Comparison | Families that help | Families that hurt | Overall |
|---|---|---|---|
| + rate level minus baseline | 0 | 2 | No gain, hurts in 2 families |
| + rate change and interaction minus + rate level | 0 | 0 | No family shows a gain that clears the rule |
| + rate change and interaction minus baseline | 0 | 1 | No gain, hurts in 1 family |

Compared with the validation folds of phase 5 (point changes and verdicts):

| Family | Comparison | Validation (phase 5) | Test (phase 6) |
|---|---|---|---|
| Logistic regression | + rate level minus baseline | +0.0005 (no significant effect) | +0.0009 (no significant effect) |
| Logistic regression | + rate change and interaction minus + rate level | +0.0004 (no significant effect) | -0.0028 (no significant effect) |
| Logistic regression | + rate change and interaction minus baseline | +0.0008 (no significant effect) | -0.0020 (no significant effect) |
| Random forest | + rate level minus baseline | -0.0116 (hurts) | -0.0077 (hurts) |
| Random forest | + rate change and interaction minus + rate level | -0.0101 (no significant effect) | +0.0023 (no significant effect) |
| Random forest | + rate change and interaction minus baseline | -0.0217 (hurts) | -0.0054 (no significant effect) |
| Histogram gradient boosting | + rate level minus baseline | -0.0141 (hurts) | -0.0223 (hurts) |
| Histogram gradient boosting | + rate change and interaction minus + rate level | -0.0013 (no significant effect) | -0.0003 (no significant effect) |
| Histogram gradient boosting | + rate change and interaction minus baseline | -0.0155 (hurts) | -0.0226 (hurts) |

- The verdicts agree except in one place: for the random forest, adding both rate steps lowers
  ROC-AUC on validation (significantly) but not significantly on Test (-0.0054, interval -0.0175
  to +0.0066).
- Adding the rate level lowers ROC-AUC for both tree families on Test as well. The random forest
  drop is now clearly below zero (interval ends at -0.0044, against -0.0002 on validation).
- Logistic regression is flat when the rate level is added. For the second step its Test interval
  is wide (up to +0.0188), so on Test alone it cannot rule out a gain of +0.01, which validation
  could.

### The families against each other on Test

Differences in ROC-AUC from the same bootstrap draws:

| Feature step | Comparison | Difference | 95% interval | Interval excludes zero |
|---|---|---|---|---|
| Baseline | random forest minus logistic regression | +0.0189 | +0.0008 to +0.0470 | yes |
| Baseline | random forest minus gradient boosting | -0.0058 | -0.0107 to -0.0022 | yes |
| Baseline | gradient boosting minus logistic regression | +0.0247 | +0.0050 to +0.0558 | yes |
| + rate level | random forest minus logistic regression | +0.0103 | -0.0077 to +0.0396 | no |
| + rate level | random forest minus gradient boosting | +0.0087 | -0.0053 to +0.0274 | no |
| + rate level | gradient boosting minus logistic regression | +0.0016 | -0.0238 to +0.0366 | no |
| + rate change and interaction | random forest minus logistic regression | +0.0154 | -0.0116 to +0.0430 | no |
| + rate change and interaction | random forest minus gradient boosting | +0.0114 | +0.0000 to +0.0237 | yes |
| + rate change and interaction | gradient boosting minus logistic regression | +0.0041 | -0.0197 to +0.0295 | no |

- At baseline, **histogram gradient boosting is ahead of the random forest by 0.0058** (interval
  -0.0107 to -0.0022 for random forest minus gradient boosting), and both are ahead of logistic
  regression.
- The **random forest stays the recommended model**. It was chosen on validation, where it led
  gradient boosting by 0.0014, and a switch because of Test would be a new choice made with Test
  knowledge. The difference is reported and not acted on.

### Decision rules on Test

"Flagged" is the share of all counties flagged, "precision" the share of flagged counties that
declined, "recall" the share of all declines that were flagged, and "lift" is precision divided by
the base rate. Recommended model, validation against Test:

| Split | Rule | TP | FP | FN | TN | Precision | Recall | Flagged | Lift |
|---|---|---|---|---|---|---|---|---|---|
| validation | top 5% each quarter | 1,650 | 3,983 | 2,602 | 104,499 | 0.2929 | 0.3881 | 5.0% | 7.8 |
| validation | top 10% each quarter | 2,351 | 8,923 | 1,901 | 99,559 | 0.2085 | 0.5529 | 10.0% | 5.5 |
| validation | top 20% each quarter | 3,082 | 19,467 | 1,170 | 89,015 | 0.1367 | 0.7248 | 20.0% | 3.6 |
| validation | F1 threshold from validation | 2,099 | 3,098 | 2,153 | 105,384 | 0.4039 | 0.4937 | 4.6% | 10.7 |
| test | top 5% each quarter | 1,259 | 1,342 | 2,955 | 46,424 | 0.4840 | 0.2988 | 5.0% | 6.0 |
| test | top 10% each quarter | 2,046 | 3,151 | 2,168 | 44,615 | 0.3937 | 0.4855 | 10.0% | 4.9 |
| test | top 20% each quarter | 2,981 | 7,416 | 1,233 | 40,350 | 0.2867 | 0.7074 | 20.0% | 3.5 |
| test | F1 threshold from validation | 1,824 | 1,435 | 2,390 | 46,331 | 0.5597 | 0.4328 | 6.3% | 6.9 |

- Flagging the riskiest 10% of counties each quarter catches 48.6% of Test declines, and 39.4% of
  the flagged counties decline, 4.9 times the base rate.
- Precision is higher on Test because Test has more declines (8.11% against 3.77%), so **lift** is
  the fair comparison: 6.0, 4.9 and 3.5 on Test against 7.8, 5.5 and 3.6 on validation. Recall is
  lower on Test for the same reason.
- The F1 threshold (0.3386, fixed on validation) flags 6.3% of Test counties against 4.6% on
  validation. A probability cut-off does not carry over when the base rate moves, while the
  top-X% rules always flag the intended share.

The three families at baseline on Test (precision / recall / share flagged):

| Rule | Logistic regression | Random forest | Histogram gradient boosting |
|---|---|---|---|
| top 5% each quarter | 0.502 / 0.310 / 5.0% | 0.484 / 0.299 / 5.0% | 0.482 / 0.297 / 5.0% |
| top 10% each quarter | 0.404 / 0.498 / 10.0% | 0.394 / 0.485 / 10.0% | 0.397 / 0.490 / 10.0% |
| top 20% each quarter | 0.283 / 0.699 / 20.0% | 0.287 / 0.707 / 20.0% | 0.288 / 0.710 / 20.0% |
| F1 threshold from validation | 0.581 / 0.447 / 6.2% | 0.560 / 0.433 / 6.3% | 0.587 / 0.395 / 5.5% |

The differences are small (at most about 0.02 in precision) and have no intervals, so they are read
as roughly equal. Logistic regression is slightly ahead at the top 5% and 10%, in line with its
higher PR-AUC.

### Calibration

Recommended model, Test and validation split into probability deciles (mean predicted probability
against the share that actually declined):

| Decile | Validation predicted | Validation actual | Test predicted | Test actual |
|---|---|---|---|---|
| 1 | 0.35% | 0.39% | 0.36% | 0.46% |
| 2 | 0.42% | 0.32% | 0.44% | 0.58% |
| 3 | 0.47% | 0.32% | 0.54% | 0.77% |
| 4 | 0.55% | 0.35% | 0.64% | 1.02% |
| 5 | 0.70% | 0.76% | 0.83% | 2.40% |
| 6 | 1.01% | 0.84% | 1.32% | 2.92% |
| 7 | 1.67% | 1.47% | 2.20% | 3.37% |
| 8 | 3.06% | 2.27% | 4.40% | 6.98% |
| 9 | 7.59% | 5.49% | 12.28% | 14.99% |
| 10 | 38.06% | 25.49% | 46.05% | 47.58% |

- Average predicted against actual: **6.91% against 8.11% on Test**, and 5.39% against 3.77% on
  validation. Brier scores: 0.0549 on Test and 0.0297 on validation.
- On Test the model under-predicts in all 10 deciles (for example 1.3% predicted against 2.9%
  actual in decile 6). On validation it over-predicts in the upper deciles, mostly the top one
  (38.1% against 25.5%).
- A probable reason, not tested separately: the models carry over the decline rate of the years
  they were trained on. In 9 of the 11 folds the validation year had a lower rate than its
  training years, and Test has a higher rate than Train (8.11% against 4.85%).
- So the ranking is useful, but a predicted probability is not a stable estimate of the share
  that will decline. No recalibration is applied: one fitted on validation would lower the
  probabilities, which is the wrong direction for Test.

All nine models on Test:

| Family | Feature step | Validation mean predicted (actual 3.77%) | Test mean predicted (actual 8.11%) | Test Brier | Test deciles under-predicted |
|---|---|---|---|---|---|
| Logistic regression | Baseline | 5.13% | 6.47% | 0.0545 | 10 of 10 |
| Logistic regression | + rate level | 4.56% | 8.48% | 0.0537 | 5 of 10 |
| Logistic regression | + rate change and interaction | 4.50% | 6.75% | 0.0563 | 9 of 10 |
| Random forest | Baseline | 5.39% | 6.91% | 0.0549 | 10 of 10 |
| Random forest | + rate level | 5.70% | 9.65% | 0.0587 | 7 of 10 |
| Random forest | + rate change and interaction | 5.91% | 9.02% | 0.0558 | 6 of 10 |
| Histogram gradient boosting | Baseline | 5.42% | 6.93% | 0.0545 | 10 of 10 |
| Histogram gradient boosting | + rate level | 5.76% | 8.57% | 0.0608 | 8 of 10 |
| Histogram gradient boosting | + rate change and interaction | 5.25% | 8.17% | 0.0588 | 8 of 10 |

All baseline models under-predict in every decile. Adding the rate level raises the average
prediction toward 8.11% (8.48% for logistic regression, 9.65% for the random forest) without
raising ROC-AUC, so it appears to adjust the overall level and not the ranking. For logistic
regression it helps a little (best Brier, 0.0537). For the trees it overshoots and the Brier score
worsens.

### Stability over time: each Test quarter

Recommended model. "Top 10% recall" is the share of that quarter's declines among its riskiest
10% of counties.

| Quarter | Counties | Declines | Base rate | ROC-AUC | PR-AUC | Top 10% recall | Top 10% precision |
|---|---|---|---|---|---|---|---|
| 2022-Q1 | 3,020 | 39 | 1.29% | 0.7555 | 0.2269 | 0.436 | 0.056 |
| 2022-Q2 | 3,019 | 63 | 2.09% | 0.9626 | 0.5365 | 0.889 | 0.185 |
| 2022-Q3 | 3,021 | 249 | 8.24% | 0.7897 | 0.3717 | 0.406 | 0.334 |
| 2022-Q4 | 3,060 | 712 | 23.27% | 0.8793 | 0.7086 | 0.354 | 0.824 |
| 2023-Q1 | 3,060 | 671 | 21.93% | 0.8416 | 0.6291 | 0.350 | 0.768 |
| 2023-Q2 | 3,059 | 98 | 3.20% | 0.8497 | 0.2622 | 0.541 | 0.173 |
| 2023-Q3 | 3,060 | 269 | 8.79% | 0.8838 | 0.5507 | 0.573 | 0.503 |
| 2023-Q4 | 3,063 | 380 | 12.41% | 0.9261 | 0.7296 | 0.595 | 0.739 |
| 2024-Q1 | 3,063 | 129 | 4.21% | 0.9015 | 0.2886 | 0.643 | 0.271 |
| 2024-Q2 | 3,063 | 10 | 0.33% | 0.9606 | 0.1127 | 0.800 | 0.026 |
| 2024-Q3 | 3,069 | 162 | 5.28% | 0.9102 | 0.4517 | 0.685 | 0.362 |
| 2024-Q4 | 3,071 | 142 | 4.62% | 0.8987 | 0.3789 | 0.655 | 0.303 |
| 2025-Q1 | 3,071 | 125 | 4.07% | 0.9056 | 0.4375 | 0.720 | 0.293 |
| 2025-Q2 | 3,071 | 524 | 17.06% | 0.8297 | 0.6066 | 0.414 | 0.707 |
| 2025-Q3 | 3,070 | 411 | 13.39% | 0.9078 | 0.6298 | 0.489 | 0.655 |
| 2025-Q4 | 3,070 | 197 | 6.42% | 0.9177 | 0.4426 | 0.604 | 0.388 |
| 2026-Q1 | 3,070 | 33 | 1.07% | 0.9637 | 0.2929 | 0.909 | 0.098 |

- Quarterly ROC-AUC runs from 0.7555 (2022-Q1, only 39 declines) to 0.9637 (2026-Q1, 33
  declines), with a median of 0.9015. Twelve of 17 quarters are at or above 0.85. The five below
  are 2022-Q1, 2022-Q3, 2023-Q1, 2023-Q2 and 2025-Q2. From 2023-Q4 on, every quarter except
  2025-Q2 is above 0.89.
- Quarters with few declines are noisy: 2024-Q2 has only 10.
- Recall at the top 10% depends on how many counties decline. In 2022-Q4 and 2023-Q1 (22% to 23%
  declines) a 10% list can catch at most about 43% to 46% of them, and it catches 35%, with 82%
  and 77% of the flagged counties declining.
- 2022-Q1, the quarter right after the embargo, is the weakest quarter for 8 of the 9 models.

<details>
<summary>ROC-AUC per quarter, all nine models (LR logistic regression, RF random forest, GB gradient boosting)</summary>

| Quarter | Base rate | LR base | LR + level | LR + change | RF base | RF + level | RF + change | GB base | GB + level | GB + change |
|---|---|---|---|---|---|---|---|---|---|---|
| 2022-Q1 | 1.29% | 0.709 | 0.716 | 0.734 | 0.755 | 0.766 | 0.797 | 0.778 | 0.686 | 0.748 |
| 2022-Q2 | 2.09% | 0.969 | 0.970 | 0.973 | 0.963 | 0.952 | 0.950 | 0.966 | 0.965 | 0.968 |
| 2022-Q3 | 8.24% | 0.835 | 0.841 | 0.851 | 0.790 | 0.830 | 0.735 | 0.801 | 0.830 | 0.821 |
| 2022-Q4 | 23.27% | 0.902 | 0.904 | 0.893 | 0.879 | 0.872 | 0.880 | 0.883 | 0.887 | 0.872 |
| 2023-Q1 | 21.93% | 0.847 | 0.849 | 0.865 | 0.842 | 0.835 | 0.843 | 0.845 | 0.837 | 0.838 |
| 2023-Q2 | 3.20% | 0.817 | 0.815 | 0.793 | 0.850 | 0.838 | 0.845 | 0.845 | 0.839 | 0.843 |
| 2023-Q3 | 8.79% | 0.893 | 0.897 | 0.913 | 0.884 | 0.867 | 0.866 | 0.897 | 0.885 | 0.860 |
| 2023-Q4 | 12.41% | 0.906 | 0.905 | 0.896 | 0.926 | 0.923 | 0.926 | 0.928 | 0.910 | 0.923 |
| 2024-Q1 | 4.21% | 0.883 | 0.885 | 0.892 | 0.902 | 0.897 | 0.895 | 0.908 | 0.895 | 0.896 |
| 2024-Q2 | 0.33% | 0.943 | 0.935 | 0.921 | 0.961 | 0.942 | 0.938 | 0.963 | 0.953 | 0.944 |
| 2024-Q3 | 5.28% | 0.873 | 0.876 | 0.886 | 0.910 | 0.910 | 0.899 | 0.907 | 0.890 | 0.898 |
| 2024-Q4 | 4.62% | 0.862 | 0.867 | 0.861 | 0.899 | 0.893 | 0.891 | 0.903 | 0.891 | 0.886 |
| 2025-Q1 | 4.07% | 0.883 | 0.884 | 0.884 | 0.906 | 0.896 | 0.898 | 0.903 | 0.898 | 0.894 |
| 2025-Q2 | 17.06% | 0.783 | 0.785 | 0.786 | 0.830 | 0.834 | 0.819 | 0.836 | 0.818 | 0.819 |
| 2025-Q3 | 13.39% | 0.869 | 0.874 | 0.878 | 0.908 | 0.896 | 0.890 | 0.908 | 0.902 | 0.896 |
| 2025-Q4 | 6.42% | 0.909 | 0.911 | 0.912 | 0.918 | 0.910 | 0.913 | 0.919 | 0.909 | 0.914 |
| 2026-Q1 | 1.07% | 0.951 | 0.948 | 0.945 | 0.964 | 0.966 | 0.967 | 0.965 | 0.958 | 0.963 |
</details>

Spread of the quarterly ROC-AUC by model:

| Family | Feature step | Lowest | Median | Highest | Std | Weakest quarter |
|---|---|---|---|---|---|---|
| Logistic regression | Baseline | 0.7092 | 0.8832 | 0.9695 | 0.0635 | 2022-Q1 |
| Logistic regression | + rate level | 0.7158 | 0.8836 | 0.9698 | 0.0615 | 2022-Q1 |
| Logistic regression | + rate change and interaction | 0.7336 | 0.8857 | 0.9727 | 0.0593 | 2022-Q1 |
| Random forest | Baseline | 0.7555 | 0.9015 | 0.9637 | 0.0585 | 2022-Q1 |
| Random forest | + rate level | 0.7661 | 0.8957 | 0.9657 | 0.0515 | 2022-Q1 |
| Random forest | + rate change and interaction | 0.7351 | 0.8905 | 0.9674 | 0.0584 | 2022-Q3 |
| Histogram gradient boosting | Baseline | 0.7782 | 0.9032 | 0.9658 | 0.0545 | 2022-Q1 |
| Histogram gradient boosting | + rate level | 0.6855 | 0.8912 | 0.9647 | 0.0658 | 2022-Q1 |
| Histogram gradient boosting | + rate change and interaction | 0.7478 | 0.8938 | 0.9676 | 0.0565 | 2022-Q1 |

### Rates outside the training range on Test

Tree models cannot predict beyond the values they saw in Train.

| Feature | Train range | Test range | Share of Test rows outside the Train range |
|---|---|---|---|
| `rate_level` | 2.684 to 7.160 | 3.098 to 7.200 | 5.9% |
| `rate_roc_12m` | -1.420 to 1.112 | -1.020 to 3.266 | 29.4% |

The 12-month rate change is outside the Train range for every county in the five quarters from
2022-Q3 to 2023-Q3 (the core of the hiking cycle), and the rate level only in 2023-Q4:

| Quarter | Rate level outside | Rate change outside |
|---|---|---|
| 2022-Q1 | 0% | 0% |
| 2022-Q2 | 0% | 0% |
| 2022-Q3 | 0% | 100% |
| 2022-Q4 | 0% | 100% |
| 2023-Q1 | 0% | 100% |
| 2023-Q2 | 0% | 100% |
| 2023-Q3 | 0% | 100% |
| 2023-Q4 | 100% | 0% |
| 2024-Q1 | 0% | 0% |
| 2024-Q2 | 0% | 0% |
| 2024-Q3 | 0% | 0% |
| 2024-Q4 | 0% | 0% |
| 2025-Q1 | 0% | 0% |
| 2025-Q2 | 0% | 0% |
| 2025-Q3 | 0% | 0% |
| 2025-Q4 | 0% | 0% |
| 2026-Q1 | 0% | 0% |

In those five quarters the effect of adding the rate change on the random forest is mixed: a
large drop in 2022-Q3 (0.830 to 0.735) and small changes in the other four. This does not show
that the range explains the results.

### Compared with the earlier version of this phase

| | Earlier version | This version |
|---|---|---|
| Models scored | Random forest on the baseline | All nine, frozen |
| Where thresholds were chosen | On the Test predictions | On the validation predictions, locked before Test was scored |
| Test ROC-AUC of the random forest on the baseline | 0.8843 | 0.8857 |
| Brier score of the same model | 0.0552 | 0.0549 |
| Calibration | Under-confident in 10 of 10 deciles | Under-confident in 10 of 10 deciles |
| Quarterly ROC-AUC | 0.7695 to 0.9635, weakest 2022-Q1 | 0.7555 to 0.9637, weakest 2022-Q1 |

The earlier numbers came from an older table and an older design, so they are retired and shown
only to say that the picture is the same. What changed is the discipline: nothing here was chosen
on Test.

### What is saved and how it was checked

- Two lock files go into git: `outputs/phase6_thresholds_lock.json` (written before Test was
  scored) and `outputs/phase6_test_lock.json` (the nine Test scores). A re-run must reproduce both
  within 1e-6 or the notebook stops. Changing one locked number was tested and stops it.
- Eleven tables are written to Postgres: `phase6_test_scores`, `phase6_test_deltas`,
  `phase6_family_deltas`, `phase6_thresholds`, `phase6_decision_rules` (72 rows),
  `phase6_calibration` (20), `phase6_calibration_all`, `phase6_per_quarter` (153),
  `phase6_range_check`, `phase6_eval_summary` and `phase6_test_predictions` (51,980).
- The bootstrap AUC matches scikit-learn to 1.1e-16. Before the real run, the notebook was run on
  synthetic data and the top-X% counts, the F1 threshold, one bootstrap draw and the per-quarter
  scores were checked against independent calculations.
- Fitting the nine models on all Train rows and scoring Test took about 92 seconds (random forest
  25 to 32 seconds each). Seconds per model:

| Family | Baseline | + rate level | + rate change and interaction |
|---|---|---|---|
| Logistic regression | 0.2 | 0.3 | 0.4 |
| Random forest | 24.7 | 32.4 | 26.9 |
| Histogram gradient boosting | 2.4 | 2.5 | 1.9 |

## Phase 7: the dashboard

`notebooks/07_phase7_dashboard_sql.py` is a Streamlit dashboard with five pages. It does **no
modeling**: it only reads the tables written by notebooks 04 to 06, so every number on a page
traces back to a verified table. It reads Postgres first, and if the database cannot be reached it
reads a small CSV snapshot of the summary tables in `outputs/dashboard_data/`, so anyone who clones
the repository can run it without a database.

```bash
python notebooks/07b_export_dashboard_data.py          # after notebooks 04 to 06
streamlit run notebooks/07_phase7_dashboard_sql.py
```

| Page | What it shows |
|---|---|
| 1. The answer | A headline built from the tables, four numbers for the recommended model (Test ROC-AUC 0.8857 with its interval, PR-AUC 0.4665 against the 8.11% base rate, 48.6% of declines found in the riskiest 10% each quarter, lift 4.9x), and a chart of the change in ROC-AUC when the rate is added, for validation and Test, with the +0.01 line |
| 2. Data and folds | The modeling table by period, the decline share and the mortgage rate over time, the 11 validation folds and their decline rates, and the share of validation rows outside the training range of the rate features |
| 3. Models on validation | The nine-model summary, a fold-by-fold chart (ROC-AUC or PR-AUC, with the base rate as a dotted line, one feature step or all) and the validation bootstrap table |
| 4. Test and decision rules | Test scores with intervals, a picker for the four fixed decision rules and for the model with validation and Test side by side (flagged share, precision, recall, lift and the 2x2 counts), calibration, ROC-AUC per Test quarter for any model, and the Test range check |
| 5. Limits and method | How the results were made, an integrity check of the dashboard against the three lock files, and the limits |

Design choices:

- **The reader cannot tune on Test.** The decision page offers the four fixed rules of phase 6 (top
  5%, 10% and 20% each quarter, and the F1 threshold from validation), not a free slider, and always
  shows validation next to Test.
- **Numbers are read from the tables, not typed into the text.** Where a sentence quotes a number
  (for example the fold with the fewest declines), it is computed from the table.
- **Integrity check on page 5.** The Test scores, the F1 thresholds and the baseline validation
  scores shown by the dashboard are compared with `phase6_test_lock.json`,
  `phase6_thresholds_lock.json` and `phase5_baseline_lock.json`. On the real data all three gaps
  are exactly 0, and a changed lock file turns the line red.
- **Per-table fallback.** Each table is read from Postgres if it can be, and from its CSV otherwise.
  The sidebar says how many tables came from each, and the snapshot date when it is used. The cache
  refreshes every 5 minutes, so re-running a notebook does not need a restart.

### The snapshot

`notebooks/07b_export_dashboard_data.py` builds five small overview tables in Postgres (`dash_*`)
and writes 18 tables to `outputs/dashboard_data/` (62 KB in total), plus `snapshot_info.json`:

| Table | Rows | Content |
|---|---|---|
| `phase5_fold_scores`, `phase5_step_summary`, `phase5_bootstrap_deltas` | 99, 9, 9 | Phase 5 results |
| `phase6_test_scores`, `phase6_test_deltas`, `phase6_family_deltas`, `phase6_thresholds` | 9 each | Phase 6 scores, bootstrap and thresholds |
| `phase6_decision_rules`, `phase6_calibration`, `phase6_calibration_all`, `phase6_per_quarter` | 72, 20, 9, 153 | Decision rules, calibration, quarterly scores |
| `phase6_range_check`, `phase6_eval_summary` | 2, 12 | Range check and key facts |
| `dash_split_summary`, `dash_quarterly_rate`, `dash_fold_overview`, `dash_fold_range_check`, `dash_test_range_by_quarter` | 4, 101, 11, 11, 17 | Overview tables built from the modeling table and the fold view |

Only aggregated results are exported. The script stops if any table holds a county-level column or
thousands of rows, so no Zillow data can reach the repository. Re-run it after re-running notebooks
04 to 06, otherwise the snapshot is out of date (the dashboard always prefers the database).

### How the phase was checked

- Before the real run, every page and control was run headlessly on a snapshot built from the
  verified results: the rule picker, the model selectors and the fold controls. A changed lock file
  gave a red line, a missing lock file gave a note, and a missing table gave a clear stop message
  with instructions. The export script was run on a stand-in database, and its five overview tables
  matched independent pandas calculations.
- On the real data, the export printed 18 tables (62 KB) and no county-level rows. Each of the five
  pages was compared with the verified numbers of notebooks 04 to 06 (the headline counts of 7
  comparisons that lower the score, the four headline numbers, the fold table, the Test scores, all
  eight rows of the decision-rule table, the calibration tables, the quarterly table, the range
  table and the three integrity lines).
- Reviewing the real pages led to small fixes: grey up-arrows removed from the headline numbers (they
  read as "increase"), an ambiguous axis label, every year shown on the fold charts, readable
  column names, bars on a cut axis replaced by dots with intervals, a logical order for the rules,
  and quarter labels and a zero-based right axis on the quarterly chart.

[Back to the README](../README.md)
