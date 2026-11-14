-- One row per requisition with applications: public posting dates (real) next to the hire (SYNTHETIC).
-- Time to fill runs from the ATS publish date, which resets on a repost, so treat it as a lower bound.

with hires as (

    select job_id, offer_resolved_date as offer_accepted_date
    from {{ ref('fct_applications') }}
    where is_hired

),

jobs as (

    select job_id, count(*) as applications
    from {{ ref('fct_applications') }}
    group by 1

)

select
    j.job_id,
    r.title,
    r.job_function,
    r.n_postings,
    j.applications,
    r.published_date,
    r.closed_date,
    r.is_open,
    h.offer_accepted_date,
    case
        when h.job_id is not null then 'filled'
        when r.is_open then 'open'
        else 'closed_unfilled'
    end as requisition_status,
    date_diff(h.offer_accepted_date, r.published_date, day) as days_to_fill
from jobs as j
inner join {{ ref('dim_requisition') }} as r on r.job_id = j.job_id
left join hires as h on h.job_id = j.job_id
