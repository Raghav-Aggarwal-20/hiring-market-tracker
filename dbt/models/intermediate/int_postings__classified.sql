-- Business rules: data-role family, job function, workplace type, US location, seniority, pay usability.
-- Each rule was prototyped against real titles first (see docs/learning_log.md, Hour 4).

with postings as (

    select * from {{ ref('int_postings__unioned') }}

),

function_rules as (

    select * from {{ ref('function_rules') }}

),

data_roles as (

    select
        *,
        -- Role phrases: the data word sits directly before the job noun, so "Database Research Scientist"
        -- and "Engineer, Data Visualization" don't match. First match wins.
        case
            when regexp_contains(lower(title), r'\banalytics engineer') then 'analytics_engineering'
            when regexp_contains(lower(title), r'\bdata scien(ce|tist)|\bdecision scien') then 'data_science'
            when regexp_contains(lower(title), r'\bdata (platform |infrastructure )?engineer\b') then 'data_engineering'
            when regexp_contains(lower(title), r'\bbusiness intelligence\b|\bbi (analyst|developer|engineer)') then 'bi'
            when regexp_contains(lower(title), r'\b(data|analytics|insights?|reporting|product|marketing|growth|people|hr|bi)( and \w+)? analyst') then 'data_analyst'
            when regexp_contains(lower(title), r'\b(business|operations|strategy|revenue|sales operations|bizops|gtm|finance|financial|fp&a|pricing)( & \w+| and \w+)?( operations)? analyst') then 'business_analyst'
            -- Fallback: analytics as the subject of the job, unless the title is an engineering/product/sales role.
            when regexp_contains(lower(title), r'\banalytics\b|\bdata (governance|operations|specialist|quality|products? analyst)\b|\b(people|hr|employee|workforce)\b.*\bdata\b')
                and not regexp_contains(lower(title), r'\b(software|backend|frontend|full ?stack|systems engineer|reliability|security|infrastructure|platform|product manag\w*|product management|product marketing|engineering manager|manager i+, engineering|partnerships?|account executive|account manager|sales engineer|solutions?|architect|engineer)\b')
                then 'analytics_general'
        end as data_role_family
    from postings

),

-- Lowest-priority-number rule wins; title first, department only when the title matches nothing.
function_by_title as (

    select p.posting_key, p.snapshot_date, r.job_function
    from data_roles as p
    inner join function_rules as r on regexp_contains(lower(p.title), r.pattern)
    qualify row_number() over (partition by p.posting_key, p.snapshot_date order by r.priority) = 1

),

function_by_department as (

    select p.posting_key, p.snapshot_date, r.job_function
    from data_roles as p
    inner join function_rules as r on regexp_contains(lower(p.department_name), r.pattern)
    qualify row_number() over (partition by p.posting_key, p.snapshot_date order by r.priority) = 1

),

classified as (

    select
        p.*,
        p.data_role_family is not null and p.data_role_family != 'business_analyst' as is_data_role,

        case
            when p.data_role_family is not null and p.data_role_family != 'business_analyst' then 'data_analytics'
            else coalesce(t.job_function, d.job_function, 'other')
        end as job_function,
        case
            when p.data_role_family is not null and p.data_role_family != 'business_analyst' then 'data_rule'
            when t.job_function is not null then 'title'
            when d.job_function is not null then 'department'
            else 'none'
        end as job_function_source,

        -- Company-provided field first (Greenhouse custom metadata or Ashby workplaceType), then location text.
        case
            when regexp_contains(lower(p.workplace_type_raw), r'remote') then 'remote'
            when regexp_contains(lower(p.workplace_type_raw), r'hybrid|flexible') then 'hybrid'
            when regexp_contains(lower(p.workplace_type_raw), r'on-?site|in office') then 'onsite'
            when regexp_contains(lower(p.location_name), r'remote|distributed') then 'remote'
            when regexp_contains(lower(p.location_name), r'hybrid') then 'hybrid'
            when regexp_contains(lower(p.location_name), r'in-office|on-?site') then 'onsite'
            else 'unknown'
        end as workplace_type,

        -- US if any listed location is in the US. NULL when the text names no place at all ("Remote", "Hybrid").
        case
            when p.country is not null then p.country in ('United States', 'USA')
            when regexp_contains(lower(p.location_name), r'united states|\busa?\b|u\.s\.|\bus-|\bnyc\b|san francisco|new york|seattle|boston|denver|austin|chicago|washington|menlo park|oakland|atlanta|nashville|los angeles|palo alto|mountain view|san jose|sunnyvale|portland|miami|dallas|houston|philadelphia|pittsburgh|raleigh|salt lake|phoenix|san diego|minneapolis|bay area')
                -- State abbreviations are matched case-sensitively after a comma ("Austin, TX").
                or regexp_contains(p.location_name, r',\s*(AL|AK|AZ|AR|CA|CO|CT|DE|FL|GA|HI|ID|IL|IN|IA|KS|KY|LA|ME|MD|MA|MI|MN|MS|MO|MT|NE|NV|NH|NJ|NM|NY|NC|ND|OH|OK|OR|PA|RI|SC|SD|TN|TX|UT|VT|VA|WA|WV|WI|WY|DC)\b')
                then true
            when p.location_name is null
                or regexp_contains(lower(trim(p.location_name)), r'^(remote|hybrid|distributed|in-office|onsite|on-site)$')
                then null
            else false
        end as is_us,

        -- Individual-contributor level from title words. "Manager" is left out: it's an IC title in sales and product.
        case
            when regexp_contains(lower(p.title), r'\bintern(ship)?\b|\bco-?op\b|\bfellow\b') then 'intern'
            when regexp_contains(lower(p.title), r'\b(vp|vice president|chief|head of)\b') then 'executive'
            when regexp_contains(lower(p.title), r'\bdirector\b') then 'director'
            when regexp_contains(lower(p.title), r'\b(staff|principal|distinguished)\b') then 'staff_plus'
            when regexp_contains(lower(p.title), r'\b(senior|sr\.?)\b') then 'senior'
            when regexp_contains(lower(p.title), r'\b(junior|jr\.?|entry|new grad|graduate|associate)\b') then 'entry'
            else 'unspecified'
        end as seniority,

        case
            when p.salary_min is null then null
            when p.salary_interval = '1 HOUR' or regexp_contains(lower(p.salary_label), r'hour') then 'hourly'
            when p.salary_interval = '1 MONTH' then 'monthly'
            when regexp_contains(lower(p.salary_label), r'\bote\b|on.?target') then 'ote'
            else 'annual'
        end as pay_basis

    from data_roles as p
    left join function_by_title as t using (posting_key, snapshot_date)
    left join function_by_department as d using (posting_key, snapshot_date)

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
