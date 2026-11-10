-- One-time load of artist genres from the MusicBrainz API into the raw layer.
-- Before running:
--   1. Run the extract:  python extract/musicbrainz_genres.py
--   2. Upload data/musicbrainz_artist_genres.csv to the stage below
--      (Snowsight -> Databases -> SPOTIFY_DB -> RAW -> Stages -> MUSICBRAINZ_STAGE -> + Files).
-- The file gets its own stage, so COPY INTO never mixes it up with data.csv in spotify_stage.

use role accountadmin;

create stage if not exists spotify_db.raw.musicbrainz_stage
    file_format = spotify_db.raw.csv_format;

-- One row per artist + genre. All varchar: raw stays untouched, staging does the typing.
create table if not exists spotify_db.raw.musicbrainz_artist_genres (
    artist_name     varchar,
    mbid            varchar,
    mb_artist_name  varchar,
    match_score     varchar,
    genre           varchar,
    genre_votes     varchar,
    extracted_at    varchar
);

list @spotify_db.raw.musicbrainz_stage;

copy into spotify_db.raw.musicbrainz_artist_genres
    from @spotify_db.raw.musicbrainz_stage;

select count(*) from spotify_db.raw.musicbrainz_artist_genres;
