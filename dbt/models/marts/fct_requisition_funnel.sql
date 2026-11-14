-- One row per job per interview stage: how many applications reached it and what share of the previous stage
-- moved on. SYNTHETIC funnel.

with reached as (

    select
        s.job_id,
        s.stage_order,
        s.stage_name,
        countif(a.furthest_stage_order >= s.stage_order) as applications_reached
    from {{ ref('stg_harvest__job_stages') }} as s
    inner join {{ ref('fct_applications') }} as a on a.job_id = s.job_id
    group by 1, 2, 3

)

select
    *,
    safe_divide(
        applications_reached,
        lag(applications_reached) over (partition by job_id order by stage_order)
    ) as pass_through_rate
from reached
