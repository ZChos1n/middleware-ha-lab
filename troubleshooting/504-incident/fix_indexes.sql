-- ============================================================
-- THE FIX — from the 504 incident
-- Root cause: dashboard query filtered device_id + time range and sorted,
-- but device_reports had NO index supporting that access path -> full scan
-- + temp B-tree sort. Under concurrent device reporting this blew past the
-- 60s Nginx read timeout and returned 504.
-- ============================================================

-- 1) Confirm the problem (run BEFORE the fix). Look for "type: ALL" and "Using filesort".
EXPLAIN
SELECT metric_name, COUNT(*), AVG(metric_value)
FROM device_reports
WHERE device_id = 'device-0500'
  AND reported_at >= '2026-01-01'
GROUP BY metric_name;

-- 2) THE FIX: composite index whose column order matches WHERE equality then range.
--    Leftmost-prefix rule: device_id (equality) first, reported_at (range) second.
ALTER TABLE device_reports
    ADD INDEX idx_device_time (device_id, reported_at);

-- 3) Verify: expect "type: range", key=idx_device_time, no full table scan.
EXPLAIN
SELECT metric_name, COUNT(*), AVG(metric_value)
FROM device_reports
WHERE device_id = 'device-0500'
  AND reported_at >= '2026-01-01'
GROUP BY metric_name;

-- 4) Why NOT just index reported_at alone?
--    The query filters device_id (equality) AND reported_at (range). A single
--    reported_at index still leaves device_id filtering as a post-filter.
--    The composite index satisfies both predicates in one index seek.

-- 5) Rollback plan (keep for safety during rollout).
-- ALTER TABLE device_reports DROP INDEX idx_device_time;
