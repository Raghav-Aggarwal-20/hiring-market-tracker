-- One row per active company: latest extract status and data-quality coverage, for the pipeline health page.

with latest_day as (

    select max(snapshot_date) as snapshot_date from {{ ref('fct_company_daily') }}

),

latest_runs as (

    select
        r.company_slug,
        r.status,
        r.http_status,
        r.n_postings as postings_extracted,
        r.duration_ms,
        r.extracted_at
    from {{ ref('stg_extract_runs') }} as r
    inner join latest_day as l using (snapshot_date)
    qualify row_number() over (partition by r.company_slug order by r.extracted_at desc) = 1

),

last_success as (

    select company_slug, max(snapshot_date) as last_successful_date
    from {{ ref('fct_company_daily') }}
    where is_successful
    group by company_slug

),

coverage as (

    select
        company_slug,
        safe_divide(countif(salary_min is not null), count(*)) as share_with_pay,
        safe_divide(countif(is_pay_usable), count(*)) as share_pay_usable,
        safe_divide(countif(workplace_type = 'unknown'), count(*)) as share_workplace_not_stated,
        safe_divide(countif(job_function = 'other'), count(*)) as share_function_other,
        safe_divide(countif(is_us is null), count(*)) as share_location_not_stated
    from {{ ref('fct_postings_current') }}
    group by company_slug

)

select
    c.company_slug,
    c.company_name,
    c.ats,
    {{ peer_lens('c.peer_group') }} as peer_lens,
    (select snapshot_date from latest_day) as latest_snapshot_date,
    coalesce(r.status, 'missing') as latest_status,
    case when r.status = 'success' then 'OK' else 'Needs attention' end as status_label,
    r.http_status,
    r.postings_extracted,
    r.duration_ms,
    r.extracted_at,
    s.last_successful_date,
    v.share_with_pay,
    v.share_pay_usable,
    v.share_workplace_not_stated,
    v.share_function_other,
    v.share_location_not_stated
from {{ ref('dim_company') }} as c
left join latest_runs as r using (company_slug)
left join last_success as s using (company_slug)
left join coverage as v using (company_slug)
where c.is_active
