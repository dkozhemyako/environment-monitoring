-- ============================================================
-- SELECT 01.
-- Журнал вимірювань із даними про канал, датчик і приміщення
-- ============================================================

SELECT
    rd.id AS reading_id,
    rm.room_code,
    d.device_code,
    s.sensor_code,
    sc.channel_code,
    st.name AS measurement_type,
    rd.measured_at,
    rd.value,
    st.unit,
    rd.is_valid,
    rd.time_synced
FROM public.readings rd
JOIN public.sensor_channels sc
    ON sc.id = rd.channel_id
JOIN public.sensor_types st
    ON st.id = sc.sensor_type_id
JOIN public.sensors s
    ON s.id = sc.sensor_id
JOIN public.devices d
    ON d.id = s.device_id
JOIN public.rooms rm
    ON rm.id = d.room_id
ORDER BY rd.measured_at, rd.id;

-- ============================================================
-- SELECT 02.
-- Останній вимір для кожного каналу
-- ============================================================

SELECT DISTINCT ON (sc.id)
    sc.channel_code,
    st.name AS measurement_type,
    rd.measured_at,
    rd.value,
    st.unit,
    rd.is_valid
FROM public.sensor_channels sc
JOIN public.sensor_types st
    ON st.id = sc.sensor_type_id
LEFT JOIN public.readings rd
    ON rd.channel_id = sc.id
ORDER BY
    sc.id,
    rd.measured_at DESC NULLS LAST,
    rd.id DESC NULLS LAST;

    -- ============================================================
-- SELECT 03.
-- Статистика вимірювань по кожному каналу
-- ============================================================

SELECT
    sc.channel_code,
    st.name AS measurement_type,
    COUNT(rd.id) AS readings_count,
    ROUND(AVG(rd.value), 2) AS avg_value,
    MIN(rd.value) AS min_value,
    MAX(rd.value) AS max_value,
    st.unit
FROM public.sensor_channels sc
JOIN public.sensor_types st
    ON st.id = sc.sensor_type_id
LEFT JOIN public.readings rd
    ON rd.channel_id = sc.id
   AND rd.is_valid = true
GROUP BY
    sc.id,
    sc.channel_code,
    st.name,
    st.unit
ORDER BY sc.id;

-- ============================================================
-- SELECT 04.
-- Вимірювання поза допустимим робочим діапазоном
-- ============================================================

SELECT
    rd.id AS reading_id,
    sc.channel_code,
    st.name AS measurement_type,
    rd.measured_at,
    rd.value,
    ar.min_value AS allowed_min,
    ar.max_value AS allowed_max,
    st.unit
FROM public.readings rd
JOIN public.sensor_channels sc
    ON sc.id = rd.channel_id
JOIN public.sensor_types st
    ON st.id = sc.sensor_type_id
JOIN public.alert_rules ar
    ON ar.channel_id = sc.id
WHERE rd.is_valid = true
  AND (
        (ar.min_value IS NOT NULL AND rd.value < ar.min_value)
        OR
        (ar.max_value IS NOT NULL AND rd.value > ar.max_value)
      )
ORDER BY rd.measured_at;

-- ============================================================
-- SELECT 05.
-- Кількість зареєстрованих відхилень по кожному каналу
-- ============================================================

SELECT
    sc.channel_code,
    st.name AS measurement_type,
    COUNT(a.id) AS alerts_count,
    COUNT(a.id) FILTER (
        WHERE a.resolved_at IS NULL
    ) AS active_alerts,
    COUNT(a.id) FILTER (
        WHERE a.resolved_at IS NOT NULL
    ) AS resolved_alerts
FROM public.sensor_channels sc
JOIN public.sensor_types st
    ON st.id = sc.sensor_type_id
LEFT JOIN public.alert_rules ar
    ON ar.channel_id = sc.id
LEFT JOIN public.alerts a
    ON a.rule_id = ar.id
GROUP BY
    sc.id,
    sc.channel_code,
    st.name
ORDER BY sc.id;

-- ============================================================
-- SELECT 06.
-- Канали без жодного вимірювання
-- ============================================================

SELECT
    sc.channel_code,
    st.name AS measurement_type,
    st.unit
FROM public.sensor_channels sc
JOIN public.sensor_types st
    ON st.id = sc.sensor_type_id
LEFT JOIN public.readings rd
    ON rd.channel_id = sc.id
WHERE rd.id IS NULL
ORDER BY sc.id;

-- ============================================================
-- SELECT 07.
-- Вимірювання температури за заданий часовий інтервал
-- ============================================================

SELECT
    rd.id AS reading_id,
    sc.channel_code,
    rd.measured_at,
    rd.value,
    st.unit
FROM public.readings rd
JOIN public.sensor_channels sc
    ON sc.id = rd.channel_id
JOIN public.sensor_types st
    ON st.id = sc.sensor_type_id
WHERE sc.channel_code = 'AHT20-TEMP'
  AND rd.measured_at >= '2026-11-18 08:00:00+02'
  AND rd.measured_at <  '2026-11-18 08:04:00+02'
ORDER BY rd.measured_at;

-- ============================================================
-- SELECT 08.
-- Добова статистика вимірювань по каналах
-- ============================================================

SELECT
    sc.channel_code,
    date_trunc('day', rd.measured_at) AS measurement_day,
    COUNT(*) AS readings_count,
    ROUND(AVG(rd.value), 2) AS avg_value,
    MIN(rd.value) AS min_value,
    MAX(rd.value) AS max_value
FROM public.readings rd
JOIN public.sensor_channels sc
    ON sc.id = rd.channel_id
WHERE rd.is_valid = true
GROUP BY
    sc.channel_code,
    date_trunc('day', rd.measured_at)
ORDER BY
    measurement_day,
    sc.channel_code;

    -- ============================================================
-- SELECT 09.
-- Зміна значення відносно попереднього вимірювання
-- ============================================================

SELECT
    sc.channel_code,
    rd.measured_at,
    rd.value,
    LAG(rd.value) OVER (
        PARTITION BY rd.channel_id
        ORDER BY rd.measured_at
    ) AS previous_value,
    rd.value
        - LAG(rd.value) OVER (
            PARTITION BY rd.channel_id
            ORDER BY rd.measured_at
          ) AS value_change
FROM public.readings rd
JOIN public.sensor_channels sc
    ON sc.id = rd.channel_id
WHERE rd.is_valid = true
ORDER BY
    sc.channel_code,
    rd.measured_at;

    -- ============================================================
-- SELECT 10.
-- Ранжування вимірювань за значенням у межах кожного каналу
-- ============================================================

SELECT
    sc.channel_code,
    rd.measured_at,
    rd.value,
    DENSE_RANK() OVER (
        PARTITION BY rd.channel_id
        ORDER BY rd.value DESC
    ) AS value_rank
FROM public.readings rd
JOIN public.sensor_channels sc
    ON sc.id = rd.channel_id
WHERE rd.is_valid = true
ORDER BY
    sc.channel_code,
    value_rank,
    rd.measured_at;

    -- ============================================================
-- SELECT 11.
-- Тривалість зареєстрованих відхилень
-- ============================================================

SELECT
    a.id AS alert_id,
    sc.channel_code,
    a.opened_at,
    a.resolved_at,
    a.resolved_at - a.opened_at AS alert_duration,
    a.actual_value,
    st.unit
FROM public.alerts a
JOIN public.alert_rules ar
    ON ar.id = a.rule_id
JOIN public.sensor_channels sc
    ON sc.id = ar.channel_id
JOIN public.sensor_types st
    ON st.id = sc.sensor_type_id
ORDER BY a.opened_at;

-- ============================================================
-- SELECT 12.
-- Кількість вимірювань по фізичних датчиках
-- ============================================================

SELECT
    s.sensor_code,
    s.model AS sensor_model,
    COUNT(rd.id) AS readings_count
FROM public.sensors s
LEFT JOIN public.sensor_channels sc
    ON sc.sensor_id = s.id
LEFT JOIN public.readings rd
    ON rd.channel_id = sc.id
GROUP BY
    s.id,
    s.sensor_code,
    s.model
ORDER BY s.id;

-- ============================================================
-- SELECT 13.
-- Стан активності обладнання та каналів
-- ============================================================

SELECT
    d.device_code,
    d.is_active AS device_active,
    s.sensor_code,
    s.is_active AS sensor_active,
    sc.channel_code,
    sc.is_active AS channel_active
FROM public.devices d
JOIN public.sensors s
    ON s.device_id = d.id
JOIN public.sensor_channels sc
    ON sc.sensor_id = s.id
ORDER BY
    d.device_code,
    s.sensor_code,
    sc.channel_code;

-- ============================================================
-- SELECT 14.
-- Канали, у яких останній показ виходить за робочий діапазон
-- ============================================================

WITH latest_readings AS (
    SELECT DISTINCT ON (rd.channel_id)
        rd.channel_id,
        rd.measured_at,
        rd.value,
        rd.is_valid
    FROM public.readings rd
    ORDER BY
        rd.channel_id,
        rd.measured_at DESC,
        rd.id DESC
)
SELECT
    sc.channel_code,
    st.name AS measurement_type,
    lr.measured_at,
    lr.value,
    ar.min_value AS allowed_min,
    ar.max_value AS allowed_max,
    st.unit
FROM latest_readings lr
JOIN public.sensor_channels sc
    ON sc.id = lr.channel_id
JOIN public.sensor_types st
    ON st.id = sc.sensor_type_id
JOIN public.alert_rules ar
    ON ar.channel_id = sc.id
WHERE lr.is_valid = true
  AND (
        (ar.min_value IS NOT NULL AND lr.value < ar.min_value)
        OR
        (ar.max_value IS NOT NULL AND lr.value > ar.max_value)
      )
ORDER BY sc.channel_code;

-- ============================================================
-- SELECT 15.
-- Відхилення останнього показу від середнього значення каналу
-- ============================================================

WITH channel_stats AS (
    SELECT
        channel_id,
        AVG(value) AS avg_value
    FROM public.readings
    WHERE is_valid = true
    GROUP BY channel_id
),
latest_readings AS (
    SELECT DISTINCT ON (channel_id)
        channel_id,
        measured_at,
        value
    FROM public.readings
    WHERE is_valid = true
    ORDER BY
        channel_id,
        measured_at DESC,
        id DESC
)
SELECT
    sc.channel_code,
    lr.measured_at,
    lr.value AS latest_value,
    ROUND(cs.avg_value, 2) AS avg_value,
    ROUND(lr.value - cs.avg_value, 2) AS deviation_from_avg,
    st.unit
FROM latest_readings lr
JOIN channel_stats cs
    ON cs.channel_id = lr.channel_id
JOIN public.sensor_channels sc
    ON sc.id = lr.channel_id
JOIN public.sensor_types st
    ON st.id = sc.sensor_type_id
ORDER BY sc.id;
