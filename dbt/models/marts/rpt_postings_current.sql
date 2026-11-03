-- Dashboard copy of fct_postings_current: same rows, plus readable labels and a peer lens for filters.

select
    *,
    {{ display_label('job_function', 'job_function') }} as job_function_label,
    {{ display_label('workplace_type', 'workplace_type') }} as workplace_label,
    {{ display_label('seniority', 'seniority') }} as seniority_label,
    {{ display_label('data_role_family', 'data_role_family') }} as data_role_family_label,
    {{ display_label('peer_group', 'peer_group') }} as peer_group_label,
    {{ peer_lens('peer_group') }} as peer_lens,
    case when is_us then 'US' when is_us is false then 'Outside US' else 'Not stated' end as us_label
from {{ ref('fct_postings_current') }}
