
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;

const secretKeysRaw = Deno.env.get("SUPABASE_SECRET_KEYS");
const legacyServiceRoleKey = Deno.env.get(
  "SUPABASE_SERVICE_ROLE_KEY"
);

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

const supabase = createClient(
  SUPABASE_URL,
  serviceKey
);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

function jsonResponse(
  body: unknown,
  status = 200
) {
  return new Response(
    JSON.stringify(body),
    {
      status,
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json",
      },
    }
  );
}

Deno.serve(async (req: Request) => {
  try {
    // ========================================================
    // CORS
    // ========================================================

    if (req.method === "OPTIONS") {
      return new Response("ok", {
        headers: corsHeaders,
      });
    }

    // ========================================================
    // GET only
    // ========================================================

    if (req.method !== "GET") {
      return jsonResponse(
        {
          error: "Method not allowed",
        },
        405
      );
    }

    // ========================================================
    // Time period
    // ========================================================

    const url = new URL(req.url);

    let hours = Number(
      url.searchParams.get("hours") ?? "24"
    );

    if (!Number.isFinite(hours)) {
      hours = 24;
    }

    hours = Math.min(
      Math.max(Math.round(hours), 1),
      168
    );

    // ========================================================
    // Current sensor state
    // ========================================================

    const {
      data: currentState,
      error: currentStateError,
    } = await supabase
      .from("v_current_sensor_state")
      .select(`
        room_id,
        room_code,
        room_name,
        device_id,
        device_code,
        device_name,
        last_seen_at,
        sensor_id,
        sensor_code,
        sensor_model,
        channel_id,
        channel_code,
        channel_name,
        type_code,
        measurement_type,
        unit,
        reading_id,
        measured_at,
        received_at,
        value,
        is_valid,
        time_synced,
        allowed_min,
        allowed_max,
        status
      `)
      .order("channel_id", {
        ascending: true,
      });

    if (currentStateError) {
      throw new Error(
        `Current state: ${currentStateError.message}`
      );
    }

    // ========================================================
    // Aggregated readings for charts
    // ========================================================
    //
    // Дані отримуються через PostgreSQL-функцію
    // get_dashboard_history().
    //
    // Агрегація залежить від обраного періоду:
    // 6 годин   - 2 хвилини
    // 24 години - 10 хвилин
    // 72 години - 30 хвилин
    // 168 годин - 1 година
    //
    // Початкові записи readings не змінюються.
    // ========================================================

    const {
      data: history,
      error: historyError,
    } = await supabase.rpc(
      "get_dashboard_history",
      {
        p_hours: hours,
      }
    );

    if (historyError) {
      throw new Error(
        `Dashboard history: ${historyError.message}`
      );
    }

    // ========================================================
    // Channel metadata
    // ========================================================
    //
    // Формуємо відповідність між кодом каналу
    // та типом вимірюваної величини.
    // ========================================================

    const channelInfo = new Map<
      string,
      {
        channelName: string;
        typeCode: string;
        measurementType: string;
        unit: string;
      }
    >();

    for (const item of currentState ?? []) {
      channelInfo.set(item.channel_code, {
        channelName: item.channel_name,
        typeCode: item.type_code,
        measurementType: item.measurement_type,
        unit: item.unit,
      });
    }

    // ========================================================
    // Prepare chart response
    // ========================================================
    //
    // Формування структури recent_readings для
    // відображення агрегованих значень на графіках.
    //
    // Агреговані точки не мають власного reading ID
    // та received_at, оскільки є результатом AVG.
    // ========================================================

    const recentReadings = [];

    for (const item of history ?? []) {
      const channel = channelInfo.get(
        item.channel_code
      );

      if (!channel) {
        throw new Error(
          `Unknown channel in history: ${item.channel_code}`
        );
      }

      recentReadings.push({
        id: null,
        measured_at: item.measured_at,
        received_at: null,
        value: Number(item.value),
        is_valid: true,
        time_synced: null,

        sensor_channels: {
          channel_code: item.channel_code,
          name: channel.channelName,

          sensor_types: {
            type_code: channel.typeCode,
            name: channel.measurementType,
            unit: channel.unit,
          },
        },
      });
    }

    // ========================================================
    // Alerts
    // ========================================================

    const {
      data: alerts,
      error: alertsError,
    } = await supabase
      .from("v_alert_history")
      .select(`
        alert_id,
        room_code,
        room_name,
        device_code,
        sensor_code,
        sensor_model,
        channel_code,
        measurement_type,
        unit,
        allowed_min,
        allowed_max,
        actual_value,
        opened_at,
        resolved_at,
        alert_status,
        acknowledged,
        acknowledged_at,
        acknowledged_by,
        opened_by_reading_id,
        resolved_by_reading_id
      `)
      .order("opened_at", {
        ascending: false,
      })
      .limit(20);

    if (alertsError) {
      throw new Error(
        `Alerts: ${alertsError.message}`
      );
    }

    // ========================================================
    // Devices
    // ========================================================

    const {
      data: devices,
      error: devicesError,
    } = await supabase
      .from("devices")
      .select(`
        device_code,
        name,
        model,
        firmware_version,
        last_seen_at,
        is_active
      `)
      .order("device_code", {
        ascending: true,
      });

    if (devicesError) {
      throw new Error(
        `Devices: ${devicesError.message}`
      );
    }

    // ========================================================
    // Response
    // ========================================================

    return jsonResponse({
      generated_at: new Date().toISOString(),
      period_hours: hours,
      current_state: currentState ?? [],
      recent_readings: recentReadings,
      alerts: alerts ?? [],
      devices: devices ?? [],
    });

  } catch (error) {
    console.error(error);

    return jsonResponse(
      {
        error: "Failed to load dashboard data",
        details:
          error instanceof Error
            ? error.message
            : String(error),
      },
      500
    );
  }
});

