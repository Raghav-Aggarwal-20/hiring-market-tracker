{#- Classification rules as reusable SQL expressions, so the model and the regression test run the exact same logic. -#}

{% macro data_role_family(title) %}
    -- Role phrases: the data word sits directly before the job noun, so "Database Research Scientist"
    -- and "Engineer, Data Visualization" don't match. First match wins.
    case
        when regexp_contains(lower({{ title }}), r'\banalytics engineer') then 'analytics_engineering'
        when regexp_contains(lower({{ title }}), r'\bdata scien(ce|tist)|\bdecision scien') then 'data_science'
        when regexp_contains(lower({{ title }}), r'\bdata (platform |infrastructure )?engineer\b') then 'data_engineering'
        when regexp_contains(lower({{ title }}), r'\bbusiness intelligence\b|\bbi (analyst|developer|engineer)') then 'bi'
        when regexp_contains(lower({{ title }}), r'\b(data|analytics|insights?|reporting|product|marketing|growth|people|hr|bi)( and \w+)? analyst') then 'data_analyst'
        when regexp_contains(lower({{ title }}), r'\b(business|operations|strategy|revenue|sales operations|bizops|gtm|finance|financial|fp&a|pricing)( & \w+| and \w+)?( operations)? analyst') then 'business_analyst'
        -- Fallback: analytics as the subject of the job, unless the title is an engineering/product/sales role.
        when regexp_contains(lower({{ title }}), r'\banalytics\b|\bdata (governance|operations|specialist|quality|products? analyst)\b|\b(people|hr|employee|workforce)\b.*\bdata\b')
            and not regexp_contains(lower({{ title }}), r'\b(software|backend|frontend|full ?stack|systems engineer|reliability|security|infrastructure|platform|product manag\w*|product management|product marketing|engineering manager|manager i+, engineering|partnerships?|account executive|account manager|sales engineer|solutions?|architect|engineer)\b')
            then 'analytics_general'
    end
{% endmacro %}


{% macro function_from_rules(text) %}
    {#- Compiles the function_rules seed into one CASE expression, in priority order (first match wins). -#}
    {%- if execute -%}
        {%- set rules = run_query("select job_function, pattern from " ~ ref('function_rules') ~ " order by priority") -%}
        case
        {%- for rule in rules.rows %}
            when regexp_contains(lower({{ text }}), r'''{{ rule[1] }}''') then '{{ rule[0] }}'
        {%- endfor %}
        end
    {%- else -%}
        cast(null as string)
    {%- endif -%}
{% endmacro %}


{% macro job_function(title, department, data_role_family) %}
    case
        when {{ data_role_family }} is not null and {{ data_role_family }} != 'business_analyst' then 'data_analytics'
        else coalesce({{ function_from_rules(title) }}, {{ function_from_rules(department) }}, 'other')
    end
{% endmacro %}
