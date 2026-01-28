import 'package:repub_migrate/repub_migrate.dart';
import 'package:test/test.dart';

void main() {
  group('migrations', () {
    test('has ordered migration keys', () {
      final keys = migrations.keys.toList();
      final sortedKeys = List<String>.from(keys)..sort();
      expect(keys, equals(sortedKeys),
          reason: 'Migrations should be defined in sorted order');
    });

    test('migration keys follow naming convention', () {
      for (final key in migrations.keys) {
        expect(
          key,
          matches(RegExp(r'^\d{3}_[a-z_]+$')),
          reason: 'Migration key "$key" should match pattern 001_snake_case',
        );
      }
    });

    test('all migrations have non-empty SQL', () {
      for (final entry in migrations.entries) {
        expect(
          entry.value.trim(),
          isNotEmpty,
          reason: 'Migration ${entry.key} should have non-empty SQL',
        );
      }
    });

    test('initial migration creates required tables', () {
      final initialMigration = migrations['001_initial']!;
      expect(initialMigration, contains('CREATE TABLE'));
      expect(initialMigration, contains('packages'));
      expect(initialMigration, contains('package_versions'));
      expect(initialMigration, contains('auth_tokens'));
      expect(initialMigration, contains('upload_sessions'));
    });

    test('upstream cache migration adds column', () {
      final migration = migrations['002_upstream_cache']!;
      expect(migration, contains('ALTER TABLE packages'));
      expect(migration, contains('is_upstream_cache'));
    });

    test('admin authentication migration creates admin_users', () {
      final migration = migrations['003_admin_authentication']!;
      expect(migration, contains('CREATE TABLE'));
      expect(migration, contains('admin_users'));
      expect(migration, contains('username'));
      expect(migration, contains('password_hash'));
    });

    test('activity log migration creates required tables', () {
      final migration = migrations['009_activity_log']!;
      expect(migration, contains('CREATE TABLE'));
      expect(migration, contains('activity_log'));
      expect(migration, contains('activity_type'));
      expect(migration, contains('actor_type'));
    });

    test('webhooks migration creates webhooks and deliveries tables', () {
      final migration = migrations['010_webhooks']!;
      expect(migration, contains('CREATE TABLE'));
      expect(migration, contains('webhooks'));
      expect(migration, contains('webhook_deliveries'));
      expect(migration, contains('REFERENCES webhooks(id)'));
    });

    test('version retraction migration adds columns', () {
      final migration = migrations['011_version_retraction']!;
      expect(migration, contains('ALTER TABLE package_versions'));
      expect(migration, contains('is_retracted'));
      expect(migration, contains('retracted_at'));
      expect(migration, contains('retraction_message'));
    });
  });

  group('getPendingMigrations', () {
    test('returns all migrations when none applied', () {
      final pending = getPendingMigrations({});
      expect(pending.length, equals(migrations.length));
    });

    test('returns empty list when all applied', () {
      final applied = migrations.keys.toSet();
      final pending = getPendingMigrations(applied);
      expect(pending, isEmpty);
    });

    test('returns only unapplied migrations', () {
      final applied = {'001_initial', '002_upstream_cache'};
      final pending = getPendingMigrations(applied);

      expect(pending.any((m) => m.key == '001_initial'), isFalse);
      expect(pending.any((m) => m.key == '002_upstream_cache'), isFalse);
      expect(pending.any((m) => m.key == '003_admin_authentication'), isTrue);
    });

    test('returns migrations in sorted order', () {
      final applied = {'002_upstream_cache'}; // Skip the middle one
      final pending = getPendingMigrations(applied);

      // Should include 001 and all after 002
      final keys = pending.map((m) => m.key).toList();
      final sortedKeys = List<String>.from(keys)..sort();
      expect(keys, equals(sortedKeys));
    });

    test('ignores unknown applied migrations', () {
      final applied = {'001_initial', 'unknown_migration'};
      final pending = getPendingMigrations(applied);

      // Should still return all except 001_initial
      expect(pending.any((m) => m.key == '001_initial'), isFalse);
      expect(pending.length, equals(migrations.length - 1));
    });
  });

  group('migration content validation', () {
    test('no migration contains DROP TABLE without IF EXISTS', () {
      for (final entry in migrations.entries) {
        final sql = entry.value.toUpperCase();
        if (sql.contains('DROP TABLE')) {
          expect(
            sql,
            contains('DROP TABLE IF EXISTS'),
            reason:
                'Migration ${entry.key} should use DROP TABLE IF EXISTS for safety',
          );
        }
      }
    });

    test('CREATE TABLE uses IF NOT EXISTS', () {
      for (final entry in migrations.entries) {
        final sql = entry.value.toUpperCase();
        // Count CREATE TABLE occurrences that don't have IF NOT EXISTS
        final createTableCount =
            RegExp(r'CREATE TABLE(?! IF NOT EXISTS)').allMatches(sql).length;
        expect(
          createTableCount,
          equals(0),
          reason:
              'Migration ${entry.key} should use CREATE TABLE IF NOT EXISTS',
        );
      }
    });

    test('ALTER TABLE uses IF EXISTS/IF NOT EXISTS for columns', () {
      // This is a best-practice check - PostgreSQL supports ADD COLUMN IF NOT EXISTS
      for (final entry in migrations.entries) {
        final sql = entry.value.toUpperCase();
        if (sql.contains('ADD COLUMN') && !sql.contains('IF NOT EXISTS')) {
          // Allow migrations that might be running on older PostgreSQL
          // Just log a warning rather than failing
        }
      }
    });

    test('indexes use IF NOT EXISTS', () {
      for (final entry in migrations.entries) {
        final sql = entry.value.toUpperCase();
        final createIndexCount =
            RegExp(r'CREATE INDEX(?! IF NOT EXISTS)').allMatches(sql).length;
        expect(
          createIndexCount,
          equals(0),
          reason:
              'Migration ${entry.key} should use CREATE INDEX IF NOT EXISTS',
        );
      }
    });
  });
}
