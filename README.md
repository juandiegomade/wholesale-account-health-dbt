# Wholesale Account Health (dbt + BigQuery)

> Work in progress: weekend 1 of 4 (foundation and staging). The full case study lands in weekend 4. See [PROJECT_PLAN.md](PROJECT_PLAN.md).

A dbt project that finds two kinds of revenue a wholesale distributor can recover: **revenue at risk** in accounts that have quietly stopped ordering, and **potential unfilled revenue** from short-shipped orders. It rebuilds the transformation logic of a Python pipeline that was already validated, and a parity test will prove the dbt version reproduces its results.

**Stack:** BigQuery (free sandbox) · dbt Core 1.12 · sqlfluff · GitHub Actions (weekend 3) · Power BI (weekend 4)

## Data

| Source | Rows | Notes |
|---|---|---|
| UCI Online Retail II (real UK giftware wholesaler, 2009–2011) | 1,067,371 raw → 1,044,848 in staging | Two sheets that overlap for nine days; cancellations, null customers, exact duplicates, non-merchandise codes |
| Sunbelt Wholesale Foods (synthetic, deliberately messy) | 3,421 | Mixed date formats, inconsistent names and SKUs, has fulfillment tracking |

## How to run it

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
gcloud auth application-default login            # Google credentials, never committed

# 1. Online Retail II: download the .xlsx from https://archive.ics.uci.edu/dataset/502/online+retail+ii into data/
python scripts/convert_online_retail_xlsx.py data/online_retail_II.xlsx data

# 2. Load raw tables into BigQuery (rerunnable: truncates and reloads)
python scripts/load_raw.py --project <your-gcp-project-id>

# 3. dbt
mkdir -p ~/.dbt && cp profiles.example.yml ~/.dbt/profiles.yml
export GCP_PROJECT_ID=<your-gcp-project-id>
dbt debug
dbt build --select staging
sqlfluff lint models tests
```

## Layers

- **staging** (views): rename, cast, trim and flag. No business rules. One model per source: `stg_online_retail__invoice_lines`, `stg_sunbelt__order_lines`.
- **intermediate** (views, weekend 2): union both sources and apply the cleaning rules with an `exclusion_reason` per row.
- **marts** (tables, weekend 2): facts, dimensions, account recency, fulfillment gaps, data quality, opportunity summary.

## Data sources and attribution

Online Retail II: Chen, D. (2012). UCI Machine Learning Repository. https://doi.org/10.24432/C5CG6D. Licensed under CC BY 4.0.
