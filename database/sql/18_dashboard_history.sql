
-- ============================================================
-- 18_dashboard_history
-- Агрегація історії вимірювань для графіків вебінтерфейсу
-- ============================================================
--
-- Функція формує усереднені значення вимірювань
-- за часовими інтервалами залежно від періоду графіка.
--
-- Підтримувані періоди:
--   6 годин   - інтервал агрегації 2 хвилини;
--   24 години - інтервал агрегації 10 хвилин;
--   72 години - інтервал агрегації 30 хвилин;
--   168 годин - інтервал агрегації 1 година.
--
-- Агрегація виконується на рівні PostgreSQL.
-- Початкові записи в таблиці readings не змінюються.
--
-- Функція призначена для використання серверною
-- частиною системи через Supabase Edge Functions.
-- ============================================================

BEGIN;

-- ============================================================
-- 1. Функція отримання агрегованої історії вимірювань
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_dashboard_history(
    p_hours integer DEFAULT 24
)
RETURNS TABLE (
    channel_code text,
    measured_at timestamptz,
    value numeric
)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    WITH settings AS (
        SELECT
            LEAST(
                GREATEST(COALESCE(p_hours, 24), 1),
                168
            ) AS hours
    ),

    bounds AS (
        SELECT
            now() AS to_time,

            now() - hours * INTERVAL '1 hour'
                AS from_time,

            CASE
                WHEN hours <= 6
                    THEN INTERVAL '2 minutes'

                WHEN hours <= 24
                    THEN INTERVAL '10 minutes'

                WHEN hours <= 72
                    THEN INTERVAL '30 minutes'

                ELSE INTERVAL '1 hour'
            END AS bucket_interval

        FROM settings
    )

    SELECT
        sc.channel_code,

        date_bin(
            b.bucket_interval,
            rd.measured_at,
            '2000-01-01 00:00:00+00'::timestamptz
        ) AS measured_at,

        ROUND(AVG(rd.value), 4) AS value

    FROM public.readings rd

    JOIN public.sensor_channels sc
        ON sc.id = rd.channel_id

    CROSS JOIN bounds b

    WHERE rd.is_valid = true
      AND rd.measured_at >= b.from_time
      AND rd.measured_at <= b.to_time

    GROUP BY
        sc.channel_code,

        date_bin(
            b.bucket_interval,
            rd.measured_at,
            '2000-01-01 00:00:00+00'::timestamptz
        )

    ORDER BY
        measured_at,
        channel_code;
$$;


-- ============================================================
-- 2. Обмеження публічного доступу до функції
-- ============================================================

REVOKE EXECUTE
ON FUNCTION public.get_dashboard_history(integer)
FROM PUBLIC;


-- ============================================================
-- 3. Дозвіл виконання серверній ролі Supabase
-- ============================================================

GRANT EXECUTE
ON FUNCTION public.get_dashboard_history(integer)
TO service_role;


COMMIT;


-- ============================================================
-- 4. Контрольна перевірка функції
-- ============================================================
--
-- Перевіряється кількість агрегованих точок
-- та часові межі доступної історії для кожного каналу.
--
-- Очікується:
--   - наявність даних для чотирьох каналів;
--   - відсутність помилок виконання;
--   - коректні часові межі.
-- ============================================================

SELECT
    channel_code,

    COUNT(*) AS chart_points,

    MIN(measured_at) AS first_point,

    MAX(measured_at) AS last_point

FROM public.get_dashboard_history(24)

GROUP BY
    channel_code

ORDER BY
    channel_code;


-- ============================================================
-- 5. Перевірка прав виконання функції
-- ============================================================
--
-- service_role повинен мати право EXECUTE.
-- anon та authenticated не повинні мати такого права.
-- ============================================================

SELECT
    role_name,

    has_function_privilege(
        role_name,
        'public.get_dashboard_history(integer)',
        'EXECUTE'
    ) AS can_execute

FROM (
    VALUES
        ('anon'),
        ('authenticated'),
        ('service_role')
) AS roles(role_name)

ORDER BY
    role_name;


-- ============================================================
-- ПІДСУМОК
-- ============================================================
--
-- Створено функцію get_dashboard_history(integer).
--
-- Функція:
--   - отримує вимірювання за вибраний період;
--   - враховує лише достовірні показники;
--   - групує дані за часовими інтервалами;
--   - обчислює середнє значення для кожного каналу;
--   - повертає дані в хронологічному порядку.
--
-- Вихідні вимірювання зберігаються без змін.
--
-- Доступ до функції надається серверній ролі.
--
-- Отримані дані використовуються для побудови
-- графіків вебінтерфейсу системи моніторингу.
-- ============================================================

