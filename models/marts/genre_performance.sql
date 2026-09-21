SELECT 
    COALESCE(g.genre, 'Unclassified') AS genre,
    SUM(f.total_streams) AS total_streams,
    COUNT(a.artist_id) AS nr_of_songs
FROM {{ ref('fct_chart_performance')}} f
JOIN {{ ref('dim_artist')}} a 
    ON f.artist_id = a.artist_id
LEFT JOIN {{ ref('artist_genres')}} g
    ON a.artist_name = g.artist_name
GROUP BY g.genre
ORDER BY total_streams DESC