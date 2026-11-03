-- One row per company per extraction attempt. Already typed at load; staged so models never read raw directly.

select
    run_id,
    snapshot_date,
    extracted_at,
    company_slug,
    ats,
    status,
    http_status,
    n_postings,
    duration_ms,
    error
from {{ source('raw', 'extract_runs') }}
