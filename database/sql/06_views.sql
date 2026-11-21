BEGIN;

-- ============================================================
-- VIEW 1. Поточний стан усіх вимірювальних каналів
-- ============================================================

CREATE OR REPLACE VIEW public.v_current_sensor_state AS

SELECT
    r.id AS room_id,
    r.room_code,
    r.name AS room_name,

    d.id AS device_id,
    d.device_code,
    d.name AS device_name,
    d.last_seen_at,

    s.id AS sensor_id,
    s.sensor_code,
    s.model AS sensor_model,

    sc.id AS channel_id,
    sc.channel_code,
    sc.name AS channel_name,

    st.type_code,
    st.name AS measurement_type,
    st.unit,

    lr.reading_id,
    lr.measured_at,
    lr.received_at,
    lr.value,
    lr.is_valid,
    lr.time_synced,

    ar.min_value AS allowed_min,
    ar.max_value AS allowed_max,

    CASE
        WHEN lr.reading_id IS NULL THEN 'NO_DATA'
        WHEN lr.is_valid = false THEN 'INVALID'
        WHEN ar.id IS NULL OR ar.is_active = false THEN 'NO_RULE'
        WHEN
            (ar.min_value IS NOT NULL AND lr.value < ar.min_value)
            OR
            (ar.max_value IS NOT NULL AND lr.value > ar.max_value)
            THEN 'ALERT'
        ELSE 'NORMAL'
    END AS status

FROM public.sensor_channels sc

JOIN public.sensors s
    ON s.id = sc.sensor_id

JOIN public.devices d
    ON d.id = s.device_id

JOIN public.rooms r
    ON r.id = d.room_id

JOIN public.sensor_types st
    ON st.id = sc.sensor_type_id

LEFT JOIN public.alert_rules ar
    ON ar.channel_id = sc.id

LEFT JOIN LATERAL (
    SELECT
        rd.id AS reading_id,
        rd.measured_at,
        rd.received_at,
        rd.value,
        rd.is_valid,
        rd.time_synced
    FROM public.readings rd
    WHERE rd.channel_id = sc.id
    ORDER BY rd.measured_at DESC, rd.id DESC
    LIMIT 1
) lr ON true;


-- ============================================================
-- VIEW 2. Історія відхилень
-- ============================================================

CREATE OR REPLACE VIEW public.v_alert_history AS

SELECT
    a.id AS alert_id,

    r.room_code,
    r.name AS room_name,

    d.device_code,

    s.sensor_code,
    s.model AS sensor_model,

    sc.channel_code,

    st.name AS measurement_type,
    st.unit,

    ar.min_value AS allowed_min,
    ar.max_value AS allowed_max,

    a.actual_value,
    a.opened_at,
    a.resolved_at,

    CASE
        WHEN a.resolved_at IS NULL
            THEN 'ACTIVE'
        ELSE 'RESOLVED'
    END AS alert_status,

    a.acknowledged,
    a.acknowledged_at,
    a.acknowledged_by,

    a.opened_by_reading_id,
    a.resolved_by_reading_id

FROM public.alerts a

JOIN public.alert_rules ar
    ON ar.id = a.rule_id

JOIN public.sensor_channels sc
    ON sc.id = ar.channel_id

JOIN public.sensor_types st
    ON st.id = sc.sensor_type_id

JOIN public.sensors s
    ON s.id = sc.sensor_id

JOIN public.devices d
    ON d.id = s.device_id

JOIN public.rooms r
    ON r.id = d.room_id;

COMMIT;
