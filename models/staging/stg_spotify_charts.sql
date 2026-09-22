with source as (
    select * from {{ source('spotify_raw', 'spotify_charts_raw') }}
),

renamed as (
    select
        trim(artist_and_title)      as artist_and_title,
        {{ fill_artist_name('artist_name', 'artist_and_title') }} as artist_name,
        trim(song_name)             as song_name,
        trim(lyrics)                as lyrics,
        wks::number                 as weeks_charted,
        t10::number                 as weeks_top10,
        pk::number                  as peak_position,
        {{ clean_weeks_at_peak('weeks_at_peak') }}::number as weeks_at_peak,
        pkstreams::number           as peak_week_streams,
        total::number               as total_streams
    from source
)

select * from renamed