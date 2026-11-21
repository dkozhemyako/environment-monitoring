SELECT
    version() AS postgres_version,
    current_database() AS database_name,
    current_user AS current_user,
    current_setting('server_version') AS server_version,
    current_setting('TimeZone') AS timezone,
    now() AS checked_at;
