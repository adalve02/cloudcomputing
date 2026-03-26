#Step 1 – Create the Schema
CREATE DATABASE ltc_transit
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_0900_ai_ci;
  
#Step 2 – Use the Schema
USE ltc_transit;

#Step 3 – Create All Tables
#T1: Agency
CREATE TABLE agency (
  agency_id INT AUTO_INCREMENT PRIMARY KEY,
  agency_name VARCHAR(255) NOT NULL UNIQUE
);

#T2: Route
CREATE TABLE route (
  route_id VARCHAR(32) PRIMARY KEY,
  agency_id INT NOT NULL,
  route_short_name VARCHAR(64),
  route_long_name VARCHAR(255),
  route_desc VARCHAR(512),
  route_type TINYINT,
  FOREIGN KEY (agency_id) REFERENCES agency(agency_id)
);

#T3: Service
CREATE TABLE service (
  service_id VARCHAR(32) PRIMARY KEY,
  service_date DATE NOT NULL,
  weekday BOOLEAN,
  weekend BOOLEAN
);

#T4: Trip
CREATE TABLE trip (
  trip_id VARCHAR(64) PRIMARY KEY,
  route_id VARCHAR(32),
  service_id VARCHAR(32),
  trip_headsign VARCHAR(255),
  direction_id TINYINT,
  wheelchair_accessible BOOLEAN,
  FOREIGN KEY (route_id) REFERENCES route(route_id),
  FOREIGN KEY (service_id) REFERENCES service(service_id)
);

#T5: Bus
CREATE TABLE bus (
  bus_id VARCHAR(32) PRIMARY KEY
);

#T6: Driver
CREATE TABLE driver (
  driver_id VARCHAR(32) PRIMARY KEY
);

#T7: Weather
CREATE TABLE weather (
  weather_code TINYINT PRIMARY KEY,
  weather_label VARCHAR(32) UNIQUE
);

#T8: Ridership fact
CREATE TABLE ridership_fact (
  fact_date DATE NOT NULL,
  trip_id VARCHAR(64),
  service_id VARCHAR(32),
  route_id VARCHAR(32),
  weekday BOOLEAN,
  weekend BOOLEAN,
  ridership_count INT CHECK (ridership_count >= 0),
  avg_wait_time_min DECIMAL(5,2),
  avg_delay_min DECIMAL(5,2),
  fare_collected DECIMAL(10,2),
  weather_code TINYINT,
  bus_id VARCHAR(32),
  driver_id VARCHAR(32),
  PRIMARY KEY (fact_date, trip_id),
  FOREIGN KEY (trip_id) REFERENCES trip(trip_id),
  FOREIGN KEY (service_id) REFERENCES service(service_id),
  FOREIGN KEY (route_id) REFERENCES route(route_id),
  FOREIGN KEY (weather_code) REFERENCES weather(weather_code),
  FOREIGN KEY (bus_id) REFERENCES bus(bus_id),
  FOREIGN KEY (driver_id) REFERENCES driver(driver_id)
);

#Step 4 - Create a staging table that matches the CSV
CREATE TABLE stage_ltc (
  date                DATE,
  service_id          VARCHAR(32),
  agency_name         VARCHAR(255),
  trip_id             VARCHAR(64),
  trip_headsign       VARCHAR(255),
  direction_id        TINYINT,
  route_id            VARCHAR(32),
  route_short_name    VARCHAR(64),
  route_long_name     VARCHAR(255),
  route_desc          VARCHAR(512),
  route_type          TINYINT,
  route_color         VARCHAR(10),   -- will be ignored later
  shape_id            VARCHAR(64),   -- will be ignored later
  shape_points        INT,           -- will be ignored later
  wheelchair_accessible TINYINT,
  bikes_allowed       TINYINT,       -- will be ignored later
  weekday             TINYINT,
  weekend             TINYINT,
  ridership_count     INT,
  avg_wait_time_min   DECIMAL(5,2),
  avg_delay_min       DECIMAL(5,2),
  fare_collected      DECIMAL(10,2),
  weather_condition   VARCHAR(32),
  bus_id              VARCHAR(32),
  driver_id           VARCHAR(32)
);

#Step 5 - Load data into stage_ltc
SET GLOBAL local_infile = 1;

LOAD DATA INFILE
  '/docker-entrypoint-initdb.d/Data.csv'
INTO TABLE stage_ltc
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

#Step 6 - Load parent tables first (key mapping / transformation)
#Order: agency → weather → bus → driver → route → service → trip → ridership_fact
#6.1: Agency
INSERT IGNORE INTO agency (agency_name)
SELECT DISTINCT agency_name
FROM stage_ltc
WHERE agency_name IS NOT NULL
ON DUPLICATE KEY UPDATE agency.agency_name = agency.agency_name;

#6.2: Weather
INSERT INTO weather (weather_code, weather_label)
VALUES
  (1,'Sunny'),
  (2,'Cloudy'),
  (3,'Rain'),
  (4,'Snow'),
  (5,'Windy')
ON DUPLICATE KEY UPDATE weather.weather_label = weather.weather_label;

#6.3: Bus and Driver
INSERT IGNORE INTO bus (bus_id)
SELECT DISTINCT TRIM(s.bus_id)
FROM stage_ltc s
WHERE s.bus_id IS NOT NULL
  AND s.bus_id <> ''
  AND TRIM(s.bus_id) NOT IN (SELECT bus_id FROM bus);

-- Insert new drivers
INSERT IGNORE INTO driver (driver_id)
SELECT DISTINCT TRIM(s.driver_id)
FROM stage_ltc s
WHERE s.driver_id IS NOT NULL
  AND s.driver_id <> ''
  AND TRIM(s.driver_id) NOT IN (SELECT driver_id FROM driver);


#6.4: Route
INSERT INTO route (route_id, agency_id, route_short_name, route_long_name, route_desc, route_type)
SELECT *
FROM (
    SELECT DISTINCT
      s.route_id,
      a.agency_id,
      s.route_short_name,
      s.route_long_name,
      s.route_desc,
      s.route_type
    FROM stage_ltc s
    JOIN agency a ON a.agency_name = s.agency_name
    WHERE s.route_id IS NOT NULL
) AS new_data
ON DUPLICATE KEY UPDATE
  route_short_name = new_data.route_short_name,
  route_long_name  = new_data.route_long_name,
  route_desc       = new_data.route_desc,
  route_type       = new_data.route_type;


#6.5: Service
INSERT INTO service (service_id, service_date, weekday, weekend)
SELECT
  service_id,
  MIN(date) AS service_date,
  MAX(weekday) AS weekday,
  MAX(weekend) AS weekend
FROM stage_ltc
WHERE service_id IS NOT NULL
GROUP BY service_id
ON DUPLICATE KEY UPDATE
  service_date = VALUES(service_date),
  weekday      = VALUES(weekday),
  weekend      = VALUES(weekend);

#6.6: Trip
INSERT INTO trip (trip_id, route_id, service_id, trip_headsign, direction_id, wheelchair_accessible)
SELECT *
FROM (
    SELECT DISTINCT
        trip_id,
        route_id,
        service_id,
        trip_headsign,
        direction_id,
        wheelchair_accessible
    FROM stage_ltc
    WHERE trip_id IS NOT NULL
) AS new_data
ON DUPLICATE KEY UPDATE
    route_id             = new_data.route_id,
    service_id           = new_data.service_id,
    trip_headsign        = new_data.trip_headsign,
    direction_id         = new_data.direction_id,
    wheelchair_accessible= new_data.wheelchair_accessible;


#Step 7 - Load child table:ridership_fact
INSERT INTO ridership_fact
  (fact_date, trip_id, service_id, route_id,
   weekday, weekend,
   ridership_count, avg_wait_time_min, avg_delay_min, fare_collected,
   weather_code, bus_id, driver_id)
SELECT *
FROM (
    SELECT
      s.date                  AS fact_date,
      s.trip_id,
      s.service_id,
      s.route_id,
      s.weekday,
      s.weekend,
      s.ridership_count,
      s.avg_wait_time_min,
      s.avg_delay_min,
      s.fare_collected,
      CASE s.weather_condition
        WHEN 'Sunny'  THEN 1
        WHEN 'Cloudy' THEN 2
        WHEN 'Rain'   THEN 3
        WHEN 'Snow'   THEN 4
        WHEN 'Windy'  THEN 5
        ELSE NULL
      END AS weather_code,
      s.bus_id,
      s.driver_id
    FROM stage_ltc s
    JOIN trip t ON t.trip_id = s.trip_id
) AS new_data
ON DUPLICATE KEY UPDATE
  ridership_count   = new_data.ridership_count,
  avg_wait_time_min = new_data.avg_wait_time_min,
  avg_delay_min     = new_data.avg_delay_min,
  fare_collected    = new_data.fare_collected,
  weather_code      = new_data.weather_code,
  bus_id            = new_data.bus_id,
  driver_id         = new_data.driver_id;

  SHOW Tables;
  DESCRIBE agency;
DESCRIBE bus;
DESCRIBE driver;
DESCRIBE ridership_fact;
DESCRIBE route;
DESCRIBE service;
DESCRIBE stage_ltc;
DESCRIBE trip;
DESCRIBE weather;
SELECT * FROM bus LIMIT 10;
-- SQL to create the users table for Flask-Login authentication
CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(80) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL, -- Stores the secure hash
    role ENUM('user', 'admin') NOT NULL DEFAULT 'user'
);
-- SQL to insert the first admin user
-- REPLACE 'PASTE_YOUR_COPIED_HASH_HERE' with the output from Python
INSERT INTO users (username, password_hash, role) 
VALUES ('admin', 'PASTE_YOUR_COPIED_HASH_HERE', 'admin');
-- Replace 'YOUR_FRESH_HASH_FROM_STEP_1' with the string you just copied.

UPDATE users 
SET password_hash = 'admin_password' 
WHERE username = 'admin';

-- Save the change
COMMIT;
DESCRIBE users;
SELECT * FROM users LIMIT 10;
UPDATE users
SET password_hash = 'scrypt:32768:8:1$cSjjofIyejSKPEkf$0594c224f0fdc4459ce61401bd35705675f1e57b9ee822f841eb114fc317d8c3f1811a86f806bc10ea1242fa6d08fac24b6096b8ae5ddd04c980827e16668772'
WHERE username = 'admin';
SELECT * FROM ridership_fact LIMIT 10;
SELECT trip_id FROM trip LIMIT 20;
SELECT * FROM service;
SHOW CREATE TABLE service;
SHOW CREATE TABLE ridership_fact;
SELECT * FROM trip LIMIT 5;
SELECT * FROM route LIMIT 10;ridership_fact
SELECT * FROM weather LIMIT 5;
SELECT * FROM driver LIMIT 5;
SELECT * FROM bus LIMIT 5;
SELECT service_id FROM service WHERE service_id = '1';
SELECT service_id FROM service WHERE service_id = '1';
INSERT INTO service (service_id, service_name) VALUES ('1', 'Default Service');
SELECT CONCAT('*', service_id, '*') AS check_value FROM service;
ALTER TABLE ridership_fact MODIFY service_id VARCHAR(255) NULL;
SELECT * 
FROM ridership_fact
ORDER BY fact_date DESC, trip_id DESC
LIMIT 10;
SELECT * FROM ridership_fact ORDER BY fact_date DESC LIMIT 5;
SELECT * FROM service WHERE service_id = '3302';
SELECT * FROM trip WHERE trip_id = '2235257';
UPDATE users 
SET password_hash = 'ashwini123' 
WHERE username = 'ashwini';
UPDATE users 
SET password_hash = 'ashu123' 
WHERE username = 'ashu';
ALTER TABLE ridership_fact
ADD COLUMN trip_time TIME;
SELECT * FROM ridership_fact LIMIT 10;
ALTER TABLE trip
ADD COLUMN arrival_time TIME NULL,
ADD COLUMN departure_time TIME NULL;

SELECT *
FROM trip
LIMIT 20;
ALTER TABLE trip
DROP COLUMN arrival_time,
DROP COLUMN departure_time;
SELECT * FROM stage_ltc LIMIT 5;



-----2ndfile-------
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
LOAD DATA LOCAL INFILE 'C:/Users/Asus/Downloads/times.csv'
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
SET SQL_SAFE_UPDATES = 0;
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
ALTER TABLE trip
ADD COLUMN arrival_time TIME NULL,
ADD COLUMN departure_time TIME NULL;

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
