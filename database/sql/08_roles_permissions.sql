BEGIN;

-- ============================================================
-- Контрольовані операції виконуються з правами власника
-- ============================================================

ALTER FUNCTION public.process_reading_alert()
SECURITY DEFINER;

ALTER FUNCTION public.process_reading_alert()
SET search_path = public;


ALTER PROCEDURE public.acknowledge_alert(bigint, text)
SECURITY DEFINER;

ALTER PROCEDURE public.acknowledge_alert(bigint, text)
SET search_path = public;


-- ============================================================
-- Створення предметних ролей
-- ============================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'course_operator'
    ) THEN
        CREATE ROLE course_operator NOLOGIN;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'course_analyst'
    ) THEN
        CREATE ROLE course_analyst NOLOGIN;
    END IF;
END;
$$;


-- ============================================================
-- Дозвіл тестувати предметні ролі через Supabase SQL Editor
-- ============================================================

GRANT course_operator TO postgres
WITH INHERIT FALSE, SET TRUE;

GRANT course_analyst TO postgres
WITH INHERIT FALSE, SET TRUE;


-- ============================================================
-- Базовий доступ до схеми
-- ============================================================

GRANT USAGE
ON SCHEMA public
TO course_operator, course_analyst;


-- ============================================================
-- OPERATOR
-- ============================================================

GRANT SELECT ON
    public.rooms,
    public.devices,
    public.sensor_types,
    public.sensors,
    public.sensor_channels,
    public.alert_rules,
    public.readings,
    public.alerts,
    public.v_current_sensor_state,
    public.v_alert_history
TO course_operator;

GRANT INSERT
ON public.readings
TO course_operator;

GRANT USAGE, SELECT
ON SEQUENCE public.readings_id_seq
TO course_operator;


-- ============================================================
-- ANALYST
-- ============================================================

GRANT SELECT ON
    public.v_current_sensor_state,
    public.v_alert_history
TO course_analyst;


-- ============================================================
-- Забираємо EXECUTE у PUBLIC
-- ============================================================

REVOKE EXECUTE
ON FUNCTION public.get_channel_statistics(
    text,
    timestamptz,
    timestamptz
)
FROM PUBLIC;

REVOKE EXECUTE
ON FUNCTION public.get_channel_alert_summary(text)
FROM PUBLIC;

REVOKE EXECUTE
ON PROCEDURE public.acknowledge_alert(bigint, text)
FROM PUBLIC;


-- ============================================================
-- Доступ до функцій
-- ============================================================

GRANT EXECUTE
ON FUNCTION public.get_channel_statistics(
    text,
    timestamptz,
    timestamptz
)
TO course_operator, course_analyst;

GRANT EXECUTE
ON FUNCTION public.get_channel_alert_summary(text)
TO course_operator, course_analyst;


-- ============================================================
-- Лише оператор може підтверджувати alert
-- ============================================================

GRANT EXECUTE
ON PROCEDURE public.acknowledge_alert(bigint, text)
TO course_operator;


-- ============================================================
-- Явна заборона прямої зміни службових таблиць
-- ============================================================

REVOKE INSERT, UPDATE, DELETE
ON public.rooms,
   public.devices,
   public.sensor_types,
   public.sensors,
   public.sensor_channels,
   public.alert_rules,
   public.alerts,
   public.alert_rule_audit
FROM course_operator, course_analyst;

REVOKE INSERT, UPDATE, DELETE
ON public.readings
FROM course_analyst;

COMMIT;
