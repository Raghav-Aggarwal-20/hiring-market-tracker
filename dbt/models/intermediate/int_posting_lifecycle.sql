-- One row per posting ever seen: when it was first and last seen, and whether it has closed.
-- A posting counts as closed only when its company had a successful extract after the posting's last sighting,
-- so a failed API call never looks like mass closures.

with sightings as (

    select
        posting_key,
        company_slug,
        min(snapshot_date) as first_seen_date,
        max(snapshot_date) as last_seen_date,
        count(distinct snapshot_date) as days_seen
    from {{ ref('int_postings__unioned') }}
    group by posting_key, company_slug

),

successful_days as (

    select company_slug, snapshot_date
    from {{ ref('int_company_extract_days') }}
    where is_successful

),

latest_success as (

    select company_slug, max(snapshot_date) as latest_success_date
    from successful_days
    group by company_slug

),

-- The first successful day the posting was missing from is the day it closed.
closures as (

    select s.posting_key, min(d.snapshot_date) as closed_date
    from sightings as s
    inner join successful_days as d
        on d.company_slug = s.company_slug
        and d.snapshot_date > s.last_seen_date
    group by s.posting_key

)

select
    s.posting_key,
    s.company_slug,
    s.first_seen_date,
    s.last_seen_date,
    s.days_seen,
    c.closed_date,
    c.closed_date is null as is_open,
    -- Observed lifespan only: postings open before tracking began are left-censored at first_seen_date.
    date_diff(coalesce(c.closed_date, l.latest_success_date), s.first_seen_date, day) as days_observed_open
from sightings as s
left join closures as c using (posting_key)
left join latest_success as l using (company_slug)
