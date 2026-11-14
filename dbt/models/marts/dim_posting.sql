-- One row per posting ever seen: attributes as of its latest sighting, plus its lifecycle.

with lifecycle as (

    select * from {{ ref('int_posting_lifecycle') }}

),

latest_sighting as (

    select * from {{ ref('int_postings__classified') }}

)

select
    l.posting_key,
    p.ats,
    p.company_slug,
    p.posting_id,
    p.internal_job_id,
    p.requisition_id,
    p.title,
    p.department_name,
    p.team_name,
    p.location_name,
    p.job_function,
    p.job_function_source,
    p.data_role_family,
    p.is_data_role,
    p.workplace_type,
    p.is_us,
    p.seniority,
    p.employment_type,
    p.job_url,

    date(p.published_at) as published_date,
    p.req_open_date,
    -- "Reported" because a repost resets the ATS publish date; this is age since the latest publish.
    date_diff(coalesce(l.closed_date, l.last_seen_date), date(p.published_at), day) as reported_age_days,

    p.salary_min,
    p.salary_max,
    p.salary_currency,
    p.pay_basis,
    p.is_pay_usable,
    if(p.is_pay_usable, (p.salary_min + p.salary_max) / 2, null) as salary_midpoint_usd,

    l.first_seen_date,
    l.last_seen_date,
    l.days_seen,
    l.closed_date,
    l.is_open,
    l.days_observed_open

from lifecycle as l
inner join latest_sighting as p
    on p.posting_key = l.posting_key
    and p.snapshot_date = l.last_seen_date
