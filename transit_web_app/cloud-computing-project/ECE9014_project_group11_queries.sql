SELECT * FROM agency;
SELECT * FROM weather;
SELECT * FROM bus;
SELECT * FROM driver;
SELECT * FROM route;
SELECT * FROM service;
SELECT * FROM trip;
SELECT * FROM ridership_fact LIMIT 5;

ALTER TABLE route DROP COLUMN route_color;
ALTER TABLE route DROP COLUMN route_desc;

SHOW Tables;

SELECT COUNT(*) FROM stage_ltc;
SELECT * FROM stage_ltc LIMIT 5;

SELECT COUNT(*) AS fact_rows FROM ridership_fact;
SELECT COUNT(*) AS routes FROM route;
SELECT COUNT(*) AS trips  FROM trip;

DESCRIBE Trip;
DESCRIBE ridership_fact;
SHOW COLUMNS FROM ridership_fact;
-----------------------------------------------------------------------
#DM1 verification
SELECT COUNT(*) FROM service;
SELECT service_date, COUNT(*)
FROM service
GROUP BY service_date
HAVING COUNT(*) > 1;
SELECT *
FROM service
ORDER BY service_date DESC
LIMIT 10;

#DM1 fixing
#STEP 1 — View the duplicate service rows
SELECT *
FROM service
WHERE service_date = '2025-09-15';
#STEP 2 - Decide which service_id to keep
SELECT service_id, COUNT(*)
FROM ridership_fact
WHERE fact_date = '2025-09-15'
GROUP BY service_id;
# 2.1 - Update ridership_fact to point everything to 3302
UPDATE ridership_fact
SET service_id = 3302
WHERE fact_date = '2025-09-15'
  AND service_id = 3602;
# 2.2 - Verify nothing references 3602 anymore
SELECT service_id, COUNT(*)
FROM ridership_fact
WHERE fact_date = '2025-09-15'
GROUP BY service_id;
#STEP 3 — Delete the duplicate service row safely
SELECT COUNT(*)
FROM trip
WHERE service_id = 3602;
SELECT *
FROM trip
WHERE service_id = 3602
LIMIT 20;
UPDATE trip
SET service_id = 3302
WHERE service_id = 3602;
SET SQL_SAFE_UPDATES = 0;
DELETE FROM service
WHERE service_id = 3602
LIMIT 1;
#STEP 5 — Verification
SELECT service_date, COUNT(*)
FROM service
GROUP BY service_date
HAVING COUNT(*) > 1;
SET SQL_SAFE_UPDATES = 1;

#DM2 verification
SELECT COUNT(*)
FROM trip t
JOIN service s ON t.service_id = s.service_id
WHERE s.weekend = 1
  AND t.wheelchair_accessible = 0;

#DM3 verification
SELECT *
FROM ridership_fact
WHERE fact_date = '2025-09-12'
  AND ridership_count <= 1;
SELECT COUNT(*)
FROM ridership_fact
WHERE fact_date = '2025-09-12';
-----------------------------------------------------------------------------
#View1 verification
SELECT *
FROM accessible_trips
LIMIT 10;
UPDATE accessible_trips
SET wheelchair_accessible = 0
WHERE trip_id = 12345;

#View2 verification
UPDATE trip_with_service_info 
SET weekend = 0;

#View3 verification
SELECT * FROM high_ridership_summary
LIMIT 10;
UPDATE high_ridership_summary
SET total_riders = 9999
WHERE route_id = '01';
---------------------------------------------------------------
#Add times into stage_ltc first, then populate trip
#1 - Add columns in stage_ltc
ALTER TABLE stage_ltc
ADD COLUMN arrival_time_raw VARCHAR(20),
ADD COLUMN departure_time_raw VARCHAR(20);
#2 - Load the times into stage_ltc
SET GLOBAL local_infile = 1;
LOAD DATA LOCAL INFILE 'C:/Users/Akshay/Downloads/times.csv'
INTO TABLE stage_ltc
FIELDS TERMINATED BY ',' 
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(trip_id, arrival_time_raw, departure_time_raw);
#3 - Add final TIME columns to stage_ltc
ALTER TABLE stage_ltc
ADD COLUMN arrival_time TIME NULL,
ADD COLUMN departure_time TIME NULL;
#4 - Convert text time values (arrival_time_raw, departure_time_raw) into proper MySQL TIME format
UPDATE stage_ltc
SET arrival_time = STR_TO_DATE(arrival_time_raw, '%r'),
    departure_time = STR_TO_DATE(departure_time_raw, '%r');
#5 - Check all distinct raw time strings loaded from CSV (to verify formats and spot errors)
SELECT arrival_time_raw, COUNT(*)
FROM stage_ltc
GROUP BY arrival_time_raw
ORDER BY arrival_time_raw;
#6 - Remove rows where raw times are NULL
DELETE FROM stage_ltc
WHERE arrival_time_raw IS NULL;
#7 - Remove rows where raw times are empty strings
DELETE FROM stage_ltc
WHERE arrival_time_raw = '';
#8 - Re-check remaining raw time values after cleaning
SELECT arrival_time_raw, COUNT(*)
FROM stage_ltc
GROUP BY arrival_time_raw
ORDER BY arrival_time_raw;
#9 - Convert AM/PM time values again using explicit hour-minute-second format
UPDATE stage_ltc
SET arrival_time = STR_TO_DATE(arrival_time_raw, '%h:%i:%s %p'),
    departure_time = STR_TO_DATE(departure_time_raw, '%h:%i:%s %p');
#10 - Preview the converted times
SELECT arrival_time_raw, arrival_time, departure_time_raw, departure_time
FROM stage_ltc
LIMIT 30;
#11 - Check if any valid raw times failed to convert into MySQL TIME format
SELECT COUNT(*) AS failed_conversions
FROM stage_ltc
WHERE arrival_time IS NULL
  AND arrival_time_raw IS NOT NULL;
#12 - Remove the temporary raw text columns
ALTER TABLE stage_ltc
DROP COLUMN arrival_time_raw,
DROP COLUMN departure_time_raw;
#13 - Populate final arrival_time & departure_time into TRIP table (matching on trip_id)
UPDATE trip t
JOIN stage_ltc s ON t.trip_id = s.trip_id
SET t.arrival_time = s.arrival_time,
    t.departure_time = s.departure_time;
#14 - To verify new columns exist or need to be added
SHOW COLUMNS FROM trip;
#15 - Add arrival_time and departure_time columns to trip if they do not already exist
ALTER TABLE trip
ADD COLUMN arrival_time TIME NULL,
ADD COLUMN departure_time TIME NULL;
#16 - Populate the new columns in TRIP table using values from stage_ltc
UPDATE trip t
JOIN stage_ltc s ON t.trip_id = s.trip_id
SET t.arrival_time = s.arrival_time,
    t.departure_time = s.departure_time;
#17 - Preview trip table with new data
SELECT *
FROM trip
LIMIT 20;







