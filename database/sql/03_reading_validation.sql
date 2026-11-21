BEGIN;

-- ============================================================
-- Функція перевірки фізично допустимого діапазону
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_reading_physical_range()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_type_name text;
    v_physical_min numeric(14,4);
    v_physical_max numeric(14,4);
BEGIN
    SELECT
        st.name,
        st.physical_min,
        st.physical_max
    INTO
        v_type_name,
        v_physical_min,
        v_physical_max
    FROM public.sensor_channels sc
    JOIN public.sensor_types st
        ON st.id = sc.sensor_type_id
    WHERE sc.id = NEW.channel_id;

    -- Якщо channel_id не існує, пропускаємо цю перевірку.
    -- Помилку сформує FOREIGN KEY таблиці readings.
    IF NOT FOUND THEN
        RETURN NEW;
    END IF;

    IF NEW.value < v_physical_min
       OR NEW.value > v_physical_max THEN

        RAISE EXCEPTION
            'Значення % для % виходить за фізично допустимий діапазон [% .. %]',
            NEW.value,
            v_type_name,
            v_physical_min,
            v_physical_max;
    END IF;

    RETURN NEW;
END;
$$;


-- ============================================================
-- Тригер
-- ============================================================

DROP TRIGGER IF EXISTS trg_validate_reading_physical_range
ON public.readings;

CREATE TRIGGER trg_validate_reading_physical_range
BEFORE INSERT OR UPDATE OF channel_id, value
ON public.readings
FOR EACH ROW
EXECUTE FUNCTION public.validate_reading_physical_range();

COMMIT;
