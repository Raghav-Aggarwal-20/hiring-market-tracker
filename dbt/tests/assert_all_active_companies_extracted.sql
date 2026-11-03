-- Fails when an active company has no successful extract on the latest snapshot day
-- (dead board token, ATS migration, API outage). Returns one row per missing company.

with latest_day as (

    select max(snapshot_date) as snapshot_date
    from {{ ref('int_company_extract_days') }}

),

latest_status as (

    select d.company_slug, d.is_successful
    from {{ ref('int_company_extract_days') }} as d
    inner join latest_day using (snapshot_date)

)

select
    c.company_slug,
    c.ats,
    (select snapshot_date from latest_day) as snapshot_date,
    coalesce(s.is_successful, false) as is_successful
from {{ ref('companies') }} as c
left join latest_status as s using (company_slug)
where c.is_active
    and not coalesce(s.is_successful, false)
