# Spotify Chart Analytics (dbt + Snowflake)

A dbt project that turns the Kaggle "Spotify Global Chart Totals & Lyrics" dataset into a star schema for analysis, using a bronze/silver/gold medallion architecture on Snowflake.

## Architecture

- **Bronze** — raw inputs, untouched:
  - `spotify_charts_raw` — raw CSV load
  - `artist_genres` — seed (hand-made CSV in `seeds/`) mapping top artists to a genre
- **Silver** (`silver.stg_spotify_charts`) — cleaned and typed staging model.
- **Gold** (`gold.*`) — star schema and marts for analysis:
  - `dim_artist`, `dim_song` — dimension tables with surrogate keys
  - `fct_chart_performance` — chart metrics (peak position, weeks charted, streams) joined to both dimensions
  - `genre_performance` — total streams and song count per genre (artists not in the seed are grouped as `Unclassified`)
- **Snapshots** (`snapshots.artist_genres_snapshot`) — SCD2 history of `artist_genres`, tracking genre changes over time. Kept in its own schema because, unlike everything else, it can't be rebuilt.

## Data notes

- `dim_song`'s key is hashed from `artist_name + song_name`, since song titles alone collide across different artists.
- There's no date dimension — the source data is pre-aggregated lifetime totals per song, not time-series data.
- Surrogate keys are hashed from text (names), not stable source IDs, so a corrected name would break historical links.

## CI

A GitHub Actions workflow (`.github/workflows/dbt_test.yml`) runs `dbt build` against Snowflake on every push to `main`.

## Running locally

```
dbt deps
dbt build   # seeds, snapshots, models and tests, in order
```
