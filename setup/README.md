# Setup from scratch

Run these in order. Every SQL script is idempotent (safe to run again).

| Step | What | File |
|---|---|---|
| 1 | Warehouse, database, raw schema, file format, stage, raw table, load the Kaggle CSV | `01_setup.sql` |
| 2 | `transformer` role for dbt (least privilege) | `02_roles.sql` |
| 3 | Load the MusicBrainz genres (optional to re-run) | `03_musicbrainz.sql` |
| 4 | Key-pair authentication | below |
| 5 | dbt profile | below |
| 6 | Build | below |

## 1. Snowflake objects and raw data

Run `01_setup.sql` in a Snowsight worksheet. It creates the warehouse (`my_wh`, X-Small, auto-suspend 60 s), the database `spotify_db`, the `raw` schema, a CSV file format, an internal stage and the raw table. Before the final `COPY INTO`, download the CSV from Kaggle and upload it to the stage `spotify_db.raw.spotify_stage` in Snowsight. `COPY INTO` skips files that are already loaded.

## 2. Access control

Run `02_roles.sql` (replace `<your_user>` with your Snowflake username). It creates a `transformer` role with only the privileges dbt needs: read `raw`, create the `staging`, `intermediate` and `marts` schemas, and use the warehouse. dbt, locally and in CI, runs as this role instead of ACCOUNTADMIN.

## 3. Artist genres

Put the Kaggle CSV at `data/data.csv` and run `python extract/musicbrainz_genres.py` (about 11 minutes, see [extract/README.md](../extract/README.md)). Then run `03_musicbrainz.sql`, uploading `data/musicbrainz_artist_genres.csv` to `spotify_db.raw.musicbrainz_stage` before the `COPY INTO`. The `data/` folder is git-ignored.

## 4. Authentication

dbt connects with key-pair authentication (Snowflake no longer allows password-only logins). Register your public key on your Snowflake user:

```sql
alter user <your_user> set rsa_public_key = '<public key, without the BEGIN/END lines>';
```

Power BI connects with its own service user, because the connector can't handle a username containing a dot. It needs an encrypted copy of the private key (with a passphrase).

## 5. dbt profile

Add this to `~/.dbt/profiles.yml`:

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

## 6. Build

```
dbt debug   # check the connection
dbt deps    # install dbt_utils
dbt build   # seeds, models and tests, in order
```

CI (`.github/workflows/dbt_test.yml`) runs `dbt build` on every push to `main`, using GitHub secrets for the Snowflake connection.
