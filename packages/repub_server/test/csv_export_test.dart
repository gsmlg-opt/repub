import 'package:repub_server/src/csv_export.dart';
import 'package:test/test.dart';

void main() {
  group('escapeCsvField', () {
    test('returns empty string for null', () {
      expect(escapeCsvField(null), equals(''));
    });

    test('returns empty string for empty string', () {
      expect(escapeCsvField(''), equals(''));
    });

    test('returns value as-is for simple strings', () {
      expect(escapeCsvField('hello'), equals('hello'));
      expect(escapeCsvField('123'), equals('123'));
    });

    test('wraps value with comma in quotes', () {
      expect(escapeCsvField('hello,world'), equals('"hello,world"'));
    });

    test('wraps value with newline in quotes', () {
      expect(escapeCsvField('hello\nworld'), equals('"hello\nworld"'));
    });

    test('wraps value with carriage return in quotes', () {
      expect(escapeCsvField('hello\rworld'), equals('"hello\rworld"'));
    });

    test('doubles quotes and wraps in quotes', () {
      expect(escapeCsvField('say "hello"'), equals('"say ""hello"""'));
    });

    test('handles multiple special characters', () {
      expect(escapeCsvField('say "hello", friend\n'),
          equals('"say ""hello"", friend\n"'));
    });
  });

  group('mapListToCsv', () {
    test('returns empty string for empty list', () {
      expect(mapListToCsv([]), equals(''));
    });

    test('converts single row with simple values', () {
      final data = [
        {'name': 'Alice', 'age': '30', 'city': 'NYC'}
      ];
      final csv = mapListToCsv(data);
      expect(csv, equals('name,age,city\nAlice,30,NYC'));
    });

    test('converts multiple rows', () {
      final data = [
        {'name': 'Alice', 'age': '30'},
        {'name': 'Bob', 'age': '25'},
        {'name': 'Carol', 'age': '35'},
      ];
      final csv = mapListToCsv(data);
      expect(csv, equals('name,age\nAlice,30\nBob,25\nCarol,35'));
    });

    test('handles null values', () {
      final data = [
        {'name': 'Alice', 'email': 'alice@example.com'},
        {'name': 'Bob', 'email': null},
      ];
      final csv = mapListToCsv(data);
      expect(csv, equals('name,email\nAlice,alice@example.com\nBob,'));
    });

    test('escapes special characters in values', () {
      final data = [
        {'name': 'Alice, Bob', 'note': 'Say "hi"'},
      ];
      final csv = mapListToCsv(data);
      expect(csv, equals('name,note\n"Alice, Bob","Say ""hi"""'));
    });

    test('handles newlines in values', () {
      final data = [
        {'text': 'Line 1\nLine 2'}
      ];
      final csv = mapListToCsv(data);
      expect(csv, equals('text\n"Line 1\nLine 2"'));
    });

    test('preserves column order from first row', () {
      final data = [
        {'c': '3', 'a': '1', 'b': '2'},
        {'c': '6', 'a': '4', 'b': '5'},
      ];
      final csv = mapListToCsv(data);
      // Order should match first row's key order
      expect(csv.startsWith('c,a,b\n'), isTrue);
    });

    test('handles integer and boolean values', () {
      final data = [
        {'name': 'test', 'count': 42, 'active': true},
      ];
      final csv = mapListToCsv(data);
      expect(csv, equals('name,count,active\ntest,42,true'));
    });
  });

  group('objectListToCsv', () {
    test('converts objects using toJson function', () {
      final users = [
        _TestUser('Alice', 'alice@example.com'),
        _TestUser('Bob', 'bob@example.com'),
      ];
      final csv = objectListToCsv(users, (u) => u.toMap());
      expect(csv,
          equals('name,email\nAlice,alice@example.com\nBob,bob@example.com'));
    });

    test('handles empty list', () {
      final csv = objectListToCsv<_TestUser>([], (u) => u.toMap());
      expect(csv, equals(''));
    });

    test('handles complex objects', () {
      final packages = [
        _TestPackage('pkg1', '1.0.0', true),
        _TestPackage('pkg2', '2.0.0', false),
      ];
      final csv = objectListToCsv(packages, (p) => p.toMap());
      expect(
          csv,
          equals(
              'name,version,discontinued\npkg1,1.0.0,true\npkg2,2.0.0,false'));
    });
  });
}

class _TestUser {
  final String name;
  final String email;
  _TestUser(this.name, this.email);

  Map<String, dynamic> toMap() => {'name': name, 'email': email};
}

class _TestPackage {
  final String name;
  final String version;
  final bool discontinued;
  _TestPackage(this.name, this.version, this.discontinued);

  Map<String, dynamic> toMap() => {
        'name': name,
        'version': version,
        'discontinued': discontinued,
      };
}
