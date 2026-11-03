-- One row per tracked company, from the seed, plus when tracking began.

with companies as (

    select * from {{ ref('companies') }}

),

first_tracked as (

    select company_slug, min(snapshot_date) as first_tracked_date
    from {{ ref('int_company_extract_days') }}
    where is_successful
    group by company_slug

)

select
    c.company_slug,
    c.company_name,
    c.ats,
    c.peer_group,
    c.is_active,
    f.first_tracked_date
from companies as c
left join first_tracked as f using (company_slug)
