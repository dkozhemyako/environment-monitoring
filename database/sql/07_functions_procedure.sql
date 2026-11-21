BEGIN;

-- ============================================================
-- ФУНКЦІЯ 1.
-- Статистика вимірювань каналу за часовий інтервал
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_channel_statistics(
    p_channel_code text,
    p_from timestamptz,
    p_to timestamptz
)
RETURNS TABLE (
    readings_count bigint,
    avg_value numeric(14,4),
    min_value numeric(14,4),
    max_value numeric(14,4)
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        COUNT(*)::bigint,
        ROUND(AVG(r.value), 4)::numeric(14,4),
        MIN(r.value)::numeric(14,4),
        MAX(r.value)::numeric(14,4)
    FROM public.readings r
    JOIN public.sensor_channels sc
        ON sc.id = r.channel_id
    WHERE sc.channel_code = p_channel_code
      AND r.is_valid = true
      AND r.measured_at >= p_from
      AND r.measured_at < p_to;
$$;


-- ============================================================
-- ФУНКЦІЯ 2.
-- Зведена статистика відхилень для каналу
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_channel_alert_summary(
    p_channel_code text
)
RETURNS TABLE (
    total_alerts bigint,
    active_alerts bigint,
    resolved_alerts bigint,
    last_alert_at timestamptz
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        COUNT(*)::bigint,
        COUNT(*) FILTER (
            WHERE a.resolved_at IS NULL
        )::bigint,
        COUNT(*) FILTER (
            WHERE a.resolved_at IS NOT NULL
        )::bigint,
        MAX(a.opened_at)
    FROM public.alerts a
    JOIN public.alert_rules ar
        ON ar.id = a.rule_id
    JOIN public.sensor_channels sc
        ON sc.id = ar.channel_id
    WHERE sc.channel_code = p_channel_code;
$$;


-- ============================================================
-- ПРОЦЕДУРА.
-- Підтвердження оператором зареєстрованого відхилення
-- ============================================================

CREATE OR REPLACE PROCEDURE public.acknowledge_alert(
    p_alert_id bigint,
    p_acknowledged_by text
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_rows integer;
BEGIN
    IF p_acknowledged_by IS NULL
       OR btrim(p_acknowledged_by) = '' THEN
        RAISE EXCEPTION
            'Ім''я користувача, який підтверджує відхилення, не може бути порожнім';
    END IF;

    UPDATE public.alerts
    SET
        acknowledged = true,
        acknowledged_at = clock_timestamp(),
        acknowledged_by = p_acknowledged_by
    WHERE id = p_alert_id
      AND acknowledged = false;

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows = 0 THEN
        IF NOT EXISTS (
            SELECT 1
            FROM public.alerts
            WHERE id = p_alert_id
        ) THEN
            RAISE EXCEPTION
                'Відхилення з id=% не існує',
                p_alert_id;
        ELSE
            RAISE EXCEPTION
                'Відхилення з id=% уже підтверджено',
                p_alert_id;
        END IF;
    END IF;
END;
$$;

COMMIT;
