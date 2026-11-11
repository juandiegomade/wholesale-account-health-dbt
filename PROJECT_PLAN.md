# Project Plan: Wholesale Account Health — an Analytics Engineering Showcase

**Owner:** Juan Diego Machado · **Version:** 1.1 (updated after weekend 1) · **Date:** November 10, 2026
**Repo name (planned):** `wholesale-account-health-dbt`

> This document is the brief for anyone (person or AI assistant) helping build this project. Section 12 has specific instructions for AI assistants.

---

## 1. Context

**Who I am.** Industrial engineer with 4+ years in B2B/CPG sales (Customer Development Executive at Colgate-Palmolive: wholesale accounts, sell-in/sell-out, days on hand). Skills: SQL (PostgreSQL), Python (pandas), Power BI (strongest), Tableau, Excel. I'm moving into **analytics engineering** and looking for a remote analytics role.

**What already exists.** A working Python pipeline (`ops-pipeline`) that audits a distributor's order export and produces a PDF report. Its logic has been validated on two datasets:

| Dataset | Rows | Result the Python pipeline produces |
|---|---|---|
| Sunbelt Wholesale Foods (synthetic, built to be messy) | 3,421 raw → 3,406 clean | **$215,395** revenue opportunity = $199,027 at risk in dormant accounts + $16,368 potential unfilled revenue |
| UCI Online Retail (real, UK giftware wholesaler) | 541,909 rows in the full dataset | Exposed real-data bugs: returns, null customer IDs, no fulfillment tracking |

**What this project is.** Rebuild that pipeline's transformation logic as a **dbt project on BigQuery**: version-controlled, tested, documented, with CI and a BI layer on top. The point is to prove analytics engineering skills with logic that is already validated, not to invent new analysis.

**Who it's for.**
1. Hiring managers for analytics engineering / BI / analytics roles (primary).
2. Later, the reusable model layer for my freelance "Commercial Operations Analyst" build tier.

---

## 2. Goals and definition of done

The project is done when all of this is true:

- [ ] Public GitHub repo with a clear README written as a case study
- [ ] Raw data loads into BigQuery with one rerunnable command
- [ ] dbt models in three layers (staging → intermediate → marts), all documented
- [ ] Data tests on every model; `dbt build` passes with zero failures
- [ ] **Parity test:** the dbt marts reproduce the Python pipeline's Sunbelt result ($215,395; $199,027 + $16,368) within $1
- [ ] dbt docs (with lineage graph) published as a public link
- [ ] GitHub Actions runs lint + `dbt build` on every pull request
- [ ] Power BI dashboard on the marts, with screenshots in the README
- [ ] One LinkedIn post summarizing the project

---

## 3. Scope

**In scope:** two sources, conformed into one model; account recency segmentation (active / at risk / dormant); fulfillment-gap analysis where the source tracks it; a data quality mart; tests; docs; CI; one dashboard.

**Out of scope (on purpose):** orchestration tools (Airflow, Dagster), Docker, incremental models, streaming, paid tools, machine learning, any real client data.

---

## 4. Constraints

- **$0 budget.** dbt Core (open source), BigQuery free sandbox, GitHub free, Power BI Desktop (free).
- **BigQuery sandbox limits:** about 10 GB storage and 1 TB of queries per month; tables expire after 60 days; DML (MERGE / INSERT / UPDATE) is not allowed. Therefore: only `view` and `table` materializations (no `incremental`), and the raw load must be fully rerunnable.
- **Time:** about 5 hours per weekend, for 4 weekends. Weekdays are reserved for job applications.
- **Language:** everything in English (code, docs, README).
- **Data license:** the UCI dataset must be cited in the README (check its license on the UCI page; it is published for reuse with attribution).

---

## 5. Data sources

### 5.1 UCI Online Retail II (real)
- Source: UCI Machine Learning Repository, dataset 502, "Online Retail II" (Daqing Chen). Transactions from a UK online giftware wholesaler, **Dec 2009 – Dec 2011**, 1,067,371 rows. Licensed CC BY 4.0 (confirm on the UCI page before publishing).
- Delivered as one .xlsx with **two sheets** ("Year 2009-2010", "Year 2010-2011"). `scripts/convert_online_retail_xlsx.py` turns them into two CSVs without cleaning anything; the CSVs are not committed.
- Columns: `Invoice, StockCode, Description, Quantity, InvoiceDate, Price, Customer ID, Country` (loaded as `invoice, stock_code, description, quantity, invoice_date, price, customer_id, country`, all STRING).
- Known issues, measured on the full file:
  - **Sheet overlap:** the 2009-2010 sheet repeats 2010-12-01 to 2010-12-09 (22,523 rows), identical row for row to the start of the 2010-2011 sheet. Staging keeps those days from the 2010-2011 sheet only; a singular test proves both copies are identical. Expected staging rows: **1,044,848**.
  - Cancellations: 19,494 rows on invoices starting with `C`; 6 rows on `A` invoices (bad-debt adjustments). 22,950 rows have negative quantity, 3,457 of them not on a `C` invoice.
  - 243,007 rows (22.8%) with null `customer_id` (excluded and counted, never grouped into a fake "null" customer).
  - 6,207 rows with `price <= 0`.
  - 34,335 exact duplicate rows (all eight columns equal). Staging flags them (`is_exact_duplicate`); the dedup rule is decided in weekend 2 (see section 13).
  - Non-merchandise stock codes (postage `POST`/`DOT`, fees, manual adjustments `M`, discounts `D`, vouchers, test codes): flagged in staging (`is_non_merchandise`), list kept in `dbt_project.yml` vars. Whether they count as revenue is decided in weekend 2.
  - Untrimmed descriptions (213,035) and lowercase stock codes (3,471): fixed in staging.
  - **No fulfillment tracking:** the fulfillment-gap analysis must report "not measurable" for this source rather than "$0".

### 5.2 Sunbelt Wholesale Foods (synthetic)
- 3,421 rows, CSV, small enough to commit to the repo as a dbt seed or raw file.
- Columns: `order_id, order_date, account_name, sku, product, qty_ordered, qty_fulfilled, unit_price, fulfillment_status, channel`
- Deliberately messy: duplicate lines, mixed date formats, inconsistent account-name casing, inconsistent SKU prefixes, missing `qty_fulfilled`.
- **Has fulfillment tracking:** `fulfillment_status` in (`PARTIAL`, `UNFULFILLED`, blank).

---

## 6. Business logic to reproduce (from the validated Python pipeline)

Apply in this order:

1. **Deduplicate** on (`order_id`, `sku`, `account_name`, `order_date`), keep one row.
2. **Parse dates;** drop rows whose date can't be parsed (count them).
3. **Drop unattributed rows:** null or blank account/customer ID (count them).
4. **Normalize** account names (trim, consistent casing) and SKUs (uppercase; standardize the `SKU-` prefix).
5. **Exclude returns/cancellations:** negative quantity (count them). Reason: a late return would otherwise make a dormant account look recently active.
6. **Fulfillment:** if `qty_fulfilled` is missing, assume it equals `qty_ordered` and count how many rows relied on that assumption.
7. **Revenue** = `qty_fulfilled × unit_price`. **Unfilled revenue** = `max(qty_ordered − qty_fulfilled, 0) × unit_price`, counted only on lines with status `PARTIAL` or `UNFULFILLED`.
8. **Recency per account:** `as_of_date` = the latest order date in that source (NOT today's date; these are historical datasets). `days_since_last_order = as_of_date − last_order_date`.
9. **Segmentation** (dbt vars, defaults from the Python config): `> 90` days = Dormant, `> 45` days = At Risk, else Active.
10. **Headline metrics:** revenue at risk = total revenue of Dormant accounts; potential unfilled revenue = sum of unfilled revenue; total opportunity = the two added.

**Wording rule (important):** these are "revenue at risk" and "potential unfilled revenue", never "lost revenue". Use that language in column names, docs and the dashboard.

---

## 7. Architecture

```
CSV files ──(scripts/load_raw.py)──▶ BigQuery dataset `raw`
                                         │
                          dbt (BigQuery adapter)
                                         │
   staging (views)        stg_online_retail__invoice_lines, stg_sunbelt__order_lines
        │                 → rename to one schema, cast types, no business logic
   intermediate (views)   int_order_lines__unioned  (adds source_system column)
        │                 int_order_lines__cleaned  (rules 1–7 above, plus an exclusion_reason column)
   marts (tables)         fct_order_lines           (one row per clean order line)
                          dim_accounts              (one row per account per source)
                          dim_products
                          mart_account_recency      (rules 8–9, one row per account)
                          mart_fulfillment_gaps     (by SKU; only sources with fulfillment tracking)
                          mart_data_quality         (rows excluded, by reason and source)
                          mart_opportunity_summary  (headline metrics per source)
                                         │
                          Power BI Desktop (connects to marts)
```

**Datasets in BigQuery:** `raw`, `dbt_dev` (personal development), `dbt_ci` (used by GitHub Actions), `analytics` (final).

---

## 8. Testing strategy

| Type | Examples |
|---|---|
| Generic tests (`schema.yml`) | `unique` + `not_null` on every primary key; `relationships` from facts to dims; `accepted_values` on `account_status` and `source_system` |
| dbt_utils tests (deferred: add `packages.yml` once `dbt deps` can run on your machine) | `unique_combination_of_columns` on the dedup key; `expression_is_true` for `revenue >= 0` and `unfilled_revenue >= 0` |
| Singular tests (`tests/`) | `assert_no_returns_in_fct_order_lines`; `assert_no_null_accounts_in_marts`; **`assert_sunbelt_parity_with_python_pipeline`** (total = 215,395 ± 1; dormant = 199,027 ± 1; unfilled = 16,368 ± 1) |
| Model contracts | Enforced contracts (column names and types) on all marts |

---

## 9. Repository structure

```
wholesale-account-health-dbt/
├── README.md                    # the case study (outline in section 11)
├── PROJECT_PLAN.md              # this document
├── data/
│   └── sunbelt_raw_export.csv   # synthetic data (Online Retail II CSVs are generated, not committed)
├── scripts/
│   ├── convert_online_retail_xlsx.py  # xlsx → two CSVs, no cleaning
│   └── load_raw.py              # rerunnable: truncates and reloads raw tables
├── dbt_project.yml
├── packages.yml                 # dbt_utils (added in weekend 3)
├── profiles.example.yml         # no credentials committed
├── models/
│   ├── staging/
│   ├── intermediate/
│   └── marts/
├── tests/                       # singular tests, incl. the parity test
├── macros/
├── dashboards/                  # .pbix + screenshots
├── .sqlfluff
└── .github/workflows/ci.yml     # lint + dbt build on pull requests
```

**Conventions:** BigQuery Standard SQL; lowercase SQL; CTEs, no nested subqueries; model prefixes `stg_`, `int_`, `fct_`, `dim_`, `mart_`; one feature per branch, merged by pull request (so the history shows real PRs with CI runs); never commit credentials.

---

## 10. Timeline (4 weekends)

| Weekend | Deliverables | Done when |
|---|---|---|
| **1. Foundation** | Repo; BigQuery datasets; `load_raw.py` for both sources; dbt project initialized; sources declared; staging models | `dbt build --select staging` passes; raw row counts match the source files |
| **2. Modeling** | Intermediate + all marts; logic rules 1–10 implemented | `mart_opportunity_summary` shows the Sunbelt numbers |
| **3. Quality** | All tests incl. parity; contracts; docs for every model and column; GitHub Actions CI; docs site published | Parity test passes; a PR shows green CI; docs link works |
| **4. Delivery** | Power BI dashboard; README case study; LinkedIn post | Someone outside the project understands it in 2 minutes from the README |

---

## 11. README outline (the case study)

1. **The problem** (3 sentences): distributors lose revenue to accounts that quietly stop ordering and to short-shipped orders, and spreadsheets don't show either.
2. **What I built:** architecture diagram + stack.
3. **What the data taught me:** the real-data issues (returns making dormant accounts look active, null customers, no fulfillment tracking) and how each is handled and tested.
4. **Parity with the original Python pipeline:** how the parity test proves the dbt version reproduces validated results.
5. **Results:** dashboard screenshots; headline metrics per source with honest caveats.
6. **How to run it:** five commands.
7. **What I'd do next:** incremental models on a paid project, a semantic layer, source freshness for live data.
8. **Data sources and attribution.**

---

## 12. Instructions for AI assistants helping on this project

- Work one weekend's deliverables at a time; don't jump ahead.
- Use BigQuery Standard SQL and current stable versions of `dbt-core` and `dbt-bigquery`. No incremental models (sandbox has no DML).
- Don't add tools outside this plan (no Airflow, Docker, Dagster, paid services) without asking.
- Keep business logic exactly as in section 6. If something seems wrong, flag it; don't silently change it. The parity test is the arbiter.
- Explain *why* for each modeling decision in one or two sentences. I'm learning analytics engineering, and I need to be able to defend every choice in an interview.
- Prefer small, reviewable changes, each ending with a command I can run to verify it.
- Never put credentials in code or commits.

---

## 13. Open decisions

- **Online Retail dedup rule (weekend 2):** drop exact duplicates only (all columns equal) or apply the Python key (invoice, stock code, customer, date). The Python key would also merge different prices or quantities on the same invoice line, so exact duplicates is the safer default; the parity test is unaffected because it runs on Sunbelt.
- **Non-merchandise lines (weekend 2):** exclude postage, fees and adjustments from account revenue (likely) or keep them; either way they get an `exclusion_reason`.

- dbt docs hosting: GitHub Pages (preferred) vs. committing a static `index.html`.
- Dashboard: Power BI (strongest skill, default) vs. also a live Claude Data dashboard on the same BigQuery marts.
- Whether to add a third source later (e.g., a public retail dataset) to strengthen the "conforming multiple sources" story.

---

## 14. Status log

- **Weekend 1 (Nov 2026):** scaffold, loaders, sources, both staging models, generic + singular tests, sqlfluff clean. Staging validated in BigQuery on sample raw tables. Next: load the full raw data from a machine with Google credentials and run `dbt build --select staging`.
