# Spotify Chart Analytics (dbt + Snowflake)

A dbt project that turns the Kaggle "Spotify Global Chart Totals & Lyrics" dataset into a star schema for analysis, using a layered raw → staging → marts architecture on Snowflake (the dbt naming convention; equivalent to bronze/silver/gold in medallion terms).

**Stack:** Snowflake · dbt-core 1.12 (dbt-snowflake) · dbt_utils · GitHub Actions

**Data source:** [Spotify Global Chart Totals & Lyrics](https://www.kaggle.com/datasets/batudev/spotify-global-chart-totals-and-lyrics) on Kaggle: about 8,000 songs that appeared on Spotify's Global Weekly Chart, with lifetime chart stats, streams and lyrics.

## Architecture

- **Raw** (`raw.*`) — raw inputs, untouched:
  - `spotify_charts_raw` — raw CSV load (all columns `varchar`; created and loaded by `setup/01_setup.sql`)
  - `artist_genres` — seed (hand-made CSV in `seeds/`) mapping top artists to a genre
- **Staging** (`staging.stg_spotify_charts`) — cleaned and typed staging model.
- **Marts** (`marts.*`) — star schema and marts for analysis:
  - `dim_artist`, `dim_song` — dimension tables with surrogate keys
  - `fct_chart_performance` — chart metrics (peak position, weeks charted, streams) joined to both dimensions
  - `genre_performance` — total streams and song count per genre (artists not in the seed are grouped as `Unclassified`)
- **Snapshots** (`snapshots.artist_genres_snapshot`) — SCD2 history of `artist_genres`, tracking genre changes over time. Kept in its own schema because, unlike everything else, it can't be rebuilt.

## Data notes

- `dim_song`'s key is hashed from `artist_name + song_name`, since song titles alone collide across different artists.
- There's no date dimension — the source data is pre-aggregated lifetime totals per song, not time-series data.
- Surrogate keys are hashed from text (names), not stable source IDs, so a corrected name would break historical links.

## Tests

- **Generic tests** (in `models/staging/schema.yml` and `models/marts/schema.yml`):
  - `not_null` on key columns in staging, the fact table and `genre_performance`
  - `unique` + `not_null` on the dimension keys (`dim_artist.artist_id`, `dim_song.song_id`) and on `genre_performance.genre`
  - `relationships` on `fct_chart_performance.artist_id` and `song_id` — every fact row must point to an existing dimension row
- **Singular tests** (in `tests/`):
  - `top10_not_longer_than_charted` — fails if any song has more weeks in the top 10 than weeks on the chart overall

## Macros

- `generate_schema_name` — overrides dbt's default so models land in clean `raw`/`staging`/`marts` schemas instead of `<target>_staging` etc.
- `clean_weeks_at_peak` — cleans `weeks_at_peak` values like `(x13)` into a number, defaulting to 1 when empty
- `fill_artist_name` — uses `artist_name`, falling back to the artist part of `artist_and_title` when it's empty

## Documentation

Every model and column has a description in the `schema.yml` files. Browse them, plus the lineage graph, with:

```
dbt docs generate
dbt docs serve
```

## CI

A GitHub Actions workflow (`.github/workflows/dbt_test.yml`) runs `dbt build` against Snowflake on every push to `main`.

## Setup from scratch

**1. Snowflake objects and raw data.** Run `setup/01_setup.sql` in a Snowsight worksheet. It creates the warehouse (`my_wh`, X-Small, auto-suspend 60 s), the database `spotify_db`, the `raw` schema, a CSV file format, an internal stage and the raw table. Before the final `COPY INTO`, download the CSV from Kaggle and upload it to the stage `spotify_db.raw.spotify_stage` in Snowsight. The script is idempotent: it can be re-run safely, and `COPY INTO` skips files already loaded.

**2. Access control.** Run `setup/02_roles.sql` (replace `<your_user>` with your Snowflake username). It creates a `transformer` role with only the privileges dbt needs: read access to `raw`, permission to create the `staging`, `marts` and `snapshots` schemas, and use of the warehouse (least privilege). dbt, locally and in CI, runs as this role instead of ACCOUNTADMIN.

**3. Authentication.** dbt connects with key-pair authentication (Snowflake no longer allows password-only logins). Register your public key on your Snowflake user:

```sql
alter user <your_user> set rsa_public_key = '<public key, without the BEGIN/END lines>';
```

**4. dbt profile.** Add this to `~/.dbt/profiles.yml`:

```yaml
spotify_project:
  target: dev
  outputs:
    dev:
      type: snowflake
      account: <orgname-accountname>
      user: <your_user>
      private_key_path: <path to rsa_key.p8>
      role: transformer
      warehouse: my_wh
      database: spotify_db
      schema: staging
      threads: 4
```

**5. Build.**

```
dbt debug   # check the connection
dbt deps    # install dbt_utils
dbt build   # seeds, snapshots, models and tests, in order
```
