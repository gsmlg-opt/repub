import 'package:postgres/postgres.dart';

import 'migrations.dart';

/// Run pending database migrations.
Future<int> runMigrations(Connection conn) async {
  // Ensure schema_migrations table exists
  await conn.execute('''
    CREATE TABLE IF NOT EXISTS schema_migrations (
      version VARCHAR(255) PRIMARY KEY,
      applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  ''');

  // Get applied migrations
  final result = await conn.execute('SELECT version FROM schema_migrations');
  final applied = result.map((row) => row[0] as String).toSet();

  // Run pending migrations
  final pending = getPendingMigrations(applied);
  var count = 0;

  for (final migration in pending) {
    print('Applying migration: ${migration.key}');

    await conn.runTx((session) async {
      // Run the migration SQL
      await session.execute(migration.value);

      // Record it as applied
      await session.execute(
        Sql.named('INSERT INTO schema_migrations (version) VALUES (@version)'),
        parameters: {'version': migration.key},
      );
    });

    count++;
  }

  return count;
}
