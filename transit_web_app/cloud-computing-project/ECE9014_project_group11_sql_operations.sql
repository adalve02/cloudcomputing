---------------------------------------------------------------
# Six diverse SELECT–FROM–WHERE queries on ltc_transit
---------------------------------------------------------------
#Query 1 – Simple filter on one table
#Trips with high ridership on a specific day.
SELECT
    fact_date,
    route_id,
    trip_id,
    ridership_count,
    avg_delay_min
FROM ridership_fact
WHERE fact_date = '2025-10-01'
  AND ridership_count > 60 LIMIT 5;

#Query 2 – Join and aggregation with GROUP BY
#Top routes by total ridership in October 2025
SELECT
    r.route_short_name,
    r.route_long_name,
    SUM(f.ridership_count) AS total_ridership
FROM ridership_fact AS f
JOIN route AS r
  ON f.route_id = r.route_id
WHERE f.fact_date BETWEEN '2025-10-01' AND '2025-10-31'
GROUP BY r.route_short_name, r.route_long_name
HAVING SUM(f.ridership_count) > 500
ORDER BY total_ridership DESC LIMIT 5;

#Query 3 – Subquery in HAVING
#Trips whose average delay is above the system-wide average delay
SELECT
    trip_id,
    AVG(avg_delay_min) AS avg_delay_per_trip
FROM ridership_fact
GROUP BY trip_id
HAVING AVG(avg_delay_min) >
       (SELECT AVG(avg_delay_min) FROM ridership_fact)
ORDER BY avg_delay_per_trip DESC LIMIT 5;

#Query 4 – EXISTS over another relation
#Routes with delays > 5 min
SELECT DISTINCT
    r.route_id,
    r.route_short_name,
    r.route_long_name
FROM route r
WHERE EXISTS (
    SELECT 1
    FROM ridership_fact f
    WHERE f.route_id = r.route_id
      AND f.avg_delay_min > 5
) 
LIMIT 5;

#Query 5 – Join across fact and lookup table
#Average ridership under each weather condition in Oct–Nov 2025
SELECT
    w.weather_label,
    ROUND(AVG(f.ridership_count), 1) AS avg_ridership
FROM ridership_fact AS f
JOIN weather AS w
  ON f.weather_code = w.weather_code
WHERE f.fact_date BETWEEN '2025-10-01' AND '2025-11-30'
GROUP BY w.weather_label
ORDER BY avg_ridership DESC;

#Query 6 – Aggregation by driver with ordering and LIMIT
#Top 10 drivers by total fare collected, with delay stats
SELECT
    f.driver_id,
    COUNT(*) AS trip_count,
    ROUND(SUM(f.fare_collected), 2) AS total_revenue,
    ROUND(AVG(f.avg_delay_min), 2) AS avg_delay
FROM ridership_fact AS f
WHERE f.driver_id IS NOT NULL
GROUP BY f.driver_id
ORDER BY total_revenue DESC
LIMIT 5;

------------------------------------------------------------------------------------
# Three data modification commands
------------------------------------------------------------------------------------
#Data Modification 1 — INSERT using the result of a query
#INSERT new service dates into service table from ridership_fact, without inserting duplicates
INSERT INTO service (service_id, service_date, weekday, weekend)
SELECT
    CONCAT('S', DATE_FORMAT(f.fact_date, '%Y%m%d')) AS service_id,
    f.fact_date AS service_date,
    CASE 
        WHEN DAYOFWEEK(f.fact_date) BETWEEN 2 AND 6 THEN 1
        ELSE 0
    END AS weekday,
    CASE
        WHEN DAYOFWEEK(f.fact_date) IN (1, 7) THEN 1
        ELSE 0
    END AS weekend
FROM ridership_fact f
WHERE NOT EXISTS (
    SELECT 1
    FROM service s
    WHERE s.service_date = f.fact_date
);

#DATA MODIFICATION 2 - Mass UPDATE involving multiple tables
#All trips that currently have wheelchair_accessible = 0 will now be marked as accessible if they belong to routes that operate on weekends
UPDATE trip t
JOIN service s ON t.service_id = s.service_id
SET t.wheelchair_accessible = 1
WHERE s.weekend = 1
  AND t.wheelchair_accessible = 0;
   
#DATA MODIFICATION 3 - DELETE a meaningful subset of tuples
#Remove all ridership records from ridership_fact for the date 2025-09-12 where the ridership value was 1 or less, because these entries were identified as low-value data
DELETE FROM ridership_fact
WHERE fact_date = '2025-09-12'
  AND ridership_count <= 1;

-----------------------------------------------------------------
# Three views
-----------------------------------------------------------------
#VIEW 1 — Simple Selection View (Updatable)
#Shows all trips that are wheelchair accessible
CREATE VIEW accessible_trips AS
SELECT trip_id, route_id, service_id, wheelchair_accessible
FROM trip
WHERE wheelchair_accessible = 1;

#VIEW 2 — Multi-Table Join View (Not Updatable)
#Summaries of trips with service day information
CREATE VIEW trip_with_service_info AS
SELECT  
    t.trip_id,
    t.route_id,
    t.wheelchair_accessible,
    DATE(s.service_date) AS service_date,   -- expression makes view non-updatable
    s.weekday,
    s.weekend
FROM trip t
JOIN service s 
    ON t.service_id = s.service_id;

#VIEW 3 — Aggregated Ridership Summary (Not Updatable)
#Total riders per route per day
CREATE VIEW high_ridership_summary AS
SELECT 
    route_id,
    fact_date,
    SUM(ridership_count) AS total_riders,
    COUNT(*) AS trips_included
FROM ridership_fact
GROUP BY route_id, fact_date;
