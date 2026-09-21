select *
from {{ ref('fct_chart_performance') }}
where weeks_top10 > weeks_charted