# Wholesale Account Health (dbt + BigQuery)

A dbt project that answers two questions for a wholesale distributor:

1. **Which accounts have quietly stopped ordering, and how much were they worth?** (revenue at risk)
2. **How much was ordered but never shipped?** (potential unfilled revenue)

It rebuilds the logic of a Python pipeline I had already validated, as tested and documented SQL models. A parity test proves the dbt version reproduces the Python results to the dollar.

**Stack:** BigQuery (free sandbox) · dbt Core 1.12 · sqlfluff · GitHub Actions · Power BI

> Status: models, tests and CI are done. Dashboard and published docs site are next. See [PROJECT_PLAN.md](PROJECT_PLAN.md).

## Results

| | Sunbelt Wholesale Foods (synthetic) | Online Retail II (real UK giftware wholesaler) |
|---|---|---|
| Order lines, raw → kept | 3,421 → 3,406 | 1,044,848 → 776,596 |
| Accounts | 30 | 5,852 |
| Dormant accounts (no order in 90+ days) | 9 | 2,967 |
| Revenue at risk in dormant accounts | $199,027 | £3,302,544 |
| Potential unfilled revenue | $16,368 | not measurable |
| **Total revenue opportunity** | **$215,395** | **£3,302,544** |

How to read these numbers:

- **Revenue at risk is not lost revenue.** It is what the now-dormant accounts bought during the period. It sizes the win-back list; it does not forecast what comes back.
- **Online Retail II covers two years and many one-time buyers**, so half its accounts are dormant by the 90-day rule. For a business like this, the next step would be to separate repeat accounts from one-off buyers before calling anyone.
- **"Not measurable" is not zero.** Online Retail II has no shipped quantities, so the fulfillment analysis leaves it out instead of reporting £0.

## What the data taught me

| Problem found in the data | Why it matters | How the project handles it |
|---|---|---|
| The workbook's two sheets repeat the same nine days (22,523 rows) | Counting both would double nine days of sales | Staging keeps those days from one sheet; a test proves both copies match row for row, including repeated rows |
| Returns and cancellations (18,390 lines) | A late return makes a dormant account look recently active | Excluded with reason `return_or_cancellation` |
| 22.5% of lines have no customer | They cannot be assigned to an account; grouping them would invent a giant fake customer | Excluded with reason `missing_account`, and counted |
| 11,812 lines are exact copies of another line | Double-counted revenue | Only lines where every column matches are dropped; the same product at a different quantity on one invoice is kept |
| Postage, fees, manual adjustments (2,838 lines) | Not product demand; they make accounts look healthier than they are | Excluded with reason `non_merchandise`; the code list lives in `dbt_project.yml` |
| Sunbelt: two date formats, 60 spellings of 30 account names, two SKU formats | Splits one account or product into several | Standardized in staging |
| Sunbelt: 20 lines with no shipped quantity | Revenue cannot be computed | Assumed shipped in full, and flagged so the assumption can be counted |

Nothing is silently deleted. Every line gets an `exclusion_reason` (or none), and `mart_data_quality` shows the count for each reason.

## How it is built

```
CSV files ──(scripts/load_raw.py)──▶ BigQuery `raw` (all text, no cleaning)
                                          │
staging (views)        stg_online_retail__invoice_lines · stg_sunbelt__order_lines
                       rename, convert types, trim, flag. No business rules.
                                          │
intermediate (views)   int_order_lines__unioned   both sources in one shape
                       int_order_lines__cleaned   business rules + exclusion_reason
                                          │
marts (tables)         fct_order_lines · dim_accounts · dim_products
                       mart_account_recency · mart_fulfillment_gaps
                       mart_data_quality · mart_opportunity_summary
```

Design choices worth knowing:

- **Staging never removes rows.** It only makes them readable. That keeps one place (the cleaning model) responsible for every business decision.
- **Business rules classify instead of filtering.** That is what makes the data quality report possible.
- **Thresholds are variables** (`dormant_days: 90`, `at_risk_days: 45`), so a different business can change them without touching SQL.
- **No incremental models.** The BigQuery sandbox does not allow the statements they need, and at one million rows a full rebuild takes seconds.
- **Marts have enforced contracts:** if a column's name or type changes, the build fails instead of breaking a dashboard.

## Tests

- **Parity test:** the Sunbelt figures must equal the Python pipeline's ($215,395 = $199,027 + $16,368) within $1.
- **Reconciliation tests:** no rows lost or added between raw, staging and the cleaned model; mart totals must agree with the fact table.
- **Sheet overlap test:** the repeated nine days must be identical in both sheets, counting repeated rows.
- **Column tests** on every model: unique and filled keys, allowed values, and links from the fact table to its dimensions.

Run `dbt build` to build everything and run every test.

## How to run it

```bash
python -m venv .venv && source .venv/bin/activate     # Windows: .venv\Scripts\Activate.ps1
pip install -r requirements.txt
gcloud auth application-default login                  # Google credentials, never committed

# 1. Online Retail II: download the .xlsx from https://archive.ics.uci.edu/dataset/502/online+retail+ii into data/
python scripts/convert_online_retail_xlsx.py data/online_retail_II.xlsx data

# 2. Load the raw tables into BigQuery (safe to rerun: it replaces them)
python scripts/load_raw.py --project <your-gcp-project-id>

# 3. dbt
mkdir -p ~/.dbt && cp profiles.example.yml ~/.dbt/profiles.yml
export GCP_PROJECT_ID=<your-gcp-project-id>
dbt build
sqlfluff lint models tests
```

## CI setup

Every pull request runs sqlfluff and `dbt build` in a separate `dbt_ci` dataset. The dbt job needs two repository secrets (Settings → Secrets and variables → Actions):

- `GCP_PROJECT_ID`: the Google Cloud project ID.
- `GCP_KEYFILE_JSON`: the JSON key of a service account with the roles **BigQuery Data Editor** and **BigQuery Job User**.

Without the secrets, the dbt job is skipped and only the lint runs.

## What I would do next

- Incremental models and source freshness checks, on a project with live data and a paid warehouse.
- Separate repeat accounts from one-time buyers before measuring dormancy.
- A semantic layer so the dashboard and ad-hoc queries share one definition of each metric.

## Data sources and attribution

Online Retail II: Chen, D. (2012). UCI Machine Learning Repository. https://doi.org/10.24432/C5CG6D. Licensed under CC BY 4.0. Amounts are in pounds sterling.

Sunbelt Wholesale Foods is synthetic data I generated to be deliberately messy. Amounts are in US dollars.
