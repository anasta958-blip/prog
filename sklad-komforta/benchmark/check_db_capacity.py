"""Read PostgreSQL connection headroom without printing database credentials."""

from restore_test_config import db_settings, sql

user, database = db_settings()
print("max_connections", sql(user, database, "SHOW max_connections;"))
print("superuser_reserved_connections", sql(user, database, "SHOW superuser_reserved_connections;"))
print("active_connections", sql(user, database, "SELECT count(*) FROM pg_stat_activity;"))
print("by_state", sql(user, database,
    "SELECT COALESCE(state,'unknown') || ':' || count(*) FROM pg_stat_activity GROUP BY state;"))
print("client_backends_by_source", sql(user, database,
    "SELECT concat_ws('|', coalesce(state,'unknown'), usename, application_name, "
    "client_addr::text, count(*), "
    "round(extract(epoch from max(now() - state_change)))::int) "
    "FROM pg_stat_activity WHERE backend_type='client backend' "
    "GROUP BY state, usename, application_name, client_addr ORDER BY count(*) DESC;"))
print("timeouts", sql(user, database,
    "SELECT name || '=' || setting FROM pg_settings "
    "WHERE name IN ('idle_session_timeout', 'idle_in_transaction_session_timeout', "
    "'reserved_connections') ORDER BY name;"))
