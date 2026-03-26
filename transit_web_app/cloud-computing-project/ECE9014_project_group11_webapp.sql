#-----------WEB APP-----------
CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(100) NOT NULL UNIQUE,
    role ENUM('admin', 'user') NOT NULL DEFAULT 'user',
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

SHOW TABLES FROM ltc_transit;
SELECT * FROM users;
SELECT 
    TABLE_NAME, 
    COLUMN_NAME
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'ltc_transit'    -- change if needed
  AND COLUMN_NAME IN ('date', 'arrival_time', 'departure_time')
ORDER BY TABLE_NAME, COLUMN_NAME;
DESCRIBE ridership_fact;
DESCRIBE accessible_trips;
DESCRIBE trip;

