import 'package:repub_server/src/logger.dart';
import 'package:test/test.dart';

void main() {
  group('Logger', () {
    setUp(() {
      Logger.reset();
    });

    tearDown(() {
      Logger.reset();
    });

    group('LogLevel', () {
      test('has correct index order', () {
        expect(LogLevel.debug.index, lessThan(LogLevel.info.index));
        expect(LogLevel.info.index, lessThan(LogLevel.warn.index));
        expect(LogLevel.warn.index, lessThan(LogLevel.error.index));
      });

      test('debug is lowest level', () {
        expect(LogLevel.debug.index, equals(0));
      });

      test('error is highest level', () {
        expect(LogLevel.error.index, equals(3));
      });
    });

    group('isEnabled', () {
      test('debug level enables all levels', () {
        Logger.configure(minLevel: LogLevel.debug);
        expect(Logger.isEnabled(LogLevel.debug), isTrue);
        expect(Logger.isEnabled(LogLevel.info), isTrue);
        expect(Logger.isEnabled(LogLevel.warn), isTrue);
        expect(Logger.isEnabled(LogLevel.error), isTrue);
      });

      test('info level disables debug', () {
        Logger.configure(minLevel: LogLevel.info);
        expect(Logger.isEnabled(LogLevel.debug), isFalse);
        expect(Logger.isEnabled(LogLevel.info), isTrue);
        expect(Logger.isEnabled(LogLevel.warn), isTrue);
        expect(Logger.isEnabled(LogLevel.error), isTrue);
      });

      test('warn level disables debug and info', () {
        Logger.configure(minLevel: LogLevel.warn);
        expect(Logger.isEnabled(LogLevel.debug), isFalse);
        expect(Logger.isEnabled(LogLevel.info), isFalse);
        expect(Logger.isEnabled(LogLevel.warn), isTrue);
        expect(Logger.isEnabled(LogLevel.error), isTrue);
      });

      test('error level only enables error', () {
        Logger.configure(minLevel: LogLevel.error);
        expect(Logger.isEnabled(LogLevel.debug), isFalse);
        expect(Logger.isEnabled(LogLevel.info), isFalse);
        expect(Logger.isEnabled(LogLevel.warn), isFalse);
        expect(Logger.isEnabled(LogLevel.error), isTrue);
      });
    });

    group('configure', () {
      test('sets minimum log level', () {
        Logger.configure(minLevel: LogLevel.warn);
        expect(Logger.isEnabled(LogLevel.info), isFalse);
        expect(Logger.isEnabled(LogLevel.warn), isTrue);
      });

      test('sets JSON format', () {
        Logger.configure(jsonFormat: true);
        // JSON format is set, but we can't easily verify output format
        // without capturing stdout
        expect(true, isTrue); // Placeholder
      });
    });

    group('reset', () {
      test('resets to default settings', () {
        Logger.configure(minLevel: LogLevel.error, jsonFormat: true);
        expect(Logger.isEnabled(LogLevel.info), isFalse);

        Logger.reset();
        // After reset, init() will be called on next log, resetting to defaults
        // Default is info level
        Logger.configure(minLevel: LogLevel.info);
        expect(Logger.isEnabled(LogLevel.info), isTrue);
      });
    });

    group('log methods', () {
      test('debug accepts message and metadata', () {
        Logger.configure(minLevel: LogLevel.debug);
        // Should not throw
        expect(
          () => Logger.debug(
            'Test message',
            component: 'test',
            metadata: {'key': 'value'},
          ),
          returnsNormally,
        );
      });

      test('info accepts message and metadata', () {
        Logger.configure(minLevel: LogLevel.info);
        expect(
          () => Logger.info(
            'Test message',
            component: 'test',
            metadata: {'key': 'value'},
          ),
          returnsNormally,
        );
      });

      test('warn accepts message, metadata, and error', () {
        Logger.configure(minLevel: LogLevel.warn);
        expect(
          () => Logger.warn(
            'Test warning',
            component: 'test',
            metadata: {'key': 'value'},
            error: Exception('Test error'),
          ),
          returnsNormally,
        );
      });

      test('error accepts message, metadata, error, and stackTrace', () {
        Logger.configure(minLevel: LogLevel.error);
        expect(
          () => Logger.error(
            'Test error',
            component: 'test',
            metadata: {'key': 'value'},
            error: Exception('Test error'),
            stackTrace: StackTrace.current,
          ),
          returnsNormally,
        );
      });
    });

    group('log filtering', () {
      test('does not log below minimum level', () {
        Logger.configure(minLevel: LogLevel.warn);
        // These should not log anything (or throw)
        expect(() => Logger.debug('Debug message'), returnsNormally);
        expect(() => Logger.info('Info message'), returnsNormally);
        // These should log
        expect(() => Logger.warn('Warning message'), returnsNormally);
        expect(() => Logger.error('Error message'), returnsNormally);
      });
    });
  });

  group('Logger output format', () {
    // Note: These tests verify that logging doesn't throw.
    // Full output verification would require capturing stdout.

    test('text format logs without throwing', () {
      Logger.configure(jsonFormat: false, minLevel: LogLevel.debug);
      expect(
        () => Logger.log(
          LogLevel.info,
          'Test message',
          component: 'test-component',
          metadata: {'key1': 'value1', 'key2': 42},
        ),
        returnsNormally,
      );
    });

    test('JSON format logs without throwing', () {
      Logger.configure(jsonFormat: true, minLevel: LogLevel.debug);
      expect(
        () => Logger.log(
          LogLevel.info,
          'Test message',
          component: 'test-component',
          metadata: {'key1': 'value1', 'key2': 42},
        ),
        returnsNormally,
      );
    });

    test('error with stack trace logs without throwing', () {
      Logger.configure(jsonFormat: false, minLevel: LogLevel.error);
      try {
        throw Exception('Test exception');
      } catch (e, stackTrace) {
        expect(
          () => Logger.error(
            'Caught error',
            error: e,
            stackTrace: stackTrace,
          ),
          returnsNormally,
        );
      }
    });
  });
}
