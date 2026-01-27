import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class DownloadsLineChart extends StatelessWidget {
  final Map<String, int> data;
  final double height;

  const DownloadsLineChart({
    super.key,
    required this.data,
    this.height = 300,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text('No data available'),
        ),
      );
    }

    // Sort data by timestamp
    final sortedData = Map.fromEntries(
      data.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );

    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _LineChartPainter(sortedData),
        child: Container(),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final Map<String, int> data;
  static final _timeFormat = DateFormat('HH:mm');

  _LineChartPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    const padding = EdgeInsets.fromLTRB(60, 20, 20, 60);
    final chartWidth = size.width - padding.left - padding.right;
    final chartHeight = size.height - padding.top - padding.bottom;

    // Parse timestamps
    final timestamps = data.keys.map((k) => DateTime.parse(k)).toList();
    if (timestamps.isEmpty) return;

    final maxValue = data.values.isEmpty ? 1 : data.values.reduce((a, b) => a > b ? a : b);

    // Draw axes
    _drawAxes(canvas, size, padding, timestamps, maxValue);

    // Create line points
    final points = <Offset>[];
    for (var i = 0; i < timestamps.length; i++) {
      final x = (i / (timestamps.length - 1)) * chartWidth;
      final entry = data.entries.elementAt(i);
      final y = chartHeight - (entry.value / maxValue) * chartHeight;
      points.add(Offset(padding.left + x, padding.top + y));
    }

    // Draw area under the line
    final areaPaint = Paint()
      ..color = Colors.green.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    final areaPath = Path();
    if (points.isNotEmpty) {
      areaPath.moveTo(points.first.dx, size.height - padding.bottom);
      areaPath.lineTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        areaPath.lineTo(points[i].dx, points[i].dy);
      }
      areaPath.lineTo(points.last.dx, size.height - padding.bottom);
      areaPath.close();
    }
    canvas.drawPath(areaPath, areaPaint);

    // Draw line
    final linePaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path();
    if (points.isNotEmpty) {
      path.moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
    }
    canvas.drawPath(path, linePaint);

    // Draw points
    final pointPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.fill;

    for (final point in points) {
      canvas.drawCircle(point, 3, pointPaint);
    }
  }

  void _drawAxes(
    Canvas canvas,
    Size size,
    EdgeInsets padding,
    List<DateTime> timestamps,
    int maxValue,
  ) {
    final axisPaint = Paint()
      ..color = Colors.black54
      ..strokeWidth = 1;

    final textStyle = const TextStyle(
      color: Colors.black87,
      fontSize: 11,
    );

    final chartHeight = size.height - padding.top - padding.bottom;

    // Y-axis
    canvas.drawLine(
      Offset(padding.left, padding.top),
      Offset(padding.left, size.height - padding.bottom),
      axisPaint,
    );

    // X-axis
    canvas.drawLine(
      Offset(padding.left, size.height - padding.bottom),
      Offset(size.width - padding.right, size.height - padding.bottom),
      axisPaint,
    );

    // Y-axis labels
    final yTicks = 5;
    for (var i = 0; i <= yTicks; i++) {
      final value = (maxValue / yTicks * i).round();
      final y = chartHeight - (value / maxValue) * chartHeight;

      // Grid line
      final gridPaint = Paint()
        ..color = Colors.grey.withValues(alpha: 0.2)
        ..strokeWidth = 1;
      canvas.drawLine(
        Offset(padding.left, padding.top + y),
        Offset(size.width - padding.right, padding.top + y),
        gridPaint,
      );

      // Label
      final textSpan = TextSpan(
        text: value.toString(),
        style: textStyle,
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: ui.TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(padding.left - textPainter.width - 8, padding.top + y - textPainter.height / 2),
      );
    }

    // X-axis labels (show every nth label to avoid crowding)
    final xTicks = 6;
    for (var i = 0; i <= xTicks; i++) {
      final idx = ((timestamps.length - 1) * i / xTicks).round();
      if (idx >= timestamps.length) continue;

      final time = timestamps[idx];
      final x = (idx / (timestamps.length - 1)) * (size.width - padding.left - padding.right);
      final timeLabel = _timeFormat.format(time);

      final textSpan = TextSpan(
        text: timeLabel,
        style: textStyle,
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: ui.TextDirection.ltr,
      );
      textPainter.layout();

      // Rotate label 45 degrees
      canvas.save();
      canvas.translate(
        padding.left + x,
        size.height - padding.bottom + 10,
      );
      canvas.rotate(0.785398); // 45 degrees in radians
      textPainter.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return data != oldDelegate.data;
  }
}
