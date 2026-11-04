# Metric definitions

Every number on the dashboards comes from one of the columns below. If a dashboard and this page disagree, this page and the dbt model it names are the reference.

Grain notation: **posting** means one row per open posting today (`rpt_postings_current`); **company-day** means one row per company per snapshot (`fct_company_daily`).

## Volume

| Metric | Definition | Source | Notes |
|---|---|---|---|
| Open postings | Postings present in today's snapshot at active companies | `count(*)` on `rpt_postings_current` | Inactive companies (`is_active = false` in the seed) are excluded. |
| Companies hiring | Distinct companies with at least one open posting | `count(distinct company_slug)` | |
| New postings | Postings whose first sighting is this snapshot | `fct_company_daily.new_postings` | NULL on a company's first tracked day (everything is "new" then) and on failed extract days. |
| Closed postings | Postings first missing on this day, where the company's extract succeeded | `fct_company_daily.closed_postings` | A failed extract never closes postings. |
| Net change | Open postings minus open postings on the company's previous successful day | `fct_company_daily.net_change` | NULL on the first tracked day and on failed days. |

## Role mix

| Metric | Definition | Source | Notes |
|---|---|---|---|
| Data & analytics roles | Postings whose title matches one of six role families: analytics engineering, data science, data engineering, BI, data analyst, analytics (general) | `is_data_role` | Business analyst titles are tagged (`data_role_family = 'business_analyst'`) but not counted. Rules: `macros/classify.sql`, regression-tested by `seeds/classification_cases.csv`. |
| Function share | Share of a company's open postings in each function | `rpt_company_summary.share_<function>` | Functions come from `seeds/function_rules.csv`, applied in priority order to the title, then the department. Shares are 0 to 1. The eight function shares plus the unshown "other" share sum to 1. |
| Seniority | Level parsed from the title: executive, director, staff+, senior, entry, intern, not stated | `seniority` | "Manager" alone is not treated as a level, because it covers both people managers and individual contributors. |

## Workplace and location

| Metric | Definition | Source | Notes |
|---|---|---|---|
| Remote share of stated | Remote postings ÷ postings that state remote, hybrid or onsite | computed from `workplace_type` | Postings that don't say are excluded from the denominator, so this is not "% of all postings". |
| Workplace not stated | Postings with no workplace in the ATS field or the location text ÷ all postings | `workplace_type = 'unknown'` | Read it as a data-quality signal. Elastic and Okta are 100% not stated. |
| US location | `true` if the country is US, or the location text matches a US city or state; `NULL` if there is no location | `is_us` | |

## Time

| Metric | Definition | Source | Notes |
|---|---|---|---|
| Posting age (reported) | Days from the ATS publish date to the posting's last sighting, or its close date | `reported_age_days` | Uses Greenhouse `first_published` and Ashby `publishedAt`. A repost resets it. |
| Median posting age | Median of reported age across the postings in view | `percentile_cont(reported_age_days, 0.5)` | An exact median, not an approximation. |
| Days observed open | Days from first sighting in this pipeline to close date (or the latest successful extract) | `days_observed_open` | Left-censored: postings that opened before tracking began start counting at the first snapshot. Use reported age until there are weeks of history. |

## Pay

| Metric | Definition | Source | Notes |
|---|---|---|---|
| Usable pay | Pay range that is USD, annual, between $20K and $2M, with min ≤ max, and not a sales role | `is_pay_usable` | Excludes $0.01 and $1 placeholders, hourly rates labeled as salary, typos such as a $179M maximum, and sales on-target earnings. |
| Pay midpoint | (min + max) ÷ 2 for usable pay; otherwise NULL | `salary_midpoint_usd` | Uses the first pay range when a posting lists several. |
| Median salary midpoint | Median pay midpoint across a company's usable postings | `rpt_company_summary.median_salary_midpoint_usd` | |

## Pipeline health

| Metric | Definition | Source | Notes |
|---|---|---|---|
| Status | "OK" if the company's latest extract succeeded, otherwise "Needs attention" | `rpt_pipeline_health.status_label` | Backed by the `assert_all_active_companies_extracted` test, which fails the daily build. |
| Postings extracted | Rows returned by the company's API on the latest run | `postings_extracted` | From `raw.extract_runs`, before any dbt filtering. |
| Coverage shares | Share of a company's open postings with pay, usable pay, a stated workplace, a classified function, and a location | `share_with_pay`, `share_pay_usable`, `share_workplace_not_stated`, `share_function_other`, `share_location_not_stated` | Tracks how complete each company's postings are, not how healthy the pipeline is. |
