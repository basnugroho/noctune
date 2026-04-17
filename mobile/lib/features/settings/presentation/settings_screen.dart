import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/test_provider.dart';
import '../../../widgets/common_widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double? _draftSamplesPerTarget;
  double? _draftDelayBetweenSamples;
  double? _draftPingDuration;
  String _draftBrand = '';
  String _draftNoInternetNumber = '';
  bool _hasUnsavedChanges = false;
  String? _syncedSignature;
  final TextEditingController _brandController = TextEditingController();
  final TextEditingController _noInternetController = TextEditingController();

  @override
  void dispose() {
    _brandController.dispose();
    _noInternetController.dispose();
    super.dispose();
  }

  String _buildSignature({
    required int samplesPerTarget,
    required int delayBetweenSamples,
    required int pingCount,
    required String brand,
    required String noInternetNumber,
  }) {
    return '$samplesPerTarget|$delayBetweenSamples|$pingCount|$brand|$noInternetNumber';
  }

  void _syncDraftFromProvider(TestProvider provider) {
    final nextSignature = _buildSignature(
      samplesPerTarget: provider.samplesPerTarget,
      delayBetweenSamples: provider.delayBetweenSamples,
      pingCount: provider.pingCount,
      brand: provider.brand,
      noInternetNumber: provider.noInternetNumber,
    );

    if (_hasUnsavedChanges && _draftSamplesPerTarget != null) {
      return;
    }

    if (_syncedSignature == nextSignature && _draftSamplesPerTarget != null) {
      return;
    }

    _draftSamplesPerTarget = provider.samplesPerTarget.toDouble();
    _draftDelayBetweenSamples = provider.delayBetweenSamples.toDouble();
    _draftPingDuration = provider.pingCount.toDouble();
    _draftBrand = provider.brand;
    if (_brandController.text != _draftBrand) {
      _brandController.text = _draftBrand;
    }
    _draftNoInternetNumber = provider.noInternetNumber;
    if (_noInternetController.text != _draftNoInternetNumber) {
      _noInternetController.text = _draftNoInternetNumber;
    }
    _syncedSignature = nextSignature;
    _hasUnsavedChanges = false;
  }

  void _markDirty({
    double? samplesPerTarget,
    double? delayBetweenSamples,
    double? pingDuration,
    String? brand,
    String? noInternetNumber,
  }) {
    setState(() {
      _draftSamplesPerTarget = samplesPerTarget ?? _draftSamplesPerTarget;
      _draftDelayBetweenSamples =
          delayBetweenSamples ?? _draftDelayBetweenSamples;
      _draftPingDuration = pingDuration ?? _draftPingDuration;
      _draftBrand = brand ?? _draftBrand;
      _draftNoInternetNumber = noInternetNumber ?? _draftNoInternetNumber;
      _hasUnsavedChanges = true;
    });
  }

  void _reloadDraftFromProvider(TestProvider provider) {
    setState(() {
      _draftSamplesPerTarget = provider.samplesPerTarget.toDouble();
      _draftDelayBetweenSamples = provider.delayBetweenSamples.toDouble();
      _draftPingDuration = provider.pingCount.toDouble();
      _syncedSignature = _buildSignature(
        samplesPerTarget: provider.samplesPerTarget,
        delayBetweenSamples: provider.delayBetweenSamples,
        pingCount: provider.pingCount,
        brand: provider.brand,
        noInternetNumber: provider.noInternetNumber,
      );
      _draftBrand = provider.brand;
      _brandController.text = _draftBrand;
      _draftNoInternetNumber = provider.noInternetNumber;
      _noInternetController.text = _draftNoInternetNumber;
      _hasUnsavedChanges = false;
    });
  }

  void _loadDefaultsToDraft() {
    setState(() {
      _draftSamplesPerTarget = AppConstants.defaultSamplesPerTarget.toDouble();
      _draftDelayBetweenSamples = AppConstants.defaultDelayBetweenSamples
          .toDouble();
      _draftPingDuration = AppConstants.defaultPingDuration.toDouble();
      _draftBrand = '';
      _brandController.text = '';
      _draftNoInternetNumber = '';
      _noInternetController.text = '';
      _hasUnsavedChanges = true;
    });
  }

  Future<void> _saveDraft(TestProvider provider) async {
    final samples = (_draftSamplesPerTarget ?? provider.samplesPerTarget)
        .toInt();
    final delay = (_draftDelayBetweenSamples ?? provider.delayBetweenSamples)
        .toInt();
    final pingDuration = (_draftPingDuration ?? provider.pingCount).toInt();
    final brand = _brandController.text.trim();
    final noInternetNumber = _noInternetController.text.trim();

    await provider.saveSettings(
      samplesPerTarget: samples,
      delayBetweenSamples: delay,
      pingCount: pingDuration,
      brand: brand,
      noInternetNumber: noInternetNumber,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _syncedSignature = _buildSignature(
        samplesPerTarget: samples,
        delayBetweenSamples: delay,
        pingCount: pingDuration,
        brand: brand,
        noInternetNumber: noInternetNumber,
      );
      _draftBrand = brand;
      _draftNoInternetNumber = noInternetNumber;
      _hasUnsavedChanges = false;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Test settings saved')));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TestProvider>(
      builder: (context, provider, child) {
        _syncDraftFromProvider(provider);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // App Info
              _buildAppInfoCard(context),
              const SizedBox(height: 16),

              // Test Settings
              _buildTestSettingsCard(context, provider),
              const SizedBox(height: 16),

              // Thresholds
              _buildThresholdsCard(context),
              const SizedBox(height: 16),

              // Network Defaults
              _buildNetworkDefaultsCard(context),
              const SizedBox(height: 16),

              // Data & Privacy
              _buildDataPrivacyCard(context, provider),
              const SizedBox(height: 16),

              // About
              _buildAboutCard(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAppInfoCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppTheme.accentBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.speed,
                size: 32,
                color: AppTheme.accentBlue,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppConstants.appName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Version ${AppConstants.appVersion}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    'Released: ${AppConstants.releaseDate}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTestSettingsCard(BuildContext context, TestProvider provider) {
    final samplesValue =
        _draftSamplesPerTarget ?? provider.samplesPerTarget.toDouble();
    final delayValue =
        _draftDelayBetweenSamples ?? provider.delayBetweenSamples.toDouble();
    final pingDurationValue =
        _draftPingDuration ?? provider.pingCount.toDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(title: 'Test Settings'),
            const SizedBox(height: 16),

            _buildSliderSetting(
              context: context,
              title: 'Samples per Target',
              value: samplesValue,
              min: 1,
              max: 30,
              divisions: 29,
              unit: 'samples',
              onChanged: (value) {
                _markDirty(samplesPerTarget: value);
              },
            ),

            const SizedBox(height: 16),

            _buildSliderSetting(
              context: context,
              title: 'Delay Between Samples',
              value: delayValue,
              min: 1,
              max: 30,
              divisions: 29,
              unit: 'seconds',
              onChanged: (value) {
                _markDirty(delayBetweenSamples: value);
              },
            ),

            const SizedBox(height: 16),

            _buildSliderSetting(
              context: context,
              title: 'Ping Duration',
              value: pingDurationValue,
              min: 10,
              max: 120,
              divisions: 11,
              unit: 'seconds',
              onChanged: (value) {
                _markDirty(pingDuration: value);
              },
            ),

            const SizedBox(height: 16),

            TextField(
              controller: _brandController,
              decoration: const InputDecoration(
                labelText: 'Brand / ISP',
                hintText: 'e.g. indihome, telkomsel, biznet',
                helperText: 'Opsional. Dipakai untuk kolom brand di QoSMic.',
                prefixIcon: Icon(Icons.business_outlined),
              ),
              onChanged: (value) {
                _markDirty(brand: value);
              },
            ),

            const SizedBox(height: 16),

            TextField(
              controller: _noInternetController,
              decoration: const InputDecoration(
                labelText: 'No Internet Number',
                hintText: 'Optional manual value',
                helperText:
                    'Kosongkan jika tidak ingin mengirim nilai no_internet.',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              onChanged: (value) {
                _markDirty(noInternetNumber: value);
              },
            ),

            const SizedBox(height: 12),

            Text(
              _hasUnsavedChanges
                  ? 'You have unsaved changes.'
                  : 'Saved values are active for the next test run.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _hasUnsavedChanges
                    ? AppTheme.statusWarning
                    : AppTheme.textSecondary,
              ),
            ),

            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _hasUnsavedChanges
                        ? () => _saveDraft(provider)
                        : null,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      _reloadDraftFromProvider(provider);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Reloaded saved test settings'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reload'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _loadDefaultsToDraft,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Default'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliderSetting({
    required BuildContext context,
    required String title,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String unit,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title),
            Text(
              '${value.toInt()} $unit',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppTheme.accentBlue,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildThresholdsCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(title: 'TTFB Thresholds'),
            const SizedBox(height: 16),

            _buildThresholdRow(
              context: context,
              label: 'Good',
              value: '≤ ${AppConstants.goodTtfbThreshold}ms',
              color: AppTheme.statusGood,
            ),
            const SizedBox(height: 12),
            _buildThresholdRow(
              context: context,
              label: 'Warning',
              value:
                  '${AppConstants.goodTtfbThreshold + 1} - ${AppConstants.warningTtfbThreshold}ms',
              color: AppTheme.statusWarning,
            ),
            const SizedBox(height: 12),
            _buildThresholdRow(
              context: context,
              label: 'Poor',
              value: '> ${AppConstants.warningTtfbThreshold}ms',
              color: AppTheme.statusPoor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkDefaultsCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(title: 'Network Defaults'),
            const SizedBox(height: 8),
            _buildThresholdRow(
              context: context,
              label: 'Signal Threshold',
              value: '${AppConstants.defaultSignalThreshold} dBm',
              color: AppTheme.accentBlue,
            ),
            const SizedBox(height: 12),
            _buildThresholdRow(
              context: context,
              label: 'Custom DNS',
              value: AppConstants.defaultDnsServers.join(', '),
              color: AppTheme.textPrimary,
            ),
            const SizedBox(height: 12),
            Text(
              'DNS override default servers are prepared to match the web configuration.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThresholdRow({
    required BuildContext context,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Text(label),
        const Spacer(),
        Text(
          value,
          style: TextStyle(color: color, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildDataPrivacyCard(BuildContext context, TestProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(title: 'Data & Privacy'),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto Contribute'),
              subtitle: const Text(
                'Share anonymous test results to improve network quality data',
              ),
              value: provider.autoContribute,
              onChanged: provider.setAutoContribute,
            ),

            const Divider(),

            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.delete_outline,
                color: AppTheme.accentRed,
              ),
              title: const Text('Clear Test History'),
              subtitle: const Text('Delete all saved test results'),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Clear History?'),
                    content: const Text(
                      'This will delete all saved test results. This action cannot be undone.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () {
                          // Clear history
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('History cleared')),
                          );
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.accentRed,
                        ),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(title: 'About'),

            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.code),
              title: const Text('Source Code'),
              subtitle: const Text('View on GitHub'),
              trailing: const Icon(Icons.open_in_new, size: 16),
              onTap: () async {
                final uri = Uri.parse('https://github.com/basnugroho/noctune');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),

            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.bug_report),
              title: const Text('Report Issue'),
              subtitle: const Text('Found a bug? Let us know'),
              trailing: const Icon(Icons.open_in_new, size: 16),
              onTap: () async {
                final uri = Uri.parse(
                  'https://github.com/basnugroho/noctune/issues',
                );
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),

            const Divider(),

            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: Text(
                  'Made with ❤️ by @basnugroho',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textSecondary,
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
