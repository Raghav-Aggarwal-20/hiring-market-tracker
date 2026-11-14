-- One row per Harvest application. SYNTHETIC data; real Harvest would land in the same shape.

select
    cast(json_value(payload, '$.id') as int64) as application_id,
    cast(json_value(payload, '$.candidate_id') as int64) as candidate_id,
    -- Harvest allows several jobs per application; prospects aside, it is always one.
    cast(json_value(payload, '$.jobs[0].id') as int64) as job_id,
    json_value(payload, '$.status') as status,
    cast(json_value(payload, '$.current_stage.id') as int64) as current_stage_id,
    json_value(payload, '$.source.public_name') as source_name,
    json_value(payload, '$.rejection_reason.name') as rejection_reason,
    json_value(payload, '$.rejection_reason.type.name') as rejection_type,
    timestamp(json_value(payload, '$.applied_at')) as applied_at,
    timestamp(json_value(payload, '$.rejected_at')) as rejected_at
from {{ source('raw', 'harvest_applications') }}
where not cast(json_value(payload, '$.prospect') as bool)
