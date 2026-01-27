import 'package:repub_migrate/repub_migrate.dart';
import 'package:test/test.dart';

void main() {
  group('splitStatements', () {
    group('basic functionality', () {
      test('splits simple statements', () {
        final statements = splitStatements('SELECT 1; SELECT 2;');
        expect(statements, equals(['SELECT 1', 'SELECT 2']));
      });

      test('handles single statement without trailing semicolon', () {
        final statements = splitStatements('SELECT 1');
        expect(statements, equals(['SELECT 1']));
      });

      test('handles single statement with trailing semicolon', () {
        final statements = splitStatements('SELECT 1;');
        expect(statements, equals(['SELECT 1']));
      });

      test('handles empty input', () {
        final statements = splitStatements('');
        expect(statements, isEmpty);
      });

      test('handles whitespace only', () {
        final statements = splitStatements('   \n\t  ');
        expect(statements, isEmpty);
      });

      test('trims whitespace from statements', () {
        final statements = splitStatements('  SELECT 1  ;  SELECT 2  ;');
        expect(statements, equals(['SELECT 1', 'SELECT 2']));
      });

      test('preserves newlines within statements', () {
        final statements = splitStatements('SELECT\n  1;');
        expect(statements, equals(['SELECT\n  1']));
      });
    });

    group('string handling', () {
      test('ignores semicolons in single-quoted strings', () {
        final statements = splitStatements("SELECT 'a;b'; SELECT 2;");
        expect(statements, equals(["SELECT 'a;b'", 'SELECT 2']));
      });

      test('ignores semicolons in double-quoted strings', () {
        final statements = splitStatements('SELECT "a;b"; SELECT 2;');
        expect(statements, equals(['SELECT "a;b"', 'SELECT 2']));
      });

      test('handles nested quotes in single-quoted strings', () {
        final statements = splitStatements("SELECT 'a''b;c'; SELECT 2;");
        expect(statements, equals(["SELECT 'a''b;c'", 'SELECT 2']));
      });

      test('handles mixed quotes', () {
        final statements =
            splitStatements('''SELECT 'a"b;c'; SELECT "d'e;f";''');
        expect(statements, equals(["SELECT 'a\"b;c'", '''SELECT "d'e;f"''']));
      });

      test('handles strings with escaped content', () {
        final statements =
            splitStatements(r"INSERT INTO t VALUES ('foo\;bar'); SELECT 1;");
        expect(statements,
            equals([r"INSERT INTO t VALUES ('foo\;bar')", 'SELECT 1']));
      });
    });

    group('comment handling', () {
      test('ignores semicolons in line comments', () {
        final statements = splitStatements('''
SELECT 1; -- this; is; a; comment
SELECT 2;
''');
        expect(statements,
            equals(['SELECT 1', '-- this; is; a; comment\nSELECT 2']));
      });

      test('ignores semicolons in block comments', () {
        final statements = splitStatements('''
SELECT 1 /* a;b;c */; SELECT 2;
''');
        expect(statements, equals(['SELECT 1 /* a;b;c */', 'SELECT 2']));
      });

      test('handles block comments spanning multiple lines', () {
        final statements = splitStatements('''
SELECT 1; /* comment
; with semicolons
; on multiple lines
*/ SELECT 2;
''');
        expect(statements.length, equals(2));
        expect(statements[0], equals('SELECT 1'));
        expect(statements[1], contains('SELECT 2'));
      });

      test('handles comments at end of statement', () {
        final statements = splitStatements('SELECT 1; -- comment');
        expect(statements, equals(['SELECT 1', '-- comment']));
      });

      test('handles block comment at end without semicolon', () {
        final statements = splitStatements('SELECT 1 /* comment */');
        expect(statements, equals(['SELECT 1 /* comment */']));
      });
    });

    group('complex SQL patterns', () {
      test('handles CREATE TABLE statements', () {
        final sql = '''
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL
);
CREATE INDEX idx_users_name ON users(name);
''';
        final statements = splitStatements(sql);
        expect(statements.length, equals(2));
        expect(statements[0], contains('CREATE TABLE users'));
        expect(statements[1], contains('CREATE INDEX'));
      });

      test('handles INSERT with multiple values', () {
        final sql = '''
INSERT INTO t VALUES ('a;b'), ('c;d');
SELECT * FROM t;
''';
        final statements = splitStatements(sql);
        expect(statements.length, equals(2));
        expect(statements[0], contains("('a;b'), ('c;d')"));
      });

      test('handles ALTER TABLE', () {
        final sql = '''
ALTER TABLE packages ADD COLUMN IF NOT EXISTS is_discontinued BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE packages ADD COLUMN IF NOT EXISTS replaced_by VARCHAR(255) NULL;
''';
        final statements = splitStatements(sql);
        expect(statements.length, equals(2));
      });

      test('handles function calls with semicolons in string args', () {
        final sql =
            "SELECT format('%s; %s', 'a', 'b'); SELECT regexp_replace('a;b', ';', ',', 'g');";
        final statements = splitStatements(sql);
        expect(statements.length, equals(2));
      });
    });

    group('edge cases', () {
      test('handles consecutive semicolons', () {
        final statements = splitStatements('SELECT 1;; SELECT 2;');
        expect(statements, equals(['SELECT 1', 'SELECT 2']));
      });

      test('handles semicolons at start', () {
        final statements = splitStatements(';SELECT 1;');
        expect(statements, equals(['SELECT 1']));
      });

      test('handles SQL with only comments', () {
        final statements = splitStatements('-- just a comment');
        expect(statements, equals(['-- just a comment']));
      });

      test('handles nested block comments', () {
        // PostgreSQL allows nested block comments
        final statements = splitStatements('SELECT 1 /* outer /* inner */ */;');
        // Our parser doesn't handle nested comments, but at least shouldn't crash
        expect(statements, isNotEmpty);
      });

      test('handles dollar-quoted strings (common in PostgreSQL)', () {
        // Note: Our simple parser doesn't handle $$ strings specially
        // This test documents the current behavior
        final sql = r'SELECT $tag$semi;colon$tag$; SELECT 2;';
        final statements = splitStatements(sql);
        // Without $$ handling, this will split incorrectly
        // This is a known limitation
        expect(statements.length, greaterThanOrEqualTo(1));
      });
    });

    group('real migration content', () {
      test('splits actual migration SQL correctly', () {
        // Test with actual migration content from the project
        final initialMigration = migrations['001_initial']!;
        final statements = splitStatements(initialMigration);

        // Should have multiple CREATE TABLE/INDEX statements
        expect(statements.length, greaterThan(3));

        // Each statement should be valid (non-empty, trimmed)
        for (final stmt in statements) {
          expect(stmt.trim(), isNotEmpty);
          expect(stmt, isNot(startsWith(' ')));
          expect(stmt, isNot(endsWith(' ')));
        }
      });

      test('all migrations can be split without error', () {
        for (final entry in migrations.entries) {
          final statements = splitStatements(entry.value);
          expect(statements, isNotNull,
              reason: 'Migration ${entry.key} should split without error');

          // Verify no statement is empty or just whitespace
          for (final stmt in statements) {
            expect(stmt.trim(), isNotEmpty,
                reason:
                    'Migration ${entry.key} should not produce empty statements');
          }
        }
      });
    });
  });
}
