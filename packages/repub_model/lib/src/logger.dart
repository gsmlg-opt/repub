import 'dart:convert';
import 'dart:io';

/// Log levels for the server.
enum LogLevel {
  debug,
  info,
  warn,
  error,
}

/// Structured logger for the repub application.
///
/// Features:
/// - Configurable log levels via REPUB_LOG_LEVEL env var
/// - JSON output format via REPUB_LOG_JSON=true
/// - Structured metadata support
/// - Timestamp and level prefixes
class Logger {
  static LogLevel _minLevel = LogLevel.info;
  static bool _jsonFormat = false;
  static bool _initialized = false;

  /// Initialize logger from environment variables.
  static void init() {
    if (_initialized) return;

    final levelStr = Platform.environment['REPUB_LOG_LEVEL']?.toLowerCase();
    switch (levelStr) {
      case 'debug':
        _minLevel = LogLevel.debug;
        break;
      case 'info':
        _minLevel = LogLevel.info;
        break;
      case 'warn':
      case 'warning':
        _minLevel = LogLevel.warn;
        break;
      case 'error':
        _minLevel = LogLevel.error;
        break;
    }

    _jsonFormat =
        Platform.environment['REPUB_LOG_JSON']?.toLowerCase() == 'true';
    _initialized = true;
  }

  /// Configure logger programmatically (useful for testing).
  static void configure({LogLevel? minLevel, bool? jsonFormat}) {
    if (minLevel != null) _minLevel = minLevel;
    if (jsonFormat != null) _jsonFormat = jsonFormat;
    _initialized = true;
  }

  /// Reset logger to default state (useful for testing).
  static void reset() {
    _minLevel = LogLevel.info;
    _jsonFormat = false;
    _initialized = false;
  }

  /// Check if a log level is enabled.
  static bool isEnabled(LogLevel level) {
    return level.index >= _minLevel.index;
  }

  /// Log a message at the specified level.
  static void log(
    LogLevel level,
    String message, {
    String? component,
    Map<String, dynamic>? metadata,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!_initialized) init();
    if (!isEnabled(level)) return;

    if (_jsonFormat) {
      _logJson(level, message,
          component: component,
          metadata: metadata,
          error: error,
          stackTrace: stackTrace);
    } else {
      _logText(level, message,
          component: component,
          metadata: metadata,
          error: error,
          stackTrace: stackTrace);
    }
  }

  static void _logJson(
    LogLevel level,
    String message, {
    String? component,
    Map<String, dynamic>? metadata,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final entry = <String, dynamic>{
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'level': level.name.toUpperCase(),
      'message': message,
    };

    if (component != null) entry['component'] = component;
    if (metadata != null) entry.addAll(metadata);
    if (error != null) entry['error'] = error.toString();
    if (stackTrace != null) entry['stack_trace'] = stackTrace.toString();

    print(jsonEncode(entry));
  }

  static void _logText(
    LogLevel level,
    String message, {
    String? component,
    Map<String, dynamic>? metadata,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final levelStr = level.name.toUpperCase().padRight(5);
    final componentStr = component != null ? '[$component] ' : '';

    var output = '$timestamp $levelStr $componentStr$message';

    if (metadata != null && metadata.isNotEmpty) {
      final metaStr =
          metadata.entries.map((e) => '${e.key}=${e.value}').join(' ');
      output += ' ($metaStr)';
    }

    print(output);

    if (error != null) {
      print('$timestamp ERROR ${componentStr}Error: $error');
    }
    if (stackTrace != null) {
      print('$timestamp ERROR ${componentStr}Stack trace:');
      print(stackTrace);
    }
  }

  /// Log a debug message.
  static void debug(
    String message, {
    String? component,
    Map<String, dynamic>? metadata,
  }) {
    log(LogLevel.debug, message, component: component, metadata: metadata);
  }

  /// Log an info message.
  static void info(
    String message, {
    String? component,
    Map<String, dynamic>? metadata,
  }) {
    log(LogLevel.info, message, component: component, metadata: metadata);
  }

  /// Log a warning message.
  static void warn(
    String message, {
    String? component,
    Map<String, dynamic>? metadata,
    Object? error,
  }) {
    log(LogLevel.warn, message,
        component: component, metadata: metadata, error: error);
  }

  /// Log an error message.
  static void error(
    String message, {
    String? component,
    Map<String, dynamic>? metadata,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(LogLevel.error, message,
        component: component,
        metadata: metadata,
        error: error,
        stackTrace: stackTrace);
  }
}
