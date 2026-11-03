-- One row per Greenhouse posting per snapshot day: JSON fields pulled out, renamed and typed. No business logic.

with source as (

    select * from {{ source('raw', 'job_postings') }}
    where ats = 'greenhouse'

),

renamed as (

    select
        concat(ats, '|', company_slug, '|', posting_id) as posting_key,
        snapshot_date,
        extracted_at,
        ats,
        company_slug,
        posting_id,

        json_value(payload, '$.requisition_id') as requisition_id,
        json_value(payload, '$.title') as title,
        -- Every posting has exactly one department (profiled 2026-11-03).
        json_value(payload, '$.departments[0].name') as department_name,
        json_value(payload, '$.location.name') as location_name,

        -- Workplace type is a per-company custom field; these are the names in use, values interpreted downstream.
        (
            select coalesce(json_value(m, '$.value'), json_value(m, '$.value[0]'))
            from unnest(json_query_array(payload, '$.metadata')) as m
            where json_value(m, '$.name') in ('Workplace Type', 'Location Type', 'Working Model Eligibility')
            limit 1
        ) as workplace_type_raw,

        -- Elastic-only custom field: when the requisition opened, which can predate the posting.
        (
            select safe_cast(json_value(m, '$.value') as date)
            from unnest(json_query_array(payload, '$.metadata')) as m
            where json_value(m, '$.name') = 'Requisition open date'
            limit 1
        ) as req_open_date,

        timestamp(json_value(payload, '$.first_published')) as published_at,
        timestamp(json_value(payload, '$.updated_at')) as updated_at,
        json_value(payload, '$.absolute_url') as job_url

    from source

)

select * from renamed
