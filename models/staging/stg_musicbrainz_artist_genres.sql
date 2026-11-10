with source as (
    select * from {{ source('spotify_raw', 'musicbrainz_artist_genres') }}
),

renamed as (
    select
        trim(artist_name)               as artist_name,
        nullif(trim(mbid), '')          as musicbrainz_id,
        trim(mb_artist_name)            as musicbrainz_artist_name,
        match_score::number             as match_score,
        lower(trim(genre))              as genre,
        genre_votes::number             as genre_votes,
        extracted_at::timestamp_ntz     as extracted_at
    from source
)

select * from renamed
