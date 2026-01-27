import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/package_stats.dart';
import '../services/admin_api_client.dart';
import '../widgets/admin_layout.dart';

class PackageDetailScreen extends StatefulWidget {
  final String packageName;

  const PackageDetailScreen({super.key, required this.packageName});

  @override
  State<PackageDetailScreen> createState() => _PackageDetailScreenState();
}

class _PackageDetailScreenState extends State<PackageDetailScreen> {
  final AdminApiClient _apiClient = AdminApiClient();
  PackageStats? _stats;
  Map<String, dynamic>? _packageInfo;
  bool _isLoading = true;
  String? _error;
  int _historyDays = 30;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response =
          await _apiClient.getPackageStats(widget.packageName, days: _historyDays);
      setState(() {
        _stats = PackageStats.fromJson(response);
        _packageInfo = response['package'] as Map<String, dynamic>?;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      currentPath: '/packages/local',
      child: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              const SizedBox(height: 16),
              Expanded(child: _buildContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 8),
        const Icon(Icons.inventory, size: 32),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.packageName,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              Text(
                _stats != null
                    ? '${_stats!.versionCount} version(s) • ${_formatNumber(_stats!.totalDownloads)} downloads'
                    : 'Loading...',
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
        DropdownButton<int>(
          value: _historyDays,
          items: const [
            DropdownMenuItem(value: 7, child: Text('Last 7 days')),
            DropdownMenuItem(value: 30, child: Text('Last 30 days')),
            DropdownMenuItem(value: 90, child: Text('Last 90 days')),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() => _historyDays = value);
              _loadStats();
            }
          },
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _loadStats,
          tooltip: 'Refresh',
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadStats,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_stats == null) {
      return const Center(child: Text('No data available'));
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatsCards(),
          const SizedBox(height: 24),
          _buildDownloadChart(),
          const SizedBox(height: 24),
          _buildVersionStats(),
          const SizedBox(height: 24),
          if (_packageInfo != null) _buildPackageInfo(),
        ],
      ),
    );
  }

  Widget _buildStatsCards() {
    return Row(
      children: [
        Expanded(child: _buildStatCard('Total Downloads',
            _formatNumber(_stats!.totalDownloads), Icons.download, Colors.blue)),
        const SizedBox(width: 16),
        Expanded(child: _buildStatCard('Versions',
            _stats!.versionCount.toString(), Icons.tag, Colors.green)),
        const SizedBox(width: 16),
        Expanded(child: _buildStatCard('Latest Version',
            _stats!.latestVersion ?? 'N/A', Icons.new_releases, Colors.orange)),
        const SizedBox(width: 16),
        Expanded(child: _buildStatCard('Avg/Day',
            _formatNumber(_calculateAvgDownloads()), Icons.trending_up, Colors.purple)),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadChart() {
    final dailyDownloads = _stats!.dailyDownloads;
    if (dailyDownloads.isEmpty) {
      return Card(
        child: Container(
          height: 300,
          padding: const EdgeInsets.all(24),
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bar_chart, size: 48, color: Colors.grey),
                SizedBox(height: 16),
                Text('No download data available',
                    style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ),
      );
    }

    // Sort and get data points
    final sortedDates = dailyDownloads.keys.toList()..sort();
    final maxDownloads = dailyDownloads.values.reduce((a, b) => a > b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Downloads Over Time',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Y-axis labels
                  SizedBox(
                    width: 50,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(_formatNumber(maxDownloads),
                            style: const TextStyle(fontSize: 10)),
                        Text(_formatNumber(maxDownloads ~/ 2),
                            style: const TextStyle(fontSize: 10)),
                        const Text('0', style: TextStyle(fontSize: 10)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Bars
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: sortedDates.map((date) {
                        final count = dailyDownloads[date]!;
                        final height = maxDownloads > 0
                            ? (count / maxDownloads * 170)
                            : 0.0;
                        return Expanded(
                          child: Tooltip(
                            message: '${_formatDateShort(date)}: $count downloads',
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 1),
                              child: Container(
                                height: height,
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.7),
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // X-axis labels (show first, middle, last)
            Padding(
              padding: const EdgeInsets.only(left: 58),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (sortedDates.isNotEmpty)
                    Text(_formatDateShort(sortedDates.first),
                        style: const TextStyle(fontSize: 10)),
                  if (sortedDates.length > 2)
                    Text(_formatDateShort(sortedDates[sortedDates.length ~/ 2]),
                        style: const TextStyle(fontSize: 10)),
                  if (sortedDates.isNotEmpty)
                    Text(_formatDateShort(sortedDates.last),
                        style: const TextStyle(fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVersionStats() {
    final downloadsByVersion = _stats!.downloadsByVersion;
    if (downloadsByVersion.isEmpty) {
      return const SizedBox.shrink();
    }

    // Sort by download count descending
    final sortedVersions = downloadsByVersion.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Downloads by Version',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            DataTable(
              columns: const [
                DataColumn(label: Text('Version')),
                DataColumn(label: Text('Downloads'), numeric: true),
                DataColumn(label: Text('Percentage'), numeric: true),
              ],
              rows: sortedVersions.take(10).map((entry) {
                final percentage = _stats!.totalDownloads > 0
                    ? (entry.value / _stats!.totalDownloads * 100)
                    : 0.0;
                return DataRow(cells: [
                  DataCell(Text(entry.key)),
                  DataCell(Text(_formatNumber(entry.value))),
                  DataCell(Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 60,
                        child: LinearProgressIndicator(
                          value: percentage / 100,
                          backgroundColor: Colors.grey.shade200,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${percentage.toStringAsFixed(1)}%'),
                    ],
                  )),
                ]);
              }).toList(),
            ),
            if (sortedVersions.length > 10)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '...and ${sortedVersions.length - 10} more versions',
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPackageInfo() {
    final dateFormat = DateFormat('MMM d, y HH:mm');
    final pkg = _packageInfo!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Package Information',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (pkg['description'] != null)
              _buildInfoRow('Description', pkg['description'] as String),
            _buildInfoRow('Created',
                dateFormat.format(DateTime.parse(pkg['created_at'] as String))),
            if (pkg['updated_at'] != null)
              _buildInfoRow('Last Updated',
                  dateFormat.format(DateTime.parse(pkg['updated_at'] as String))),
            if (pkg['is_discontinued'] == true)
              _buildInfoRow('Status', 'Discontinued',
                  valueColor: Colors.orange),
            if (pkg['is_upstream_cache'] == true)
              _buildInfoRow('Type', 'Cached from upstream'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value, style: TextStyle(color: valueColor)),
          ),
        ],
      ),
    );
  }

  int _calculateAvgDownloads() {
    if (_stats!.dailyDownloads.isEmpty) return 0;
    final total = _stats!.dailyDownloads.values.fold(0, (sum, val) => sum + val);
    return (total / _stats!.dailyDownloads.length).round();
  }

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    }
    if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toString();
  }

  String _formatDateShort(String dateStr) {
    final date = DateTime.parse(dateStr);
    return DateFormat('M/d').format(date);
  }
}
