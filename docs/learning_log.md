# Learning Log

Interview-ready notes written at the end of each hour block: what was built, why it was chosen, and one question an interviewer might ask.

## Hour 1: GCP and dbt foundation (2026-11-03)

1. **Billing instead of the BigQuery sandbox.**
   *Built:* linked a billing account (free trial) to the `hiring-market-tracker` project.
   *Why:* the sandbox blocks DML, expires every table after 60 days and caps storage at 10 GiB for the project's lifetime. A pipeline that builds history from daily snapshots can't live with a 60-day expiry.
   *Interviewer might ask:* "How did you keep costs under control?" Free-tier usage, a $1 budget alert with credits excluded so it reflects real spend, and a per-query `maximum_bytes_billed` cap in dbt. The daily project quota is locked during the free trial and gets set once the account is upgraded.

2. **Two datasets: `raw` and `analytics`.**
   *Built:* both in the US multi-region, with no table expiry.
   *Why:* the extractor writes untouched API data to `raw`, and dbt writes only to `analytics`. A bad model can be dropped and rebuilt without risking source history. Same location because BigQuery can't join across locations.
   *Interviewer might ask:* "Why keep raw data at all if you model it anyway?" Re-processing: when an API field changes or a business rule changes, I can rebuild every model from the original payloads.

3. **Least-privilege service account.**
   *Built:* `hmt-pipeline` with BigQuery Job User on the project and BigQuery Data Editor on only the two datasets.
   *Why:* the scheduled pipeline runs as a robot identity, not as me, and can't touch anything else in the project. No key exists yet; one is created only when GitHub Actions needs it.
   *Interviewer might ask:* "Why two roles instead of one?" Job User lets it *run* jobs (queries, loads) in the project; Data Editor lets it read and write *tables*. They're separate permissions, and scoping Data Editor per dataset keeps any future sensitive dataset (e.g. compensation) out of reach.

4. **Local auth via Application Default Credentials.**
   *Built:* `gcloud auth application-default login`; dbt's profile uses `method: oauth`, so `profiles.yml` holds no secrets and is committed.
   *Why:* no key files on the laptop. The same profile works in CI, where the auth action supplies credentials through the same ADC mechanism.
   *Interviewer might ask:* "How do you manage credentials across local and CI?" Personal ADC locally, the service account in CI, and secrets only in GitHub Secrets, never in the repo.

5. **Pinned, isolated tooling.**
   *Built:* a Python 3.12 virtual environment (via `uv`) with dbt-core 1.12.6 and dbt-bigquery 1.12.1 pinned in `requirements.txt`; `dbt debug` passes against BigQuery.
   *Why:* the system Python is 3.14, which the Google client libraries may not fully support yet, and CI should install exactly what runs locally.
   *Interviewer might ask:* "What does `dbt debug` actually verify?" That the project and profile files parse, required tools exist, and a real authenticated query succeeds against the warehouse.

## Hour 2: Extractor and raw layer (2026-11-03)

First full pull: 5,407 postings from 30/30 companies (19 Greenhouse, 11 Ashby) in ~19 seconds, ~3.9 MB stored.

1. **Extract-and-load only; no transformation in Python.**
   *Built:* fetchers that return each posting exactly as the API sent it (minus description HTML), stored in a `JSON` column in `raw.job_postings`.
   *Why:* ELT keeps business logic in one place (dbt SQL). When an API renames a field, I fix one staging model and can rebuild all history from the stored payloads.
   *Interviewer might ask:* "Why store raw JSON instead of a clean table?" Schema drift in the source can't break the load, and nothing is lost before I know I need it.

2. **Idempotent daily loads without DML.**
   *Built:* each day's postings are written with a load job to the `job_postings$YYYYMMDD` partition using `WRITE_TRUNCATE`. Tested: loading the same day twice left 40 rows, not 80.
   *Why:* a rerun or retry must not double-count postings. Partition replacement achieves that without `MERGE`, and load jobs are free where streaming inserts are billed.
   *Interviewer might ask:* "What happens if the job runs twice in one day?" The second run replaces that day's partition; history for other days is untouched.

3. **An extraction run log, separate from the data.**
   *Built:* `raw.extract_runs` records status, HTTP code, posting count, duration and error per company per run; it's append-only.
   *Why:* a posting disappearing should mean "closed" only if that company's extract succeeded. Without the log, a failed API call would look like hundreds of requisitions closing at once.
   *Interviewer might ask:* "How do you tell a real drop in openings from a broken pipeline?" Join to the run log: only successful runs count, and a completeness test fails when an active company has no successful run for the day.

4. **Failure isolation and retries.**
   *Built:* up to 3 retries with exponential backoff on 429/5xx, a 30-second timeout, a shape check on every response, and a per-company try/except so one broken board doesn't block the other 29. The job exits non-zero only if every company fails.
   *Why:* external APIs fail in small, temporary ways; the pipeline should degrade, not stop.
   *Interviewer might ask:* "Why not fail the whole job when one company fails?" Partial data plus a loud data-quality test is more useful than no data; the dbt test turns the partial failure into an alert.

5. **Partitioning and clustering from day one.**
   *Built:* both raw tables are partitioned by `snapshot_date` and clustered by `company_slug`.
   *Why:* nearly every query filters by date range and often by company, so BigQuery scans only the matching partitions and blocks. That keeps costs flat as history grows.
   *Interviewer might ask:* "What's the difference between partitioning and clustering?" Partitioning splits the table into separate per-day storage that a date filter can skip entirely; clustering sorts data within each partition so filters on the cluster column read fewer blocks.

## Hour 3: dbt sources, seed and staging (2026-11-03)

`dbt build` passes 24/24: 1 seed, 2 staging views, 21 tests. Staging today: 4,118 Greenhouse and 1,289 Ashby postings, no duplicates.

1. **Sources with freshness checks.**
   *Built:* `raw.job_postings` and `raw.extract_runs` declared as dbt sources; freshness warns after 30 hours and errors after 48, based on `extracted_at`.
   *Why:* models reference `source('raw', ...)` instead of hard-coded table names, which gives dbt the lineage graph, and freshness turns a silently broken schedule into a failed check.
   *Interviewer might ask:* "How would you know if the pipeline stopped running?" Source freshness fails when the newest load is older than the threshold, independent of whether any model errored.

2. **Staging does only renaming, typing and parsing.**
   *Built:* one staging view per ATS that pulls fields out of the JSON payload, casts timestamps and numbers, and normalizes names (`department_name`, `published_at`). Interpreting values ("On-Site" means onsite) is left to the intermediate layer.
   *Why:* each layer has one job, so a bug is easy to locate. Staging stays a faithful, typed mirror of the source; business rules live in one place downstream. Views cost no storage and always reflect the latest raw data.
   *Interviewer might ask:* "Where would you put the logic that decides if a job is remote, and why?" In intermediate: it combines several source fields and company-specific conventions, which is business logic, not source cleanup.

3. **Profiling before modeling.**
   *Built:* queried the raw JSON before writing each model. That found Greenhouse always has exactly one department, workplace type only exists in three companies' custom metadata (under three different names), Ashby's `isRemote` is also true for hybrid jobs, and each Ashby posting has at most one salary component.
   *Why:* those facts decided the SQL (taking `departments[0]` is safe; `workplaceType` is trusted over `isRemote`). Without profiling, they'd be guesses that quietly produce wrong numbers.
   *Interviewer might ask:* "How do you approach a source you've never seen?" Profile null rates, cardinalities and value distributions per field first, and write down the assumptions the model relies on as comments or tests.

4. **Grain and keys: one row per posting per day.**
   *Built:* `posting_key = ats|company_slug|posting_id`, tested as unique together with `snapshot_date` (dbt_utils `unique_combination_of_columns`), plus a `relationships` test from every model's `company_slug` to the seed.
   *Why:* a posting legitimately appears once per day it's open, so `posting_key` alone isn't unique. The compound key states the real grain. Including the ATS in the key prevents two systems' numeric IDs from colliding after the union.
   *Interviewer might ask:* "What's the grain of this table?" One row per posting per snapshot day, enforced by a uniqueness test on (`posting_key`, `snapshot_date`).

5. **Test severity as a design choice.**
   *Built:* most tests fail the build; the Ashby `employment_type` accepted-values test only warns.
   *Why:* a new employment type from the vendor is something to review, not a reason to stop the whole daily load. Failures are reserved for things that make numbers wrong: duplicates, missing keys, orphaned companies, min salary above max.
   *Interviewer might ask:* "How do you decide whether a test should warn or error?" Error when the data would produce an incorrect metric; warn when it's a change worth knowing about that downstream logic can tolerate.

## Hour 4: Intermediate layer, business rules and lifecycle (2026-11-03)

Built before this hour: structured Greenhouse pay (`pay_transparency=true`, 2,186 postings) alongside Ashby's. Built this hour: union, classification, a 24-case regression test, and the posting lifecycle with a unit test. `dbt build` green.

1. **Prototype rules against real data before writing SQL.**
   *Built:* the data-role and job-function rules were tested in Python against all 5,409 real titles first. A naive "title contains data/analytics" rule matched 289 titles, mostly data centers, databases and "Software Engineer, Data Platform". Role phrases ("data *scientist*", "*X* analyst") plus a guarded fallback matched 120 real data roles. The function rules leave only 1.6% of postings as "other".
   *Why:* classification errors are invisible in a chart. Reading actual matches and misses is the only way to know the precision.
   *Interviewer might ask:* "How did you validate a rule-based classifier with no labeled data?" Reviewed matches and near-misses by hand, measured the unclassified share, then froze the tricky cases as a regression test.

2. **Rules as data, tested like code.**
   *Built:* job-function rules live in a seed (`function_rules.csv`: priority, function, regex). A macro compiles them into one `CASE` at build time. The same macros feed the model and a singular test that checks 24 known titles ("Database Research Scientist" is engineering, not a data role). Breaking one rule's priority made the test fail with exactly one case.
   *Why:* analysts can edit a CSV row, and the test stops a fix for one title from silently breaking another.
   *Interviewer might ask:* "How do you stop a classification change from quietly breaking earlier decisions?" Put the known edge cases in a regression test that runs the production logic, and require it to pass in every build.

3. **Value checks beat labels for pay.**
   *Built:* `is_pay_usable` keeps only USD, annual, $20K–$2M, min ≤ max, non-sales salaries (1,747 of 2,989 postings with pay). The labels missed $0.01 and $1 placeholders, hourly rates under an "OTE or base" label, a $179M typo, and sales roles reported as OTE under "Annual Salary".
   *Why:* company-written labels are free text; numeric bounds catch what the text hides. Unusable rows are flagged, not deleted, so coverage itself is reportable.
   *Interviewer might ask:* "How do you handle unreliable source fields in a metric?" Define an explicit eligibility flag with documented rules, report how many rows pass it, and compute the metric only on those rows.

4. **Unknown is a real answer.**
   *Built:* `workplace_type` uses the company's own field first, then location text, and returns `unknown` (37% of postings) rather than assuming onsite. `is_us` is NULL when a location names no place ("Remote"). Seniority skips "manager" because Account and Product Managers are individual contributors.
   *Why:* a guessed value inflates or deflates a metric silently; an explicit unknown keeps the denominator honest.
   *Interviewer might ask:* "What's the remote share if a third of postings don't say?" Remote divided by postings with a known workplace type, with the unknown share shown next to it.

5. **Closures are inferred, so they need guarding and a unit test.**
   *Built:* `int_posting_lifecycle` closes a posting on the first *successful* extract day for its company that doesn't include it, using the run log. A dbt unit test with 5 made-up postings across a failed run and a recovery verifies the exact output, before real history exists.
   *Why:* job-board APIs don't report closures; absence is the signal, and a failed API call would otherwise look like mass closures.
   *Interviewer might ask:* "How did you test logic that needs a week of data on day one?" dbt unit tests: mocked inputs for the upstream models and an exact expected output, run in every `dbt build`.

**Time checkpoint (plan: fall back if more than 1 hour behind at the end of Hour 4):** on track. Hours 1–4 took about 4 hours, including two additions beyond the v1 plan (Greenhouse pay and the regression test). No fallback needed: Ashby stays, and the dashboard keeps 4 charts.

## Hour 5: Marts, monitoring tests and a deliberate break (2026-11-03)

Four marts built as tables (`dim_company`, `dim_posting`, `fct_company_daily`, `fct_postings_current`); totals reconcile with raw (5,409 open postings, 120 data roles). `dbt build` passes 73/73.

1. **Dimensions and facts, built as tables.**
   *Built:* `dim_posting` (one row per posting ever seen: latest attributes plus lifecycle), `dim_company`, `fct_company_daily` (company × day: open, new, closed, net change), and `fct_postings_current` (today's open postings at active companies, the dashboard's main table).
   *Why:* the marts are what BI reads. Materializing them as tables runs the regex classification once per build instead of on every dashboard click; staging and intermediate stay views because only dbt reads them.
   *Interviewer might ask:* "Why are some models views and others tables?" Views where only the pipeline reads them and freshness matters more than speed; tables where people query them repeatedly.

2. **Empty means unknown, not zero.**
   *Built:* failed extract days keep their row in `fct_company_daily` with NULL counts; `new_postings` and `net_change` are NULL on a company's first tracked day instead of counting every posting as new.
   *Why:* a zero on a failed day draws a fake collapse on a trend line, and a day-one "5,409 new postings" spike would dominate every chart.
   *Interviewer might ask:* "How do you handle the first day of a snapshot-based metric?" Treat it as a baseline: report levels, leave flows (new, closed) undefined until there's a prior day to compare against.

3. **Monitoring tests with deliberate severities.**
   *Built:* extraction completeness (error), open count falling by more than half since the previous good day (warn, boards of 10+ only), and unclassified function share over 25% (warn).
   *Why:* errors are for things that make numbers wrong (a company silently missing); warnings are for changes that might be real (a hiring freeze looks exactly like a broken API).
   *Interviewer might ask:* "How do you monitor a pipeline beyond 'did it run'?" Test the data itself: is every expected source present, did any volume move abnormally, and is the classification coverage holding.

4. **Break it on purpose.**
   *Built:* in throwaway datasets, a real extract with one board token broken plus a simulated prior day with one company inflated. Result: the completeness test failed naming the company, its 8 postings stayed open, its daily row showed NULLs, the drop test warned on the inflated company, and its fake postings closed on the right day.
   *Why:* a test that has never failed hasn't been shown to work. Running the failure end to end proves the alert and the downstream behavior together.
   *Interviewer might ask:* "How do you know your data quality checks work?" Inject the failure they're meant to catch, in an isolated environment, and check both that the alert fires and that the outputs behave correctly.

5. **The alert itself can break the product.**
   *Found:* when the completeness test failed, `dbt build` skipped `dim_company` and `fct_postings_current`, because the test read the `companies` seed and dbt skips everything downstream of a failed test's inputs. One dead board would have frozen the dashboard for all 30 companies.
   *Fixed:* the test now reads only `fct_company_daily`, which has no downstream models. Re-ran the same break: the build still fails (CI alerts), nothing is skipped, and the dashboard table refreshes with the healthy companies.
   *Interviewer might ask:* "Tell me about a bug you found in your own pipeline." This one: where a test sits in the DAG decides what it blocks, so placing it was a design decision, not an afterthought.

## Hour 6: Dashboards and automation

1. **Reporting tables shaped for the BI tool.**
   *Built:* four `rpt_` tables (`rpt_postings_current`, `rpt_company_summary`, `rpt_company_daily`, `rpt_pipeline_health`) with readable labels, a peer-group lens, and every share and median pre-computed in SQL.
   *Why:* when the dashboard only sums and filters, every tool (Data Studio, the code dashboard, a future LLM layer) shows the same number. Logic in the BI tool drifts; logic in dbt is tested and versioned.
   *Interviewer might ask:* "Where should metric logic live: the warehouse or the BI tool?" In the warehouse, close to tests and version control; BI should mostly aggregate and display.

2. **Two dashboards, one source of truth.**
   *Built:* a Google Data Studio (formerly Looker Studio) report with a peer filter, KPI row, function heatmap, workplace mix and a volume-vs-age bubble chart; plus a dashboard-as-code page (`dashboard/build.py` + Plotly) with cross-filtering, insight cards and a searchable roles table.
   *Why:* Data Studio is what most recruiting teams use; the code version is reviewable, rebuilt by CI, and shows I can ship without a BI license.
   *Interviewer might ask:* "When would you choose dashboard-as-code over a BI tool?" When the audience is fixed, the logic needs code review, or the page must be published automatically; BI tools win for ad-hoc self-service.

3. **Verify the dashboard, not just the model.**
   *Checked:* every KPI against `fct_postings_current`, and every company's count against `raw.job_postings` (0 mismatches). *Found:* BigQuery `NUMERIC` pay values were serialized as text, so sorting by pay would have been alphabetical. Fixed by casting `Decimal` to float in the build.
   *Interviewer might ask:* "How do you QA a dashboard?" Recompute headline numbers from a lower layer with independent SQL, spot-check filtered views, and check data types at every hand-off.

4. **Daily automation with GitHub Actions.**
   *Built:* `.github/workflows/daily.yml` runs at 11:00 UTC: extract → `dbt source freshness` → `dbt build` → dashboard build, authenticated with a least-privilege service account key stored as a GitHub secret. Any failed step stops the run, so a broken run never publishes a dashboard.
   *Why:* the pipeline must run without me; the JD asks to "automate recurring recruiting reports."
   *Interviewer might ask:* "How would you harden this auth?" Replace the JSON key with Workload Identity Federation so GitHub gets short-lived tokens and no long-lived key exists (planned after week 1).
