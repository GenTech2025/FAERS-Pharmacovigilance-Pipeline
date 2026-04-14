# Capstone Project Plan — FDA Drug Adverse Event Analytics Pipeline

## Problem Statement

Drug adverse event reporting is a cornerstone of post-market pharmacovigilance. The FDA's Adverse Event Reporting System (FAERS) collects millions of reports from patients, healthcare providers, and manufacturers about suspected side effects and medication errors. Despite being publicly available, this data is released as raw quarterly flat files that are difficult to query and analyze at scale.

This project builds a fully automated, end-to-end batch data pipeline that ingests FAERS quarterly data, stores it in a cloud data lake, models it in a data warehouse, and surfaces insights through an interactive dashboard — answering questions like:
- Which drugs are most frequently associated with serious adverse events?
- How have adverse event report volumes trended over time?
- What are the most common reported reactions by patient age group and gender?
- Which drug manufacturers generate the most reports?

---

## Dataset: FDA FAERS (FDA Adverse Event Reporting System)

| Attribute        | Detail |
|-----------------|--------|
| **Source**       | U.S. Food & Drug Administration — https://fis.fda.gov/extensions/FPD-QDE-FAERS/FPD-QDE-FAERS.html |
| **Domain**       | Healthcare / Pharmacovigilance / Drug Safety |
| **Update cadence** | Quarterly (Q1–Q4 each year) |
| **Format**       | ASCII `.txt` delimited flat files (zipped quarterly archives) |
| **Volume**       | ~20–30 million total records (2004–present), ~1–2M new records/quarter |
| **License**      | Public domain (U.S. government open data, no sign-up required) |

### FAERS Schema (7 relational files per quarter)

| File          | Contents |
|---------------|----------|
| `DEMO`        | Patient demographics — age, sex, weight, country, report date |
| `DRUG`        | Drug information — name, role (primary suspect, concomitant, etc.) |
| `REAC`        | Adverse reactions reported (MedDRA preferred terms) |
| `OUTC`        | Outcome codes — hospitalisation, death, disability, etc. |
| `RPSR`        | Report source — healthcare provider, patient, manufacturer |
| `THER`        | Drug therapy start/end dates |
| `INDI`        | Drug indication (what the drug was prescribed for) |

The primary key linking all files is `primaryid`.

---

## Tech Stack

| Layer                       | Technology | Justification |
|-----------------------------|-----------|---------------|
| **Cloud**                   | GCP (Google Cloud Platform) | Course default; BigQuery + GCS are first-class |
| **Infrastructure as Code**  | Terraform | Provision GCS bucket, BigQuery datasets, IAM — reproducible infra |
| **Containerisation**        | Docker / Docker Compose | Consistent local dev and Kestra worker environments |
| **Workflow Orchestration**  | Kestra | Covered in course (Module 2); YAML-native pipelines |
| **Data Lake**               | Google Cloud Storage (GCS) | Raw quarterly FAERS zips stored as-is in `raw/` prefix |
| **Data Warehouse**          | BigQuery | Partitioned + clustered tables for efficient analytical queries |
| **Transformations**         | dbt (BigQuery adapter) | Staging → Intermediate → Mart layer (Module 4 pattern) |
| **Dashboard**               | Looker Studio | Native BigQuery integration; shareable public links |

---

## End-to-End Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                         ORCHESTRATION (Kestra)                        │
│                                                                        │
│  ┌──────────┐   ┌─────────────┐   ┌──────────────┐   ┌───────────┐  │
│  │ Download │──▶│ Upload to   │──▶│ Load raw to  │──▶│ Trigger   │  │
│  │ FAERS    │   │ GCS (raw/)  │   │ BigQuery     │   │ dbt run   │  │
│  │ ZIP      │   │             │   │ staging      │   │           │  │
│  └──────────┘   └─────────────┘   └──────────────┘   └───────────┘  │
│       │                                                     │         │
│  (quarterly trigger)                                        ▼         │
│                                                    ┌─────────────┐   │
│                                                    │ Dashboard   │   │
│                                                    │ refresh     │   │
│                                                    └─────────────┘   │
└──────────────────────────────────────────────────────────────────────┘

FDA FAERS Site                GCS                      BigQuery
     │                         │                           │
     │  quarterly .zip         │  raw/faers/YYYYQN/*.txt   │  stg_faers_*
     │─────────────────────────▶  ──────────────────────────▶  fact_adverse_events
                                                              dim_drugs
                                                              dim_patients
                                                              mart_drug_signals
```

---

## Pipeline Stages (Detailed)

### Stage 1 — Infrastructure Provisioning (Terraform)
- Create GCS bucket: `de-zoomcamp-faers-lake`
- Create BigQuery datasets: `faers_raw`, `faers_staging`, `faers_mart`
- Set up GCP service account with least-privilege IAM roles

### Stage 2 — Data Ingestion (Kestra, Batch/Quarterly)

**Kestra flow: `faers_quarterly_ingest`**

1. Parameterised by `year` and `quarter` (e.g. `2024`, `Q3`)
2. Download FAERS ZIP from FDA public HTTPS endpoint
3. Unzip and validate file presence (DEMO, DRUG, REAC, OUTC, RPSR, THER, INDI)
4. Upload raw `.txt` files to GCS under `raw/faers/{year}{quarter}/`
5. Load each file into BigQuery `faers_raw` dataset as append-only external or native tables
6. Emit success/failure notification

**Backfill strategy**: Run the flow for all quarters from 2019 Q1 to present to seed the warehouse.

### Stage 3 — Data Warehouse Modelling (BigQuery)

**Partitioning & Clustering strategy:**

| Table | Partition | Cluster |
|-------|-----------|---------|
| `stg_faers_demographics` | `receipt_date` (monthly) | `reporter_country`, `sex` |
| `stg_faers_drugs` | `quarter` (ingestion quarter) | `drugname`, `role_cod` |
| `stg_faers_reactions` | `quarter` | `pt` (MedDRA preferred term) |
| `fact_adverse_events` | `receipt_date` (monthly) | `drugname`, `serious` |

Partitioning on `receipt_date` enables time-range queries to scan only relevant partitions. Clustering on `drugname` accelerates the most common analytical filter.

### Stage 4 — Transformations (dbt)

**Model layers:**

```
models/
├── staging/
│   ├── stg_faers_demographics.sql   -- clean + cast raw DEMO
│   ├── stg_faers_drugs.sql          -- normalise drug names (upper, trim)
│   ├── stg_faers_reactions.sql      -- deduplicate reaction terms
│   └── stg_faers_outcomes.sql       -- map outcome codes to labels
├── intermediate/
│   └── int_reports_enriched.sql     -- join demo + drug + reaction on primaryid
└── marts/
    ├── mart_drug_safety_signals.sql  -- count reports per drug, % serious
    ├── mart_reaction_trends.sql      -- monthly reaction volume by MedDRA term
    └── mart_patient_demographics.sql -- age group + gender breakdown
```

**dbt tests:** `not_null`, `unique` on `primaryid`; `accepted_values` on `sex`, `role_cod`, outcome codes.

### Stage 5 — Dashboard (Looker Studio)

**Tile 1 — Temporal trend (line chart)**
- X-axis: Month of report receipt (2019–present)
- Y-axis: Number of adverse event reports
- Breakdown: Serious vs. non-serious
- Insight: Spot surges (e.g. COVID-era drug reporting spikes)

**Tile 2 — Top drugs by adverse event count (bar chart)**
- X-axis: Drug name (top 20)
- Y-axis: Total reports / % involving serious outcomes
- Filter: Year, outcome type
- Insight: Identify drugs with high signal burden

**Tile 3 (bonus) — Reaction heatmap by patient demographics**
- Dimensions: Age group × Most common reaction term
- Insight: Which patient populations report which reaction types most

---

## Repository Structure (new standalone repo)

```
faers-adverse-events-pipeline/
├── terraform/
│   ├── main.tf          # GCS bucket + BigQuery datasets
│   ├── variables.tf
│   └── outputs.tf
├── kestra/
│   └── flows/
│       └── faers_quarterly_ingest.yaml
├── dbt/
│   └── faers_analytics/
│       ├── dbt_project.yml
│       ├── profiles.yml
│       └── models/
│           ├── staging/
│           ├── intermediate/
│           └── marts/
├── docker-compose.yml   # Local Kestra dev environment
├── .env.example
└── README.md
```

---

## Evaluation Criteria Mapping

| Criterion | Approach | Expected Score |
|-----------|----------|---------------|
| Problem description | Clear drug safety problem statement with KPIs | 4/4 |
| Cloud | GCP throughout, infra via Terraform | 4/4 |
| Data ingestion | Kestra multi-step DAG: download → GCS → BQ | 4/4 |
| Data warehouse | BigQuery with partition + cluster (justified above) | 4/4 |
| Transformations | dbt staging → intermediate → mart layers | 4/4 |
| Dashboard | Looker Studio ≥2 tiles (temporal + categorical) | 4/4 |
| Reproducibility | Terraform + Docker Compose + dbt + README with step-by-step | 4/4 |

**Target total: 28/28**

---

## Optional Enhancements (Portfolio Boosters)

- **CI/CD**: GitHub Actions running `dbt test` on PR, `terraform plan` validation
- **Data quality**: Great Expectations or dbt tests with severity thresholds
- **Makefile**: `make infra`, `make ingest`, `make transform`, `make dashboard`
- **Deduplication logic**: FAERS has known duplicate reports — implement dedup logic in dbt intermediate layer using `caseid` grouping

---

## Key Data Considerations

- FAERS data uses `$` as a delimiter in older quarters; parser must handle this
- Drug names are free-text — normalisation (uppercasing, removing brand/generic variants) is important in dbt staging
- `primaryid` is unique per report version; `caseid` links versions of the same case — the latest version per `caseid` should be used in the mart layer
- Reports prior to 2012 are in a legacy format — scope the pipeline to 2019–present for simplicity

---

*Document created: 2026-04-01*
*Zoomcamp cohort: 2026*
