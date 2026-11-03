-- Regression test: known tricky titles must keep their expected classification.
-- Returns one row per case the current rules get wrong; any row fails the build.
-- depends_on: {{ ref('function_rules') }}

with cases as (

    select * from {{ ref('classification_cases') }}

),

actual as (

    select
        *,
        {{ data_role_family('title') }} as actual_data_role_family
    from cases

),

compared as (

    select
        title,
        department_name,
        expected_job_function,
        {{ job_function('title', 'department_name', 'actual_data_role_family') }} as actual_job_function,
        expected_data_role_family,
        actual_data_role_family,
        why
    from actual

)

select *
from compared
where actual_job_function != expected_job_function
    or coalesce(actual_data_role_family, '') != coalesce(expected_data_role_family, '')
