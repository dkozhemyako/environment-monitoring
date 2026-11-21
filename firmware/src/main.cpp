#include <Arduino.h>
#include <Wire.h>
#include <LittleFS.h>

#include <ESP8266WiFi.h>
#include <ESP8266HTTPClient.h>
#include <WiFiClientSecureBearSSL.h>

#include <Adafruit_AHTX0.h>
#include <Adafruit_BMP280.h>
#include <BH1750.h>

#include <ArduinoJson.h>

#include <time.h>
#include <sys/time.h>

extern "C" {
#include "user_interface.h"
}

#include "secrets.h"

// ============================================================
// Device configuration
// ============================================================

static const char* DEVICE_CODE = "ESP-001";

static const uint8_t I2C_SDA = 4;  // D2
static const uint8_t I2C_SCL = 5;  // D1

static const uint8_t BMP280_I2C_ADDRESS = 0x77;
static const uint8_t BH1750_ADDRESS = 0x23;

// ============================================================
// Timing
// ============================================================

static uint32_t measurementIntervalMs = 10000;

static const uint32_t MIN_MEASUREMENT_INTERVAL_MS = 1000;
static const uint32_t MAX_MEASUREMENT_INTERVAL_MS = 60000;

static const uint32_t NORMAL_SYNC_INTERVAL_MS = 60000;
static const uint32_t CATCHUP_SYNC_INTERVAL_MS = 5000;

static const uint32_t WIFI_RETRY_INTERVAL_MS = 15000;
static const uint32_t WIFI_CONNECT_TIMEOUT_MS = 15000;

static const uint32_t NTP_RETRY_INTERVAL_MS = 60000;
static const uint32_t NTP_RESYNC_INTERVAL_MS =
    6UL * 60UL * 60UL * 1000UL;

// ============================================================
// Queue configuration
// ============================================================

static const char* QUEUE_FILE = "/pending_readings.ndjson";
static const char* QUEUE_TMP_FILE = "/pending_readings.tmp";

static const size_t MAX_BATCH_SIZE = 12;

static const uint8_t QUEUE_MAX_FS_PERCENT = 55;

static const size_t QUEUE_ABSOLUTE_MAX_BYTES =
    1024UL * 1024UL;

static const uint8_t QUEUE_TRIM_TARGET_PERCENT = 60;

static const size_t QUEUE_MAX_RECORDS = 10000;

static const size_t MIN_FREE_FS_BYTES = 32UL * 1024UL;

// ============================================================
// Sensors
// ============================================================

Adafruit_AHTX0 aht;
Adafruit_BMP280 bmp;
BH1750 lightMeter;

// ============================================================
// Runtime state
// ============================================================

bool ahtReady = false;
bool bmpReady = false;
bool bh1750Ready = false;

bool littleFsReady = false;

bool running = true;

bool clockSynced = false;

bool catchupMode = false;
bool forceSyncRequested = false;

uint32_t currentBootId = 0;

size_t queueCount = 0;

uint32_t lastMeasurementMs = 0;
uint32_t lastQueueSyncMs = 0;
uint32_t lastWiFiRetryMs = 0;
uint32_t lastNtpAttemptMs = 0;
uint32_t lastSuccessfulNtpSyncMs = 0;

bool previousWiFiConnected = false;

int64_t clockSyncEpochMs = 0;
uint32_t clockSyncMillis = 0;

// ============================================================
// Helpers
// ============================================================

bool elapsed(
    uint32_t now,
    uint32_t previous,
    uint32_t interval
) {
    return static_cast<uint32_t>(now - previous) >= interval;
}

bool validTemperature(float value) {
    return isfinite(value) &&
           value >= -40.0f &&
           value <= 85.0f;
}

bool validHumidity(float value) {
    return isfinite(value) &&
           value >= 0.0f &&
           value <= 100.0f;
}

bool validPressure(float value) {
    return isfinite(value) &&
           value >= 300.0f &&
           value <= 1100.0f;
}

bool validLight(float value) {
    return isfinite(value) &&
           value >= 0.0f &&
           value <= 120000.0f;
}

// ============================================================
// Time
// ============================================================

bool systemTimeLooksValid() {
    time_t now = time(nullptr);

    // 2024-01-01 UTC
    return now >= 1704067200;
}

String formatIsoUtcMs(int64_t epochMs) {
    time_t seconds =
        static_cast<time_t>(epochMs / 1000LL);

    int milliseconds =
        static_cast<int>(epochMs % 1000LL);

    if (milliseconds < 0) {
        milliseconds += 1000;
        seconds--;
    }

    struct tm utcTime;
    gmtime_r(&seconds, &utcTime);

    char buffer[32];

    snprintf(
        buffer,
        sizeof(buffer),
        "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ",
        utcTime.tm_year + 1900,
        utcTime.tm_mon + 1,
        utcTime.tm_mday,
        utcTime.tm_hour,
        utcTime.tm_min,
        utcTime.tm_sec,
        milliseconds
    );

    return String(buffer);
}

bool getCurrentEpochMs(int64_t& result) {
    if (!systemTimeLooksValid()) {
        return false;
    }

    struct timeval tv;

    if (gettimeofday(&tv, nullptr) != 0) {
        return false;
    }

    result =
        static_cast<int64_t>(tv.tv_sec) * 1000LL +
        static_cast<int64_t>(tv.tv_usec / 1000);

    return true;
}

String currentIsoTime() {
    int64_t epochMs = 0;

    if (!getCurrentEpochMs(epochMs)) {
        return "";
    }

    return formatIsoUtcMs(epochMs);
}

bool syncClock(bool verbose = true) {
    if (WiFi.status() != WL_CONNECTED) {
        return false;
    }

    lastNtpAttemptMs = millis();

    if (verbose) {
        Serial.println("Synchronizing time...");
    }

    configTime(
        0,
        0,
        "pool.ntp.org",
        "time.google.com",
        "time.cloudflare.com"
    );

    const uint32_t started = millis();

    while (
        !systemTimeLooksValid() &&
        !elapsed(millis(), started, 10000)
    ) {
        delay(250);
        yield();

        if (verbose) {
            Serial.print(".");
        }
    }

    if (verbose) {
        Serial.println();
    }

    if (!systemTimeLooksValid()) {
        if (verbose) {
            Serial.println("Time synchronization failed");
        }

        return false;
    }

    int64_t epochMs = 0;

    if (!getCurrentEpochMs(epochMs)) {
        return false;
    }

    clockSynced = true;

    clockSyncEpochMs = epochMs;
    clockSyncMillis = millis();

    lastSuccessfulNtpSyncMs = millis();

    if (verbose) {
        Serial.print("Time synchronized: ");
        Serial.println(formatIsoUtcMs(epochMs));
    }

    return true;
}

bool reconstructCurrentBootTime(
    uint32_t capturedMs,
    int64_t& reconstructedEpochMs
) {
    if (!clockSynced || clockSyncEpochMs <= 0) {
        return false;
    }

    const int32_t deltaMs =
        static_cast<int32_t>(
            capturedMs - clockSyncMillis
        );

    reconstructedEpochMs =
        clockSyncEpochMs +
        static_cast<int64_t>(deltaMs);

    return true;
}

// ============================================================
// LittleFS
// ============================================================

size_t getQueueFileSize() {
    if (!littleFsReady ||
        !LittleFS.exists(QUEUE_FILE)) {
        return 0;
    }

    File file = LittleFS.open(
        QUEUE_FILE,
        "r"
    );

    if (!file) {
        return 0;
    }

    const size_t size = file.size();
    file.close();

    return size;
}

size_t calculateQueueLimitBytes() {
    if (!littleFsReady) {
        return 0;
    }

    FSInfo info;

    if (!LittleFS.info(info)) {
        return 0;
    }

    size_t limit =
        (info.totalBytes *
         QUEUE_MAX_FS_PERCENT) /
        100;

    if (limit > QUEUE_ABSOLUTE_MAX_BYTES) {
        limit = QUEUE_ABSOLUTE_MAX_BYTES;
    }

    return limit;
}

size_t countQueueRecords() {
    if (!littleFsReady ||
        !LittleFS.exists(QUEUE_FILE)) {
        return 0;
    }

    File file = LittleFS.open(
        QUEUE_FILE,
        "r"
    );

    if (!file) {
        return 0;
    }

    size_t count = 0;

    while (file.available()) {
        String line =
            file.readStringUntil('\n');

        line.trim();

        if (line.length() > 0) {
            count++;
        }

        yield();
    }

    file.close();

    return count;
}

bool rewriteQueueSkippingFirst(
    size_t recordsToSkip
) {
    if (!littleFsReady) {
        return false;
    }

    if (!LittleFS.exists(QUEUE_FILE)) {
        queueCount = 0;
        return true;
    }

    File source = LittleFS.open(
        QUEUE_FILE,
        "r"
    );

    if (!source) {
        return false;
    }

    LittleFS.remove(QUEUE_TMP_FILE);

    File target = LittleFS.open(
        QUEUE_TMP_FILE,
        "w"
    );

    if (!target) {
        source.close();
        return false;
    }

    size_t index = 0;
    size_t kept = 0;

    while (source.available()) {
        String line =
            source.readStringUntil('\n');

        line.trim();

        if (line.length() == 0) {
            continue;
        }

        if (index >= recordsToSkip) {
            target.println(line);
            kept++;
        }

        index++;
        yield();
    }

    source.close();
    target.close();

    if (!LittleFS.remove(QUEUE_FILE)) {
        if (LittleFS.exists(QUEUE_FILE)) {
            LittleFS.remove(QUEUE_TMP_FILE);
            return false;
        }
    }

    if (!LittleFS.rename(
            QUEUE_TMP_FILE,
            QUEUE_FILE
        )) {
        return false;
    }

    queueCount = kept;

    return true;
}

void enforceQueueLimits() {
    if (!littleFsReady ||
        !LittleFS.exists(QUEUE_FILE)) {
        return;
    }

    FSInfo info;

    if (!LittleFS.info(info)) {
        return;
    }

    const size_t queueBytes =
        getQueueFileSize();

    const size_t queueLimit =
        calculateQueueLimitBytes();

    const size_t freeBytes =
        info.totalBytes > info.usedBytes
            ? info.totalBytes - info.usedBytes
            : 0;

    const bool tooLarge =
        queueLimit > 0 &&
        queueBytes > queueLimit;

    const bool tooMany =
        queueCount > QUEUE_MAX_RECORDS;

    const bool lowFreeSpace =
        freeBytes < MIN_FREE_FS_BYTES;

    if (
        !tooLarge &&
        !tooMany &&
        !lowFreeSpace
    ) {
        return;
    }

    Serial.println();
    Serial.println(
        "Queue protection activated"
    );

    size_t targetBytes =
        queueLimit > 0
            ? (queueLimit *
               QUEUE_TRIM_TARGET_PERCENT) /
                  100
            : queueBytes;

    size_t bytesToDrop = 0;

    if (queueBytes > targetBytes) {
        bytesToDrop =
            queueBytes - targetBytes;
    }

    if (lowFreeSpace) {
        const size_t additionallyNeeded =
            MIN_FREE_FS_BYTES -
            freeBytes +
            4096;

        if (additionallyNeeded > bytesToDrop) {
            bytesToDrop =
                additionallyNeeded;
        }
    }

    const size_t targetRecordCount =
        (QUEUE_MAX_RECORDS *
         QUEUE_TRIM_TARGET_PERCENT) /
        100;

    size_t recordsToDrop = 0;

    if (queueCount > targetRecordCount) {
        recordsToDrop =
            queueCount -
            targetRecordCount;
    }

    File file = LittleFS.open(
        QUEUE_FILE,
        "r"
    );

    if (!file) {
        return;
    }

    size_t droppedBytes = 0;
    size_t dropCount = 0;

    while (file.available()) {
        if (
            droppedBytes >= bytesToDrop &&
            dropCount >= recordsToDrop
        ) {
            break;
        }

        String line =
            file.readStringUntil('\n');

        droppedBytes +=
            line.length() + 1;

        dropCount++;

        yield();
    }

    file.close();

    if (dropCount == 0 &&
        queueCount > 0) {
        dropCount = 1;
    }

    if (
        rewriteQueueSkippingFirst(
            dropCount
        )
    ) {
        Serial.print(
            "Oldest queue records removed: "
        );
        Serial.println(dropCount);
    } else {
        Serial.println(
            "Queue trimming failed"
        );
    }
}

bool appendQueueLine(
    const String& line
) {
    if (!littleFsReady) {
        Serial.println(
            "LittleFS unavailable - "
            "measurement cannot be persisted"
        );

        return false;
    }

    File file = LittleFS.open(
        QUEUE_FILE,
        "a"
    );

    if (!file) {
        Serial.println(
            "Failed to open queue file"
        );

        return false;
    }

    const size_t written =
        file.println(line);

    file.close();

    if (written == 0) {
        Serial.println(
            "Failed to write queue record"
        );

        return false;
    }

    queueCount++;

    enforceQueueLimits();

    return true;
}

void clearQueue() {
    if (!littleFsReady) {
        return;
    }

    if (LittleFS.exists(QUEUE_FILE)) {
        LittleFS.remove(QUEUE_FILE);
    }

    if (LittleFS.exists(QUEUE_TMP_FILE)) {
        LittleFS.remove(QUEUE_TMP_FILE);
    }

    queueCount = 0;
    catchupMode = false;

    Serial.println("Queue cleared");
}

void dumpQueue() {
    Serial.println();
    Serial.println(
        "========== QUEUE DUMP =========="
    );

    if (!littleFsReady) {
        Serial.println(
            "LittleFS unavailable"
        );
        return;
    }

    if (!LittleFS.exists(QUEUE_FILE)) {
        Serial.println(
            "Queue is empty"
        );
        return;
    }

    File file = LittleFS.open(
        QUEUE_FILE,
        "r"
    );

    if (!file) {
        Serial.println(
            "Cannot open queue"
        );
        return;
    }

    size_t index = 1;

    while (file.available()) {
        String line =
            file.readStringUntil('\n');

        line.trim();

        if (line.length() == 0) {
            continue;
        }

        Serial.print(index);
        Serial.print(": ");
        Serial.println(line);

        index++;
        yield();
    }

    file.close();

    Serial.println(
        "================================"
    );
}

// ============================================================
// Wi-Fi
// ============================================================

bool connectWiFiBlocking() {
    Serial.println();
    Serial.print("Connecting to Wi-Fi: ");
    Serial.println(WIFI_SSID);

    WiFi.persistent(false);
    WiFi.mode(WIFI_STA);

    WiFi.begin(
        WIFI_SSID,
        WIFI_PASSWORD
    );

    const uint32_t started = millis();

    while (
        WiFi.status() != WL_CONNECTED &&
        !elapsed(
            millis(),
            started,
            WIFI_CONNECT_TIMEOUT_MS
        )
    ) {
        delay(500);
        Serial.print(".");
        yield();
    }

    Serial.println();

    if (WiFi.status() != WL_CONNECTED) {
        Serial.println(
            "Wi-Fi connection failed"
        );

        previousWiFiConnected = false;

        return false;
    }

    Serial.println("Wi-Fi connected");

    Serial.print("IP address: ");
    Serial.println(WiFi.localIP());

    Serial.print("RSSI: ");
    Serial.print(WiFi.RSSI());
    Serial.println(" dBm");

    previousWiFiConnected = true;

    return true;
}

void maintainWiFi() {
    const bool connected =
        WiFi.status() == WL_CONNECTED;

    if (connected) {
        if (!previousWiFiConnected) {
            Serial.println();
            Serial.println(
                "Wi-Fi restored"
            );

            Serial.print("IP address: ");
            Serial.println(
                WiFi.localIP()
            );

            Serial.print("RSSI: ");
            Serial.print(WiFi.RSSI());
            Serial.println(" dBm");

            if (queueCount > 0) {
                catchupMode = true;
                forceSyncRequested = true;
            }
        }

        previousWiFiConnected = true;
        return;
    }

    if (previousWiFiConnected) {
        Serial.println();
        Serial.println(
            "Wi-Fi connection lost"
        );
    }

    previousWiFiConnected = false;

    const uint32_t now = millis();

    if (
        !elapsed(
            now,
            lastWiFiRetryMs,
            WIFI_RETRY_INTERVAL_MS
        )
    ) {
        return;
    }

    lastWiFiRetryMs = now;

    Serial.println(
        "Trying Wi-Fi reconnect..."
    );

    WiFi.disconnect();
    delay(100);

    WiFi.begin(
        WIFI_SSID,
        WIFI_PASSWORD
    );
}

// ============================================================
// I2C + sensors
// ============================================================

void scanI2C() {
    Serial.println();
    Serial.println("I2C scan:");

    uint8_t found = 0;

    for (
        uint8_t address = 1;
        address < 127;
        address++
    ) {
        Wire.beginTransmission(address);

        const uint8_t error =
            Wire.endTransmission();

        if (error == 0) {
            Serial.print(
                "  Found device at 0x"
            );

            if (address < 16) {
                Serial.print("0");
            }

            Serial.println(
                address,
                HEX
            );

            found++;
        }

        yield();
    }

    if (found == 0) {
        Serial.println(
            "  No I2C devices found"
        );
    }

    Serial.println();
}

void initializeSensors() {
    ahtReady = aht.begin();

    Serial.print("AHT20: ");
    Serial.println(
        ahtReady ? "OK" : "FAILED"
    );

    bmpReady = bmp.begin(
        BMP280_I2C_ADDRESS
    );

    Serial.print("BMP280 (0x77): ");
    Serial.println(
        bmpReady ? "OK" : "FAILED"
    );

    bh1750Ready = lightMeter.begin(
        BH1750::CONTINUOUS_HIGH_RES_MODE,
        BH1750_ADDRESS,
        &Wire
    );

    Serial.print("BH1750 (0x23): ");
    Serial.println(
        bh1750Ready ? "OK" : "FAILED"
    );

    Serial.println();
}

// ============================================================
// Capture
// ============================================================

bool createCaptureLine(
    String& line
) {
    JsonDocument doc;

    const uint32_t capturedMs =
        millis();

    doc["_boot_id"] =
        currentBootId;

    doc["_captured_ms"] =
        capturedMs;

    if (clockSynced &&
        systemTimeLooksValid()) {
        const String measuredAt =
            currentIsoTime();

        if (measuredAt.length() > 0) {
            doc["measured_at"] =
                measuredAt;

            doc["time_synced"] =
                true;
        } else {
            doc["time_synced"] =
                false;
        }
    } else {
        doc["time_synced"] =
            false;
    }

    JsonArray readings =
        doc["readings"]
            .to<JsonArray>();

    float temperature = NAN;
    float humidity = NAN;

    if (ahtReady) {
        sensors_event_t humidityEvent;
        sensors_event_t temperatureEvent;

        aht.getEvent(
            &humidityEvent,
            &temperatureEvent
        );

        temperature =
            temperatureEvent.temperature;

        humidity =
            humidityEvent.relative_humidity;
    }

    if (validTemperature(temperature)) {
        JsonObject reading =
            readings.add<JsonObject>();

        reading["channel_code"] =
            "AHT20-TEMP";

        reading["value"] =
            temperature;
    }

    if (validHumidity(humidity)) {
        JsonObject reading =
            readings.add<JsonObject>();

        reading["channel_code"] =
            "AHT20-HUM";

        reading["value"] =
            humidity;
    }

    float pressure = NAN;

    if (bmpReady) {
        pressure =
            bmp.readPressure() /
            100.0f;
    }

    if (validPressure(pressure)) {
        JsonObject reading =
            readings.add<JsonObject>();

        reading["channel_code"] =
            "BMP280-PRESS";

        reading["value"] =
            pressure;
    }

    float light = NAN;

    if (bh1750Ready) {
        light =
            lightMeter.readLightLevel();
    }

    if (validLight(light)) {
        JsonObject reading =
            readings.add<JsonObject>();

        reading["channel_code"] =
            "BH1750-LIGHT";

        reading["value"] =
            light;
    }

    Serial.println();
    Serial.println(
        "--------------------------------------"
    );

    if (validTemperature(temperature)) {
        Serial.print("Temperature : ");
        Serial.print(temperature, 2);
        Serial.println(" C");
    } else {
        Serial.println(
            "Temperature : INVALID"
        );
    }

    if (validHumidity(humidity)) {
        Serial.print("Humidity    : ");
        Serial.print(humidity, 2);
        Serial.println(" %");
    } else {
        Serial.println(
            "Humidity    : INVALID"
        );
    }

    if (validPressure(pressure)) {
        Serial.print("Pressure    : ");
        Serial.print(pressure, 2);
        Serial.println(" hPa");
    } else {
        Serial.println(
            "Pressure    : INVALID"
        );
    }

    if (validLight(light)) {
        Serial.print("Light       : ");
        Serial.print(light, 2);
        Serial.println(" lx");
    } else {
        Serial.println(
            "Light       : INVALID"
        );
    }

    if (doc["measured_at"].is<String>()) {
        Serial.print("Measured at : ");
        Serial.println(
            doc["measured_at"]
                .as<String>()
        );
    } else {
        Serial.println(
            "Measured at : pending NTP"
        );
    }

    if (readings.size() == 0) {
        Serial.println(
            "No valid readings - capture skipped"
        );

        return false;
    }

    line = "";

    serializeJson(
        doc,
        line
    );

    return true;
}

void takeMeasurement() {
    String line;

    if (!createCaptureLine(line)) {
        return;
    }

    if (appendQueueLine(line)) {
        Serial.print(
            "Stored in queue. Pending: "
        );
        Serial.println(queueCount);
    }
}

// ============================================================
// Batch preparation
// ============================================================

bool buildBatchPayload(
    String& payload,
    size_t& consumedLines,
    size_t& captureCount
) {
    payload = "";
    consumedLines = 0;
    captureCount = 0;

    if (
        !littleFsReady ||
        !LittleFS.exists(QUEUE_FILE)
    ) {
        return false;
    }

    File file = LittleFS.open(
        QUEUE_FILE,
        "r"
    );

    if (!file) {
        return false;
    }

    JsonDocument outgoing;

    outgoing["device_code"] =
        DEVICE_CODE;

    JsonArray captures =
        outgoing["captures"]
            .to<JsonArray>();

    while (
        file.available() &&
        captureCount < MAX_BATCH_SIZE
    ) {
        String line =
            file.readStringUntil('\n');

        line.trim();

        if (line.length() == 0) {
            continue;
        }

        consumedLines++;

        JsonDocument stored;

        const DeserializationError error =
            deserializeJson(
                stored,
                line
            );

        if (error) {
            Serial.print(
                "Skipping corrupted queue line: "
            );
            Serial.println(
                error.c_str()
            );

            continue;
        }

        JsonArray storedReadings =
            stored["readings"]
                .as<JsonArray>();

        if (
            storedReadings.isNull() ||
            storedReadings.size() == 0
        ) {
            Serial.println(
                "Skipping queue line without readings"
            );

            continue;
        }

        JsonObject capture =
            captures.add<JsonObject>();

        bool hasMeasuredAt = false;

        if (
            stored["measured_at"]
                .is<const char*>()
        ) {
            const char* value =
                stored["measured_at"]
                    .as<const char*>();

            if (
                value != nullptr &&
                strlen(value) > 0
            ) {
                capture["measured_at"] =
                    value;

                capture["time_synced"] =
                    stored["time_synced"] |
                    false;

                hasMeasuredAt = true;
            }
        }

        if (!hasMeasuredAt) {
            const uint32_t storedBootId =
                stored["_boot_id"] | 0UL;

            const uint32_t capturedMs =
                stored["_captured_ms"] |
                0UL;

            int64_t reconstructedMs = 0;

            if (
                storedBootId ==
                    currentBootId &&
                reconstructCurrentBootTime(
                    capturedMs,
                    reconstructedMs
                )
            ) {
                capture["measured_at"] =
                    formatIsoUtcMs(
                        reconstructedMs
                    );

                capture["time_synced"] =
                    false;

                hasMeasuredAt = true;
            }
        }

        if (!hasMeasuredAt) {
            capture["time_synced"] =
                false;
        }

        JsonArray outputReadings =
            capture["readings"]
                .to<JsonArray>();

        for (
            JsonObject storedReading :
            storedReadings
        ) {
            const char* channelCode =
                storedReading[
                    "channel_code"
                ].as<const char*>();

            JsonVariant valueVariant =
                storedReading["value"];

            const bool numericValue =
                valueVariant.is<float>() ||
                valueVariant.is<double>() ||
                valueVariant.is<int>() ||
                valueVariant.is<long>();

            if (
                channelCode == nullptr ||
                strlen(channelCode) == 0 ||
                !numericValue
            ) {
                continue;
            }

            JsonObject outputReading =
                outputReadings
                    .add<JsonObject>();

            outputReading[
                "channel_code"
            ] = channelCode;

            outputReading["value"] =
                valueVariant;
        }

        if (outputReadings.size() == 0) {
            captures.remove(
                captures.size() - 1
            );

            continue;
        }

        captureCount++;

        yield();
    }

    file.close();

    if (captureCount == 0) {
        if (consumedLines > 0) {
            rewriteQueueSkippingFirst(
                consumedLines
            );
        }

        return false;
    }

    serializeJson(
        outgoing,
        payload
    );

    return true;
}

// ============================================================
// HTTPS
// ============================================================

bool sendBatchPayload(
    const String& payload
) {
    if (
        WiFi.status() != WL_CONNECTED
    ) {
        return false;
    }

    BearSSL::WiFiClientSecure client;

    /*
     * Передавання даних через HTTPS.
     * Перевірка CA-сертифіката вимкнена (setInsecure).
     * Для авторизації використовується DEVICE_INGEST_KEY.
     */
    client.setInsecure();

    HTTPClient http;

    if (!http.begin(
            client,
            INGEST_URL
        )) {
        Serial.println(
            "HTTPS initialization failed"
        );

        return false;
    }

    http.setTimeout(15000);

    http.addHeader(
        "Content-Type",
        "application/json"
    );

    http.addHeader(
        "x-device-key",
        DEVICE_INGEST_KEY
    );

    Serial.println(
        "Sending batch to Supabase..."
    );

    const int httpCode =
        http.POST(payload);

    const String response =
        http.getString();

    Serial.print("HTTP status  : ");
    Serial.println(httpCode);

    Serial.print("Response     : ");
    Serial.println(response);

    bool success = false;

    if (
        httpCode >= 200 &&
        httpCode < 300
    ) {
        JsonDocument responseDoc;

        const DeserializationError error =
            deserializeJson(
                responseDoc,
                response
            );

        if (!error) {
            success =
                responseDoc["ok"] |
                false;
        }
    }

    http.end();

    return success;
}

// ============================================================
// Queue synchronization
// ============================================================

bool synchronizeQueueOnce() {
    if (
        queueCount == 0 ||
        WiFi.status() != WL_CONNECTED
    ) {
        return false;
    }

    String payload;
    size_t consumedLines = 0;
    size_t captures = 0;

    if (
        !buildBatchPayload(
            payload,
            consumedLines,
            captures
        )
    ) {
        return false;
    }

    Serial.println();
    Serial.print(
        "Preparing batch: "
    );
    Serial.print(captures);
    Serial.print(
        " capture(s), queue="
    );
    Serial.println(queueCount);

    const bool success =
        sendBatchPayload(payload);

    if (!success) {
        Serial.println(
            "Batch upload failed - "
            "queue preserved"
        );

        return false;
    }

    if (
        !rewriteQueueSkippingFirst(
            consumedLines
        )
    ) {
        Serial.println(
            "WARNING: server accepted batch, "
            "but local queue cleanup failed"
        );

        return false;
    }

    Serial.print(
        "Batch synchronized. Remaining: "
    );
    Serial.println(queueCount);

    if (queueCount == 0) {
        catchupMode = false;
    }

    return true;
}

void maintainQueueSync() {
    if (
        queueCount == 0 ||
        WiFi.status() != WL_CONNECTED
    ) {
        return;
    }

    const uint32_t now = millis();

    const uint32_t interval =
        catchupMode
            ? CATCHUP_SYNC_INTERVAL_MS
            : NORMAL_SYNC_INTERVAL_MS;

    if (
        !forceSyncRequested &&
        !elapsed(
            now,
            lastQueueSyncMs,
            interval
        )
    ) {
        return;
    }

    forceSyncRequested = false;
    lastQueueSyncMs = now;

    synchronizeQueueOnce();
}

// ============================================================
// NTP maintenance
// ============================================================

void maintainClock() {
    if (
        WiFi.status() != WL_CONNECTED
    ) {
        return;
    }

    const uint32_t now = millis();

    if (!clockSynced) {
        if (
            lastNtpAttemptMs == 0 ||
            elapsed(
                now,
                lastNtpAttemptMs,
                NTP_RETRY_INTERVAL_MS
            )
        ) {
            if (syncClock(false)) {
                Serial.print(
                    "Time synchronized: "
                );
                Serial.println(
                    currentIsoTime()
                );

                if (queueCount > 0) {
                    forceSyncRequested =
                        true;
                }
            }
        }

        return;
    }

    if (
        elapsed(
            now,
            lastSuccessfulNtpSyncMs,
            NTP_RESYNC_INTERVAL_MS
        )
    ) {
        syncClock(false);
    }
}

// ============================================================
// Status / commands
// ============================================================

void printStatus() {
    Serial.println();
    Serial.println(
        "========== STATUS =========="
    );

    Serial.print("Device        : ");
    Serial.println(DEVICE_CODE);

    Serial.print("State         : ");
    Serial.println(
        running
            ? "RUNNING"
            : "STOPPED"
    );

    Serial.print(
        "Interval      : "
    );
    Serial.print(
        measurementIntervalMs
    );
    Serial.println(" ms");

    Serial.print("Wi-Fi         : ");
    Serial.println(
        WiFi.status() == WL_CONNECTED
            ? "CONNECTED"
            : "DISCONNECTED"
    );

    if (
        WiFi.status() == WL_CONNECTED
    ) {
        Serial.print("IP            : ");
        Serial.println(
            WiFi.localIP()
        );

        Serial.print("RSSI          : ");
        Serial.print(
            WiFi.RSSI()
        );
        Serial.println(" dBm");
    }

    Serial.print("NTP           : ");
    Serial.println(
        clockSynced
            ? "SYNCED"
            : "NOT SYNCED"
    );

    if (
        clockSynced &&
        systemTimeLooksValid()
    ) {
        Serial.print("UTC           : ");
        Serial.println(
            currentIsoTime()
        );
    }

    Serial.print("Queue records : ");
    Serial.println(queueCount);

    if (littleFsReady) {
        FSInfo info;

        if (LittleFS.info(info)) {
            const size_t queueBytes =
                getQueueFileSize();

            const size_t queueLimit =
                calculateQueueLimitBytes();

            const size_t freeBytes =
                info.totalBytes >
                        info.usedBytes
                    ? info.totalBytes -
                          info.usedBytes
                    : 0;

            Serial.print(
                "LittleFS total: "
            );
            Serial.println(
                info.totalBytes
            );

            Serial.print(
                "LittleFS used : "
            );
            Serial.println(
                info.usedBytes
            );

            Serial.print(
                "LittleFS free : "
            );
            Serial.println(
                freeBytes
            );

            Serial.print(
                "Queue bytes   : "
            );
            Serial.println(
                queueBytes
            );

            Serial.print(
                "Queue limit   : "
            );
            Serial.println(
                queueLimit
            );
        }
    } else {
        Serial.println(
            "LittleFS       : UNAVAILABLE"
        );
    }

    Serial.println(
        "============================"
    );
}

void handleSerialCommand() {
    if (!Serial.available()) {
        return;
    }

    String command =
        Serial.readStringUntil('\n');

    command.trim();

    if (command.length() == 0) {
        return;
    }

    String upper = command;
    upper.toUpperCase();

    if (upper == "STATUS") {
        printStatus();
        return;
    }

    if (upper == "START") {
        running = true;

        lastMeasurementMs =
            millis() -
            measurementIntervalMs;

        Serial.println(
            "Measurement started"
        );

        return;
    }

    if (upper == "STOP") {
        running = false;

        Serial.println(
            "Measurement stopped"
        );

        return;
    }

    if (
        upper.startsWith(
            "SET_INTERVAL "
        )
    ) {
        const String valueText =
            command.substring(
                strlen(
                    "SET_INTERVAL "
                )
            );

        uint32_t value =
            static_cast<uint32_t>(
                valueText.toInt()
            );

        if (
            value <
            MIN_MEASUREMENT_INTERVAL_MS
        ) {
            value =
                MIN_MEASUREMENT_INTERVAL_MS;
        }

        if (
            value >
            MAX_MEASUREMENT_INTERVAL_MS
        ) {
            value =
                MAX_MEASUREMENT_INTERVAL_MS;
        }

        measurementIntervalMs =
            value;

        Serial.print(
            "Measurement interval: "
        );
        Serial.print(
            measurementIntervalMs
        );
        Serial.println(" ms");

        return;
    }

    if (upper == "SEND_NOW") {
        forceSyncRequested = true;

        Serial.println(
            "Queue synchronization requested"
        );

        return;
    }

    if (
        upper ==
        "WIFI_RECONNECT"
    ) {
        Serial.println(
            "Manual Wi-Fi reconnect"
        );

        WiFi.disconnect();
        delay(100);

        WiFi.begin(
            WIFI_SSID,
            WIFI_PASSWORD
        );

        return;
    }

    if (
        upper == "DUMP_QUEUE" ||
        upper == "DUMP_LOG"
    ) {
        dumpQueue();
        return;
    }

    if (
        upper == "CLEAR_QUEUE" ||
        upper == "CLEAR_LOG"
    ) {
        clearQueue();
        return;
    }

    Serial.print(
        "Unknown command: "
    );
    Serial.println(command);
}

// ============================================================
// Setup
// ============================================================

void setup() {
    Serial.begin(115200);
    delay(500);

    Serial.println();
    Serial.println();
    Serial.println(
        "======================================"
    );
    Serial.println(
        "Environment Monitoring System"
    );
    Serial.println(
        "ESP8266 -> LittleFS -> Supabase"
    );
    Serial.println(
        "======================================"
    );

    currentBootId =
        os_random();

    Serial.print("Boot ID: ");
    Serial.println(
        currentBootId
    );

    // --------------------------------------------------------
    // LittleFS
    // --------------------------------------------------------

    littleFsReady =
        LittleFS.begin();

    if (littleFsReady) {
        queueCount =
            countQueueRecords();

        Serial.println(
            "LittleFS: OK"
        );

        Serial.print(
            "Pending queue records: "
        );
        Serial.println(
            queueCount
        );

        if (queueCount > 0) {
            catchupMode = true;
        }

        enforceQueueLimits();
    } else {
        Serial.println(
            "LittleFS: FAILED"
        );

        Serial.println(
            "Offline persistence is unavailable"
        );
    }

    // --------------------------------------------------------
    // I2C / sensors
    // --------------------------------------------------------

    Wire.begin(
        I2C_SDA,
        I2C_SCL
    );

    scanI2C();
    initializeSensors();

    // --------------------------------------------------------
    // Network / time
    // --------------------------------------------------------

    if (connectWiFiBlocking()) {
        syncClock(true);
    }

    // --------------------------------------------------------
    // Automatic start
    // --------------------------------------------------------

    running = true;

    lastMeasurementMs =
        millis() -
        measurementIntervalMs;

    lastQueueSyncMs =
        millis() -
        NORMAL_SYNC_INTERVAL_MS;

    if (
        queueCount > 0 &&
        WiFi.status() == WL_CONNECTED
    ) {
        catchupMode = true;
        forceSyncRequested = true;
    }

    Serial.println();
    Serial.println(
        "System state: RUNNING"
    );

    Serial.println(
        "Commands:"
    );

    Serial.println(
        "  STATUS"
    );
    Serial.println(
        "  START"
    );
    Serial.println(
        "  STOP"
    );
    Serial.println(
        "  SET_INTERVAL <ms>"
    );
    Serial.println(
        "  SEND_NOW"
    );
    Serial.println(
        "  WIFI_RECONNECT"
    );
    Serial.println(
        "  DUMP_QUEUE"
    );
    Serial.println(
        "  CLEAR_QUEUE"
    );
}

// ============================================================
// Loop
// ============================================================

void loop() {
    handleSerialCommand();

    maintainWiFi();
    maintainClock();

    const uint32_t now = millis();

    if (
        running &&
        elapsed(
            now,
            lastMeasurementMs,
            measurementIntervalMs
        )
    ) {
        lastMeasurementMs = now;

        takeMeasurement();
    }

    maintainQueueSync();

    delay(10);
    yield();
}