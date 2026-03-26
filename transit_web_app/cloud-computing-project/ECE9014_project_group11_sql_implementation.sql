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
