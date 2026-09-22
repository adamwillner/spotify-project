{% macro fill_artist_name(artist_col, fallback_col) -%}
    coalesce(nullif(trim({{ artist_col }}), ''), trim(split_part({{ fallback_col }}, ' - ', 1)))
{%- endmacro %}