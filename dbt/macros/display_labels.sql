{#- Human-readable labels for dashboard fields, kept in one place so every report table says the same thing. -#}

{% macro display_label(column, kind) %}
    {%- set labels = {
        'job_function': {
            'engineering': 'Engineering', 'sales': 'Sales', 'product_design': 'Product and design',
            'customer': 'Customer', 'marketing': 'Marketing', 'people_hr': 'People and HR',
            'g_and_a': 'G&A', 'data_analytics': 'Data and analytics', 'other': 'Other'
        },
        'workplace_type': {'remote': 'Remote', 'hybrid': 'Hybrid', 'onsite': 'Onsite', 'unknown': 'Not stated'},
        'seniority': {
            'intern': 'Intern', 'entry': 'Entry', 'senior': 'Senior', 'staff_plus': 'Staff+',
            'director': 'Director', 'executive': 'Executive', 'unspecified': 'Not stated'
        },
        'data_role_family': {
            'analytics_engineering': 'Analytics engineering', 'data_science': 'Data science',
            'data_engineering': 'Data engineering', 'bi': 'BI', 'data_analyst': 'Data analyst',
            'business_analyst': 'Business analyst', 'analytics_general': 'Analytics (general)'
        },
        'peer_group': {
            'target': 'Elastic', 'hr_tech': 'HR tech', 'hr_analytics': 'HR analytics', 'analytics': 'Analytics and BI',
            'data_infra': 'Data infrastructure', 'observability': 'Observability', 'ai': 'AI', 'consumer': 'Consumer',
            'dev_tools': 'Developer tools', 'security': 'Security', 'fintech': 'Fintech', 'productivity': 'Productivity'
        }
    } -%}
    case {{ column }}
    {%- for value, label in labels[kind].items() %}
        when '{{ value }}' then '{{ label }}'
    {%- endfor %}
        else {{ column }}
    end
{% endmacro %}


{% macro peer_lens(peer_group) %}
    -- Four filter groups for the dashboard: the target, HR companies, data/AI companies, everyone else.
    case
        when {{ peer_group }} = 'target' then 'Elastic'
        when {{ peer_group }} in ('hr_tech', 'hr_analytics') then 'HR tech and analytics'
        when {{ peer_group }} in ('analytics', 'data_infra', 'ai') then 'Data and AI'
        else 'Other peers'
    end
{% endmacro %}
