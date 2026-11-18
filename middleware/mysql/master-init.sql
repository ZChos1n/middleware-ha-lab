-- MySQL master init: create replication user and a realistic IoT device-reporting schema.
-- This schema is intentionally built to demonstrate the 504 incident (missing index -> slow query).
CREATE USER IF NOT EXISTS 'repl'@'%' IDENTIFIED BY 'replpass';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';
FLUSH PRIVILEGES;

USE iot;

-- Device telemetry: the table from the resume's "device concurrent reporting" case.
CREATE TABLE IF NOT EXISTS device_reports (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    device_id VARCHAR(64) NOT NULL,
    metric_name VARCHAR(64) NOT NULL,
    metric_value DECIMAL(12,4) NOT NULL,
    reported_at DATETIME NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    -- NOTE: no index on (reported_at, device_id) on purpose.
    -- The 504 lab shows how this one missing index causes full table scans.
) ENGINE=InnoDB;

-- Seed ~200k rows so full-scan vs index difference is measurable.
-- (Generated with a recursive CTE; removed after insert in production-style fashion.)
INSERT INTO device_reports (device_id, metric_name, metric_value, reported_at)
SELECT
    CONCAT('device-', LPAD((n % 500) + 1, 4, '0')),
    ELT((n % 5) + 1, 'voltage', 'current', 'temperature', 'power', 'energy'),
    ROUND(RAND() * 1000, 2),
    DATE_SUB(NOW(), INTERVAL (n % 10080) MINUTE)
FROM (
    WITH RECURSIVE seq AS (
        SELECT 1 AS n UNION ALL SELECT n + 1 FROM seq WHERE n < 200000
    )
    SELECT n FROM seq
) s;
