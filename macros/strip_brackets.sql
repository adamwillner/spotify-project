{% macro clean_weeks_at_peak(column) -%}

coalesce(nullif(replace(replace(replace({{column}}, '(', ''), ')', ''), 'x', ''), ''), '1')

{%- endmacro %}