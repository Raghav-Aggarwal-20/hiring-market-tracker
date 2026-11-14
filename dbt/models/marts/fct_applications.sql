-- One row per application with how far it got. SYNTHETIC funnel joined to a real requisition.
-- Harvest keeps only the current stage, and a rejected application stays on the stage it was rejected at,
-- so the current stage is also the furthest stage reached. Hires have no current stage: they reached the last one.

with stages as (

    select * from {{ ref('stg_harvest__job_stages') }}

),

last_stage as (

    select job_id, max(stage_order) as stage_order from stages group by job_id

)

select
    a.application_id,
    a.job_id,
    r.title,
    r.job_function,
    a.source_name,
    a.status,
    a.status = 'hired' as is_hired,
    coalesce(s.stage_order, if(a.status = 'hired', l.stage_order, null)) as furthest_stage_order,
    a.rejection_reason,
    a.rejection_type,
    date(a.applied_at) as applied_date,
    date(a.rejected_at) as rejected_date,
    o.offer_status,
    date(o.resolved_at) as offer_resolved_date
from {{ ref('stg_harvest__applications') }} as a
inner join {{ ref('dim_requisition') }} as r on r.job_id = a.job_id
left join stages as s on s.stage_id = a.current_stage_id
left join last_stage as l on l.job_id = a.job_id
left join {{ ref('stg_harvest__offers') }} as o on o.application_id = a.application_id
