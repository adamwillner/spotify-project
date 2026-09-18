
with staged as (
    select distinct artist_name, song_name, lyrics
    from {{ ref('stg_spotify_charts') }}
)

select
    {{ dbt_utils.generate_surrogate_key(['artist_name', 'song_name']) }} as song_id,
    artist_name,
    song_name,
    lyrics
from staged