BEGIN;

-- ============================================================
-- 1. Приміщення
-- ============================================================

INSERT INTO public.rooms (
    room_code,
    name,
    building,
    floor,
    description
)
VALUES (
    'ROOM-001',
    'Кімната',
    'Житлове приміщення',
    1,
    'Приміщення, у якому встановлена навчальна система моніторингу'
);


-- ============================================================
-- 2. Станція моніторингу
-- ============================================================

INSERT INTO public.devices (
    room_id,
    device_code,
    name,
    model,
    firmware_version,
    installed_at
)
SELECT
    id,
    'ESP-001',
    'Environment Station 1',
    'ESP8266',
    '1.0.0',
    now()
FROM public.rooms
WHERE room_code = 'ROOM-001';


-- ============================================================
-- 3. Типи вимірюваних величин
-- ============================================================

INSERT INTO public.sensor_types (
    type_code,
    name,
    unit,
    physical_min,
    physical_max,
    decimal_places
)
VALUES
    (
        'TEMPERATURE',
        'Температура',
        '°C',
        -40,
        85,
        2
    ),
    (
        'HUMIDITY',
        'Відносна вологість',
        '%',
        0,
        100,
        2
    ),
    (
        'PRESSURE',
        'Атмосферний тиск',
        'hPa',
        300,
        1100,
        2
    ),
    (
        'LIGHT',
        'Освітленість',
        'lx',
        0,
        120000,
        2
    );


-- ============================================================
-- 4. Фізичні датчики
-- ============================================================

INSERT INTO public.sensors (
    device_id,
    sensor_code,
    model,
    manufacturer,
    interface_type,
    bus_address,
    installed_at
)
SELECT
    id,
    'AHT20-001',
    'AHT20',
    'ASAIR',
    'I2C',
    '0x38',
    now()
FROM public.devices
WHERE device_code = 'ESP-001';


INSERT INTO public.sensors (
    device_id,
    sensor_code,
    model,
    manufacturer,
    interface_type,
    bus_address,
    installed_at
)
SELECT
    id,
    'BMP280-001',
    'BMP280',
    'Bosch',
    'I2C',
    '0x77',
    now()
FROM public.devices
WHERE device_code = 'ESP-001';


INSERT INTO public.sensors (
    device_id,
    sensor_code,
    model,
    manufacturer,
    interface_type,
    bus_address,
    installed_at
)
SELECT
    id,
    'BH1750-001',
    'BH1750',
    'ROHM',
    'I2C',
    '0x23',
    now()
FROM public.devices
WHERE device_code = 'ESP-001';


-- ============================================================
-- 5. Вимірювальні канали
-- ============================================================

INSERT INTO public.sensor_channels (
    sensor_id,
    sensor_type_id,
    channel_code,
    name
)
VALUES (
    (SELECT id FROM public.sensors
     WHERE sensor_code = 'AHT20-001'),

    (SELECT id FROM public.sensor_types
     WHERE type_code = 'TEMPERATURE'),

    'AHT20-TEMP',
    'Температура AHT20'
);


INSERT INTO public.sensor_channels (
    sensor_id,
    sensor_type_id,
    channel_code,
    name
)
VALUES (
    (SELECT id FROM public.sensors
     WHERE sensor_code = 'AHT20-001'),

    (SELECT id FROM public.sensor_types
     WHERE type_code = 'HUMIDITY'),

    'AHT20-HUM',
    'Вологість AHT20'
);


INSERT INTO public.sensor_channels (
    sensor_id,
    sensor_type_id,
    channel_code,
    name
)
VALUES (
    (SELECT id FROM public.sensors
     WHERE sensor_code = 'BMP280-001'),

    (SELECT id FROM public.sensor_types
     WHERE type_code = 'PRESSURE'),

    'BMP280-PRESS',
    'Атмосферний тиск BMP280'
);


INSERT INTO public.sensor_channels (
    sensor_id,
    sensor_type_id,
    channel_code,
    name
)
VALUES (
    (SELECT id FROM public.sensors
     WHERE sensor_code = 'BH1750-001'),

    (SELECT id FROM public.sensor_types
     WHERE type_code = 'LIGHT'),

    'BH1750-LIGHT',
    'Освітленість BH1750'
);


-- ============================================================
-- 6. Робочі допустимі діапазони
-- ============================================================

INSERT INTO public.alert_rules (
    channel_id,
    min_value,
    max_value
)
VALUES
    (
        (SELECT id
         FROM public.sensor_channels
         WHERE channel_code = 'AHT20-TEMP'),
        15,
        30
    ),
    (
        (SELECT id
         FROM public.sensor_channels
         WHERE channel_code = 'AHT20-HUM'),
        30,
        70
    ),
    (
        (SELECT id
         FROM public.sensor_channels
         WHERE channel_code = 'BMP280-PRESS'),
        950,
        1050
    ),
    (
        (SELECT id
         FROM public.sensor_channels
         WHERE channel_code = 'BH1750-LIGHT'),
        0,
        50000
    );

COMMIT;
