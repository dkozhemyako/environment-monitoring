import { useEffect, useMemo, useState, type ReactNode } from "react";
import {
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import "./App.css";

type CurrentStateItem = {
  room_code: string;
  room_name: string;
  device_code: string;
  device_name: string;
  last_seen_at: string | null;
  sensor_code: string;
  sensor_model: string;
  channel_code: string;
  channel_name: string;
  type_code: string;
  measurement_type: string;
  unit: string;
  measured_at: string | null;
  value: number | null;
  is_valid: boolean | null;
  time_synced: boolean | null;
  allowed_min: number | null;
  allowed_max: number | null;
  status: string;
};

type RecentReading = {
  id: number;
  measured_at: string;
  received_at: string;
  value: number;
  is_valid: boolean;
  time_synced: boolean;
  sensor_channels: {
    name: string;
    channel_code: string;
    sensor_types: {
      name: string;
      unit: string;
      type_code: string;
    };
  };
};

type AlertItem = {
  alert_id: number;
  room_code: string;
  device_code: string;
  sensor_code: string;
  channel_code: string;
  measurement_type: string;
  unit: string;
  actual_value: number;
  allowed_min: number | null;
  allowed_max: number | null;
  opened_at: string;
  resolved_at: string | null;
  alert_status: string;
};

type DeviceItem = {
  device_code: string;
  name: string;
  model: string;
  firmware_version: string | null;
  last_seen_at: string | null;
  is_active: boolean;
};

type DashboardResponse = {
  generated_at: string;
  period_hours: number;
  current_state: CurrentStateItem[];
  recent_readings: RecentReading[];
  alerts: AlertItem[];
  devices: DeviceItem[];
};

type ChartRow = {
  timestamp: number;
  TEMPERATURE?: number;
  HUMIDITY?: number;
  PRESSURE?: number;
  LIGHT?: number;
};

const API_URL = import.meta.env.VITE_DASHBOARD_API_URL;

const channelOrder = [
  "TEMPERATURE",
  "HUMIDITY",
  "PRESSURE",
  "LIGHT",
];

function formatDateTime(value: string | null) {
  if (!value) return "—";

  return new Intl.DateTimeFormat("uk-UA", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  }).format(new Date(value));
}

function formatShortTime(value: string) {
  return new Intl.DateTimeFormat("uk-UA", {
    hour: "2-digit",
    minute: "2-digit",
  }).format(new Date(value));
}

function formatChartTick(timestamp: number, periodHours: number) {
  if (!Number.isFinite(timestamp)) return "";

  if (periodHours <= 24) {
    return formatShortTime(new Date(timestamp).toISOString());
  }

  return new Intl.DateTimeFormat("uk-UA", {
    day: "2-digit",
    month: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  }).format(new Date(timestamp));
}

function formatChartDate(timestamp: ReactNode) {
  const value =
    typeof timestamp === "number" || typeof timestamp === "string"
      ? Number(timestamp)
      : NaN;
  return Number.isFinite(value)
    ? formatDateTime(new Date(value).toISOString())
    : "";
}

function formatValue(value: number | null, typeCode: string) {
  if (value === null) return "—";

  switch (typeCode) {
    case "TEMPERATURE":
    case "HUMIDITY":
      return value.toFixed(1);
    case "PRESSURE":
      return value.toFixed(1);
    case "LIGHT":
      return Math.round(value).toLocaleString("uk-UA");
    default:
      return String(value);
  }
}

function App() {
  const [data, setData] = useState<DashboardResponse | null>(null);
  const [hours, setHours] = useState(24);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  async function loadDashboard(selectedHours = hours) {
    try {
      setLoading(true);
      setError(null);

      const response = await fetch(
        `${API_URL}?hours=${selectedHours}`,
      );

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
      }

      const result: DashboardResponse = await response.json();
      setData(result);
    } catch (err) {
      setError(
        err instanceof Error
          ? err.message
          : "Не вдалося завантажити дані",
      );
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    loadDashboard(hours);

    const timer = window.setInterval(() => {
      loadDashboard(hours);
    }, 30_000);

    return () => window.clearInterval(timer);
  }, [hours]);

  const currentState = useMemo(() => {
    if (!data) return [];

    return [...data.current_state].sort(
      (a, b) =>
        channelOrder.indexOf(a.type_code) -
        channelOrder.indexOf(b.type_code),
    );
  }, [data]);

  const chartData = useMemo<ChartRow[]>(() => {
    if (!data) return [];

    const grouped = new Map<number, ChartRow>();

    for (const reading of data.recent_readings) {
      const timestamp = new Date(reading.measured_at).getTime();
      if (!Number.isFinite(timestamp)) continue;

      const typeCode =
        reading.sensor_channels.sensor_types.type_code;

      const existing = grouped.get(timestamp) ?? { timestamp };

      if (
        typeCode === "TEMPERATURE" ||
        typeCode === "HUMIDITY" ||
        typeCode === "PRESSURE" ||
        typeCode === "LIGHT"
      ) {
        existing[typeCode] = reading.value;
      }

      grouped.set(timestamp, existing);
    }

    return Array.from(grouped.values()).sort(
      (a, b) => a.timestamp - b.timestamp,
    );
  }, [data]);

  const device = data?.devices[0] ?? null;

  if (loading && !data) {
    return (
      <main className="page-shell">
        <div className="state-message">
          Завантаження даних…
        </div>
      </main>
    );
  }

  if (error && !data) {
    return (
      <main className="page-shell">
        <div className="state-message error-message">
          Не вдалося завантажити дані: {error}
        </div>
      </main>
    );
  }

  return (
    <main className="page-shell">
      <section className="dashboard">
        <header className="topbar">
          <div>
            <p className="eyebrow">
              ENVIRONMENT MONITORING
            </p>
            <h1>Моніторинг параметрів приміщення</h1>
            <p className="subtitle">
              Температура, вологість, атмосферний тиск та
              освітленість
            </p>
          </div>

          <div className="device-summary">
            <span
              className={`device-dot ${
                device?.is_active ? "online" : "offline"
              }`}
            />

            <div>
              <strong>
                {device?.name ?? "ESP-001"}
              </strong>
              <span>
                {device?.model ?? "ESP8266"} ·{" "}
                {device?.is_active
                  ? "активний"
                  : "неактивний"}
              </span>
            </div>
          </div>
        </header>

        <section className="summary-row">
          <div className="summary-box">
            <span>Приміщення</span>
            <strong>
              {currentState[0]?.room_name ?? "—"}
            </strong>
            <small>
              {currentState[0]?.room_code ?? ""}
            </small>
          </div>

          <div className="summary-box">
            <span>Останній зв’язок</span>
            <strong>
              {formatDateTime(
                device?.last_seen_at ?? null,
              )}
            </strong>
            <small>
              {device?.device_code ?? ""}
            </small>
          </div>

          <div className="summary-box">
            <span>Період графіків</span>
            <strong>{hours} год.</strong>
            <small>
              Автооновлення кожні 30 секунд
            </small>
          </div>
        </section>

        <section className="metrics-grid">
          {currentState.map((item) => (
            <article
              className="metric-card"
              key={item.channel_code}
            >
              <div className="metric-card-header">
                <div>
                  <span className="metric-type">
                    {item.measurement_type}
                  </span>
                  <span className="metric-sensor">
                    {item.sensor_model}
                  </span>
                </div>

                <span
                  className={`status-badge ${item.status.toLowerCase()}`}
                >
                  {item.status}
                </span>
              </div>

              <div className="metric-value">
                {formatValue(
                  item.value,
                  item.type_code,
                )}
                <span>{item.unit}</span>
              </div>

              <div className="metric-range">
                Допустимий діапазон:{" "}
                {item.allowed_min ?? "—"} –{" "}
                {item.allowed_max ?? "—"}{" "}
                {item.unit}
              </div>

              <div className="metric-time">
                Оновлено:{" "}
                {formatDateTime(item.measured_at)}
              </div>
            </article>
          ))}
        </section>

        <section className="panel">
          <div className="panel-header">
            <div>
              <h2>Історія вимірювань</h2>
              <p>
                Дані за вибраний часовий період
              </p>
            </div>

            <div className="period-selector">
              {[6, 24, 72, 168].map((value) => (
                <button
                  key={value}
                  type="button"
                  className={
                    hours === value ? "active" : ""
                  }
                  onClick={() => setHours(value)}
                >
                  {value === 168
                    ? "7 днів"
                    : `${value} год.`}
                </button>
              ))}
            </div>
          </div>

          <div className="charts-grid">
            <div className="chart-card">
              <h3>Температура</h3>
              <ResponsiveContainer
                width="100%"
                height={260}
              >
                <LineChart data={chartData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis
                    dataKey="timestamp"
                    type="number"
                    scale="time"
                    domain={["dataMin", "dataMax"]}
                    tickFormatter={(value) =>
                      formatChartTick(Number(value), hours)
                    }
                    minTickGap={32}
                  />
                  <YAxis />
                  <Tooltip labelFormatter={formatChartDate} />
                  <Line
                    type="monotone"
                    dataKey="TEMPERATURE"
                    name="Температура, °C"
                    dot={false}
                    strokeWidth={2}
                  />
                </LineChart>
              </ResponsiveContainer>
            </div>

            <div className="chart-card">
              <h3>Вологість</h3>
              <ResponsiveContainer
                width="100%"
                height={260}
              >
                <LineChart data={chartData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis
                    dataKey="timestamp"
                    type="number"
                    scale="time"
                    domain={["dataMin", "dataMax"]}
                    tickFormatter={(value) =>
                      formatChartTick(Number(value), hours)
                    }
                    minTickGap={32}
                  />
                  <YAxis />
                  <Tooltip labelFormatter={formatChartDate} />
                  <Line
                    type="monotone"
                    dataKey="HUMIDITY"
                    name="Вологість, %"
                    dot={false}
                    strokeWidth={2}
                  />
                </LineChart>
              </ResponsiveContainer>
            </div>

            <div className="chart-card">
              <h3>Атмосферний тиск</h3>
              <ResponsiveContainer
                width="100%"
                height={260}
              >
                <LineChart data={chartData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis
                    dataKey="timestamp"
                    type="number"
                    scale="time"
                    domain={["dataMin", "dataMax"]}
                    tickFormatter={(value) =>
                      formatChartTick(Number(value), hours)
                    }
                    minTickGap={32}
                  />
                  <YAxis domain={["auto", "auto"]} />
                  <Tooltip labelFormatter={formatChartDate} />
                  <Line
                    type="monotone"
                    dataKey="PRESSURE"
                    name="Тиск, hPa"
                    dot={false}
                    strokeWidth={2}
                  />
                </LineChart>
              </ResponsiveContainer>
            </div>

            <div className="chart-card">
              <h3>Освітленість</h3>
              <ResponsiveContainer
                width="100%"
                height={260}
              >
                <LineChart data={chartData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis
                    dataKey="timestamp"
                    type="number"
                    scale="time"
                    domain={["dataMin", "dataMax"]}
                    tickFormatter={(value) =>
                      formatChartTick(Number(value), hours)
                    }
                    minTickGap={32}
                  />
                  <YAxis />
                  <Tooltip labelFormatter={formatChartDate} />
                  <Line
                    type="monotone"
                    dataKey="LIGHT"
                    name="Освітленість, lx"
                    dot={false}
                    strokeWidth={2}
                  />
                </LineChart>
              </ResponsiveContainer>
            </div>
          </div>
        </section>

        <section className="panel">
          <div className="panel-header">
            <div>
              <h2>Історія відхилень</h2>
              <p>
                Зареєстровані виходи показників за
                допустимі межі
              </p>
            </div>
          </div>

          <div className="table-wrapper">
            <table>
              <thead>
                <tr>
                  <th>Параметр</th>
                  <th>Фактичне значення</th>
                  <th>Допустимо</th>
                  <th>Відкрито</th>
                  <th>Закрито</th>
                  <th>Статус</th>
                </tr>
              </thead>

              <tbody>
                {data?.alerts.length ? (
                  data.alerts.map((alert) => (
                    <tr key={alert.alert_id}>
                      <td>
                        {alert.measurement_type}
                      </td>
                      <td>
                        {alert.actual_value}{" "}
                        {alert.unit}
                      </td>
                      <td>
                        {alert.allowed_min ?? "—"} –{" "}
                        {alert.allowed_max ?? "—"}{" "}
                        {alert.unit}
                      </td>
                      <td>
                        {formatDateTime(
                          alert.opened_at,
                        )}
                      </td>
                      <td>
                        {formatDateTime(
                          alert.resolved_at,
                        )}
                      </td>
                      <td>
                        <span
                          className={`status-badge ${alert.alert_status.toLowerCase()}`}
                        >
                          {alert.alert_status}
                        </span>
                      </td>
                    </tr>
                  ))
                ) : (
                  <tr>
                    <td colSpan={6}>
                      Відхилень не зареєстровано
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </section>

        <footer className="footer">
          <span>
            Дані сформовано:{" "}
            {formatDateTime(
              data?.generated_at ?? null,
            )}
          </span>

          {error && (
            <span className="refresh-warning">
              Помилка останнього оновлення: {error}
            </span>
          )}
        </footer>
      </section>
    </main>
  );
}

export default App;
