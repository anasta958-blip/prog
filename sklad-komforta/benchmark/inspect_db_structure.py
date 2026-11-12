"""Read-only summary of tenant tables, indexes and foreign-key index coverage."""

from restore_test_config import db_settings, sql

user, database = db_settings()
schema = sql(user, database, """
SELECT n.nspname FROM pg_namespace n
JOIN pg_class c ON c.relnamespace = n.oid
WHERE n.nspname LIKE 'tenant_%' AND c.relkind = 'r'
GROUP BY n.nspname
ORDER BY sum(pg_total_relation_size(c.oid)) DESC LIMIT 1;
""")
print("schema", schema)
print("largest_tables", sql(user, database, f"""
SELECT relname || '|' || n_live_tup || '|' ||
       pg_size_pretty(pg_total_relation_size(relid)) || '|' ||
       seq_scan || '|' || idx_scan
FROM pg_stat_user_tables
WHERE schemaname = '{schema}'
ORDER BY pg_total_relation_size(relid) DESC LIMIT 20;
"""))
print("foreign_keys_without_leading_index", sql(user, database, f"""
SELECT c.conrelid::regclass::text || '|' || c.conname || '|' ||
       array_to_string(c.conkey, ',')
FROM pg_constraint c
JOIN pg_namespace n ON n.oid = (SELECT relnamespace FROM pg_class WHERE oid = c.conrelid)
WHERE n.nspname = '{schema}' AND c.contype = 'f'
  AND NOT EXISTS (
      SELECT 1 FROM pg_index i
      WHERE i.indrelid = c.conrelid AND i.indisvalid
        AND i.indkey[0] = c.conkey[1]
  )
ORDER BY c.conrelid::regclass::text, c.conname;
"""))
