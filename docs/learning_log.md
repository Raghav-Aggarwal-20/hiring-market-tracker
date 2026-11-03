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
