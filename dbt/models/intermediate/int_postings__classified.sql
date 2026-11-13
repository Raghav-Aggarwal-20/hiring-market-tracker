-- Business rules: data-role family, job function, workplace type, US location, seniority, pay usability.
-- Title rules live in macros/classify.sql so tests/assert_classification_cases.sql runs the exact same logic.
-- depends_on: {{ ref('function_rules') }}

with postings as (

    select * from {{ ref('int_postings__unioned') }}

),

data_roles as (

    select
        *,
        {{ data_role_family('title') }} as data_role_family
    from postings

),

classified as (

    select
        *,
        data_role_family is not null and data_role_family != 'business_analyst' as is_data_role,
        {{ job_function('title', 'department_name', 'data_role_family') }} as job_function,
        case
            when data_role_family is not null and data_role_family != 'business_analyst' then 'data_rule'
            when {{ function_from_rules('title') }} is not null then 'title'
            when {{ function_from_rules('department_name') }} is not null then 'department'
            else 'none'
        end as job_function_source,

        -- Company-provided field first (Greenhouse custom metadata, Ashby workplaceType, Workday remoteType), then location text.
        case
            when regexp_contains(lower(workplace_type_raw), r'remote') then 'remote'
            when regexp_contains(lower(workplace_type_raw), r'hybrid|flex') then 'hybrid'
            when regexp_contains(lower(workplace_type_raw), r'on-?site|in office') then 'onsite'
            when regexp_contains(lower(location_name), r'remote|distributed') then 'remote'
            when regexp_contains(lower(location_name), r'hybrid') then 'hybrid'
            when regexp_contains(lower(location_name), r'in-office|on-?site') then 'onsite'
            else 'unknown'
        end as workplace_type,

        -- US if any listed location is in the US. NULL when the text names no place at all ("Remote", "Hybrid").
        case
            when country is not null then country in ('United States', 'USA', 'United States of America')
            when regexp_contains(lower(location_name), r'united states|\busa?\b|u\.s\.|\bus-|\bnyc\b|san francisco|new york|seattle|boston|denver|austin|chicago|washington|menlo park|oakland|atlanta|nashville|los angeles|palo alto|mountain view|san jose|sunnyvale|portland|miami|dallas|houston|philadelphia|pittsburgh|raleigh|salt lake|phoenix|san diego|minneapolis|bay area')
                -- State abbreviations are matched case-sensitively after a comma ("Austin, TX").
                or regexp_contains(location_name, r',\s*(AL|AK|AZ|AR|CA|CO|CT|DE|FL|GA|HI|ID|IL|IN|IA|KS|KY|LA|ME|MD|MA|MI|MN|MS|MO|MT|NE|NV|NH|NJ|NM|NY|NC|ND|OH|OK|OR|PA|RI|SC|SD|TN|TX|UT|VT|VA|WA|WV|WI|WY|DC)\b')
                then true
            when location_name is null
                or regexp_contains(lower(trim(location_name)), r'^(remote|hybrid|distributed|in-office|onsite|on-site)$')
                then null
            else false
        end as is_us,

        -- Individual-contributor level from title words. "Manager" is left out: it's an IC title in sales and product.
        case
            when regexp_contains(lower(title), r'\bintern(ship)?\b|\bco-?op\b|\bfellow\b') then 'intern'
            when regexp_contains(lower(title), r'\b(vp|vice president|chief|head of)\b') then 'executive'
            when regexp_contains(lower(title), r'\bdirector\b') then 'director'
            when regexp_contains(lower(title), r'\b(staff|principal|distinguished)\b') then 'staff_plus'
            when regexp_contains(lower(title), r'\b(senior|sr\.?)\b') then 'senior'
            when regexp_contains(lower(title), r'\b(junior|jr\.?|entry|new grad|graduate|associate)\b') then 'entry'
            else 'unspecified'
        end as seniority,

        case
            when salary_min is null then null
            when salary_interval = '1 HOUR' or regexp_contains(lower(salary_label), r'hour') then 'hourly'
            when salary_interval = '1 MONTH' then 'monthly'
            when regexp_contains(lower(salary_label), r'\bote\b|on.?target') then 'ote'
            else 'annual'
        end as pay_basis

    from data_roles

),

final as (

    select
        *,
        -- Value checks catch what labels miss: placeholders ($0.01, $1), hourly rates labelled as salary, typos.
        -- Sales is excluded because some companies report OTE under a "salary" label.
        coalesce(
            salary_currency = 'USD'
            and pay_basis = 'annual'
            and salary_min >= 20000
            and salary_max <= 2000000
            and salary_min <= salary_max
            and job_function != 'sales',
            false
        ) as is_pay_usable
    from classified

)

select * from final
