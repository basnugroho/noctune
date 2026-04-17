import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/test_models.dart';
import '../../../providers/test_provider.dart';
import '../../../widgets/common_widgets.dart';

class TtfbTestScreen extends StatefulWidget {
  const TtfbTestScreen({super.key});

  @override
  State<TtfbTestScreen> createState() => _TtfbTestScreenState();
}

class _TtfbTestScreenState extends State<TtfbTestScreen> {
  final TextEditingController _urlController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _addUrl(TestProvider provider) {
    final url = _urlController.text.trim();
    if (url.isNotEmpty) {
      provider.addTarget(url);
      _urlController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TestProvider>(
      builder: (context, provider, child) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Network Info Card
              _buildNetworkInfoCard(provider),
              const SizedBox(height: 16),

              // Configuration Section
              _buildConfigurationSection(provider),
              const SizedBox(height: 16),

              // Action Button
              _buildActionButton(provider),
              const SizedBox(height: 24),

              // Results Section
              if (provider.ttfbResults.isNotEmpty) ...[
                _buildResultsSection(provider),
              ],

              // Empty State
              if (provider.status == TestStatus.idle &&
                  provider.ttfbResults.isEmpty)
                const EmptyState(
                  icon: Icons.speed,
                  title: 'Ready to Test',
                  subtitle:
                      'Add target URLs and tap "Run Test" to start measuring TTFB',
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNetworkInfoCard(TestProvider provider) {
    final networkInfo = provider.networkInfo;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.accentBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                networkInfo?.connectionType == 'WiFi'
                    ? Icons.wifi
                    : Icons.signal_cellular_4_bar,
                color: AppTheme.accentBlue,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    networkInfo?.connectionType ?? 'Unknown',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (networkInfo?.ssid != null)
                    Text(
                      networkInfo!.ssid!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (networkInfo?.ipAddress != null)
                    Text(
                      networkInfo!.ipAddress!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  if (networkInfo?.publicIp != null)
                    Text(
                      'Public IP: ${networkInfo!.publicIp}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  if (networkInfo?.location != null)
                    Text(
                      [
                            networkInfo?.location?.city,
                            networkInfo?.location?.region,
                            networkInfo?.location?.country,
                          ]
                          .whereType<String>()
                          .where((value) => value.isNotEmpty)
                          .join(', '),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    )
                  else
                    Text(
                      'Tap refresh or run a test to grant location access.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: provider.refreshNetworkInfo,
              tooltip: 'Refresh',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigurationSection(TestProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(title: 'Target URLs'),
            const SizedBox(height: 8),

            // URL Input
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      hintText: 'Enter URL (e.g., google.com)',
                      prefixIcon: Icon(Icons.link),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _addUrl(provider),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _addUrl(provider),
                  icon: const Icon(Icons.add_circle),
                  color: AppTheme.accentBlue,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // URL Chips
            if (provider.targetUrls.isEmpty)
              Text(
                'No targets added. Add URLs above or use defaults.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: provider.targetUrls.map((url) {
                  return UrlChip(
                    url: url,
                    onDelete: provider.status == TestStatus.idle
                        ? () => provider.removeTarget(url)
                        : null,
                  );
                }).toList(),
              ),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),

            // Quick Add Defaults
            TextButton.icon(
              onPressed: provider.status == TestStatus.idle
                  ? () {
                      for (final url in AppConstants.defaultTargets) {
                        provider.addTarget(url);
                      }
                    }
                  : null,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Default Targets'),
            ),

            const SizedBox(height: 16),
            const SectionHeader(title: 'Test Settings'),
            const SizedBox(height: 8),

            // Settings Row
            Row(
              children: [
                Expanded(
                  child: _buildSettingField(
                    'Samples',
                    provider.samplesPerTarget.toString(),
                    Icons.repeat,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSettingField(
                    'Delay (s)',
                    provider.delayBetweenSamples.toString(),
                    Icons.timer,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Auto Contribute
            SwitchListTile(
              title: const Text('Auto Contribute'),
              subtitle: const Text(
                'Share results to improve network quality data',
              ),
              value: provider.autoContribute,
              onChanged: provider.setAutoContribute,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingField(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.secondaryDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.textSecondary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppTheme.textSecondary,
                ),
              ),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(TestProvider provider) {
    final isRunning = provider.status == TestStatus.running;

    return Column(
      children: [
        if (isRunning) ...[
          // Progress indicator
          LinearProgressIndicator(
            value: provider.progress,
            backgroundColor: AppTheme.secondaryDark,
            valueColor: const AlwaysStoppedAnimation<Color>(
              AppTheme.accentBlue,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Testing: ${provider.currentTarget} (${provider.currentSample}/${provider.samplesPerTarget})',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
        ],

        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            onPressed: isRunning
                ? provider.stopTest
                : provider.targetUrls.isNotEmpty
                ? provider.startTtfbTest
                : null,
            icon: Icon(isRunning ? Icons.stop : Icons.play_arrow),
            label: Text(isRunning ? 'Stop Test' : 'Run Test'),
            style: ElevatedButton.styleFrom(
              backgroundColor: isRunning
                  ? AppTheme.accentRed
                  : AppTheme.accentBlue,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultsSection(TestProvider provider) {
    final summaries = provider.getTtfbSummaries();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SectionHeader(title: 'Results'),
            TextButton(
              onPressed: provider.clearResults,
              child: const Text('Clear'),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (provider.status == TestStatus.completed ||
            provider.contributionSummary.submitted > 0 ||
            provider.contributionSummary.failed > 0) ...[
          _buildContributionStatusCard(provider),
          const SizedBox(height: 12),
        ],

        // Summary Cards
        ...summaries.map((summary) => _buildSummaryCard(summary)),

        const SizedBox(height: 16),

        // Chart
        if (provider.ttfbResults.length > 1) _buildChart(provider),
      ],
    );
  }

  Widget _buildSummaryCard(TtfbTestSummary summary) {
    final quality = summary.overallQuality;
    Color statusColor = AppTheme.textSecondary;
    switch (quality) {
      case ResultQuality.good:
        statusColor = AppTheme.statusGood;
        break;
      case ResultQuality.warning:
        statusColor = AppTheme.statusWarning;
        break;
      case ResultQuality.poor:
        statusColor = AppTheme.statusPoor;
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StatusIndicator(quality: quality),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    summary.url,
                    style: Theme.of(context).textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Avg',
                    '${summary.avgTtfb.toStringAsFixed(0)}ms',
                    statusColor,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Min',
                    '${summary.minTtfb.toStringAsFixed(0)}ms',
                    AppTheme.statusGood,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Max',
                    '${summary.maxTtfb.toStringAsFixed(0)}ms',
                    AppTheme.textSecondary,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'OK',
                    '${summary.successCount}/${summary.results.length}',
                    AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContributionStatusCard(TestProvider provider) {
    final summary = provider.contributionSummary;
    final hasFailures = summary.failed > 0;
    final hasSuccess = summary.submitted > 0;

    Color accentColor = AppTheme.textSecondary;
    String statusText = 'Contribution idle';

    if (hasFailures) {
      accentColor = AppTheme.statusWarning;
      statusText = 'Contribution issues detected';
    } else if (hasSuccess) {
      accentColor = AppTheme.statusGood;
      statusText = 'Contribution sent successfully';
    } else if (provider.autoContribute) {
      accentColor = AppTheme.accentBlue;
      statusText = 'Auto contribute enabled';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_upload, color: accentColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    statusText,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Submitted: ${summary.submitted} / ${summary.total}',
              style: const TextStyle(color: AppTheme.textPrimary),
            ),
            if (summary.failed > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Failed: ${summary.failed}',
                style: const TextStyle(color: AppTheme.statusWarning),
              ),
            ],
            if (summary.errors.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                summary.errors.last,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: provider.ttfbResults.isEmpty
                    ? null
                    : () => provider.contributeCurrentResults(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry Contribute'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
        ),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.bold, color: valueColor),
        ),
      ],
    );
  }

  Widget _buildChart(TestProvider provider) {
    final results = provider.ttfbResults.where((r) => r.error == null).toList();
    if (results.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TTFB Over Time',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 500,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: AppTheme.borderColor,
                        strokeWidth: 1,
                      );
                    },
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 50,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '${value.toInt()}ms',
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppTheme.textSecondary,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: results.asMap().entries.map((entry) {
                        return FlSpot(entry.key.toDouble(), entry.value.ttfbMs);
                      }).toList(),
                      isCurved: true,
                      color: AppTheme.accentBlue,
                      barWidth: 2,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppTheme.accentBlue.withOpacity(0.1),
                      ),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          return LineTooltipItem(
                            '${spot.y.toStringAsFixed(0)}ms',
                            const TextStyle(color: Colors.white),
                          );
                        }).toList();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
