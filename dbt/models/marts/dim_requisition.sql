-- One row per Greenhouse requisition (Harvest jobs.id). A requisition can have several public postings, often one
-- per location, so it is open while any posting is open and closes with its last one.

select
    safe_cast(internal_job_id as int64) as job_id,
    company_slug,
    array_agg(title order by published_date, posting_key limit 1)[offset(0)] as title,
    array_agg(job_function order by published_date, posting_key limit 1)[offset(0)] as job_function,
    count(*) as n_postings,
    min(published_date) as published_date,
    logical_or(is_open) as is_open,
    if(logical_or(is_open), null, max(closed_date)) as closed_date
from {{ ref('dim_posting') }}
where ats = 'greenhouse' and internal_job_id is not null
group by 1, 2
