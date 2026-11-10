--One-time setup: warehouse, database, schemas and raw data load for the Spotify dbt project

use role accountadmin;

create warehouse if not exists my_wh
    warehouse_size = 'XSMALL'
    auto_suspend = 60
    auto_resume = true
    initially_suspended = true;

create database if not exists spotify_db;

create schema if not exists spotify_db.raw;

create file format if not exists spotify_db.raw.csv_format
    type = 'CSV'
    skip_header = 1
    field_optionally_enclosed_by = '"'
    encoding = 'UTF8';

create stage if not exists spotify_db.raw.spotify_stage
    file_format = spotify_db.raw.csv_format;

create table if not exists spotify_db.raw.spotify_charts_raw (
    artist_and_title    varchar, 
    wks                 varchar, 
    t10                 varchar, 
    pk                  varchar, 
    weeks_at_peak       varchar, 
    pkstreams           varchar, 
    total               varchar, 
    artist_name         varchar, 
    song_name           varchar, 
    lyrics              varchar
    );

-- Load the raw data.
-- Before running: upload data.csv to the stage (Snowsight → Databases → SPOTIFY_DB → RAW → Stages → SPOTIFY_STAGE → + Files).
-- Dataset: https://www.kaggle.com/datasets/batudev/spotify-global-chart-totals-and-lyrics

list @spotify_db.raw.spotify_stage;

copy into spotify_db.raw.spotify_charts_raw
    from @spotify_db.raw.spotify_stage;

select count(*) from spotify_db.raw.spotify_charts_raw;  -- expect 8058