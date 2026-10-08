# Housing Price Decline Risk: a SQL-first pipeline in PostgreSQL

Which US counties will see their home values fall by more than 2% in the next quarter, and
how much do mortgage rates add once a county's own price momentum is already known?

This project answers that question with a pipeline that runs **in SQL**. Joining, splitting
in time, building the validation folds, labelling, feature engineering and the data checks
all run inside PostgreSQL. Python downloads and cleans the two raw files before they are
loaded, fits the models and draws the plots.

This is the SQL-first part of a two-person capstone, built and verified on its own. The
[team repository](https://github.com/michobc205/capstone-housing-risk-team) holds the team's
merged pipeline.

## Key findings

- **The mortgage rate adds nothing robust once a county's own price momentum is known.** On the
  11 validation folds and on the Test period, no feature step passes the rule (a 95% interval
  above zero **and** a gain of at least +0.01 ROC-AUC) in any of the three model families. Adding
  the rate level even lowers ROC-AUC for both tree models.
- **Price momentum alone predicts well.** The recommended model, a random forest on momentum
  (chosen on validation), scores a ROC-AUC of 0.8857 on Test (95% interval 0.850 to 0.914) with
  8.11% of counties declining.
- **It works as a ranking, not as a probability.** Flagging the riskiest 10% of counties each
  quarter finds 48.6% of the declines, 4.9 times better than chance. The predicted probabilities
  are too low on Test and too high on validation.
- **No choice was made from the Test results.** Everything was chosen on the validation
  folds, Test was scored once with frozen models, and the baseline, the decision threshold and
  the Test scores are locked in files committed to git.

The full numbers are in [docs/RESULTS.md](docs/RESULTS.md). To explore them, run
`streamlit run notebooks/07_phase7_dashboard_sql.py`: the dashboard reads a CSV snapshot when no
database is available.

## Status

| Phase | What | Status |
|---|---|---|
| 1 | Ingest, month-end join, coverage audit | Done and verified |
| 2 | Split in time and 11 validation folds, generated in SQL | Done and verified |
| 3 | Exploratory analysis: lag sweep, quarter-level re-test, rate definition | Done and verified |
| 3b | Reverse-causation check with a block bootstrap | Done and verified |
| 4 | Modeling table with six features | Done and verified |
| 5 | Modeling on the validation folds: 3 families, 3 feature steps, quarter bootstrap | Done and verified |
| 6 | Evaluation on the test period: nine frozen models scored once, decision rules, calibration, stability | Done and verified |
| 7 | Dashboard: five pages on the phase 5 and 6 tables, with a CSV snapshot of the summary results | Done and verified |

Phases 5 to 7 were run on the corrected pipeline below. Phase 5 never reads the test period,
phase 6 scores it once with frozen models, and phase 7 (the dashboard) only reads the result tables
of phases 5 and 6 and does no modeling of its own.

## The data

| Source | Grain | Used for |
|---|---|---|
| [Zillow ZHVI](https://www.zillow.com/research/data/): county, middle tier (33rd to 67th percentile), single-family and condo, smoothed and seasonally adjusted | County, monthly | The decline label and the price-momentum features |
| [FRED MORTGAGE30US](https://fred.stlouisfed.org/series/MORTGAGE30US): 30-year fixed mortgage rate | National, weekly | Rate level, rate change and their interaction with momentum |

The data files are **not** included in this repository. The notebook downloads them, and both
sources have their own terms of use. The weekly rate is averaged to one value per month
(`.mean()`), dated at month-end like Zillow's columns.

### Data version

Every result in this repository comes from these two raw files. They are not part of the
repository, and the hash is the proof of the version.

| File | SHA-256 | Size | Downloaded |
|---|---|---|---|
| `data/raw/zillow/zhvi_county.csv` | `334e267a88028068d8c485363bf367a613c24a32dba3b1e288754e9728933867` | 13,579,570 bytes | 2026-09-23 |
| `data/raw/fred/mortgage30us.csv` | `11e81dbde55fab4f29cbe2e4604df594f05f655cf6f5196a3264db5b6c38c385` | 46,915 bytes | 2026-09-23 |

Zillow re-estimates and republishes its whole history every month, so a new download is a
different version and gives slightly different figures.

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
(`sql/006_checks.sql`, check 6a), and the two agree exactly.

## Results at a glance

**Does the rate help?** ROC-AUC of the three feature steps, as an average over the 11 validation
folds and on the Test period. The baseline is momentum only.

| Model family | Validation: baseline / + rate level / + rate change | Test: baseline / + rate level / + rate change |
|---|---|---|
| Logistic regression | 0.8364 / 0.8368 / 0.8372 | 0.8668 / 0.8677 / 0.8648 |
| Random forest | 0.8680 / 0.8564 / 0.8462 | 0.8857 / 0.8779 / 0.8802 |
| Histogram gradient boosting | 0.8666 / 0.8525 / 0.8511 | 0.8915 / 0.8692 / 0.8689 |

No step passes the rule in any family, on either period. For logistic regression the changes are
within +/-0.003, and on validation the intervals rule out a gain of +0.01. For both tree models,
adding the rate level lowers ROC-AUC, significantly on both periods.

**The recommended model on Test** (random forest on momentum, chosen on validation): ROC-AUC
0.8857 (95% interval 0.8502 to 0.9139), PR-AUC 0.4665 against a base rate of 8.11%, Brier score
0.0549. Flagging the riskiest counties in each quarter gives:

| Flag the riskiest... | Share of declines found | Share of flagged counties that declined | Lift |
|---|---|---|---|
| 5% of counties | 29.9% | 48.4% | 6.0x |
| 10% of counties | 48.6% | 39.4% | 4.9x |
| 20% of counties | 70.7% | 28.7% | 3.5x |

Per-fold scores, the bootstrap tables, the families against each other, calibration, the
quarter-by-quarter stability and the range check are in [docs/RESULTS.md](docs/RESULTS.md).

## The dashboard

`notebooks/07_phase7_dashboard_sql.py` is a Streamlit dashboard with five pages: the answer, data
and folds, models on validation, Test and decision rules, and limits and method. It does no
modeling: it only reads the result tables of phases 4 to 6, from Postgres if it can, and from the
CSV snapshot in `outputs/dashboard_data/` otherwise, so it also runs without a database.

```bash
python notebooks/07b_export_dashboard_data.py          # after notebooks 04 to 06
streamlit run notebooks/07_phase7_dashboard_sql.py
```

The reader can pick one of the four fixed decision rules and a model and see validation and Test
side by side. Page 5 checks the numbers on screen against the three lock files. More about the
dashboard and the snapshot is in [docs/RESULTS.md](docs/RESULTS.md#phase-7-the-dashboard).

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
notebook 06  Test scored once          -> phase6_* tables, outputs/phase6_*_lock.json
notebook 07b overview tables + snapshot -> dash_* tables, outputs/dashboard_data/*.csv
notebook 07  dashboard (Streamlit)     -> reads the tables above, or the CSV snapshot
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
  was empty. An independent recomputation of the modeling table found 448 rows built that way,
  and about 25% of them were declines against 4.9% overall. Requiring both quarter-end months
  removes them.
- **A change that spanned six months.** After a fully empty quarter, the next quarter's change
  covered six months. 91 counties have such a quarter.
- **A claim that was reasoned and not measured.** Intervals that assume independent months were first described as too narrow. A block bootstrap showed they are of similar width, so the conclusion on reverse causation is worded as "at most weak evidence" and not as "no evidence".
- **Choosing the model on the test period.** An earlier version of this phase compared
  the families and chose its thresholds on the test period. Phase 5 now chooses everything
  on the validation folds and leaves the test period for one scoring with frozen models.
- **A script splitter broken by prose.** Splitting a SQL file on `;` breaks on semicolons
  inside comments and `DO` blocks. The notebooks now send each file to the database whole.

<details>
<summary>Six more lessons, from the modeling, evaluation and dashboard phases</summary>

- **An explanation checked and only partly confirmed.** The tree models get worse when the
  rate is added, and rates outside the training range were an obvious suspect. The check shows
  it fits some folds and not others, so it is reported as a possible contribution only.
- **Reading precision across periods with different base rates.** On Test the riskiest-10% rule
  has precision 0.39 against 0.21 on validation, which looks like an improvement. It is mostly
  the higher base rate (8.11% against 3.77%). Lift, precision divided by the base rate, is the
  fair comparison, and it is lower on Test (4.9 against 5.5).
- **A probability cut-off that does not carry over.** The F1 threshold fixed on validation flags
  4.6% of validation counties but 6.3% of Test counties, because the models carry over the decline
  rate of their training years. Rank-based rules flag the intended share.
- **A dashboard nobody else could run.** The first dashboard needed the live database and read
  tables of an earlier version. The new one falls back to a CSV snapshot of the summary results,
  with a guard that stops the export if any county-level column slips in.
- **A chart that exaggerated differences.** Bars drawn on an axis that starts at 0.75 made small
  differences between models look large. Dots with their intervals show the same numbers honestly.
- **Numbers typed into the text.** A sentence such as "the 2020 fold has 71 declines" goes stale
  when the data change. The dashboard computes such facts from its tables.

</details>

## Limits

- The rate change is one national number per quarter, shared by about 3,000 counties, so the
  170,000 county-quarter rows are **not** independent evidence. The honest sample size for the
  rate link is the number of quarters, about 82.
- Zillow revises past values in each new file, so figures drift slightly with the data version.
- Counties with no Train history are scored using what the model learned from other counties.
- Phase 5 chose everything on the validation folds, and phase 6 scored the test period once with
  frozen models. An earlier version of this project compared models on the test period directly.
  That is not repeated here. The test period was also scored in earlier versions of this project,
  and those results are retired.
- The validation years (2010 to 2020) do not include the 2022-23 rate-hiking cycle. That
  cycle is in the test period, where the rate also adds nothing robust.
- Model settings were fixed and not tuned, so a tuned model could use the rate differently.
- The rate is one national number per quarter, so the evidence about it rests on 44 validation
  quarters and not on 112,734 rows. The random forest result at the first rate step is only just
  below zero.
- Fold 10 (2020) has 71 declines, so its scores are noisy and the choice between random
  forest and gradient boosting depends on whether it is included.
- The test period has 17 quarters, so its intervals are wide. On Test alone, even logistic
  regression cannot rule out a gain of +0.01 when the rate change is added on top of the rate
  level (upper end +0.0188; for the rate level alone +0.0035).
- The test period contains one rate-hiking cycle (2022-23). The result about the rate is about
  that cycle and the years after it, not about rate cycles in general.
- Predicted probabilities are not calibrated across periods (too low on Test, too high on
  validation), so the models are better used for ranking counties than for reading a probability.
- Histogram gradient boosting scores slightly higher than the random forest on Test. The random
  forest remains the recommended model because it was chosen on validation.
- Fold 0 of phase 5 trains on 35 quarters in practice, not the nominal 40 (the first Train label
  is the quarter ending 2001-06-30).
- The dashboard shows aggregated results only. It has no county-level view, because county-level
  rows come from Zillow data that is not part of the repository.
- When it runs from the CSV snapshot, the dashboard shows the results of the day the snapshot was
  made (the sidebar says so).

## Repository layout

```
sql/                   001 to 006 plus 003b, 004b and 005b, each safe to re-run
notebooks/             01 ingest, 02 split and folds, 03 and 03b analysis, 04 features, 05 modeling,
                       06 evaluation, 07 dashboard (07b exports the data it needs)
docs/                  RESULTS.md: the full results of phases 5 to 7
outputs/               figures, feature summary, phase5_baseline_lock.json,
                       phase6_thresholds_lock.json, phase6_test_lock.json,
                       dashboard_data/ (CSV snapshot of the summary tables)
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
result against an independent pandas recomputation), `notebooks/05_phase5_modeling_sql.ipynb`
(about 7 minutes of fitting plus 1 minute of bootstrap) and `notebooks/06_phase6_evaluation_sql.ipynb`
(about 3 minutes; it scores the test period once and writes two lock files). To look at the results,
run `python notebooks/07b_export_dashboard_data.py` and then
`streamlit run notebooks/07_phase7_dashboard_sql.py`. Without a database, skip the export: the
dashboard reads the CSV snapshot that is already in `outputs/dashboard_data/`.

## License

MIT. See the [LICENSE](LICENSE) file. The data files are not covered by it: Zillow and FRED
have their own terms of use.
