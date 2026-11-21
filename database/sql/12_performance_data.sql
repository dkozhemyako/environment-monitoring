-- ============================================================
-- PERFORMANCE DATA.
-- Генерація тестових вимірювань для аналізу продуктивності
-- ============================================================

INSERT INTO public.readings (
    channel_id,
    measured_at,
    value,
    is_valid,
    time_synced
)
SELECT
    sc.id,
    gs.measured_at,
    CASE sc.channel_code
        WHEN 'AHT20-TEMP' THEN
            22 + 3 * sin(EXTRACT(EPOCH FROM gs.measured_at) / 3600.0)

        WHEN 'AHT20-HUM' THEN
            50 + 10 * sin(EXTRACT(EPOCH FROM gs.measured_at) / 4200.0)

        WHEN 'BMP280-PRESS' THEN
            1000 + 20 * sin(EXTRACT(EPOCH FROM gs.measured_at) / 7200.0)

        WHEN 'BH1750-LIGHT' THEN
            10000 + 8000 * sin(EXTRACT(EPOCH FROM gs.measured_at) / 5400.0)
    END::numeric(14,4),
    true,
    true
FROM public.sensor_channels sc
CROSS JOIN LATERAL generate_series(
    '2026-10-01 00:00:00+03'::timestamptz,
    '2026-10-30 23:55:00+02'::timestamptz,
    interval '5 minutes'
) AS gs(measured_at)
WHERE sc.channel_code IN (
    'AHT20-TEMP',
    'AHT20-HUM',
    'BMP280-PRESS',
    'BH1750-LIGHT'
)
ON CONFLICT (channel_id, measured_at) DO NOTHING;
