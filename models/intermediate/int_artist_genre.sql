-- One broad genre per artist.
-- MusicBrainz gives several detailed genres per artist (e.g. Drake: hip hop, trap, pop rap).
-- We map each one to a broad genre with the genre_mapping seed, add up the votes
-- per broad genre, and keep the broad genre with the most votes.

with artist_genres as (
    select artist_name, genre, genre_votes
    from {{ ref('stg_musicbrainz_artist_genres') }}
    where genre is not null
),

mapped as (
    select
        a.artist_name,
        coalesce(m.genre, 'Other') as genre,   -- detailed genres missing from the seed count as 'Other'
        a.genre_votes
    from artist_genres a
    left join {{ ref('genre_mapping') }} m
        on a.genre = m.musicbrainz_genre
),

votes_per_genre as (
    select
        artist_name,
        genre,
        sum(genre_votes) as votes
    from mapped
    group by artist_name, genre
)

select
    artist_name,
    genre
from votes_per_genre
-- qualify filters on a window function: keep only the top-voted genre per artist
-- (ties are broken alphabetically, so the result is the same on every run)
qualify row_number() over (partition by artist_name order by votes desc, genre) = 1
