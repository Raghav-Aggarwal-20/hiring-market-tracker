{{ config(severity='warn') }}

-- Warns when more than 25% of open postings fall outside every function rule,
-- a sign that a new company's titles need rules added to seeds/function_rules.csv.

select
    countif(job_function = 'other') as other_postings,
    count(*) as open_postings,
    safe_divide(countif(job_function = 'other'), count(*)) as other_share
from {{ ref('fct_postings_current') }}
having safe_divide(countif(job_function = 'other'), count(*)) > 0.25
