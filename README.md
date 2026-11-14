# Hiring Market Tracker

A hiring benchmark for talent acquisition and workforce planning teams. It answers three questions about a set of competing companies: where they are hiring, which functions are growing, and how long their roles stay open.

Companies publish every open role on public ATS job boards, but a board only shows what is open today. This project takes a full snapshot of 34 companies' Greenhouse, Ashby and Workday career sites every day, loads the raw JSON into BigQuery, and uses dbt to track each posting from the day it appears to the day it closes. GitHub Actions runs it daily and republishes the dashboard, where any company can be compared with its industry group.

**Dashboard:** https://raghav-aggarwal-20.github.io/hiring-market-tracker/ (rebuilt after each daily run)

![Dashboard](docs/img/dashboard.png)

## Skills used

| Area | What this project uses |
|---|---|
| SQL | BigQuery Standard SQL: CTEs, window functions, JSON parsing, partition pruning |
| Data modeling | dbt Core: staging, intermediate and mart layers; fact and dimension tables; seeds; Jinja macros |
| Data quality | 95 dbt tests (generic, custom, unit), source freshness, extraction-completeness and anomaly checks |
| Cloud (GCP) | BigQuery (partitioning, clustering, load jobs), IAM service account with least-privilege roles, query cost caps |
| Python | REST API extraction with retries and run logging, BigQuery client, pytest |
| Orchestration and CI/CD | GitHub Actions daily cron, secrets, GitHub Pages deploy |
| BI and visualization | Looker Studio (Google Data Studio), Plotly dashboard built from tested report tables |
| Recruiting data | Greenhouse, Ashby and Workday career-site APIs, requisition IDs, posting lifecycle, a Harvest-schema recruiting funnel (stage conversion, time to fill, source) |

## What it shows (snapshot of 2026-11-12)

- 5,509 open postings across 30 companies in four industry groups: data and AI, dev tools and observability, HR tech and analytics, fintech and consumer. 114 are data and analytics roles (analyst, analytics engineer, data scientist, data engineer, BI).
- Median posting age is 48 days. Sigma Computing's median is 155 days.
- Of the 3,577 postings that state a workplace, 40% are remote. 35% of postings don't state one at all; Elastic and Okta never do.

## First 10 days (2026-11-03 to 2026-11-12)

Ten daily snapshots, all 30 companies extracted successfully on every day.

- 6,282 distinct postings seen. 873 opened after the first day and 773 closed, so open postings rose from 5,409 to 5,509 (+1.8%).
- Postings go up on weekdays. The two Wednesday snapshots found 129 and 145 new postings; the Sunday snapshot found 2.
- Roles that closed had been open a long time. The median closed posting had been listed for 57 days, and 30% for more than 90. Only 45 postings opened and closed inside the 10 days.
- Steady totals hide a lot of churn. Dev tools and observability opened 340 postings and closed 331, ending almost flat (2,120 to 2,129). Fintech and consumer grew 4.1% and data and AI 2.9%.
- Sales grew the most of any function (1,644 to 1,689, +45). Engineering slipped from 1,855 to 1,848.
- Fastest growing: Grafana Labs (123 to 158) and Fivetran (161 to 191). Okta shrank the most (392 to 369, with 71 closed against 48 opened), followed by Datadog (398 to 382).

## Workday companies (added 2026-11-13)

Workday, CrowdStrike, PayPal and Mastercard post through Workday career sites. Their first snapshot added 1,925 open postings.

- Mastercard has the largest board of all 34 companies (858 postings) and the most data and analytics roles (60, against 18 at the next company).
- Their median posting age is 16 to 25 days, against 48 for the original 30. Workday's `startDate` can reset when a role is reposted, so read it as days since last posted.
- PayPal and Mastercard never state remote, hybrid or onsite; Workday does on every posting.
- They are left out of the day-by-day trend until they have their own history, so their arrival doesn't read as hiring growth.

## Recruiting funnel (Harvest schema, synthetic data)

Applications, interview stages and offers live in Greenhouse's Harvest API, which needs the company's own API key. To build and test those models anyway, `extract/harvest_synthetic.py` generates Harvest v1 objects for Fivetran's real requisitions and loads them to `raw.harvest_*` the way a real extractor would. **The requisitions and their open and close dates are real; every application, stage move and offer is invented.** Swapping the generator for a Harvest client would leave the dbt models unchanged.

- `dim_requisition`: one row per requisition, keyed on the job board's `internal_job_id`, which is Harvest's `jobs.id`.
- `fct_applications` and `fct_requisition_funnel`: how far each application got, and the pass-through rate at each stage. Harvest stores only the current stage, and a rejected application stays on the stage where it was rejected, so the current stage doubles as the furthest stage reached.
- `fct_time_to_fill`: real publish date to synthetic accepted offer. 17 of the 25 closed requisitions are filled in the synthetic data, with a median of 36 days.
- Tests check that no requisition has two hires, every hire has an accepted offer, and every application joins to a real requisition.

The rates behind the synthetic data are mine (for example, referrals pass the first screen at about twice the base rate), so these tables show that the models work, not anything about Fivetran's hiring.

## Notes from building it

- **A posting coming down is not a hire.** "Closed" means it disappeared from the board. It could have been filled, paused or cancelled, and nothing here measures hires.
- **A failed load must never look like closures.** A posting closes only on a later day when its company's extract succeeded. Otherwise one bad API call would look like a hiring freeze.
- **Day one is a baseline.** Every posting is "new" in the first snapshot, so new-posting counts start on day two.
- **Missing data is a finding.** 35% of postings don't say whether they are remote, hybrid or onsite; Elastic and Okta never do. Remote share is calculated only on postings that state it, and the gap is reported as its own metric.
- **The source systems contradict themselves.** Ashby's `isRemote` and `workplaceType` can disagree (Notion lists roles as remote and hybrid at once), so `workplaceType` wins. Ashby also returns unlisted postings (41 on 2026-11-09), which are excluded.
- **A posting is not a requisition.** Fivetran's 227 postings since 2026-11-03 belong to 142 requisitions; 35 requisitions are posted 2 to 8 times, usually once per location. Counting postings overstates openings, so the funnel is keyed on the requisition.
- **Departments don't line up across companies.** Function comes from a classification seed on department and title, tested against hand-labeled cases.
- **Workday hides the useful fields.** Its search list has titles and location text only. Posting date, requisition ID, country and remote type come from a per-posting detail call, so the extractor makes that call once, on a posting's first sighting, and dbt carries the fields forward. Only the first search page reports the real total (later pages say 0), and a listing that comes back short fails the company for the day rather than closing postings that were just missed.
- **Same-day numbers drift.** The scheduled run starts hours late, and each run overwrites that day's data, so a re-run changes the day's counts. README numbers always name their snapshot date.

## Architecture

```
Greenhouse Job Board API ─┐
Ashby Posting API ────────┼─ extract/ (Python) ── raw.job_postings      (JSON payload, partitioned by snapshot_date)
Workday career sites ─────┘                    └─ raw.extract_runs      (one row per company per run: status, count, error)
harvest_synthetic.py (SYNTHETIC, run once) ───────── raw.harvest_applications, harvest_job_stages, harvest_offers
                                                          │
                                                   dbt (analytics dataset)
          staging (views)        stg_greenhouse__postings, stg_ashby__postings, stg_workday__postings, stg_extract_runs,
                                 stg_harvest__applications, stg_harvest__job_stages, stg_harvest__offers
          intermediate (views)   unioned, classified, posting lifecycle, company extract days
          marts (tables)         dim_company, dim_posting, fct_company_daily, fct_postings_current,
                                 dim_requisition, fct_applications, fct_requisition_funnel, fct_time_to_fill
          reporting (tables)     rpt_postings_current, rpt_company_summary, rpt_company_daily, rpt_pipeline_health
                                                          │
                              ┌───────────────────────────┴──────────────────────────┐
                    dashboard/build.py → GitHub Pages                     Google Data Studio report
```

| Layer | Tooling |
|---|---|
| Extract and load | Python 3.12, `requests` with retries, BigQuery load jobs. Each day's partition is overwritten, so re-running a day is safe. |
| Warehouse | BigQuery. Raw table partitioned by `snapshot_date`, clustered by `company_slug`, payload kept as `JSON`. |
| Transform and test | dbt Core 1.12 and dbt-bigquery: 23 models, 3 seeds, 95 tests including one unit test |
| Orchestration | GitHub Actions on a daily cron plus manual dispatch |
| Auth | Service account `hmt-pipeline` with BigQuery Job User on the project and Data Editor on the `raw` and `analytics` datasets only |
| Dashboards | Static Plotly page built from the `rpt_` tables, plus a Google Data Studio (formerly Looker Studio) report |
| Cost guard | Every dbt and dashboard query is capped at 1 GB billed |

## How a posting is tracked

The job-board APIs only return what is open right now, so history comes from storing a full snapshot every day.

- **Key:** `ats | company_slug | posting_id`.
- **First seen / last seen:** the first and last snapshot that contained the posting.
- **Closed:** the first day the company was extracted successfully and the posting was missing. If a company's API call fails, its postings stay open, so an outage never looks like a hiring freeze.
- **Posting age:** days since the ATS publish date (`first_published` on Greenhouse, `publishedAt` on Ashby). This is available for every posting on day one, before any history exists.

Classification is rule-based and lives in seeds and macros, so it can be reviewed and tested:

- **Data role:** title phrases such as "data analyst" or "analytics engineer", split into six families. Business analyst titles are tagged but not counted. Full definitions: [`docs/metric_definitions.md`](docs/metric_definitions.md).
- **Function:** prioritized regex rules in `function_rules.csv`, applied to the title first and then to the department. 1.7% of postings end up as "other".
- **Workplace:** the ATS field if present, otherwise the location text, otherwise "not stated".
- **Usable pay:** USD, annual, between $20K and $2M, min ≤ max, and not a sales on-target-earnings range.

## Data quality

| Check | Severity | Catches |
|---|---|---|
| Every active company extracted today | error | a board token that broke or an API that changed |
| Open postings fell by more than half since the last good day (boards with 10+ postings) | warn | a silent partial extract |
| More than 25% of postings classified "other" | warn | rules drifting as titles change |
| 24 hand-labeled tricky titles still classify correctly | error | regressions in the regex rules |
| Source freshness on `raw.job_postings` | warn at 30h, error at 48h | the daily run not happening |
| Unit test: a posting closes only after a successful extract | error | the lifecycle logic |

I tested these by breaking them on purpose. In throwaway datasets I broke one board token and inflated another company's history. The completeness test failed and named the company, its postings stayed open, and the drop test warned. That run also exposed a bug in my own setup: the completeness test read the `companies` seed, so when it failed, dbt skipped the downstream dashboard tables for every company. It now reads only `fct_company_daily`, which has nothing downstream of it.

## Limitations

- **Job-board API, not Harvest.** These public APIs cover postings only. Applications, candidates, stages, and offers need Greenhouse's authenticated Harvest API, which takes a company's own API key. The funnel models run on synthetic Harvest-shaped data for one company (see above); [`docs/harvest_extension.md`](docs/harvest_extension.md) covers what a real Harvest connection would add: auth, incremental loads and candidate-data governance. The synthetic data is generated once, so requisitions that close after 2026-11-13 show as closed without a hire.
- **Workday coverage is new and small.** Four Workday companies (Workday, CrowdStrike, PayPal, Mastercard) joined on 2026-11-13, so their lifecycle history starts then. The career-site endpoint is the one Workday's own job pages use, not a documented API, so it could change without notice.
- **Reposted roles.** A posting that is taken down and republished under a new ID counts as a close plus a new open.
- **Reopened postings.** If the same ID disappears and comes back, it is treated as one continuous posting; `days_seen` shows the gap.
- **Inactive companies.** Setting `is_active = false` in the seed removes a company from current reporting without closing its postings.
- **Short history.** Ten days show the weekly rhythm but not a trend, and time-to-close is only measurable for postings opened after 2026-11-03. Until more weeks pass, posting age comes from the ATS publish date, which resets if a company reposts.

## Run it yourself

```bash
uv venv --python 3.12 && source .venv/bin/activate
pip install -r requirements.txt
gcloud auth application-default login          # or set GOOGLE_APPLICATION_CREDENTIALS
python -m extract                              # pull today's postings into raw
python -m extract.harvest_synthetic            # once, after a first dbt build: synthetic Harvest data
dbt deps --project-dir dbt --profiles-dir dbt
dbt build --project-dir dbt --profiles-dir dbt
python -m dashboard.build                      # writes dashboard/site/index.html
```

Settings come from environment variables with defaults: `GCP_PROJECT_ID` (hiring-market-tracker), `RAW_DATASET` (raw), `DBT_DATASET` (analytics). Companies are listed in `dbt/seeds/companies.csv`.

## Repository layout

```
extract/            API clients, BigQuery loader, run log
dbt/                models, seeds, macros, singular tests
dashboard/          build.py + template.html (static Plotly page)
docs/               metric definitions, Harvest extension
.github/workflows/  daily.yml
```
