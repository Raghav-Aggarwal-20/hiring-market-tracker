-- Fails when an active company's extract has failed on its last three snapshot days in a row
-- (dead board token, ATS migration, long outage). Returns one row per affected company.
-- One or two bad days are tolerated: Workday boards rate-limit GitHub's shared runner IPs now and then
-- (429/521 on Nov 14 and 16), and int_posting_lifecycle only counts closures on successful days, so a
-- missed day leaves that company's postings open rather than faking closures.
-- Reads only fct_company_daily, which has no downstream models: a failure fails the job and alerts,
-- but dbt build doesn't skip the dashboard tables, so the other companies still refresh.

with recent as (

    select
        company_slug,
        is_successful,
        row_number() over (partition by company_slug order by snapshot_date desc) as days_ago
    from {{ ref('fct_company_daily') }}
    where is_active

)

select company_slug
from recent
where days_ago <= 3
group by company_slug
having countif(not is_successful) = 3
