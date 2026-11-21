-- ============================================================
-- CONCURRENCY TEST — SESSION B
-- Друга транзакція намагається змінити той самий рядок.
-- Якщо Session A утримує блокування, операція завершиться
-- помилкою через 5 секунд.
-- ============================================================

BEGIN;

SET LOCAL lock_timeout = '5s';

UPDATE public.devices
SET last_seen_at = clock_timestamp()
WHERE device_code = 'ESP-001';

COMMIT;
