# Spotify Chart Analytics (dbt + Snowflake)

A dbt project that turns the Kaggle "Spotify Global Chart Totals & Lyrics" dataset into a star schema for analysis, enriched with artist genres from the MusicBrainz API, using a layered raw → staging → intermediate → marts architecture on Snowflake (the dbt naming convention; equivalent to bronze/silver/gold in medallion terms).

**Stack:** Snowflake · dbt-core 1.12 (dbt-snowflake) · dbt_utils · Python (requests) · GitHub Actions

**Data source:** [Spotify Global Chart Totals & Lyrics](https://www.kaggle.com/datasets/batudev/spotify-global-chart-totals-and-lyrics) on Kaggle: about 8,000 songs that appeared on Spotify's Global Weekly Chart, with lifetime chart stats, streams and lyrics. Artist genres come from [MusicBrainz](https://musicbrainz.org/doc/MusicBrainz_API), an open music database.

## Architecture

- **Extract** (`extract/musicbrainz_genres.py`) — one-time Python script that looks up the top 300 artists (~83 % of all streams) in the MusicBrainz API and writes their genres to a CSV.
- **Raw** (`raw.*`) — raw inputs, untouched (all columns `varchar`):
  - `spotify_charts_raw` — the Kaggle chart CSV, loaded by `setup/01_setup.sql`
  - `musicbrainz_artist_genres` — the MusicBrainz extract, one row per artist + genre, loaded by `setup/03_musicbrainz.sql`
  - `genre_mapping` — seed (hand-made CSV in `seeds/`) mapping detailed MusicBrainz genres (e.g. `trap`, `dance-pop`) to broad genres (Hip-Hop, Pop)
- **Staging** (`staging.*`) — one cleaned and typed model per source: `stg_spotify_charts`, `stg_musicbrainz_artist_genres`.
- **Intermediate** (`intermediate.int_artist_genre`) — picks one broad genre per artist: maps each MusicBrainz genre with the seed, adds up the votes per broad genre and keeps the top one.
- **Marts** (`marts.*`) — star schema for analysis:
  - `dim_artist` — one row per artist with its broad genre (`Unclassified` when there is none)
  - `dim_song` — one row per song
  - `fct_chart_performance` — chart metrics (peak position, weeks charted, streams), linked to both dimensions

## Data notes

- `dim_song`'s key is hashed from `artist_name + song_name`, since song titles alone collide across different artists.
- Genre is an attribute of the artist, so it lives on `dim_artist`, not in the fact table.
- Artists outside the top 300, not found in MusicBrainz (search score below 90), or without genres are `Unclassified`.
- There's no date dimension — the source data is pre-aggregated lifetime totals per song, not time-series data.
- Surrogate keys are hashed from text (names), not stable source IDs, so a corrected name would break historical links.

## Tests

- **Generic tests** (in the `schema.yml` files):
  - `unique` + `not_null` on the dimension keys (`dim_artist.artist_id`, `dim_song.song_id`), on `int_artist_genre.artist_name` and on the seed's `musicbrainz_genre`
  - `not_null` on key columns in staging and the fact table
  - `relationships` on `fct_chart_performance.artist_id` and `song_id` — every fact row must point to an existing dimension row
  - `accepted_values` on `dim_artist.genre` and `int_artist_genre.genre` — catches typos in the genre mapping
- **Singular tests** (in `tests/`):
  - `top10_not_longer_than_charted` — fails if any song has more weeks in the top 10 than weeks on the chart overall
  - `unmapped_musicbrainz_genres` — *warns* (doesn't fail) when MusicBrainz returned genres the mapping seed doesn't cover, listing which ones to add

## Macros

- `generate_schema_name` — overrides dbt's default so models land in clean `raw`/`staging`/`intermediate`/`marts` schemas instead of `<target>_staging` etc.
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

**2. Access control.** Run `setup/02_roles.sql` (replace `<your_user>` with your Snowflake username). It creates a `transformer` role with only the privileges dbt needs: read access to `raw`, permission to create the `staging`, `intermediate` and `marts` schemas, and use of the warehouse (least privilege). dbt, locally and in CI, runs as this role instead of ACCOUNTADMIN.

**3. Artist genres (optional to re-run).** Put the Kaggle CSV at `data/data.csv` and run `python extract/musicbrainz_genres.py` (about 11 minutes; MusicBrainz allows ~1 request per second). Then run `setup/03_musicbrainz.sql`, uploading `data/musicbrainz_artist_genres.csv` to `spotify_db.raw.musicbrainz_stage` before the `COPY INTO`. The `data/` folder is git-ignored.

**4. Authentication.** dbt connects with key-pair authentication (Snowflake no longer allows password-only logins). Register your public key on your Snowflake user:

```sql
alter user <your_user> set rsa_public_key = '<public key, without the BEGIN/END lines>';
```

**5. dbt profile.** Add this to `~/.dbt/profiles.yml`:

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

**6. Build.**

```
dbt debug   # check the connection
dbt deps    # install dbt_utils
dbt build   # seeds, models and tests, in order
```
