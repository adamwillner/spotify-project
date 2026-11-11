-- One broad genre and one sub-genre per artist.
-- MusicBrainz gives several detailed genres per artist (e.g. Drake: hip hop, trap, pop rap).
-- 1. Map each detailed genre to a broad genre with the genre_mapping seed.
-- 2. Genre = the broad genre with the most votes in total.
-- 3. Sub-genre = the detailed genre with the most votes within that broad genre,
--    skipping one that just repeats the broad genre (Pop -> pop) unless it's the only one.
-- Together they give a drill-down hierarchy: genre -> sub-genre -> artist -> song.

with artist_genres as (
    select artist_name, genre, genre_votes
    from {{ ref('stg_musicbrainz_artist_genres') }}
    where genre is not null
),

mapped as (
    select
        a.artist_name,
        coalesce(m.genre, 'Other') as genre,   -- detailed genres missing from the seed count as 'Other'
        a.genre                    as sub_genre,
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
),

main_genre as (
    select artist_name, genre
    from votes_per_genre
    -- qualify filters on a window function: keep only the top-voted genre per artist
    -- (ties are broken alphabetically, so the result is the same on every run)
    qualify row_number() over (partition by artist_name order by votes desc, genre) = 1
),

sub_genre as (
    select
        mapped.artist_name,
        mapped.sub_genre
    from mapped
    join main_genre
        on  mapped.artist_name = main_genre.artist_name
        and mapped.genre = main_genre.genre
    qualify row_number() over (
        partition by mapped.artist_name
        order by
            -- 1 when the sub-genre just repeats the genre ('pop' under Pop, 'hip hop' under Hip-Hop), so it sorts last
            iff(replace(mapped.sub_genre, '-', ' ') = replace(lower(main_genre.genre), '-', ' '), 1, 0),
            mapped.genre_votes desc,
            mapped.sub_genre
    ) = 1
)

select
    main_genre.artist_name,
    main_genre.genre,
    sub_genre.sub_genre
from main_genre
join sub_genre
    on main_genre.artist_name = sub_genre.artist_name
