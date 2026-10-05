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
| 4 | Modeling table with six features | SQL done and verified, notebook being updated |
| 5 | Modeling on the validation folds | In progress |
| 6 | Evaluation on the test period | In progress |
| 7 | Dashboard | In progress |

Results of the modeling phases are added here only after they have been re-run on the
corrected pipeline below.

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
| Validation folds | 11 expanding-window folds, validation years 2010 to 2020 |
| Rate change vs decline, 12-month lag, quarter level | r = -0.145 on 82 quarters, 95% interval -0.351 to +0.074 (it includes zero) |
| Does price momentum lead rate changes? | At most weak evidence. With rate data only through Train, the correlation is about 0.12 at leads of 4 and 14 months (12-month block-bootstrap 95% intervals 0.005 to 0.222 and 0.009 to 0.236). It is 0.26 at 14 months when rate data after Train are included, and the difference comes from the latest 14 months. |

The label counts are computed twice, in pandas (notebook 01, Section 8) and in SQL
(`sql/006_checks.sql`, check 6a), and the two agree exactly. An independent pandas
implementation of the same pipeline in the team repository produces the same 164,460
Train rows, with identical features and labels.

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
- **A script splitter broken by prose.** Splitting a SQL file on `;` breaks on semicolons
  inside comments and `DO` blocks. The notebooks now send each file to the database whole.

## Limits

- The rate change is one national number per quarter, shared by about 3,000 counties, so the
  170,000 county-quarter rows are **not** independent evidence. The honest sample size for the
  rate link is the number of quarters, about 82.
- Zillow revises past values in each new file, so figures drift slightly with the data version.
- Counties with no Train history are scored using what the model learned from other counties.
- The modeling phases will choose models on the validation folds and score the test period
  once. An earlier version of this project compared models on the test period directly. That
  is not repeated here.

## Repository layout

```
sql/                   001 to 006 plus 003b, 004b and 005b, each safe to re-run
notebooks/             01 ingest, 02 split and folds, 03 to 06 analysis and modeling
outputs/               figures
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

## License

MIT. See the [LICENSE](LICENSE) file. The data files are not covered by it: Zillow and FRED
have their own terms of use.
