-- One row per company per snapshot day: did the run that produced that day's data succeed?
-- A rerun replaces the day's postings, so the latest attempt is the one that counts.

select
    company_slug,
    snapshot_date,
    status = 'success' as is_successful,
    n_postings,
    extracted_at
from {{ ref('stg_extract_runs') }}
qualify row_number() over (partition by company_slug, snapshot_date order by extracted_at desc) = 1
