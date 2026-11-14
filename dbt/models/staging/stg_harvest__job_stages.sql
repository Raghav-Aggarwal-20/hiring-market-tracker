-- One row per stage in each job's interview plan. SYNTHETIC.

select
    cast(json_value(payload, '$.id') as int64) as stage_id,
    cast(json_value(payload, '$.job_id') as int64) as job_id,
    json_value(payload, '$.name') as stage_name,
    cast(json_value(payload, '$.priority') as int64) as stage_order
from {{ source('raw', 'harvest_job_stages') }}
