-- ============================================================
-- 16_rls_api_security
-- Налаштування безпеки доступу через Supabase API
-- ============================================================
--
-- Навчальні ролі course_operator і course_analyst
-- налаштовуються окремо у 08_roles_permissions.
--
-- У цьому скрипті налаштовуються системні API-ролі Supabase:
--   anon          - неавторизований клієнт;
--   authenticated - авторизований клієнт;
--   service_role  - серверна частина / Edge Functions.
--
-- Прямий доступ клієнтських ролей до таблиць заборонено.
-- Серверна роль отримує лише права, необхідні для роботи
-- системи моніторингу.
-- ============================================================


-- ============================================================
-- 1. Увімкнення Row Level Security
-- ============================================================

ALTER TABLE public.rooms
    ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.devices
    ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.sensor_types
    ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.sensors
    ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.sensor_channels
    ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.readings
    ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.alert_rules
    ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.alerts
    ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.alert_rule_audit
    ENABLE ROW LEVEL SECURITY;


-- ============================================================
-- 2. Повна заборона прямого доступу клієнтських API-ролей
-- ============================================================

REVOKE ALL PRIVILEGES ON TABLE
    public.rooms,
    public.devices,
    public.sensor_types,
    public.sensors,
    public.sensor_channels,
    public.readings,
    public.alert_rules,
    public.alerts,
    public.alert_rule_audit,
    public.v_current_sensor_state,
    public.v_alert_history
FROM anon, authenticated;

REVOKE ALL PRIVILEGES ON SEQUENCE
    public.readings_id_seq
FROM anon, authenticated;


-- ============================================================
-- 3. Заборона виконання службових функцій клієнтськими ролями
-- ============================================================

REVOKE EXECUTE
ON FUNCTION public.get_channel_statistics(
    text,
    timestamptz,
    timestamptz
)
FROM anon, authenticated;

REVOKE EXECUTE
ON FUNCTION public.get_channel_alert_summary(text)
FROM anon, authenticated;

REVOKE EXECUTE
ON PROCEDURE public.acknowledge_alert(bigint, text)
FROM anon, authenticated;


-- ============================================================
-- 4. Очищення прав service_role на об'єкти проєкту
--    перед видачею мінімально необхідного набору
-- ============================================================

REVOKE ALL PRIVILEGES ON TABLE
    public.rooms,
    public.devices,
    public.sensor_types,
    public.sensors,
    public.sensor_channels,
    public.readings,
    public.alert_rules,
    public.alerts,
    public.alert_rule_audit,
    public.v_current_sensor_state,
    public.v_alert_history
FROM service_role;

REVOKE ALL PRIVILEGES ON SEQUENCE
    public.readings_id_seq
FROM service_role;


-- ============================================================
-- 5. Мінімальні права service_role
-- ============================================================

-- Читання конфігурації, вимірювань, тривог
-- та підготовлених представлень.

GRANT SELECT ON
    public.rooms,
    public.devices,
    public.sensor_types,
    public.sensors,
    public.sensor_channels,
    public.readings,
    public.alert_rules,
    public.alerts,
    public.v_current_sensor_state,
    public.v_alert_history
TO service_role;


-- Додавання нових вимірювань від пристрою.

GRANT INSERT ON public.readings
TO service_role;

GRANT USAGE, SELECT
ON SEQUENCE public.readings_id_seq
TO service_role;


-- Серверна частина може оновлювати тільки час
-- останнього контакту пристрою.

GRANT UPDATE (last_seen_at)
ON public.devices
TO service_role;


-- ============================================================
-- 6. Перевірка стану RLS
-- ============================================================

SELECT
    c.relname AS table_name,
    c.relrowsecurity AS rls_enabled,
    c.relforcerowsecurity AS rls_forced
FROM pg_class c
JOIN pg_namespace n
    ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
ORDER BY c.relname;


-- ============================================================
-- 7. Перевірка DML-прав API-ролей
-- ============================================================

SELECT
    grantee,
    table_name,
    privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND grantee IN (
      'anon',
      'authenticated',
      'service_role'
  )
  AND privilege_type IN (
      'SELECT',
      'INSERT',
      'UPDATE',
      'DELETE',
      'TRUNCATE',
      'REFERENCES',
      'TRIGGER'
  )
ORDER BY
    grantee,
    table_name,
    privilege_type;


-- ============================================================
-- 8. Перевірка колонкового UPDATE для devices
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
  AND privilege_type = 'UPDATE'
ORDER BY column_name;


-- ============================================================
-- 9. Контрольні тести доступу
-- Виконуються окремо.
-- ============================================================

-- ------------------------------------------------------------
-- TEST A.
-- anon не повинен мати прямого доступу до readings.
-- Очікується:
-- permission denied for table readings
-- ------------------------------------------------------------

-- SET ROLE anon;
--
-- SELECT *
-- FROM public.readings
-- LIMIT 1;
--
-- RESET ROLE;


-- ------------------------------------------------------------
-- TEST B.
-- service_role повинен мати серверний доступ до readings.
-- Очікується поточна кількість записів.
-- ------------------------------------------------------------

-- SET ROLE service_role;
--
-- SELECT
--     current_user,
--     COUNT(*) AS readings_count
-- FROM public.readings;
--
-- RESET ROLE;
