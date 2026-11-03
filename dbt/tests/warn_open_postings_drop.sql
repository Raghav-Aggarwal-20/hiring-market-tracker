{{ config(severity='warn') }}

-- Warns when a company's open postings fall by more than half since its previous successful day.
-- A warning, not a failure: hiring freezes are real, but so are silent API changes (e.g. a board split in two).
-- Boards under 10 postings are skipped; small boards swing too much to mean anything.

with successful_days as (

    select
        company_slug,
        snapshot_date,
        open_postings,
        lag(open_postings) over (partition by company_slug order by snapshot_date) as previous_open_postings
    from {{ ref('fct_company_daily') }}
    where is_successful

)

select *
from successful_days
where snapshot_date = (select max(snapshot_date) from successful_days)
    and previous_open_postings >= 10
    and open_postings < 0.5 * previous_open_postings
