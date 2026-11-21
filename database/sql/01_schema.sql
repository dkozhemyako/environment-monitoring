BEGIN;

-- ============================================================
-- 1. Приміщення
-- ============================================================

CREATE TABLE public.rooms (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    room_code text NOT NULL,
    name text NOT NULL,
    building text,
    floor smallint,
    description text,

    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT rooms_room_code_uq UNIQUE (room_code),

    CONSTRAINT rooms_room_code_not_blank_chk
        CHECK (btrim(room_code) <> ''),

    CONSTRAINT rooms_name_not_blank_chk
        CHECK (btrim(name) <> '')
);


-- ============================================================
-- 2. Пристрої моніторингу
-- ============================================================

CREATE TABLE public.devices (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    room_id bigint NOT NULL
        REFERENCES public.rooms(id)
        ON DELETE RESTRICT,

    device_code text NOT NULL,
    name text NOT NULL,
    model text NOT NULL,

    firmware_version text,
    installed_at timestamptz,
    last_seen_at timestamptz,

    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT devices_device_code_uq UNIQUE (device_code),

    CONSTRAINT devices_device_code_not_blank_chk
        CHECK (btrim(device_code) <> ''),

    CONSTRAINT devices_name_not_blank_chk
        CHECK (btrim(name) <> ''),

    CONSTRAINT devices_model_not_blank_chk
        CHECK (btrim(model) <> '')
);


-- ============================================================
-- 3. Типи вимірюваних величин
-- ============================================================

CREATE TABLE public.sensor_types (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    type_code text NOT NULL,
    name text NOT NULL,
    unit text NOT NULL,

    physical_min numeric(14,4) NOT NULL,
    physical_max numeric(14,4) NOT NULL,

    decimal_places smallint NOT NULL DEFAULT 2,

    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT sensor_types_type_code_uq UNIQUE (type_code),

    CONSTRAINT sensor_types_type_code_not_blank_chk
        CHECK (btrim(type_code) <> ''),

    CONSTRAINT sensor_types_name_not_blank_chk
        CHECK (btrim(name) <> ''),

    CONSTRAINT sensor_types_unit_not_blank_chk
        CHECK (btrim(unit) <> ''),

    CONSTRAINT sensor_types_physical_range_chk
        CHECK (physical_min < physical_max),

    CONSTRAINT sensor_types_decimal_places_chk
        CHECK (decimal_places BETWEEN 0 AND 6)
);


-- ============================================================
-- 4. Фізичні датчики
-- ============================================================

CREATE TABLE public.sensors (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    device_id bigint NOT NULL
        REFERENCES public.devices(id)
        ON DELETE RESTRICT,

    sensor_code text NOT NULL,
    model text NOT NULL,
    manufacturer text,

    interface_type text,
    bus_address text,

    installed_at timestamptz,
    is_active boolean NOT NULL DEFAULT true,

    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT sensors_sensor_code_uq UNIQUE (sensor_code),

    CONSTRAINT sensors_sensor_code_not_blank_chk
        CHECK (btrim(sensor_code) <> ''),

    CONSTRAINT sensors_model_not_blank_chk
        CHECK (btrim(model) <> '')
);


-- ============================================================
-- 5. Вимірювальні канали датчиків
-- ============================================================

CREATE TABLE public.sensor_channels (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    sensor_id bigint NOT NULL
        REFERENCES public.sensors(id)
        ON DELETE RESTRICT,

    sensor_type_id bigint NOT NULL
        REFERENCES public.sensor_types(id)
        ON DELETE RESTRICT,

    channel_code text NOT NULL,
    name text NOT NULL,

    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT sensor_channels_channel_code_uq
        UNIQUE (channel_code),

    CONSTRAINT sensor_channels_sensor_type_uq
        UNIQUE (sensor_id, sensor_type_id),

    CONSTRAINT sensor_channels_channel_code_not_blank_chk
        CHECK (btrim(channel_code) <> ''),

    CONSTRAINT sensor_channels_name_not_blank_chk
        CHECK (btrim(name) <> '')
);


-- ============================================================
-- 6. Результати вимірювань
-- ============================================================

CREATE TABLE public.readings (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    channel_id bigint NOT NULL
        REFERENCES public.sensor_channels(id)
        ON DELETE RESTRICT,

    measured_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now(),

    value numeric(14,4) NOT NULL,

    is_valid boolean NOT NULL DEFAULT true,
    time_synced boolean NOT NULL DEFAULT true,

    CONSTRAINT readings_channel_time_uq
        UNIQUE (channel_id, measured_at)
);


-- ============================================================
-- 7. Допустимі робочі діапазони
-- ============================================================

CREATE TABLE public.alert_rules (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    channel_id bigint NOT NULL
        REFERENCES public.sensor_channels(id)
        ON DELETE RESTRICT,

    min_value numeric(14,4),
    max_value numeric(14,4),

    is_active boolean NOT NULL DEFAULT true,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT alert_rules_channel_uq
        UNIQUE (channel_id),

    CONSTRAINT alert_rules_has_limit_chk
        CHECK (
            min_value IS NOT NULL
            OR max_value IS NOT NULL
        ),

    CONSTRAINT alert_rules_range_chk
        CHECK (
            min_value IS NULL
            OR max_value IS NULL
            OR min_value < max_value
        )
);


-- ============================================================
-- 8. Історія відхилень
-- ============================================================

CREATE TABLE public.alerts (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    rule_id bigint NOT NULL
        REFERENCES public.alert_rules(id)
        ON DELETE RESTRICT,

    opened_by_reading_id bigint NOT NULL
        REFERENCES public.readings(id)
        ON DELETE RESTRICT,

    resolved_by_reading_id bigint
        REFERENCES public.readings(id)
        ON DELETE RESTRICT,

    actual_value numeric(14,4) NOT NULL,

    opened_at timestamptz NOT NULL DEFAULT now(),
    resolved_at timestamptz,

    acknowledged boolean NOT NULL DEFAULT false,
    acknowledged_at timestamptz,
    acknowledged_by text,

    CONSTRAINT alerts_resolution_chk
        CHECK (
            (resolved_at IS NULL AND resolved_by_reading_id IS NULL)
            OR
            (resolved_at IS NOT NULL AND resolved_by_reading_id IS NOT NULL)
        ),

    CONSTRAINT alerts_acknowledgement_chk
        CHECK (
            (acknowledged = false
                AND acknowledged_at IS NULL
                AND acknowledged_by IS NULL)
            OR
            (acknowledged = true
                AND acknowledged_at IS NOT NULL
                AND acknowledged_by IS NOT NULL)
        )
);


-- ============================================================
-- 9. Аудит зміни допустимих діапазонів
-- ============================================================

CREATE TABLE public.alert_rule_audit (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    rule_id bigint NOT NULL
        REFERENCES public.alert_rules(id)
        ON DELETE RESTRICT,

    old_min_value numeric(14,4),
    new_min_value numeric(14,4),

    old_max_value numeric(14,4),
    new_max_value numeric(14,4),

    old_is_active boolean NOT NULL,
    new_is_active boolean NOT NULL,

    changed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    changed_by text NOT NULL DEFAULT current_user
);


-- ============================================================
-- Індекси для зовнішніх ключів та основних запитів
-- ============================================================

CREATE INDEX ix_devices_room
    ON public.devices (room_id);

CREATE INDEX ix_sensors_device
    ON public.sensors (device_id);

CREATE INDEX ix_sensor_channels_sensor
    ON public.sensor_channels (sensor_id);

CREATE INDEX ix_sensor_channels_type
    ON public.sensor_channels (sensor_type_id);

CREATE INDEX ix_readings_channel_time
    ON public.readings (channel_id, measured_at DESC);

CREATE INDEX ix_readings_measured_at
    ON public.readings (measured_at DESC);

CREATE INDEX ix_alerts_rule_opened
    ON public.alerts (rule_id, opened_at DESC);

CREATE INDEX ix_alert_rule_audit_rule_changed
    ON public.alert_rule_audit (rule_id, changed_at DESC);


-- Одночасно для одного правила може існувати
-- лише одне незакрите відхилення.

CREATE UNIQUE INDEX uq_alerts_one_active_per_rule
    ON public.alerts (rule_id)
    WHERE resolved_at IS NULL;


COMMIT;
