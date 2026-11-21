# Система моніторингу параметрів мікроклімату приміщень

**Курсова робота з дисципліни «Бази даних»**  
**Тема:** «Проєктування та реалізація бази даних системи моніторингу температури та вологості приміщень»  
**Виконав:** Кожемяко Дмитро Володимирович, група Б-121-24-3-ПІ  
**Заклад освіти:** Національний університет «Київський авіаційний інститут»  
**Рік:** 2026

**Вебінтерфейс системи:** https://environment-monitoring-dashboard-two.vercel.app/

## 1. Призначення системи

Система призначена для автоматичного збирання, зберігання й аналізу показників температури, відносної вологості, атмосферного тиску та освітленості приміщення. Вимірювання надходять від контролера ESP8266 до бази даних PostgreSQL через Supabase Edge Functions. Вебінтерфейс відображає поточні значення, графіки за вибраний період та інформацію про відхилення від установлених меж.

Основні функції системи:

- зчитування чотирьох вимірюваних величин із трьох фізичних датчиків;
- накопичення вимірювань у локальній черзі LittleFS та пакетне передавання через HTTPS;
- збереження історії вимірювань у PostgreSQL;
- перевірка фізично допустимих значень і контроль робочих діапазонів;
- автоматична реєстрація, підтвердження та закриття відхилень;
- аудит змін правил контролю;
- відображення поточних значень і агрегованої історії у вебінтерфейсі.

### Архітектура

```text
AHT20 (температура, вологість)   BMP280 (тиск)   BH1750 (освітленість)
                 \                  |                 /
                         ESP8266
                       LittleFS
                           |
                      Wi-Fi / HTTPS
                           |
              Edge Function: ingest-readings
                           |
                 PostgreSQL / Supabase
                           |
              Edge Function: dashboard-data
                           |
              React / TypeScript / Recharts
```

## 2. Технології та версії

| Компонент | Технологія / версія |
|---|---|
| Система керування базами даних | PostgreSQL 17 (локальні перевірки з PostgreSQL 17.12) |
| Хмарна платформа | Supabase: PostgreSQL, Edge Functions (Deno) |
| Бібліотека серверного доступу | `@supabase/supabase-js@2` |
| Контролер | ESP8266, плата Wemos D1 |
| Середовище прошивки | PlatformIO, Arduino Framework, C++ |
| Датчики | AHT20, BMP280, BH1750 |
| Локальне зберігання | LittleFS |
| Вебінтерфейс | React 19, TypeScript 6, Vite 8, Recharts 3 |
| Середовище вебінтерфейсу | Node.js 22.12+ або 20.19+, npm |
| Інструменти | Git, VS Code, PlatformIO, Supabase CLI, `psql`, `pg_dump`, `pg_restore` |

Версії JavaScript-залежностей фіксуються у файлі `dashboard/package-lock.json`. Для встановлення залежностей використовується `npm ci`. Бібліотеки прошивки перелічені у `firmware/platformio.ini`. Додаткові розширення PostgreSQL (`CREATE EXTENSION`) для створення схеми не потрібні: використано стандартні засоби PostgreSQL 17.

## 3. Структура проєкту

```text
environment-monitoring/
├── database/
│   └── sql/                      SQL-скрипти створення й перевірки БД
├── supabase/
│   └── functions/
│       ├── ingest-readings/      Приймання пакетів вимірювань
│       └── dashboard-data/       Отримання даних для вебінтерфейсу
├── firmware/
│   ├── platformio.ini            Конфігурація ESP8266
│   └── src/main.cpp              Код прошивки
├── dashboard/                    Вебінтерфейс React
├── docs/
│   ├── diagrams/                 ER-діаграма
│   ├── evidence/                 Результати SQL-тестування
│   ├── report/                   Пояснювальна записка
│   └── presentation/             Презентація до захисту
└── README.md
```

## 4. Структура бази даних

База даних складається з **9 таблиць**:

| Таблиця | Призначення |
|---|---|
| `rooms` | Приміщення, у яких встановлено систему |
| `devices` | Контролери та інформація про їхній стан |
| `sensor_types` | Типи вимірюваних величин і фізично допустимі межі |
| `sensors` | Фізичні датчики, підключені до контролера |
| `sensor_channels` | Канали отримання вимірювань |
| `readings` | Історія вимірювань |
| `alert_rules` | Робочі діапазони контрольованих величин |
| `alerts` | Зафіксовані відхилення |
| `alert_rule_audit` | Історія змін правил контролю |

Створено два представлення: `v_current_sensor_state` та `v_alert_history`. Для перевірки вимірювань, керування відхиленнями й аудиту використовуються функції, процедура та тригери PostgreSQL. Модель даних наведено в `docs/diagrams/01_er_database_schema.png`.

## 5. Створення бази даних

Для відтворення використовується **новий проєкт Supabase** з порожньою прикладною схемою. Вбудовані службові об'єкти Supabase не видаляються. SQL-файли запускаються в **SQL Editor** з правами адміністратора у такій послідовності:

| Порядок | SQL-файл | Результат виконання |
|---|---|---|
| 1 | `00_environment_check.sql` | Отримання даних про версію PostgreSQL |
| 2 | `01_schema.sql` | Створення 9 таблиць, ключів, обмежень та індексів |
| 3 | `02_reference_data.sql` | Заповнення довідників, пристрою, каналів і правил |
| 4 | `03_reading_validation.sql` | Створення перевірки фізичних діапазонів |
| 5 | `04_alert_processing.sql` | Створення механізму реєстрації відхилень |
| 6 | `05_rule_audit.sql` | Створення аудиту змін правил |
| 7 | `06_views.sql` | Створення двох представлень |
| 8 | `07_functions_procedure.sql` | Створення функцій і процедури керування відхиленнями |
| 9 | `08_roles_permissions.sql` | Створення ролей і призначення прав |
| 10 | `16_rls_api_security.sql` | Налаштування доступу API-ролей Supabase та RLS |
| 11 | `18_dashboard_history.sql` | Створення функції агрегування даних для графіків |
| 12 | `17_final_validation.sql` | Підсумкова перевірка структури й даних |

**Примітка до порядку запуску:** SQL-файл `01_schema.sql` створює таблиці звичайними командами `CREATE TABLE` і призначений для одноразового виконання на новій схемі. Скрипти `16_rls_api_security.sql` та `18_dashboard_history.sql` використовують системні ролі Supabase (`anon`, `authenticated`, `service_role`), тому повна послідовність призначена саме для Supabase. У локальному PostgreSQL без цих ролей можна запускати базову частину `00–08`.

Файли `09_select_queries.sql`–`15_backup_restore.sql` містять запити, операції зміни даних, тести обмежень, аналіз планів, перевірку конкурентного доступу та резервного копіювання. Тестові операції виконуються на окремій копії бази даних.

### Перевірка створеної структури

Виконати в SQL Editor:

```sql
SELECT COUNT(*) AS tables_count
FROM information_schema.tables
WHERE table_schema = 'public' AND table_type = 'BASE TABLE';

SELECT table_name
FROM information_schema.views
WHERE table_schema = 'public'
ORDER BY table_name;

SELECT COUNT(*) AS triggers_count
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND NOT t.tgisinternal;
```

**Очікуваний результат:** 9 таблиць, 2 представлення та 3 користувацькі тригери.

Після виконання `02_reference_data.sql` у довідниках наявні приміщення `ROOM-001`, пристрій `ESP-001` і чотири вимірювальні канали: `AHT20-TEMP`, `AHT20-HUM`, `BMP280-PRESS`, `BH1750-LIGHT`.

## 6. Налаштування Supabase Edge Functions

Серверна частина складається з двох Edge Functions:

- `ingest-readings` — отримує вимірювання методом `POST` та перевіряє ключ пристрою в заголовку `x-device-key`;
- `dashboard-data` — обслуговує запити `GET` до поточних показників, історії та відхилень.

Налаштувати змінні середовища Supabase у розділі **Edge Functions → Secrets**:

| Змінна | Значення |
|---|---|
| `SUPABASE_URL` | Адреса проєкту Supabase |
| `SUPABASE_SECRET_KEYS` або `SUPABASE_SERVICE_ROLE_KEY` | Серверний ключ доступу до PostgreSQL; для `SUPABASE_SECRET_KEYS` використовується JSON із полем `default` |
| `DEVICE_INGEST_KEY` | Ключ авторизації ESP8266; має збігатися зі значенням у прошивці |

Системні змінні можуть надаватися платформою автоматично. Перед розгортанням перевірити їхню наявність у налаштуваннях проєкту.

Із кореневої папки репозиторію виконати:

```powershell
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase functions deploy ingest-readings --no-verify-jwt
supabase functions deploy dashboard-data --no-verify-jwt
```

Під час запуску серверна функція `ingest-readings` перевіряє `x-device-key`; вебінтерфейс звертається до `dashboard-data` без JWT. Значення серверних ключів не додаються до клієнтського застосунку та репозиторію.

## 7. Налаштування ESP8266

1. Підключити AHT20, BMP280 і BH1750 до шини I²C контролера Wemos D1: `SDA = GPIO4 (D2)`, `SCL = GPIO5 (D1)`. У програмі задано адреси BMP280 `0x77` та BH1750 `0x23`.
2. Відкрити каталог `firmware` у VS Code з установленим розширенням PlatformIO.
3. Створити файл `firmware/src/secrets.h`:

```cpp
#pragma once
#define WIFI_SSID "YOUR_WIFI_SSID"
#define WIFI_PASSWORD "YOUR_WIFI_PASSWORD"
#define INGEST_URL "https://YOUR_PROJECT.supabase.co/functions/v1/ingest-readings"
#define DEVICE_INGEST_KEY "YOUR_DEVICE_INGEST_KEY"
```

4. Перевірити параметри в `firmware/platformio.ini`. Для використаної конфігурації: `board = d1`, `monitor_speed = 115200`, `upload_port = COM4`, `monitor_port = COM4`. За потреби змінити COM-порт відповідно до підключення пристрою.
5. Виконати **PlatformIO → Upload** та відкрити **Serial Monitor**.

Інтервал вимірювань за замовчуванням становить **10 секунд**, інтервал планового передавання — **60 секунд**. До відправлення показники зберігаються в локальній черзі LittleFS.

**Очікуваний результат у Serial Monitor:**

```text
Temperature : 23.45 C
Humidity    : 54.11 %
Pressure    : 970.27 hPa
Light       : 9.17 lx
Stored in queue. Pending: 6
Preparing batch: 6 capture(s), queue=6
Sending batch to Supabase...
HTTP status : 200
Batch synchronized. Remaining: 0
```

Числові показники змінюються залежно від умов у приміщенні. Повідомлення `HTTP status : 200` та `Batch synchronized. Remaining: 0` означають, що сервер прийняв пакет вимірювань і локальна черга синхронізована.

## 8. Запуск вебінтерфейсу

Створити файл `dashboard/.env.local`:

```dotenv
VITE_DASHBOARD_API_URL=https://YOUR_PROJECT.supabase.co/functions/v1/dashboard-data
```

Із кореневої папки проєкту виконати:

```powershell
cd dashboard
npm ci
npm run dev
```

Відкрити адресу, яку покаже Vite (зазвичай `http://localhost:5173/`).

Для перевірки збірки:

```powershell
npm run build
npm run preview
```

**Очікуваний результат:** вебсторінка показує поточні значення температури, вологості, тиску та освітленості, історичні графіки за вибраний період і відомості про відхилення. Історичні значення з'являються після надходження вимірювань до бази даних.

Публічний варіант вебінтерфейсу: https://environment-monitoring-dashboard-two.vercel.app/.

## 9. Перевірка роботи системи

| Перевірка | Очікуваний результат |
|---|---|
| Створення структури | 9 таблиць, 2 представлення, 3 тригери |
| `v_current_sensor_state` | 4 рядки з поточним станом каналів; без даних — статус `NO_DATA` |
| `v_alert_history` | Дані про зареєстровані відхилення за їх наявності |
| Перевірка фізичного діапазону | Значення температури 120 °C відхиляється тригером |
| Обмеження `UNIQUE` і зовнішні ключі | Дубльовані та неузгоджені записи не додаються |
| Зміна робочого діапазону | Зміна правила фіксується в `alert_rule_audit` |
| Відхилення від установлених меж | Тригер створює запис про відхилення; після нормалізації значення закриває його |
| Конкурентний доступ | Друга транзакція очікує блокування, після досягнення `lock_timeout` отримує повідомлення про тайм-аут |
| Історія графіків | `get_dashboard_history(24)` повертає агреговані вимірювання за останні 24 години |
| ESP8266 → Supabase | Відповідь `HTTP 200` і успішна синхронізація черги |

Для перевірок використовуються SQL-файли з `database/sql/`, а зображення результатів розміщені в [docs/evidence](docs/evidence/).

За результатами виконаних перевірок: у відновленій локальній базі налічувалося **34 613 вимірювань**; тестовий пакет із **6 наборів вимірювань** містив **24 значення** й був успішно прийнятий сервером. Аналіз двох варіантів вибірки останніх вимірювань показав час **130,368 мс** для `DISTINCT ON` і **0,180 мс** для `LATERAL + LIMIT 1` у зафіксованому запуску.

## 10. Резервне копіювання та відновлення

Для створення резервної копії PostgreSQL у форматі Custom використовуються `pg_dump` і `pg_restore`.

```powershell
pg_dump -h YOUR_DB_HOST -U YOUR_DB_USER -d YOUR_DB_NAME -Fc -f environment_monitoring.backup
createdb -h localhost -U postgres environment_monitoring_restore
pg_restore -h localhost -U postgres -d environment_monitoring_restore --no-owner --no-privileges environment_monitoring.backup
psql -h localhost -U postgres -d environment_monitoring_restore -c "SELECT COUNT(*) FROM public.readings;"
```

**Очікуваний результат:** у створеній базі `environment_monitoring_restore` доступні таблиці, представлення, тригери та вимірювання з резервної копії. У перевіреній копії кількість записів таблиці `readings` становила **34 613**.

## 11. Матеріали курсової роботи

- [ER-діаграма](docs/diagrams/01_er_database_schema.png).
- [Скриншоти результатів перевірок](docs/evidence/).
- [Пояснювальна записка](docs/report/).
- [Презентація](docs/presentation/).

Паролі, ключі Supabase, дані доступу до Wi-Fi та файли локальних налаштувань до репозиторію не включаються.
