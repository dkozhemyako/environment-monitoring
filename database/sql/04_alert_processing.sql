BEGIN;

-- ============================================================
-- Функція оброблення відхилень
-- ============================================================

CREATE OR REPLACE FUNCTION public.process_reading_alert()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_rule_id bigint;
    v_min_value numeric(14,4);
    v_max_value numeric(14,4);
    v_out_of_range boolean;
BEGIN
    -- Недостовірні покази не впливають на історію відхилень.
    IF NEW.is_valid = false THEN
        RETURN NEW;
    END IF;

    SELECT
        ar.id,
        ar.min_value,
        ar.max_value
    INTO
        v_rule_id,
        v_min_value,
        v_max_value
    FROM public.alert_rules ar
    WHERE ar.channel_id = NEW.channel_id
      AND ar.is_active = true;

    -- Якщо активного правила немає, нічого не робимо.
    IF NOT FOUND THEN
        RETURN NEW;
    END IF;

    v_out_of_range :=
           (v_min_value IS NOT NULL AND NEW.value < v_min_value)
        OR (v_max_value IS NOT NULL AND NEW.value > v_max_value);

    IF v_out_of_range THEN

        -- Створюємо відхилення лише якщо для правила
        -- ще немає активного alert.
        INSERT INTO public.alerts (
            rule_id,
            opened_by_reading_id,
            actual_value,
            opened_at
        )
        SELECT
            v_rule_id,
            NEW.id,
            NEW.value,
            NEW.measured_at
        WHERE NOT EXISTS (
            SELECT 1
            FROM public.alerts a
            WHERE a.rule_id = v_rule_id
              AND a.resolved_at IS NULL
        );

    ELSE

        -- Повернення параметра в допустимий діапазон
        -- закриває активне відхилення.
        UPDATE public.alerts
        SET
            resolved_by_reading_id = NEW.id,
            resolved_at = NEW.measured_at
        WHERE rule_id = v_rule_id
          AND resolved_at IS NULL;

    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_process_reading_alert
ON public.readings;

CREATE TRIGGER trg_process_reading_alert
AFTER INSERT
ON public.readings
FOR EACH ROW
EXECUTE FUNCTION public.process_reading_alert();

COMMIT;
