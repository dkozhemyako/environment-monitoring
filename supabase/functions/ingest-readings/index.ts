import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const DEVICE_INGEST_KEY = Deno.env.get("DEVICE_INGEST_KEY")!;

const secretKeysRaw = Deno.env.get("SUPABASE_SECRET_KEYS");
const legacyServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

let serviceKey: string | undefined;

if (secretKeysRaw) {
  const secretKeys = JSON.parse(secretKeysRaw);
  serviceKey = secretKeys.default;
} else {
  serviceKey = legacyServiceRoleKey ?? undefined;
}

if (!serviceKey) {
  throw new Error("Supabase secret key is not available");
}

const supabase = createClient(SUPABASE_URL, serviceKey);

type ReadingInput = {
  channel_code: string;
  value: number;
};

type CaptureInput = {
  measured_at?: string | null;
  time_synced?: boolean;
  readings: ReadingInput[];
};

type Payload = {
  device_code: string;

  // Одиночний формат вимірювання
  measured_at?: string;
  time_synced?: boolean;
  readings?: ReadingInput[];

  // Пакетний формат вимірювань
  captures?: CaptureInput[];
};

const allowedChannels = new Set([
  "AHT20-TEMP",
  "AHT20-HUM",
  "BMP280-PRESS",
  "BH1750-LIGHT",
]);

function jsonResponse(
  body: unknown,
  status = 200,
) {
  return Response.json(body, { status });
}

function isValidTimestamp(value: string) {
  return !Number.isNaN(Date.parse(value));
}

Deno.serve(async (req: Request) => {
  try {
    // ========================================================
    // HTTP method
    // ========================================================

    if (req.method !== "POST") {
      return jsonResponse(
        { error: "Method not allowed" },
        405,
      );
    }

    // ========================================================
    // Device authentication
    // ========================================================

    const deviceKey = req.headers.get("x-device-key");

    if (
      !deviceKey ||
      deviceKey !== DEVICE_INGEST_KEY
    ) {
      return jsonResponse(
        { error: "Unauthorized" },
        401,
      );
    }

    // ========================================================
    // Parse payload
    // ========================================================

    const body = await req.json() as Payload;

    if (!body.device_code) {
      return jsonResponse(
        { error: "device_code is required" },
        400,
      );
    }

    // ========================================================
    // Normalize single and batch formats
    // ========================================================

    let captures: CaptureInput[] = [];

    if (
      Array.isArray(body.captures) &&
      body.captures.length > 0
    ) {
      captures = body.captures;
    } else if (
      Array.isArray(body.readings) &&
      body.readings.length > 0
    ) {
      captures = [
        {
          measured_at: body.measured_at,
          time_synced: body.time_synced,
          readings: body.readings,
        },
      ];
    } else {
      return jsonResponse(
        { error: "No readings supplied" },
        400,
      );
    }

    // Захист endpoint від надмірного batch.
    if (captures.length > 12) {
      return jsonResponse(
        {
          error: "Batch too large",
          max_captures: 12,
        },
        400,
      );
    }

    // ========================================================
    // Validate device
    // ========================================================

    const {
      data: device,
      error: deviceError,
    } = await supabase
      .from("devices")
      .select("id, device_code, is_active")
      .eq("device_code", body.device_code)
      .single();

    if (deviceError || !device) {
      return jsonResponse(
        { error: "Device not found" },
        404,
      );
    }

    if (!device.is_active) {
      return jsonResponse(
        { error: "Device is inactive" },
        403,
      );
    }

    // ========================================================
    // Validate captures and collect channel codes
    // ========================================================

    const requestedChannelCodes = new Set<string>();

    for (
      let captureIndex = 0;
      captureIndex < captures.length;
      captureIndex++
    ) {
      const capture = captures[captureIndex];

      if (
        !Array.isArray(capture.readings) ||
        capture.readings.length === 0
      ) {
        return jsonResponse(
          {
            error: "Capture has no readings",
            capture_index: captureIndex,
          },
          400,
        );
      }

      if (capture.readings.length > 4) {
        return jsonResponse(
          {
            error: "Too many readings in capture",
            capture_index: captureIndex,
          },
          400,
        );
      }

      if (
        capture.measured_at &&
        !isValidTimestamp(capture.measured_at)
      ) {
        return jsonResponse(
          {
            error: "Invalid measured_at",
            capture_index: captureIndex,
          },
          400,
        );
      }

      const captureChannels = new Set<string>();

      for (const reading of capture.readings) {
        if (
          !allowedChannels.has(reading.channel_code) ||
          typeof reading.value !== "number" ||
          !Number.isFinite(reading.value)
        ) {
          return jsonResponse(
            {
              error: "Invalid reading",
              capture_index: captureIndex,
              reading,
            },
            400,
          );
        }

        if (
          captureChannels.has(reading.channel_code)
        ) {
          return jsonResponse(
            {
              error: "Duplicate channel in capture",
              capture_index: captureIndex,
              channel_code: reading.channel_code,
            },
            400,
          );
        }

        captureChannels.add(
          reading.channel_code,
        );

        requestedChannelCodes.add(
          reading.channel_code,
        );
      }
    }

    // ========================================================
    // Load channel mapping
    // ========================================================

    const {
      data: channels,
      error: channelsError,
    } = await supabase
      .from("sensor_channels")
      .select(`
        id,
        channel_code,
        is_active,
        sensors!inner (
          device_id,
          is_active
        )
      `)
      .in(
        "channel_code",
        Array.from(requestedChannelCodes),
      );

    if (channelsError) {
      return jsonResponse(
        {
          error: "Failed to load channels",
          details: channelsError.message,
        },
        500,
      );
    }

    const channelMap = new Map<string, number>();

    for (const channel of channels ?? []) {
      const sensor = Array.isArray(channel.sensors)
        ? channel.sensors[0]
        : channel.sensors;

      if (
        channel.is_active &&
        sensor?.is_active &&
        sensor?.device_id === device.id
      ) {
        channelMap.set(
          channel.channel_code,
          channel.id,
        );
      }
    }

    // ========================================================
    // Flatten captures into readings table rows
    // ========================================================

    const rows: Array<{
      channel_id: number;
      measured_at: string;
      value: number;
      is_valid: boolean;
      time_synced: boolean;
    }> = [];

    const serverBaseTime = Date.now();

    for (
      let captureIndex = 0;
      captureIndex < captures.length;
      captureIndex++
    ) {
      const capture = captures[captureIndex];

      /*
       * Якщо ESP ще не мав синхронізованого часу,
       * використовуємо серверний час.
       *
       * + captureIndex ms гарантує різні timestamps
       * для кількох unsynced capture в одному batch.
       */
      const measuredAt =
        capture.measured_at ??
        new Date(
          serverBaseTime + captureIndex,
        ).toISOString();

      const timeSynced =
        Boolean(capture.measured_at) &&
        capture.time_synced !== false;

      for (const reading of capture.readings) {
        const channelId = channelMap.get(
          reading.channel_code,
        );

        if (!channelId) {
          return jsonResponse(
            {
              error:
                "Channel not found or does not belong to device",
              capture_index: captureIndex,
              channel_code: reading.channel_code,
            },
            400,
          );
        }

        rows.push({
          channel_id: channelId,
          measured_at: measuredAt,
          value: reading.value,
          is_valid: true,
          time_synced: timeSynced,
        });
      }
    }

    // ========================================================
    // Idempotent insert
    //
    // Якщо сервер уже прийняв batch, але ESP не встиг
    // видалити його з LittleFS, повторна передача не створить
    // дублікати через UNIQUE(channel_id, measured_at).
    // ========================================================

    const {
      data: inserted,
      error: insertError,
    } = await supabase
      .from("readings")
      .upsert(
        rows,
        {
          onConflict: "channel_id,measured_at",
          ignoreDuplicates: true,
        },
      )
      .select(
        "id, channel_id, measured_at, value, time_synced",
      );

    if (insertError) {
      return jsonResponse(
        {
          error: "Failed to insert readings",
          details: insertError.message,
        },
        400,
      );
    }

    // ========================================================
    // Update device heartbeat
    // ========================================================

    const {
      error: heartbeatError,
    } = await supabase
      .from("devices")
      .update({
        last_seen_at: new Date().toISOString(),
      })
      .eq("id", device.id);

    if (heartbeatError) {
      console.error(
        "Failed to update last_seen_at:",
        heartbeatError.message,
      );
    }

    // ========================================================
    // Response
    // ========================================================

    return jsonResponse({
      ok: true,
      device_code: body.device_code,
      captures_received: captures.length,
      rows_received: rows.length,
      inserted_count: inserted?.length ?? 0,
      duplicate_count:
        rows.length - (inserted?.length ?? 0),
      readings: inserted ?? [],
    });
  } catch (error) {
    return jsonResponse(
      {
        error: "Internal server error",
        details:
          error instanceof Error
            ? error.message
            : String(error),
      },
      500,
    );
  }
});
