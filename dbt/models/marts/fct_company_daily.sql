-- One row per company per snapshot day: open, new and closed postings.
-- Failed extract days stay in the table with NULL counts, so a gap is visible instead of looking like zero.

with company_days as (

    select * from {{ ref('int_company_extract_days') }}

),

postings as (

    select * from {{ ref('int_postings__classified') }}

),

lifecycle as (

    select * from {{ ref('int_posting_lifecycle') }}

),

open_counts as (

    select
        company_slug,
        snapshot_date,
        count(*) as open_postings,
        countif(is_data_role) as open_data_roles,
        countif(workplace_type = 'remote') as open_remote_postings
    from postings
    group by company_slug, snapshot_date

),

new_counts as (

    select company_slug, first_seen_date as snapshot_date, count(*) as new_postings
    from lifecycle
    group by company_slug, first_seen_date

),

closed_counts as (

    select company_slug, closed_date as snapshot_date, count(*) as closed_postings
    from lifecycle
    where closed_date is not null
    group by company_slug, closed_date

),

first_days as (

    select company_slug, min(snapshot_date) as first_tracked_date
    from company_days
    where is_successful
    group by company_slug

),

joined as (

    select
        d.snapshot_date,
        d.company_slug,
        d.is_successful,
        d.snapshot_date = f.first_tracked_date as is_baseline_day,
        if(d.is_successful, coalesce(o.open_postings, 0), null) as open_postings,
        if(d.is_successful, coalesce(o.open_data_roles, 0), null) as open_data_roles,
        if(d.is_successful, coalesce(o.open_remote_postings, 0), null) as open_remote_postings,
        -- On the first tracked day every posting is "first seen", so new is undefined rather than inflated.
        case
            when not d.is_successful or d.snapshot_date = f.first_tracked_date then null
            else coalesce(n.new_postings, 0)
        end as new_postings,
        if(d.is_successful, coalesce(c.closed_postings, 0), null) as closed_postings
    from company_days as d
    left join first_days as f using (company_slug)
    left join open_counts as o using (company_slug, snapshot_date)
    left join new_counts as n using (company_slug, snapshot_date)
    left join closed_counts as c using (company_slug, snapshot_date)

)

select
    *,
    -- Change since the previous successful day; NULL on the baseline day and on failed days.
    open_postings - lag(open_postings) over (
        partition by company_slug, is_successful order by snapshot_date
    ) as net_change
from joined
