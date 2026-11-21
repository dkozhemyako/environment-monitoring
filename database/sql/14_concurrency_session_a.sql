-- ============================================================
-- CONCURRENCY TEST — SESSION A
-- Сесія A змінює запис пристрою та утримує блокування рядка
-- протягом 20 секунд.
-- ============================================================

BEGIN;

UPDATE public.devices
SET last_seen_at = clock_timestamp()
WHERE device_code = 'ESP-001';

SELECT pg_sleep(20);

COMMIT;
