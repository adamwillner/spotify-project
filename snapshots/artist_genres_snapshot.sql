{% snapshot artist_genres_snapshot %}

{{
    config(
      target_schema='snapshots',
      unique_key='artist_name',
      strategy='check',
      check_cols=['genre'],
    )
}}

select * from {{ ref('artist_genres') }}

{% endsnapshot %}