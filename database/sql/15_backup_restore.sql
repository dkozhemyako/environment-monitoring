-- ============================================================
-- 15_backup_restore
-- Контроль резервного копіювання та відновлення бази даних
-- ============================================================
--
-- Резервну копію створено засобом pg_dump PostgreSQL 17.12
-- у форматі custom (-Fc).
--
-- Відновлення виконано засобом pg_restore PostgreSQL 17.12
-- в окрему тестову базу:
-- environment_monitoring_restore
--
-- Після відновлення виконуються наведені нижче
-- контрольні перевірки.
-- ============================================================


-- ============================================================
-- 1. Кількість рядків у таблицях
-- ============================================================

SELECT 'rooms' AS table_name, COUNT(*) AS row_count
FROM public.rooms

UNION ALL
SELECT 'devices', COUNT(*)
FROM public.devices

UNION ALL
SELECT 'sensor_types', COUNT(*)
FROM public.sensor_types

UNION ALL
SELECT 'sensors', COUNT(*)
FROM public.sensors

UNION ALL
SELECT 'sensor_channels', COUNT(*)
FROM public.sensor_channels

UNION ALL
SELECT 'readings', COUNT(*)
FROM public.readings

UNION ALL
SELECT 'alert_rules', COUNT(*)
FROM public.alert_rules

UNION ALL
SELECT 'alerts', COUNT(*)
FROM public.alerts

UNION ALL
SELECT 'alert_rule_audit', COUNT(*)
FROM public.alert_rule_audit

ORDER BY table_name;


-- ============================================================
-- 2. Перевірка представлень, функцій і тригерів
-- ============================================================

SELECT
    'views' AS object_type,
    COUNT(*) AS object_count
FROM information_schema.views
WHERE table_schema = 'public'

UNION ALL

SELECT
    'functions',
    COUNT(*)
FROM information_schema.routines
WHERE routine_schema = 'public'

UNION ALL

SELECT
    'triggers',
    COUNT(*)
FROM information_schema.triggers
WHERE trigger_schema = 'public';


-- ============================================================
-- 3. Перевірка індексів та обмежень
-- ============================================================

SELECT
    'indexes' AS object_type,
    COUNT(*) AS object_count
FROM pg_indexes
WHERE schemaname = 'public'

UNION ALL

SELECT
    'constraints',
    COUNT(*)
FROM pg_constraint c
JOIN pg_namespace n
    ON n.oid = c.connamespace
WHERE n.nspname = 'public';


-- ============================================================
-- 4. Контроль роботи представлення
-- ============================================================

SELECT
    channel_code,
    value,
    unit,
    allowed_min,
    allowed_max,
    status
FROM public.v_current_sensor_state
ORDER BY channel_code;


-- ============================================================
-- 5. Негативна перевірка UNIQUE після відновлення
-- Виконується окремо.
-- Очікується помилка rooms_room_code_uq.
-- ============================================================

-- INSERT INTO public.rooms (
--     room_code,
--     name
-- )
-- VALUES (
--     'ROOM-001',
--     'Duplicate room'
-- );


-- ============================================================
-- 6. Перевірка тригера після відновлення
-- Виконується окремо.
-- Очікується відхилення значення 120 °C.
-- ============================================================

-- INSERT INTO public.readings (
--     channel_id,
--     measured_at,
--     value
-- )
-- VALUES (
--     (
--         SELECT id
--         FROM public.sensor_channels
--         WHERE channel_code = 'AHT20-TEMP'
--     ),
--     '2026-11-18 12:00:00+02',
--     120
-- );
