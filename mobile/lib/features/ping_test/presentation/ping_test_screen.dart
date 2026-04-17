import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/test_provider.dart';
import '../../../widgets/common_widgets.dart';

class PingTestScreen extends StatefulWidget {
  const PingTestScreen({super.key});

  @override
  State<PingTestScreen> createState() => _PingTestScreenState();
}

class _PingTestScreenState extends State<PingTestScreen> {
  final TextEditingController _hostController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _hostController.text = '8.8.8.8';
  }

  @override
  void dispose() {
    _hostController.dispose();
    super.dispose();
  }

  void _startPing(TestProvider provider) {
    final host = _hostController.text.trim();
    if (host.isNotEmpty) {
      provider.startPingTest(host);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TestProvider>(
      builder: (context, provider, child) {
        final isRunning = provider.status == TestStatus.running;
        final summary = provider.getPingSummary();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Input Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader(title: 'Ping Test'),
                      const SizedBox(height: 16),

                      TextField(
                        controller: _hostController,
                        decoration: const InputDecoration(
                          labelText: 'Host or IP Address',
                          hintText: 'e.g., 8.8.8.8 or google.com',
                          prefixIcon: Icon(Icons.router),
                        ),
                        onSubmitted: (_) => _startPing(provider),
                        enabled: !isRunning,
                      ),

                      const SizedBox(height: 16),

                      // Quick Ping Targets
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildQuickTarget('8.8.8.8', 'Google DNS', provider),
                          _buildQuickTarget('1.1.1.1', 'Cloudflare', provider),
                          _buildQuickTarget(
                            '208.67.222.222',
                            'OpenDNS',
                            provider,
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Ping Count Setting
                      Row(
                        children: [
                          const Text('Ping Count: '),
                          const SizedBox(width: 8),
                          Text(
                            '${provider.pingCount}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: isRunning
                              ? provider.stopTest
                              : () => _startPing(provider),
                          icon: Icon(isRunning ? Icons.stop : Icons.play_arrow),
                          label: Text(isRunning ? 'Stop' : 'Start Ping'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isRunning
                                ? AppTheme.accentRed
                                : AppTheme.accentBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Live Results
              if (provider.pingResults.isNotEmpty) ...[
                // Summary Stats
                if (summary != null)
                  Row(
                    children: [
                      Expanded(
                        child: StatCard(
                          title: 'Avg Latency',
                          value: summary.avgLatency.toStringAsFixed(1),
                          unit: 'ms',
                          icon: Icons.speed,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: StatCard(
                          title: 'Packet Loss',
                          value: summary.packetLoss.toStringAsFixed(1),
                          unit: '%',
                          valueColor: summary.packetLoss > 0
                              ? AppTheme.accentRed
                              : AppTheme.accentGreen,
                          icon: Icons.error_outline,
                        ),
                      ),
                    ],
                  ),

                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: StatCard(
                        title: 'Min',
                        value: summary?.minLatency.toStringAsFixed(1) ?? '0',
                        unit: 'ms',
                        icon: Icons.arrow_downward,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: StatCard(
                        title: 'Max',
                        value: summary?.maxLatency.toStringAsFixed(1) ?? '0',
                        unit: 'ms',
                        icon: Icons.arrow_upward,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: StatCard(
                        title: 'Received',
                        value:
                            '${summary?.received ?? 0}/${summary?.sent ?? 0}',
                        icon: Icons.check_circle,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Chart
                if (provider.pingResults.length > 1)
                  _buildLatencyChart(provider),

                const SizedBox(height: 16),

                // Result List
                const SectionHeader(title: 'Ping Results'),
                const SizedBox(height: 8),

                Card(
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: provider.pingResults.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final result = provider.pingResults[index];
                      final hasError = result.error != null;

                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: hasError
                              ? AppTheme.accentRed.withOpacity(0.1)
                              : AppTheme.accentGreen.withOpacity(0.1),
                          child: Text(
                            '${result.sequenceNumber}',
                            style: TextStyle(
                              fontSize: 12,
                              color: hasError
                                  ? AppTheme.accentRed
                                  : AppTheme.accentGreen,
                            ),
                          ),
                        ),
                        title: Text(
                          hasError
                              ? 'Request timed out'
                              : '${result.latencyMs.toStringAsFixed(2)} ms',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: hasError
                                ? AppTheme.accentRed
                                : AppTheme.textPrimary,
                          ),
                        ),
                        trailing: hasError
                            ? const Icon(
                                Icons.close,
                                color: AppTheme.accentRed,
                                size: 16,
                              )
                            : Text(
                                'TTL: ${result.ttl}',
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                      );
                    },
                  ),
                ),
              ],

              // Empty State
              if (provider.pingResults.isEmpty && !isRunning)
                const EmptyState(
                  icon: Icons.network_ping,
                  title: 'Ping Test',
                  subtitle:
                      'Enter a host or IP address to measure network latency',
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickTarget(String ip, String label, TestProvider provider) {
    return ActionChip(
      avatar: const Icon(Icons.dns, size: 16),
      label: Text(label),
      onPressed: provider.status == TestStatus.running
          ? null
          : () {
              _hostController.text = ip;
              _startPing(provider);
            },
    );
  }

  Widget _buildLatencyChart(TestProvider provider) {
    final results = provider.pingResults.where((r) => r.error == null).toList();
    if (results.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Latency Over Time',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 150,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 50,
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
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '${value.toInt()}',
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
                        return FlSpot(
                          entry.key.toDouble(),
                          entry.value.latencyMs,
                        );
                      }).toList(),
                      isCurved: false,
                      color: AppTheme.accentGreen,
                      barWidth: 2,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) {
                          return FlDotCirclePainter(
                            radius: 3,
                            color: AppTheme.accentGreen,
                            strokeWidth: 0,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
