-- Today's open postings at active companies: the main table behind the dashboard.
-- "Today" per company is its latest successful extract, so one failed board shows yesterday's view, not zero.

select
    p.*,
    c.company_name,
    c.peer_group
from {{ ref('dim_posting') }} as p
inner join {{ ref('dim_company') }} as c using (company_slug)
where p.is_open
    and c.is_active
