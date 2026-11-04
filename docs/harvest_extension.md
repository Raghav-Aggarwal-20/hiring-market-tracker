# Extending this pipeline to internal recruiting data

This project reads Greenhouse's public **Job Board API**, which only exposes open postings. An in-house recruiting analytics team works from the authenticated **Harvest API** (jobs, applications, candidates, stages, offers) and from the HRIS (Workday) for hires. This note covers what would change to support that, and what would stay the same.

## The join key is already here

Every Greenhouse posting in `raw.job_postings` carries two IDs besides the post ID:

| Job Board field | Harvest equivalent | Coverage today (Elastic, 2026-11-04) |
|---|---|---|
| `id` | `job_posts.id` | 424 / 424 |
| `internal_job_id` | `jobs.id` (the requisition record that applications attach to) | 424 / 424 |
| `requisition_id` | `jobs.requisition_id` (the company's own req number, often shared with the HRIS) | 424 / 424 |

Across all 19 Greenhouse boards on the same day, `internal_job_id` is present on 4,123 of 4,133 postings (99.8%) and `requisition_id` on 3,850 (93%).

So the public posting history built here could be joined to internal applications without fuzzy matching: `job_board.internal_job_id = harvest.jobs.id`. `stg_greenhouse__postings` keeps both IDs.

## What stays the same

- **Raw layer pattern:** land each endpoint's JSON as-is in a partitioned table with a run log, and type it in staging. Harvest responses would go to `raw.harvest_<endpoint>` with the same `snapshot_date`, `extracted_at`, `run_id` and `payload JSON` columns.
- **Completeness and freshness tests:** "every expected endpoint loaded today" replaces "every active company extracted today".
- **Classification seeds:** function and role-family rules keep working on Harvest job titles and departments.
- **Never infer a change from a failed load:** the lifecycle rule (a failed extract never closes a posting) applies equally to applications.

## What changes

### Extraction
- **Auth:** Harvest needs an API key with endpoint-level permissions, stored in Secret Manager rather than a GitHub secret, and created with read-only scopes for the endpoints in use. Greenhouse has been revising Harvest's versions and auth; check the current API docs before building.
- **Incremental loads:** the job board is small enough to snapshot in full. Applications and candidates are not, so pull with `updated_after` set to the last successful run and merge in dbt. A weekly full refresh catches deletes.
- **Pagination and rate limits:** Harvest pages results and enforces a per-key rate limit. The existing retry-with-backoff session handles 429s; it would also need to follow the pagination links.

### Models (sketch)

| Layer | Model | Grain | Purpose |
|---|---|---|---|
| staging | `stg_harvest__jobs`, `__applications`, `__job_stages`, `__offers`, `__candidates` | one row per API object | type and rename; hash or drop PII |
| intermediate | `int_application_stage_history` | application × stage entered | stage transitions, from daily snapshots of `current_stage` (same technique as the posting lifecycle) or from Greenhouse webhooks |
| marts | `fct_applications` | application | source, outcome, days in process |
| marts | `fct_requisition_funnel` | job × stage | counts and pass-through rates by stage |
| marts | `fct_time_to_fill` | job | req opened → offer accepted, and → start date once joined to Workday |
| marts | `dim_job` | job | this project's posting history (first public date, days posted, reposts) joined on `internal_job_id` |

### Metrics this unlocks
- Time to fill and time to hire, against an SLA by department or level.
- Stage pass-through rates and where candidates stall.
- Offer acceptance rate, overall and by level and location.
- Source effectiveness: hires per application by source.
- Req health: reqs open longer than X days with no applications in the last 14 days. This is the internal version of this project's "slowest to fill" card.

### Linking to Workday
A hire appears in Greenhouse as an accepted offer and in Workday as a hire event. The usual link is the requisition ID shared by both systems (the `requisition_id` above), backed up by candidate email matched inside the warehouse and then dropped. That join enables:
- time from offer to start,
- 90-day and one-year retention by source, recruiter and interview loop,
- one headcount number that recruiting and HR both report from.

## Governance for candidate data

The public data in this project has no personal information. Harvest data does, so the design adds:

- **Column-level security** with BigQuery policy tags on names, emails, phone numbers and compensation, with access limited to the recruiting-ops group.
- **Hashing in staging:** candidate email is hashed (SHA-256 with a salt kept in Secret Manager) before it reaches any mart. The raw dataset is restricted to the pipeline's service account.
- **Row-level security** by department for hiring-manager dashboards.
- **Retention:** raw candidate payloads expire on the same schedule as the ATS's own data-retention policy, using table partition expiry.
- **Tests:** a dbt test that fails if any mart column matches an email or phone-number pattern.

## What I'd build first

1. `stg_harvest__jobs` and `stg_harvest__applications` with incremental loads.
2. `fct_requisition_funnel`, the most-requested recruiting view and the easiest to validate against Greenhouse's built-in reports.
3. The Workday hire join, once the requisition-ID mapping is confirmed with the HRIS team.
