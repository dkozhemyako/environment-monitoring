-- ============================================================
-- 13_explain_analysis
-- Аналіз та порівняння планів виконання запитів
-- ============================================================

-- Оновлення статистики оптимізатора PostgreSQL
ANALYZE public.readings;


-- ============================================================
-- EXPLAIN 01.
-- Вибірка вимірювань одного каналу за часовим інтервалом
-- ============================================================

-- Переконуємося, що індекс за часом існує
CREATE INDEX IF NOT EXISTS ix_readings_measured_at
ON public.readings (measured_at);


-- ------------------------------------------------------------
-- Варіант 1А.
-- Виконання за наявності окремого індексу measured_at
-- ------------------------------------------------------------

EXPLAIN (ANALYZE, BUFFERS)
SELECT
    id,
    channel_id,
    measured_at,
    value
FROM public.readings
WHERE channel_id = (
    SELECT id
    FROM public.sensor_channels
    WHERE channel_code = 'AHT20-TEMP'
)
AND measured_at >= '2026-10-15 00:00:00+03'
AND measured_at <  '2026-10-16 00:00:00+03'
ORDER BY measured_at DESC;


-- ------------------------------------------------------------
-- Тимчасово видаляємо окремий індекс за measured_at,
-- щоб порівняти вибір плану PostgreSQL
-- ------------------------------------------------------------

DROP INDEX IF EXISTS public.ix_readings_measured_at;


-- ------------------------------------------------------------
-- Варіант 1Б.
-- Той самий запит без окремого індексу measured_at.
-- PostgreSQL може використати складений індекс
-- (channel_id, measured_at)
-- ------------------------------------------------------------

EXPLAIN (ANALYZE, BUFFERS)
SELECT
    id,
    channel_id,
    measured_at,
    value
FROM public.readings
WHERE channel_id = (
    SELECT id
    FROM public.sensor_channels
    WHERE channel_code = 'AHT20-TEMP'
)
AND measured_at >= '2026-10-15 00:00:00+03'
AND measured_at <  '2026-10-16 00:00:00+03'
ORDER BY measured_at DESC;


-- ------------------------------------------------------------
-- Повертаємо індекс, щоб не змінювати робочу структуру БД
-- ------------------------------------------------------------

CREATE INDEX IF NOT EXISTS ix_readings_measured_at
ON public.readings (measured_at);


-- ============================================================
-- EXPLAIN 02.
-- Отримання останнього валідного вимірювання кожного каналу
-- ============================================================

-- ------------------------------------------------------------
-- Варіант 2А.
-- DISTINCT ON
-- PostgreSQL проходить великий обсяг readings,
-- після чого залишає по одному запису на канал
-- ------------------------------------------------------------

EXPLAIN (ANALYZE, BUFFERS)
SELECT DISTINCT ON (channel_id)
    channel_id,
    measured_at,
    value
FROM public.readings
WHERE is_valid = true
ORDER BY
    channel_id,
    measured_at DESC;


-- ------------------------------------------------------------
-- Варіант 2Б.
-- Оптимізований варіант через LATERAL + LIMIT 1.
-- Для кожного каналу виконується точковий пошук
-- останнього валідного вимірювання
-- ------------------------------------------------------------

EXPLAIN (ANALYZE, BUFFERS)
SELECT
    sc.id AS channel_id,
    rd.measured_at,
    rd.value
FROM public.sensor_channels sc
CROSS JOIN LATERAL (
    SELECT
        r.measured_at,
        r.value
    FROM public.readings r
    WHERE r.channel_id = sc.id
      AND r.is_valid = true
    ORDER BY r.measured_at DESC
    LIMIT 1
) rd;


-- ============================================================
-- ПІДСУМОК ЕКСПЕРИМЕНТУ
-- ============================================================
--
-- EXPLAIN 01:
-- порівнюється вибір індексу для фільтрації вимірювань
-- за channel_id та часовим інтервалом.
--
-- EXPLAIN 02:
-- порівнюються два способи отримання останнього вимірювання
-- для кожного каналу.
--
-- На тестовому наборі з приблизно 34 600 вимірювань
-- варіант DISTINCT ON переглядав усі записи readings,
-- тоді як LATERAL + LIMIT 1 виконував окремий індексний
-- пошук останнього запису для кожного каналу.
--
-- Фактичний Execution Time може відрізнятися між запусками
-- через кешування та поточне навантаження сервера.
-- ============================================================
