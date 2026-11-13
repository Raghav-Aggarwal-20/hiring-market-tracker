-- One row per Workday posting per snapshot day: JSON fields pulled out, renamed and typed. No business logic.
-- The search list only has title and location text. Start date, req ID, country and workplace come from the
-- detail call, which the extractor makes once, on a posting's first sighting; they're carried to every day here.

with source as (

    select * from {{ source('raw', 'job_postings') }}
    where ats = 'workday'

),

details as (

    select
        company_slug,
        posting_id,
        json_value(payload, '$.location') as location_name,
        json_value(payload, '$.country.descriptor') as country,
        json_value(payload, '$.remoteType') as workplace_type_raw,
        json_value(payload, '$.timeType') as employment_type,
        json_value(payload, '$.jobReqId') as requisition_id,
        timestamp(json_value(payload, '$.startDate')) as published_at,
        json_value(payload, '$.externalUrl') as job_url
    from source
    where json_value(payload, '$.startDate') is not null
    qualify row_number() over (partition by company_slug, posting_id order by snapshot_date desc) = 1

),

renamed as (

    select
        concat(ats, '|', company_slug, '|', posting_id) as posting_key,
        snapshot_date,
        extracted_at,
        ats,
        company_slug,
        posting_id,
        json_value(payload, '$.title') as title,
        -- "2 Locations" when there are several; the detail call's primary location is preferred below.
        json_value(payload, '$.locationsText') as locations_text
    from source

)

select
    r.* except (locations_text),
    coalesce(d.location_name, r.locations_text) as location_name,
    d.country,
    d.workplace_type_raw,
    d.employment_type,
    d.requisition_id,
    d.published_at,
    d.job_url
from renamed as r
left join details as d using (company_slug, posting_id)
