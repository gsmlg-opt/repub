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
      // Split migration into individual statements and execute each
      final statements = _splitStatements(migration.value);
      for (final statement in statements) {
        if (statement.trim().isNotEmpty) {
          await session.execute(statement);
        }
      }

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

/// Split SQL into individual statements.
/// Handles semicolons inside strings and comments.
List<String> _splitStatements(String sql) {
  final statements = <String>[];
  final buffer = StringBuffer();
  var inSingleQuote = false;
  var inDoubleQuote = false;
  var inLineComment = false;
  var inBlockComment = false;

  for (var i = 0; i < sql.length; i++) {
    final char = sql[i];
    final nextChar = i + 1 < sql.length ? sql[i + 1] : '';

    // Handle comments
    if (!inSingleQuote && !inDoubleQuote) {
      if (inLineComment) {
        buffer.write(char);
        if (char == '\n') inLineComment = false;
        continue;
      }
      if (inBlockComment) {
        buffer.write(char);
        if (char == '*' && nextChar == '/') {
          buffer.write(nextChar);
          i++;
          inBlockComment = false;
        }
        continue;
      }
      if (char == '-' && nextChar == '-') {
        inLineComment = true;
        buffer.write(char);
        continue;
      }
      if (char == '/' && nextChar == '*') {
        inBlockComment = true;
        buffer.write(char);
        continue;
      }
    }

    // Handle quotes
    if (char == "'" && !inDoubleQuote && !inLineComment && !inBlockComment) {
      inSingleQuote = !inSingleQuote;
    }
    if (char == '"' && !inSingleQuote && !inLineComment && !inBlockComment) {
      inDoubleQuote = !inDoubleQuote;
    }

    // Handle semicolons
    if (char == ';' &&
        !inSingleQuote &&
        !inDoubleQuote &&
        !inLineComment &&
        !inBlockComment) {
      final stmt = buffer.toString().trim();
      if (stmt.isNotEmpty) {
        statements.add(stmt);
      }
      buffer.clear();
      continue;
    }

    buffer.write(char);
  }

  // Add remaining statement if any
  final remaining = buffer.toString().trim();
  if (remaining.isNotEmpty) {
    statements.add(remaining);
  }

  return statements;
}
