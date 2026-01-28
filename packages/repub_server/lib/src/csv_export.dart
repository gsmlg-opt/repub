/// CSV export utilities for admin analytics data.
library;

/// Escapes a CSV field value by:
/// - Wrapping in quotes if it contains comma, newline, or quote
/// - Doubling any quotes within the value
String escapeCsvField(String? value) {
  if (value == null || value.isEmpty) return '';

  final needsQuotes = value.contains(',') ||
      value.contains('\n') ||
      value.contains('"') ||
      value.contains('\r');

  if (!needsQuotes) return value;

  // Double any quotes and wrap in quotes
  final escaped = value.replaceAll('"', '""');
  return '"$escaped"';
}

/// Converts a list of maps to CSV format.
/// The first map's keys are used as headers.
/// All subsequent maps are expected to have the same keys.
String mapListToCsv(List<Map<String, dynamic>> data) {
  if (data.isEmpty) {
    return '';
  }

  final headers = data.first.keys.toList();
  final csvLines = <String>[];

  // Add header row
  csvLines.add(headers.map(escapeCsvField).join(','));

  // Add data rows
  for (final row in data) {
    final values = headers.map((key) {
      final value = row[key];
      if (value == null) return '';
      return escapeCsvField(value.toString());
    });
    csvLines.add(values.join(','));
  }

  return csvLines.join('\n');
}

/// Converts a list of objects with toJson() method to CSV format.
String objectListToCsv<T>(
    List<T> data, Map<String, dynamic> Function(T) toJson) {
  final maps = data.map(toJson).toList();
  return mapListToCsv(maps);
}
