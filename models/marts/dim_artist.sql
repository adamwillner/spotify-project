with staged as (
    select distinct artist_name
    from {{ ref('stg_spotify_charts') }}
)

select
    {{ dbt_utils.generate_surrogate_key(['artist_name']) }} as artist_id,
    artist_name
from staged