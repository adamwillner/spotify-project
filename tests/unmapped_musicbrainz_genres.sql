-- Warns (does not fail) when MusicBrainz returned genres that the genre_mapping seed doesn't cover.
-- The rows show which genres to add to seeds/genre_mapping.csv, most-voted first.
{{ config(severity='warn') }}

select
    s.genre,
    sum(s.genre_votes)          as total_votes,
    count(distinct s.artist_name) as artists
from {{ ref('stg_musicbrainz_artist_genres') }} s
left join {{ ref('genre_mapping') }} m
    on s.genre = m.musicbrainz_genre
where s.genre is not null
  and m.musicbrainz_genre is null
group by s.genre
having sum(s.genre_votes) >= 5
order by total_votes desc
