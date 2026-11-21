-- ============================================================
-- DATA MODIFICATION 01.
-- Додавання нового приміщення
-- ============================================================

INSERT INTO public.rooms (
    room_code,
    name,
    building,
    floor,
    description
)
VALUES (
    'ROOM-TEST',
    'Тестове приміщення',
    'Навчальний корпус',
    2,
    'Тимчасовий запис для демонстрації операцій зміни даних'
)
RETURNING
    id,
    room_code,
    name,
    building,
    floor;

-- ============================================================
-- DATA MODIFICATION 02.
-- Оновлення параметрів тестового приміщення
-- ============================================================

UPDATE public.rooms
SET
    name = 'Тестова лабораторія',
    floor = 3,
    description = 'Оновлений тестовий запис для перевірки UPDATE'
WHERE room_code = 'ROOM-TEST'
RETURNING
    id,
    room_code,
    name,
    building,
    floor,
    description;

-- ============================================================
-- DATA MODIFICATION 03.
-- UPSERT приміщення за унікальним room_code
-- ============================================================

INSERT INTO public.rooms (
    room_code,
    name,
    building,
    floor,
    description
)
VALUES (
    'ROOM-TEST',
    'Лабораторія після UPSERT',
    'Навчальний корпус',
    4,
    'Запис оновлено через INSERT ... ON CONFLICT'
)
ON CONFLICT (room_code)
DO UPDATE SET
    name = EXCLUDED.name,
    building = EXCLUDED.building,
    floor = EXCLUDED.floor,
    description = EXCLUDED.description
RETURNING
    id,
    room_code,
    name,
    building,
    floor,
    description;

-- ============================================================
-- DATA MODIFICATION 04.
-- Видалення тестового приміщення
-- ============================================================

DELETE FROM public.rooms
WHERE room_code = 'ROOM-TEST'
RETURNING
    id,
    room_code,
    name;
