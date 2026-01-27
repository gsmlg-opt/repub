import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class PackagesCreatedChart extends StatelessWidget {
  final Map<String, int> data;
  final double height;

  const PackagesCreatedChart({
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

    // Sort data by date
    final sortedData = Map.fromEntries(
      data.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );

    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _BarChartPainter(sortedData),
        child: Container(),
      ),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  final Map<String, int> data;
  static final _dateFormat = DateFormat('MM/dd');

  _BarChartPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    const padding = EdgeInsets.fromLTRB(60, 20, 20, 60);
    final chartWidth = size.width - padding.left - padding.right;
    final chartHeight = size.height - padding.top - padding.bottom;

    final maxValue = data.values.isEmpty ? 1 : data.values.reduce((a, b) => a > b ? a : b);
    final barCount = data.length;
    final barWidth = chartWidth / barCount * 0.8;
    final barSpacing = chartWidth / barCount * 0.2;

    // Draw axes
    _drawAxes(canvas, size, padding, maxValue);

    // Draw bars
    final paint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;

    var index = 0;
    for (final entry in data.entries) {
      final x = index * (barWidth + barSpacing) + barSpacing / 2;
      final barHeight = (entry.value / maxValue) * chartHeight;
      final y = chartHeight - barHeight;

      canvas.drawRect(
        Rect.fromLTWH(
          padding.left + x,
          padding.top + y,
          barWidth,
          barHeight,
        ),
        paint,
      );
      index++;
    }
  }

  void _drawAxes(
    Canvas canvas,
    Size size,
    EdgeInsets padding,
    int maxValue,
  ) {
    final axisPaint = Paint()
      ..color = Colors.black54
      ..strokeWidth = 1;

    final textStyle = const TextStyle(
      color: Colors.black87,
      fontSize: 11,
    );

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
    final chartHeight = size.height - padding.top - padding.bottom;
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
    final labels = data.keys.toList();
    final showEveryN = (labels.length / 10).ceil().clamp(1, labels.length);
    final chartWidth = size.width - padding.left - padding.right;
    final barCount = data.length;
    final barWidth = chartWidth / barCount * 0.8;
    final barSpacing = chartWidth / barCount * 0.2;

    for (var i = 0; i < labels.length; i += showEveryN) {
      final label = labels[i];
      final x = i * (barWidth + barSpacing) + barSpacing / 2 + barWidth / 2;

      // Format date label
      final date = DateTime.parse(label);
      final dateLabel = _dateFormat.format(date);

      final textSpan = TextSpan(
        text: dateLabel,
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
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) {
    return data != oldDelegate.data;
  }
}
