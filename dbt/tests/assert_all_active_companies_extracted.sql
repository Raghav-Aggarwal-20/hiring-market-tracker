-- Fails when an active company's extract did not succeed on the latest snapshot day
-- (dead board token, ATS migration, API outage). Returns one row per affected company.
-- Reads only fct_company_daily, which has no downstream models: a failure fails the job and alerts,
-- but dbt build doesn't skip the dashboard tables, so the other companies still refresh.
-- The extractor logs a run row for every active company, so a missing company shows up as unsuccessful.

select company_slug, snapshot_date, is_successful
from {{ ref('fct_company_daily') }}
where is_active
    and not is_successful
    and snapshot_date = (select max(snapshot_date) from {{ ref('fct_company_daily') }})
