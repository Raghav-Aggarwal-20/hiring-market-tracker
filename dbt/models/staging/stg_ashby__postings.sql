-- One row per Ashby posting per snapshot day: JSON fields pulled out, renamed and typed. No business logic.

with source as (

    select * from {{ source('raw', 'job_postings') }}
    where ats = 'ashby'

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
        json_value(payload, '$.department') as department_name,
        json_value(payload, '$.team') as team_name,
        json_value(payload, '$.location') as location_name,
        json_value(payload, '$.address.postalAddress.addressCountry') as country,
        -- Kept raw; isRemote is true for Hybrid too, so workplaceType is the field to trust downstream.
        json_value(payload, '$.workplaceType') as workplace_type_raw,
        safe_cast(json_value(payload, '$.isRemote') as bool) as is_remote_flag,
        json_value(payload, '$.employmentType') as employment_type,
        safe_cast(json_value(payload, '$.isListed') as bool) as is_listed,

        -- At most one Salary component per posting (profiled 2026-11-03); equity and commission rarely carry amounts.
        (
            select as struct
                safe_cast(json_value(c, '$.minValue') as numeric) as min_value,
                safe_cast(json_value(c, '$.maxValue') as numeric) as max_value,
                json_value(c, '$.currencyCode') as currency,
                json_value(c, '$.interval') as pay_interval
            from unnest(json_query_array(payload, '$.compensation.summaryComponents')) as c
            where json_value(c, '$.compensationType') = 'Salary'
            limit 1
        ) as salary,

        timestamp(json_value(payload, '$.publishedAt')) as published_at,
        json_value(payload, '$.jobUrl') as job_url

    from source

),

final as (

    select
        * except (salary),
        salary.min_value as salary_min,
        salary.max_value as salary_max,
        salary.currency as salary_currency,
        salary.pay_interval as salary_interval
    from renamed

)

select * from final
