import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/test_provider.dart';
import '../../../widgets/common_widgets.dart';

class DnsTestScreen extends StatefulWidget {
  const DnsTestScreen({super.key});

  @override
  State<DnsTestScreen> createState() => _DnsTestScreenState();
}

class _DnsTestScreenState extends State<DnsTestScreen> {
  final TextEditingController _domainController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _domainController.text = 'google.com';
  }

  @override
  void dispose() {
    _domainController.dispose();
    super.dispose();
  }

  Future<void> _runLookup(TestProvider provider) async {
    final domain = _domainController.text.trim();
    if (domain.isNotEmpty) {
      await provider.refreshNetworkInfo();
      await provider.dnsLookup(domain);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TestProvider>(
      builder: (context, provider, child) {
        final isPaused = provider.canResumeDns;
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
                      const SectionHeader(title: 'DNS Lookup'),
                      const SizedBox(height: 16),

                      TextField(
                        controller: _domainController,
                        decoration: const InputDecoration(
                          labelText: 'Domain or URL',
                          hintText: 'e.g., google.com or https://google.com',
                          prefixIcon: Icon(Icons.dns),
                        ),
                        onSubmitted: (_) {
                          _runLookup(provider);
                        },
                      ),

                      const SizedBox(height: 16),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: provider.status == TestStatus.running
                              ? null
                              : isPaused
                              ? provider.resumePausedTest
                              : () => _runLookup(provider),
                          icon: provider.status == TestStatus.running
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : isPaused
                              ? const Icon(Icons.play_circle_fill)
                              : const Icon(Icons.search),
                          label: Text(
                            provider.status == TestStatus.running
                                ? 'Looking up...'
                                : isPaused
                                ? 'Resume Lookup'
                                : 'Lookup',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Quick Lookups
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader(title: 'Quick Lookup'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children:
                            [
                              'google.com',
                              'cloudflare.com',
                              'facebook.com',
                              'amazon.com',
                            ].map((domain) {
                              return ActionChip(
                                label: Text(domain),
                                onPressed: () async {
                                  _domainController.text = domain;
                                  await _runLookup(provider);
                                },
                              );
                            }).toList(),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Results
              if (provider.dnsResults.isNotEmpty) ...[
                const SectionHeader(title: 'Results'),
                const SizedBox(height: 8),

                ...provider.dnsResults.map((result) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.accentBlue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  result.queryType,
                                  style: const TextStyle(
                                    color: AppTheme.accentBlue,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  result.domain,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                              Text(
                                '${result.responseTimeMs.toStringAsFixed(2)}ms',
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),

                          if (result.error != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTheme.accentRed.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.error_outline,
                                    color: AppTheme.accentRed,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      result.error!,
                                      style: const TextStyle(
                                        color: AppTheme.accentRed,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ] else if (result.answers.isEmpty) ...[
                            const SizedBox(height: 12),
                            const Text(
                              'No records found',
                              style: TextStyle(color: AppTheme.textSecondary),
                            ),
                          ] else ...[
                            const SizedBox(height: 12),
                            const Text(
                              'Answers:',
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...result.answers.map((answer) {
                              return Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 4),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.secondaryDark,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  answer,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    color: AppTheme.accentGreen,
                                  ),
                                ),
                              );
                            }),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
              ],

              // Empty State
              if (provider.dnsResults.isEmpty &&
                  provider.status == TestStatus.idle)
                const EmptyState(
                  icon: Icons.dns,
                  title: 'DNS Lookup',
                  subtitle:
                      'Enter a domain name to lookup its DNS records (A, AAAA)',
                ),
            ],
          ),
        );
      },
    );
  }
}
