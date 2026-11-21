-- ============================================================
-- 17_final_validation
-- Підсумкова перевірка бази даних
-- ============================================================


-- ============================================================
-- 1. Середовище виконання
-- ============================================================

SELECT
    version() AS postgres_version,
    current_database() AS database_name,
    current_setting('server_version') AS server_version,
    current_setting('TimeZone') AS timezone;


-- ============================================================
-- 2. Підсумковий склад об'єктів бази даних
-- ============================================================

SELECT
    'tables' AS object_type,
    COUNT(*) AS object_count
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_type = 'BASE TABLE'

UNION ALL

SELECT
    'views',
    COUNT(*)
FROM information_schema.views
WHERE table_schema = 'public'

UNION ALL

SELECT
    'routines',
    COUNT(*)
FROM information_schema.routines
WHERE routine_schema = 'public'

UNION ALL

SELECT
    'triggers',
    COUNT(*)
FROM pg_trigger t
JOIN pg_class c
    ON c.oid = t.tgrelid
JOIN pg_namespace n
    ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND NOT t.tgisinternal

UNION ALL

SELECT
    'indexes',
    COUNT(*)
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
-- 3. Підсумкова кількість записів у таблицях
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
-- 4. Поточний стан каналів моніторингу
-- ============================================================

SELECT
    room_code,
    device_code,
    sensor_code,
    channel_code,
    measurement_type,
    value,
    unit,
    allowed_min,
    allowed_max,
    status
FROM public.v_current_sensor_state
ORDER BY channel_code;


-- ============================================================
-- 5. Історія тривог
-- ============================================================

SELECT
    alert_id,
    channel_code,
    measurement_type,
    actual_value,
    allowed_min,
    allowed_max,
    opened_at,
    resolved_at,
    alert_status
FROM public.v_alert_history
ORDER BY opened_at;


-- ============================================================
-- 6. Ролі користувачів
-- ============================================================

SELECT
    rolname AS role_name,
    rolcanlogin AS can_login
FROM pg_roles
WHERE rolname IN (
    'course_operator',
    'course_analyst',
    'anon',
    'authenticated',
    'service_role'
)
ORDER BY rolname;


-- ============================================================
-- 7. Стан Row Level Security
-- ============================================================

SELECT
    c.relname AS table_name,
    c.relrowsecurity AS rls_enabled
FROM pg_class c
JOIN pg_namespace n
    ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
ORDER BY c.relname;


-- ============================================================
-- 8. Функції та процедури
-- ============================================================

SELECT
    p.proname AS routine_name,
    CASE p.prokind
        WHEN 'f' THEN 'FUNCTION'
        WHEN 'p' THEN 'PROCEDURE'
        ELSE p.prokind::text
    END AS routine_type
FROM pg_proc p
JOIN pg_namespace n
    ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
ORDER BY routine_type, routine_name;


-- ============================================================
-- 9. Тригери
-- ============================================================

SELECT
    c.relname AS table_name,
    t.tgname AS trigger_name
FROM pg_trigger t
JOIN pg_class c
    ON c.oid = t.tgrelid
JOIN pg_namespace n
    ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND NOT t.tgisinternal
ORDER BY c.relname, t.tgname;


-- ============================================================
-- 10. Представлення
-- ============================================================

SELECT
    table_name AS view_name
FROM information_schema.views
WHERE table_schema = 'public'
ORDER BY table_name;


-- ============================================================
-- 11. Перевірка відсутності прямого доступу
--     клієнтських API-ролей
-- ============================================================

SELECT
    grantee,
    table_name,
    privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND grantee IN ('anon', 'authenticated')
ORDER BY grantee, table_name, privilege_type;

-- Очікуваний результат:
-- 0 рядків.


-- ============================================================
-- 12. Права service_role
-- ============================================================

SELECT
    grantee,
    table_name,
    privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND grantee = 'service_role'
  AND privilege_type IN (
      'SELECT',
      'INSERT',
      'UPDATE',
      'DELETE'
  )
ORDER BY table_name, privilege_type;


-- ============================================================
-- 13. Колонкове право UPDATE для devices.last_seen_at
-- ============================================================

SELECT
    grantee,
    table_name,
    column_name,
    privilege_type
FROM information_schema.role_column_grants
WHERE table_schema = 'public'
  AND grantee = 'service_role'
  AND table_name = 'devices'
  AND privilege_type = 'UPDATE';


-- ============================================================
-- 14. Контрольний тест INSERT від service_role
-- Виконується окремо за потреби.
-- Зміни скасовуються через ROLLBACK.
-- ============================================================

-- BEGIN;
--
-- SET LOCAL ROLE service_role;
--
-- INSERT INTO public.readings (
--     channel_id,
--     measured_at,
--     value
-- )
-- VALUES (
--     (
--         SELECT id
--         FROM public.sensor_channels
--         WHERE channel_code = 'AHT20-HUM'
--     ),
--     '2026-11-18 13:00:00+02',
--     50.00
-- )
-- RETURNING
--     id,
--     channel_id,
--     measured_at,
--     value;
--
-- ROLLBACK;


-- ============================================================
-- 15. Перевірка ROLLBACK тестового запису
-- ============================================================

SELECT
    COUNT(*) AS test_rows_after_rollback
FROM public.readings
WHERE channel_id = (
    SELECT id
    FROM public.sensor_channels
    WHERE channel_code = 'AHT20-HUM'
)
AND measured_at = '2026-11-18 13:00:00+02';

-- Очікуваний результат:
-- test_rows_after_rollback = 0
