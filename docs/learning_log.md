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
