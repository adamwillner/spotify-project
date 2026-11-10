"""
One-time extract of artist genres from the MusicBrainz API.

What it does:
  1. Reads the Kaggle chart CSV and finds the top 300 artists by total streams.
  2. For each artist: searches MusicBrainz for the artist, then fetches its genres.
  3. Writes one row per artist + genre to data/musicbrainz_artist_genres.csv.

Then load that file into Snowflake with setup/03_musicbrainz.sql.

How to run (from the spotify_project folder, with the venv active):
    python extract/musicbrainz_genres.py

It takes about 11 minutes, because MusicBrainz only allows about 1 request per second.
If it stops halfway (e.g. a network problem), just run it again: it skips the artists
that are already in the output file and continues where it stopped.
"""

import csv
import os
import time
from datetime import datetime, timezone

import requests

# ---------- Settings ----------
INPUT_FILE = "data/data.csv"
OUTPUT_FILE = "data/musicbrainz_artist_genres.csv"
NUMBER_OF_ARTISTS = 300   # top 300 artists = about 83 % of all streams
MIN_MATCH_SCORE = 90      # MusicBrainz rates each search match 0-100; below 90 we say "not found"
WAIT_SECONDS = 1.1        # pause before every request, to stay under 1 request per second
API_ROOT = "https://musicbrainz.org/ws/2"
# MusicBrainz asks every app to say who it is
HEADERS = {"User-Agent": "spotify-dbt-project/1.0 ( https://github.com/adamwillner/spotify-project )"}


def get_top_artists():
    """Read the chart CSV and return the artists with the most total streams."""
    streams_per_artist = {}   # {"Drake": 123456789, ...}

    with open(INPUT_FILE, encoding="utf-8", newline="") as f:
        for row in csv.DictReader(f):   # each row becomes a dict: {"artist name": "Drake", ...}
            artist = row["artist name"].strip()
            if artist == "":
                # Same fallback as stg_spotify_charts: take the part before " - "
                artist = row["artist and title"].split(" - ")[0].strip()

            # Add this song's streams to the artist's total (start at 0 the first time)
            streams_per_artist[artist] = streams_per_artist.get(artist, 0) + int(row["total"])

    # Sort the artist names by their stream total, biggest first, and keep the top ones
    sorted_artists = sorted(streams_per_artist, key=streams_per_artist.get, reverse=True)
    return sorted_artists[:NUMBER_OF_ARTISTS]


def call_api(url, params):
    """Call MusicBrainz and return the answer as a Python dict."""
    params["fmt"] = "json"   # ask for JSON instead of XML

    for attempt in range(5):   # try at most 5 times
        time.sleep(WAIT_SECONDS)

        try:
            response = requests.get(url, params=params, headers=HEADERS, timeout=30)
        except requests.exceptions.RequestException:
            # No connection, timeout, etc.: wait a while, then try again
            print("   Connection problem, waiting 30 seconds and trying again...")
            time.sleep(30)
            continue

        if response.status_code == 503:
            # 503 means "too many requests": wait longer, then try again
            print("   MusicBrainz says slow down, waiting 5 seconds...")
            time.sleep(5)
            continue

        response.raise_for_status()   # any other error: stop the script with a clear message
        return response.json()

    raise Exception("Still no answer from MusicBrainz after 5 tries. Run the script again later; it will resume.")


def find_artists(name):
    """Search MusicBrainz for an artist.

    Returns the matches whose name, or one of their aliases, is exactly our artist name.
    Checking the name stops wrong matches like "Kanye West" -> "Kanye West Tribute Band".
    Aliases catch renamed artists: MusicBrainz may list Kanye West as "Ye" with the alias "Kanye West".
    """
    answer = call_api(API_ROOT + "/artist", {"query": 'artist:"' + name + '"', "limit": 5})

    matches = []
    for artist in answer["artists"]:
        if int(artist["score"]) < MIN_MATCH_SCORE:
            continue

        known_names = [artist["name"].lower()]
        for alias in artist.get("aliases", []):
            known_names.append(alias["name"].lower())

        if name.lower() in known_names:
            matches.append(artist)

    return matches


def get_genres(artist_id):
    """Return the genres of one MusicBrainz artist as a list of (genre, votes)."""
    answer = call_api(API_ROOT + "/artist/" + artist_id, {"inc": "genres"})

    genres = []
    for genre in answer.get("genres", []):   # empty list if the artist has no genres
        genres.append((genre["name"], genre["count"]))
    return genres


def get_already_done():
    """Return the artists that are already in the output file, so a re-run can skip them."""
    already_done = set()
    if os.path.exists(OUTPUT_FILE):
        with open(OUTPUT_FILE, encoding="utf-8", newline="") as f:
            for row in csv.DictReader(f):
                already_done.add(row["artist_name"])
    return already_done


def main():
    artists = get_top_artists()
    already_done = get_already_done()
    file_is_new = not os.path.exists(OUTPUT_FILE)
    extracted_at = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")

    if len(already_done) > 0:
        print(f"Resuming: {len(already_done)} artists are already done and will be skipped.")

    # "a" = append: add to the end of the file instead of starting over
    with open(OUTPUT_FILE, "a", encoding="utf-8", newline="") as f:
        writer = csv.writer(f)
        if file_is_new:
            writer.writerow(["artist_name", "mbid", "mb_artist_name", "match_score",
                             "genre", "genre_votes", "extracted_at"])

        number = 0
        for artist in artists:
            number += 1
            if artist in already_done:
                continue

            matches = find_artists(artist)

            if len(matches) == 0:
                # Keep a row anyway, so we can see which artists weren't found
                writer.writerow([artist, "", "", "", "", "", extracted_at])
                print(f"{number}/{len(artists)} {artist}: not found")
                continue

            # MusicBrainz sometimes has duplicate entries for the same artist.
            # Try the matches in order and use the first one that has genres.
            chosen = matches[0]
            genres = []
            for match in matches:
                genres = get_genres(match["id"])
                if len(genres) > 0:
                    chosen = match
                    break

            if len(genres) == 0:
                # Found, but no genres: keep one row without a genre
                writer.writerow([artist, chosen["id"], chosen["name"], chosen["score"], "", "", extracted_at])

            for genre, votes in genres:
                writer.writerow([artist, chosen["id"], chosen["name"], chosen["score"], genre, votes, extracted_at])

            f.flush()   # save to disk after every artist
            print(f"{number}/{len(artists)} {artist} -> {chosen['name']}: {len(genres)} genres")

    print("Done! Wrote", OUTPUT_FILE)


# Only run main() when the file is run directly (python extract/musicbrainz_genres.py),
# not when another Python file imports it.
if __name__ == "__main__":
    main()
