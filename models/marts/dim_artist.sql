with staged as (
    select distinct artist_name
    from {{ ref('stg_spotify_charts') }}
),

genres as (
    select artist_name, genre, sub_genre
    from {{ ref('int_artist_genre') }}
)

select
    {{ dbt_utils.generate_surrogate_key(['staged.artist_name']) }} as artist_id,
    staged.artist_name,
    coalesce(genres.genre, 'Unclassified')     as genre,       -- artists without a MusicBrainz genre
    coalesce(genres.sub_genre, 'Unclassified') as sub_genre
from staged
left join genres                                               -- left join keeps every artist
    on staged.artist_name = genres.artist_name
