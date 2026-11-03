-- One row per active company with today's headline numbers, pre-computed so the dashboard needs no formulas.
-- Function shares are 0-1 fractions (format as percent in the BI tool); medians are exact, not approximate.

with postings as (

    select * from {{ ref('rpt_postings_current') }}

),

ages as (

    select distinct
        company_slug,
        percentile_cont(reported_age_days, 0.5) over (partition by company_slug) as median_age_days,
        percentile_cont(reported_age_days, 0.75) over (partition by company_slug) as p75_age_days
    from postings

),

salaries as (

    select distinct
        company_slug,
        percentile_cont(salary_midpoint_usd, 0.5) over (partition by company_slug) as median_salary_midpoint_usd
    from postings
    where is_pay_usable

),

counts as (

    select
        company_slug,
        any_value(company_name) as company_name,
        any_value(peer_group_label) as peer_group_label,
        any_value(peer_lens) as peer_lens,
        count(*) as open_postings,
        countif(is_data_role) as data_roles,
        countif(workplace_type = 'remote') as remote_postings,
        countif(workplace_type = 'hybrid') as hybrid_postings,
        countif(workplace_type = 'onsite') as onsite_postings,
        countif(workplace_type = 'unknown') as workplace_not_stated,
        safe_divide(countif(workplace_type = 'remote'), countif(workplace_type != 'unknown')) as remote_share_of_stated,
        countif(is_pay_usable) as usable_pay_postings,
        safe_divide(countif(job_function = 'engineering'), count(*)) as share_engineering,
        safe_divide(countif(job_function = 'sales'), count(*)) as share_sales,
        safe_divide(countif(job_function = 'product_design'), count(*)) as share_product_design,
        safe_divide(countif(job_function = 'customer'), count(*)) as share_customer,
        safe_divide(countif(job_function = 'marketing'), count(*)) as share_marketing,
        safe_divide(countif(job_function = 'people_hr'), count(*)) as share_people_hr,
        safe_divide(countif(job_function = 'g_and_a'), count(*)) as share_g_and_a,
        safe_divide(countif(job_function = 'data_analytics'), count(*)) as share_data_analytics
    from postings
    group by company_slug

)

select
    c.*,
    a.median_age_days,
    a.p75_age_days,
    s.median_salary_midpoint_usd
from counts as c
left join ages as a using (company_slug)
left join salaries as s using (company_slug)
