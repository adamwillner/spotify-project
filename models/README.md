# dbt models

| Layer | Schema | Materialized | Models |
|---|---|---|---|
| Staging | `staging` | view | `stg_spotify_charts`, `stg_musicbrainz_artist_genres`: one cleaned, typed model per source |
| Intermediate | `intermediate` | view | `int_artist_genre`: one genre + sub-genre per artist |
| Marts | `marts` | table | `dim_artist`, `dim_song`, `fct_chart_performance`: the star schema |

## How an artist gets its genre

```mermaid
flowchart LR
    A["MusicBrainz genres<br/>hip hop 10 · trap 5 · r&b 8"] -->|genre_mapping seed| B["Hip-Hop 15 · R&B 8"]
    B -->|most votes| C["genre: Hip-Hop"]
    C -->|top detailed genre within it| D["sub_genre: pop rap"]
```

- **genre**: one of 8 broad genres (Pop, Hip-Hop, R&B, Latin, Rock, Electronic, Country, Afrobeats).
- **Other**: found in MusicBrainz, but its genres aren't in the mapping (e.g. jazz).
- **Unclassified**: not looked up, not found, or no genres.
- A sub-genre that just repeats the genre (Pop → pop) is skipped unless it's the only one.
- The 8 groups are a deliberate choice: few and broad, so each has enough artists to compare. Changing them means editing the seed and the `accepted_values` tests.

## Data notes

- `dim_song`'s key is hashed from `artist_name + song_name`, since 423 song titles are shared by different artists.
- Genre describes the artist, so it lives on `dim_artist`, not in the fact table.
- No date dimension: the source has lifetime totals per song, not time series.
- Surrogate keys are hashed from names, not stable source IDs, so a corrected name would break historical links.
- Staging fixes: `weeks_at_peak` values like `(x13)` → `13`; a missing artist name is taken from `artist_and_title`.

## Tests

| Test | Checks |
|---|---|
| `unique` + `not_null` | Dimension keys, `int_artist_genre.artist_name`, the seed's `musicbrainz_genre` |
| `not_null` | Key columns in staging and the fact table |
| `relationships` | Every fact row points to an existing artist and song |
| `accepted_values` | `genre` only contains the allowed genres (catches typos in the mapping) |
| `top10_not_longer_than_charted` | No song has more weeks in the top 10 than on the chart |
| `unmapped_musicbrainz_genres` | **Warns** about MusicBrainz genres (5+ votes) missing from the mapping |

## Macros

- `generate_schema_name`: models land in clean `staging` / `intermediate` / `marts` schemas instead of `<target>_staging`.
- `clean_weeks_at_peak`: `(x13)` → `13`, defaulting to 1 when empty.
- `fill_artist_name`: falls back to the artist part of `artist_and_title`.

Every model and column is described in the `schema.yml` files; browse them with `dbt docs generate && dbt docs serve`.
