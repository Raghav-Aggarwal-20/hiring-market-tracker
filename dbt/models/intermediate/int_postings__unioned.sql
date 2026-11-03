-- Both ATS in one shape. union_relations matches columns by name and fills NULL where an ATS lacks a field.

with unioned as (

    {{ dbt_utils.union_relations(
        relations=[ref('stg_greenhouse__postings'), ref('stg_ashby__postings')],
        source_column_name=none
    ) }}

)

select * except (is_listed)
from unioned
-- An unlisted Ashby posting isn't publicly open; Greenhouse has no such flag.
where coalesce(is_listed, true)
