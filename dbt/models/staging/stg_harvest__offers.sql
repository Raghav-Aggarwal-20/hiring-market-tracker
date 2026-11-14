-- One row per offer version. SYNTHETIC.

select
    cast(json_value(payload, '$.id') as int64) as offer_id,
    cast(json_value(payload, '$.application_id') as int64) as application_id,
    cast(json_value(payload, '$.job_id') as int64) as job_id,
    json_value(payload, '$.status') as offer_status,
    timestamp(json_value(payload, '$.created_at')) as created_at,
    timestamp(json_value(payload, '$.resolved_at')) as resolved_at,
    date(json_value(payload, '$.starts_at')) as starts_on
from {{ source('raw', 'harvest_offers') }}
