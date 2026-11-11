with staged as (
    select * from {{ ref('stg_spotify_charts') }}
),

artists as (
    select * from {{ ref('dim_artist') }}
),

songs as (
    select * from {{ ref('dim_song') }}
)

select
    artists.artist_id,
    songs.song_id,
    staged.peak_position,
    staged.weeks_at_peak,
    staged.weeks_charted,
    staged.weeks_top10,
    staged.total_streams
from staged
left join artists on staged.artist_name = artists.artist_name
left join songs
    on staged.artist_name = songs.artist_name
    and staged.song_name = songs.song_name
