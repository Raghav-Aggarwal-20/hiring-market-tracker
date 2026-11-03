-- Dashboard copy of fct_company_daily with company names and the peer lens, for the trends page.

select
    d.*,
    c.company_name,
    {{ display_label('c.peer_group', 'peer_group') }} as peer_group_label,
    {{ peer_lens('c.peer_group') }} as peer_lens
from {{ ref('fct_company_daily') }} as d
inner join {{ ref('dim_company') }} as c using (company_slug)
