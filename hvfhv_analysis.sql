-- =====================================================================
-- Independent project: who waits longest for a ride in New York?
-- Data:   NYC Taxi & Limousine Commission, High Volume For-Hire Vehicle
--         (HVFHV) trip records, April 2026 (Uber and Lyft)
-- Engine: DuckDB (run in Colab with %%sql cells, or in the DuckDB CLI)
-- Run each statement separately and read the output before moving on.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. LOAD
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE zones AS
SELECT * FROM read_csv_auto('taxi_zone_lookup.csv');

CREATE OR REPLACE TABLE trips_raw AS
SELECT
    hvfhs_license_num, request_datetime, on_scene_datetime,
    pickup_datetime, dropoff_datetime, PULocationID, DOLocationID,
    trip_miles, trip_time,
    shared_request_flag, shared_match_flag, wav_request_flag, wav_match_flag
FROM read_parquet('data/fhvhv_tripdata_2026-04.parquet');

-- ---------------------------------------------------------------------
-- 1. STAGE: derived fields (all durations in seconds)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE trips AS
SELECT
    CASE hvfhs_license_num WHEN 'HV0003' THEN 'Uber'
                           WHEN 'HV0005' THEN 'Lyft'
                           ELSE 'Other' END                          AS company,
    request_datetime, on_scene_datetime, pickup_datetime, dropoff_datetime,
    PULocationID, DOLocationID, trip_miles, trip_time,
    date_diff('second', request_datetime,  pickup_datetime)          AS wait_s,
    date_diff('second', request_datetime,  on_scene_datetime)        AS dispatch_s,
    date_diff('second', on_scene_datetime, pickup_datetime)          AS onscene_to_pickup_s,
    hour(request_datetime)                                           AS req_hour,
    isodow(request_datetime)                                         AS dow,   -- 1 = Monday
    CASE WHEN isodow(request_datetime) >= 6 THEN 'Weekend' ELSE 'Weekday' END AS day_type,
    shared_request_flag, shared_match_flag, wav_request_flag, wav_match_flag
FROM trips_raw;

-- ---------------------------------------------------------------------
-- 2. DATA QUALITY
-- Finding: ~1.3% of trips have a request time AFTER the driver arrived.
-- It clusters at 3-5am and in outer-borough zones, and hits 59% of
-- Lyft wheelchair-accessible requests. Excluded from wait analysis.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE trips_flagged AS
SELECT *,
    request_datetime IS NULL OR pickup_datetime IS NULL            AS bad_null_ts,
    wait_s < 0                                                      AS bad_negative_wait,
    wait_s > 7200                                                   AS bad_wait_over_2h,
    pickup_datetime >= dropoff_datetime                             AS bad_dropoff_before_pickup,
    COALESCE(trip_time, 0) <= 0 OR COALESCE(trip_miles, 0) <= 0     AS bad_zero_trip,
    on_scene_datetime IS NULL                                       AS on_scene_missing
FROM trips;

SELECT
    company,
    count(*)                                              AS trips,
    round(100.0 * avg(bad_null_ts::INT), 3)               AS pct_null_ts,
    round(100.0 * avg(bad_negative_wait::INT), 3)         AS pct_negative_wait,
    round(100.0 * avg(bad_wait_over_2h::INT), 3)          AS pct_wait_over_2h,
    round(100.0 * avg(bad_dropoff_before_pickup::INT), 3) AS pct_dropoff_before_pickup,
    round(100.0 * avg(bad_zero_trip::INT), 3)             AS pct_zero_trip,
    round(100.0 * avg(on_scene_missing::INT), 1)          AS pct_on_scene_missing
FROM trips_flagged
GROUP BY company
ORDER BY company;

CREATE OR REPLACE VIEW trips_clean AS
SELECT * FROM trips_flagged
WHERE NOT (bad_null_ts OR bad_negative_wait OR bad_wait_over_2h
           OR bad_dropoff_before_pickup OR bad_zero_trip);

-- 2a. How bad are the negative waits, and which timestamp is wrong?
SELECT
    company,
    CASE WHEN on_scene_datetime < request_datetime THEN 'driver arrived before request'
         WHEN pickup_datetime  < on_scene_datetime THEN 'pickup before driver arrival'
         ELSE 'other' END AS pattern,
    count(*) AS rows_,
    round(quantile_cont(wait_s, 0.5) / 60, 1) AS median_wait_min
FROM trips
WHERE wait_s < 0
GROUP BY ALL
ORDER BY company, rows_ DESC;

-- 2b. Do the bad rows cluster by hour?
SELECT company, req_hour, count(*) AS trips,
       round(100.0 * avg((wait_s < 0)::INT), 2) AS pct_negative
FROM trips
GROUP BY ALL
ORDER BY company, req_hour;

-- 2c. ...or by zone?
SELECT z.Borough, z.Zone, count(*) AS trips,
       round(100.0 * avg((t.wait_s < 0)::INT), 2) AS pct_negative
FROM trips t
JOIN zones z ON z.LocationID = t.PULocationID
GROUP BY ALL
HAVING count(*) >= 5000
ORDER BY pct_negative DESC
LIMIT 15;

-- 2d. Dropped share for wheelchair-accessible requests, by company
SELECT
    company, wav_request_flag,
    count(*)                                              AS trips,
    count(*) FILTER (WHERE bad_negative_wait)             AS negative_wait,
    round(100.0 * avg((bad_null_ts OR bad_negative_wait OR bad_wait_over_2h
                       OR bad_dropoff_before_pickup OR bad_zero_trip)::INT), 1) AS pct_dropped
FROM trips_flagged
GROUP BY ALL
ORDER BY company, wav_request_flag;

-- ---------------------------------------------------------------------
-- 3. HEADLINE: wait distribution (percentiles, not just the mean)
-- ---------------------------------------------------------------------
SELECT
    company,
    count(*)                                         AS trips,
    round(avg(wait_s) / 60, 1)                       AS mean_min,
    round(quantile_cont(wait_s, 0.50) / 60, 1)       AS p50_min,
    round(quantile_cont(wait_s, 0.90) / 60, 1)       AS p90_min,
    round(quantile_cont(wait_s, 0.95) / 60, 1)       AS p95_min,
    round(100.0 * avg((wait_s > 600)::INT), 1)       AS pct_wait_over_10min
FROM trips_clean
GROUP BY company
ORDER BY company;

-- 3a. Sensitivity: keep the excluded rows and floor their wait at 0 s
SELECT
    company,
    round(quantile_cont(GREATEST(wait_s, 0), 0.50) / 60, 1) AS p50_min_floored,
    round(quantile_cont(GREATEST(wait_s, 0), 0.90) / 60, 1) AS p90_min_floored,
    round(100.0 * avg((wait_s > 600)::INT), 1)              AS pct_wait_over_10min_floored
FROM trips
WHERE wait_s <= 7200
GROUP BY company
ORDER BY company;

-- 3b. Like-for-like Uber vs Lyft: same pickup zone, hour and day type
WITH cell AS (
    SELECT PULocationID, req_hour, day_type, company,
           count(*) AS n,
           quantile_cont(wait_s, 0.90) / 60 AS p90,
           avg((wait_s > 600)::INT)          AS pct_over10
    FROM trips_clean
    WHERE company IN ('Uber', 'Lyft')
    GROUP BY ALL
    HAVING count(*) >= 200
),
pair AS (
    SELECT u.PULocationID, u.req_hour, u.day_type,
           u.p90 AS uber_p90, l.p90 AS lyft_p90,
           u.pct_over10 AS uber_over10, l.pct_over10 AS lyft_over10
    FROM cell u
    JOIN cell l
      ON  u.PULocationID = l.PULocationID
      AND u.req_hour     = l.req_hour
      AND u.day_type     = l.day_type
    WHERE u.company = 'Uber' AND l.company = 'Lyft'
)
SELECT
    count(*)                                              AS comparable_cells,
    round(avg(uber_p90 - lyft_p90), 2)                    AS avg_p90_gap_min,
    round(100.0 * avg((uber_p90 > lyft_p90)::INT), 1)     AS pct_cells_uber_worse,
    round(100.0 * avg(uber_over10 - lyft_over10), 1)      AS avg_gap_pct_points_over10
FROM pair;

-- ---------------------------------------------------------------------
-- 4. WHERE: wait by pickup zone  (also carries a reliability column)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE wait_by_zone AS
WITH clean AS (
    SELECT PULocationID, wait_s FROM trips_clean
),
neg AS (
    SELECT PULocationID,
           round(100.0 * avg((wait_s < 0)::INT), 2) AS pct_dropped_negative
    FROM trips
    GROUP BY PULocationID
)
SELECT
    c.PULocationID AS location_id,
    z.Borough, z.Zone,
    count(*)                                        AS trips,
    round(quantile_cont(c.wait_s, 0.50) / 60, 2)    AS p50_min,
    round(quantile_cont(c.wait_s, 0.90) / 60, 2)    AS p90_min,
    round(100.0 * avg((c.wait_s > 600)::INT), 1)    AS pct_wait_over_10min,
    n.pct_dropped_negative
FROM clean c
JOIN zones z ON z.LocationID = c.PULocationID
JOIN neg n   ON n.PULocationID = c.PULocationID
GROUP BY ALL
HAVING count(*) >= 1000;

-- ---------------------------------------------------------------------
-- 5. WHEN: hour x day heatmap table
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE wait_by_hour_dow AS
SELECT
    dow, req_hour, day_type,
    count(*)                                         AS trips,
    round(quantile_cont(wait_s, 0.50) / 60, 2)       AS p50_min,
    round(quantile_cont(wait_s, 0.90) / 60, 2)       AS p90_min
FROM trips_clean
GROUP BY ALL
ORDER BY dow, req_hour;

-- ---------------------------------------------------------------------
-- 6. WHO IS LEAST WELL SERVED: wheelchair-accessible (WAV) requests
-- NOTE: every WAV request in this file was also matched (match rate 100%).
-- Requests that were never matched are not in the data, so unmet demand
-- cannot be measured here. Compare on wav_REQUEST_flag, not the match flag.
-- Uber only: 59% of Lyft WAV requests are lost to the timestamp defect.
-- ---------------------------------------------------------------------
SELECT wav_request_flag, wav_match_flag, count(*) AS trips
FROM trips
GROUP BY ALL
ORDER BY trips DESC;

SELECT
    company,
    CASE WHEN wav_request_flag = 'Y' THEN 'WAV requested' ELSE 'No WAV request' END AS segment,
    count(*)                                         AS trips,
    round(quantile_cont(wait_s, 0.50) / 60, 1)       AS p50_min,
    round(quantile_cont(wait_s, 0.90) / 60, 1)       AS p90_min,
    round(100.0 * avg((wait_s > 600)::INT), 1)       AS pct_over_10min
FROM trips_clean
GROUP BY ALL
ORDER BY company, segment;

CREATE OR REPLACE TABLE wav_by_borough_uber AS
SELECT
    z.Borough,
    CASE WHEN t.wav_request_flag = 'Y' THEN 'WAV requested' ELSE 'No WAV request' END AS segment,
    count(*)                                         AS trips,
    round(quantile_cont(t.wait_s, 0.50) / 60, 2)     AS p50_min,
    round(quantile_cont(t.wait_s, 0.90) / 60, 2)     AS p90_min,
    round(100.0 * avg((t.wait_s > 600)::INT), 1)     AS pct_over_10min
FROM trips_clean t
JOIN zones z ON z.LocationID = t.PULocationID
WHERE t.company = 'Uber' AND z.Borough NOT IN ('N/A', 'EWR', 'Unknown')
GROUP BY ALL;

-- ---------------------------------------------------------------------
-- 7. DRIVER ARRIVAL -> PICKUP (supporting evidence only)
-- The on-scene timestamp has logging artifacts: 42% of Lyft trips sit at
-- exactly 60 s, ~18% of Uber trips near 120 s. Lyft is unusable here and
-- the Uber comparison is indicative only.
-- ---------------------------------------------------------------------
SELECT company, onscene_to_pickup_s AS secs, n
FROM (
    SELECT company, onscene_to_pickup_s, count(*) AS n,
           row_number() OVER (PARTITION BY company ORDER BY count(*) DESC) AS rk
    FROM trips
    GROUP BY company, onscene_to_pickup_s
)
WHERE rk <= 5
ORDER BY company, n DESC;

SELECT
    wav_request_flag,
    count(*)                                                        AS trips,
    round(100.0 * avg((onscene_to_pickup_s BETWEEN 119 AND 121)::INT), 1) AS pct_near_120s,
    round(100.0 * avg((onscene_to_pickup_s = 0)::INT), 1)           AS pct_zero,
    round(quantile_cont(onscene_to_pickup_s, 0.50)
          FILTER (WHERE onscene_to_pickup_s NOT BETWEEN 119 AND 121
                    AND onscene_to_pickup_s > 0) / 60, 2)           AS p50_min_excl_spikes
FROM trips
WHERE company = 'Uber' AND onscene_to_pickup_s BETWEEN 0 AND 1800
GROUP BY wav_request_flag;

-- ---------------------------------------------------------------------
-- 8. EXPORT (the three CSVs in /data)
-- ---------------------------------------------------------------------
COPY wait_by_zone         TO 'out/wait_by_zone.csv'         (HEADER, DELIMITER ',');
COPY wait_by_hour_dow     TO 'out/wait_by_hour_dow.csv'     (HEADER, DELIMITER ',');
COPY wav_by_borough_uber  TO 'out/wav_by_borough_uber.csv'  (HEADER, DELIMITER ',');
