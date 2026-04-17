import 'dart:async';
import 'package:flutter/material.dart';
import '../core/constants/app_constants.dart';
import '../models/test_models.dart';
import '../services/ttfb_service.dart';
import '../services/ping_service.dart';
import '../services/dns_service.dart';
import '../services/contribution_service.dart';
import '../services/network_info_service.dart';
import '../services/storage_service.dart';

class TestProvider extends ChangeNotifier {
  final TtfbService _ttfbService = TtfbService();
  final PingService _pingService = PingService();
  final DnsService _dnsService = DnsService();
  final ContributionService _contributionService = ContributionService();
  final NetworkInfoService _networkInfoService = NetworkInfoService();
  final StorageService _storageService = StorageService();

  // State
  TestStatus _status = TestStatus.idle;
  List<String> _targetUrls = [];
  List<TtfbResult> _ttfbResults = [];
  List<PingResult> _pingResults = [];
  List<DnsResult> _dnsResults = [];
  AppNetworkInfo? _networkInfo;
  String _currentTarget = '';
  int _currentSample = 0;
  int _totalSamples = 0;
  String? _errorMessage;
  bool _autoContribute = false;
  String? _sessionId;
  DateTime? _testStartTime;
  ContributionSummary _contributionSummary = const ContributionSummary.empty();
  final Set<String> _submittedContributionKeys = <String>{};
  bool _isInitializing = true;
  double _initializationProgress = 0;
  String _initializationMessage = 'Preparing app...';
  final List<String> _startupLogs = <String>[];

  // Settings
  int _samplesPerTarget = AppConstants.defaultSamplesPerTarget;
  int _delayBetweenSamples = AppConstants.defaultDelayBetweenSamples;
  int _pingCount = AppConstants.defaultPingCount;
  String _brand = '';
  String _noInternetNumber = '';

  StreamSubscription? _testSubscription;
  Future<void> _contributionQueue = Future.value();

  // Getters
  TestStatus get status => _status;
  List<String> get targetUrls => _targetUrls;
  List<TtfbResult> get ttfbResults => _ttfbResults;
  List<PingResult> get pingResults => _pingResults;
  List<DnsResult> get dnsResults => _dnsResults;
  AppNetworkInfo? get networkInfo => _networkInfo;
  String get currentTarget => _currentTarget;
  int get currentSample => _currentSample;
  int get totalSamples => _totalSamples;
  String? get errorMessage => _errorMessage;
  bool get autoContribute => _autoContribute;
  int get samplesPerTarget => _samplesPerTarget;
  int get delayBetweenSamples => _delayBetweenSamples;
  int get pingCount => _pingCount;
  String get brand => _brand;
  String get noInternetNumber => _noInternetNumber;
  ContributionSummary get contributionSummary => _contributionSummary;
  bool get isInitializing => _isInitializing;
  double get initializationProgress => _initializationProgress;
  String get initializationMessage => _initializationMessage;
  List<String> get startupLogs => List.unmodifiable(_startupLogs);

  double get progress {
    if (_totalSamples == 0) return 0;
    return _ttfbResults.length / _totalSamples;
  }

  // Initialize
  Future<void> init() async {
    _setInitializationState(0.08, 'Opening local storage...');
    await _storageService.init();

    _setInitializationState(0.22, 'Loading saved targets...');
    _targetUrls = await _storageService.getTargets();
    if (_targetUrls.isEmpty || _matchesLegacyTargets(_targetUrls)) {
      _targetUrls = List<String>.from(AppConstants.defaultTargets);
      await _storageService.saveTargets(_targetUrls);
      _addStartupLog('Default targets restored');
    } else {
      _addStartupLog('Loaded ${_targetUrls.length} target(s)');
    }

    _setInitializationState(0.42, 'Loading contribution preferences...');
    if (_storageService.hasAutoContributePreference()) {
      _autoContribute = await _storageService.getAutoContribute();
    } else {
      _autoContribute = AppConstants.defaultAutoContribute;
      await _storageService.setAutoContribute(_autoContribute);
    }
    _addStartupLog(
      'Auto contribute ${_autoContribute ? 'enabled' : 'disabled'}',
    );

    _setInitializationState(0.62, 'Applying test settings...');
    final settings = await _storageService.getSettings();
    _applySettings(settings);

    if (_shouldMigrateLegacySettings(settings)) {
      _applyDefaultSettings();
      await _storageService.saveSettings(_buildSettingsPayload());
      _addStartupLog('Legacy settings migrated to defaults');
    } else {
      _addStartupLog('Settings loaded');
    }

    _setInitializationState(0.84, 'Detecting network and device info...');
    _networkInfo = await _networkInfoService.getNetworkInfo();
    _addStartupLog('Network: ${_networkInfo?.connectionType ?? 'Unknown'}');

    _setInitializationState(1, 'Ready');
    _isInitializing = false;
    notifyListeners();
  }

  void _setInitializationState(double progress, String message) {
    _initializationProgress = progress.clamp(0, 1);
    _initializationMessage = message;
    _addStartupLog(message);
    notifyListeners();
  }

  void _addStartupLog(String message) {
    if (_startupLogs.isNotEmpty && _startupLogs.last == message) {
      return;
    }
    _startupLogs.add(message);
    if (_startupLogs.length > 5) {
      _startupLogs.removeAt(0);
    }
  }

  // Target URL management
  Future<void> addTarget(String url) async {
    if (!_targetUrls.contains(url)) {
      _targetUrls.add(url);
      await _storageService.saveTargets(_targetUrls);
      notifyListeners();
    }
  }

  Future<void> removeTarget(String url) async {
    _targetUrls.remove(url);
    await _storageService.saveTargets(_targetUrls);
    notifyListeners();
  }

  // Settings
  Future<void> updateSettings({
    int? samplesPerTarget,
    int? delayBetweenSamples,
    int? pingCount,
    String? brand,
    String? noInternetNumber,
  }) async {
    await saveSettings(
      samplesPerTarget: samplesPerTarget ?? _samplesPerTarget,
      delayBetweenSamples: delayBetweenSamples ?? _delayBetweenSamples,
      pingCount: pingCount ?? _pingCount,
      brand: brand ?? _brand,
      noInternetNumber: noInternetNumber ?? _noInternetNumber,
    );
  }

  Future<void> saveSettings({
    required int samplesPerTarget,
    required int delayBetweenSamples,
    required int pingCount,
    required String brand,
    required String noInternetNumber,
  }) async {
    _samplesPerTarget = samplesPerTarget;
    _delayBetweenSamples = delayBetweenSamples;
    _pingCount = pingCount;
    _brand = brand.trim();
    _noInternetNumber = noInternetNumber.trim();

    await _storageService.saveSettings(_buildSettingsPayload());
    notifyListeners();
  }

  Future<void> reloadSavedSettings() async {
    final settings = await _storageService.getSettings();
    _applySettings(settings);
    notifyListeners();
  }

  Future<void> resetSettingsToDefaults() async {
    _applyDefaultSettings();
    await _storageService.saveSettings(_buildSettingsPayload());
    notifyListeners();
  }

  void _applySettings(Map<String, dynamic> settings) {
    _samplesPerTarget =
        settings['samples_per_target'] ?? AppConstants.defaultSamplesPerTarget;
    _delayBetweenSamples =
        settings['delay_between_samples'] ??
        AppConstants.defaultDelayBetweenSamples;
    _pingCount =
        settings['ping_count'] ??
        settings['ping_duration_seconds'] ??
        AppConstants.defaultPingCount;
    _brand = settings['brand']?.toString() ?? '';
    _noInternetNumber = settings['no_internet_number']?.toString() ?? '';
  }

  void _applyDefaultSettings() {
    _samplesPerTarget = AppConstants.defaultSamplesPerTarget;
    _delayBetweenSamples = AppConstants.defaultDelayBetweenSamples;
    _pingCount = AppConstants.defaultPingCount;
    _brand = '';
    _noInternetNumber = '';
  }

  Map<String, dynamic> _buildSettingsPayload() {
    return {
      'samples_per_target': _samplesPerTarget,
      'delay_between_samples': _delayBetweenSamples,
      'ping_count': _pingCount,
      'ping_duration_seconds': _pingCount,
      'good_ttfb_threshold': AppConstants.goodTtfbThreshold,
      'warning_ttfb_threshold': AppConstants.warningTtfbThreshold,
      'signal_threshold': AppConstants.defaultSignalThreshold,
      'dns_override_enabled': false,
      'custom_dns_servers': AppConstants.defaultDnsServers.join(', '),
      'brand': _brand,
      'no_internet_number': _noInternetNumber,
    };
  }

  bool _matchesLegacyTargets(List<String> targets) {
    if (targets.length != AppConstants.legacyDefaultTargets.length) {
      return false;
    }

    for (int index = 0; index < targets.length; index++) {
      if (targets[index] != AppConstants.legacyDefaultTargets[index]) {
        return false;
      }
    }

    return true;
  }

  bool _shouldMigrateLegacySettings(Map<String, dynamic> settings) {
    final delay = settings['delay_between_samples'];
    final pingCount =
        settings['ping_count'] ?? settings['ping_duration_seconds'];
    final warning = settings['warning_ttfb_threshold'];

    return delay == AppConstants.legacyDefaultDelayBetweenSamples &&
        pingCount == AppConstants.legacyDefaultPingCount &&
        warning == AppConstants.legacyWarningTtfbThreshold;
  }

  Future<void> setAutoContribute(bool value) async {
    _autoContribute = value;
    await _storageService.setAutoContribute(value);
    notifyListeners();
  }

  // TTFB Test
  Future<void> startTtfbTest() async {
    if (_targetUrls.isEmpty) {
      _errorMessage = 'Please add at least one target URL';
      notifyListeners();
      return;
    }

    _status = TestStatus.running;
    _ttfbResults = [];
    _errorMessage = null;
    _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    _testStartTime = DateTime.now();
    _contributionSummary = ContributionSummary(
      submitted: 0,
      failed: 0,
      total: _targetUrls.length * _samplesPerTarget,
      errors: const [],
    );
    _submittedContributionKeys.clear();
    _contributionQueue = Future.value();
    _totalSamples = _targetUrls.length * _samplesPerTarget;
    _currentSample = 0;

    _networkInfo = await _networkInfoService.getNetworkInfo(
      requestPermissions: true,
    );
    notifyListeners();

    _testSubscription = _ttfbService
        .runMultiTargetTest(
          urls: _targetUrls,
          samplesPerTarget: _samplesPerTarget,
          delayBetweenSamples: Duration(seconds: _delayBetweenSamples),
        )
        .listen(
          (result) {
            _ttfbResults.add(result);
            _currentTarget = result.url;
            _currentSample = result.sampleNumber;
            if (_autoContribute) {
              _queueContributionForResult(result);
            }
            notifyListeners();
          },
          onError: (error) {
            _errorMessage = error.toString();
            _status = TestStatus.error;
            notifyListeners();
          },
          onDone: () {
            _status = TestStatus.completed;
            _saveResults();
            notifyListeners();
          },
        );
  }

  void stopTest() {
    _testSubscription?.cancel();
    _status = TestStatus.idle;
    notifyListeners();
  }

  // Ping Test
  Future<void> startPingTest(String host) async {
    _status = TestStatus.running;
    _pingResults = [];
    _errorMessage = null;
    _currentTarget = host;
    notifyListeners();

    _testSubscription = _pingService
        .ping(host: host, count: _pingCount)
        .listen(
          (result) {
            _pingResults.add(result);
            notifyListeners();
          },
          onError: (error) {
            _errorMessage = error.toString();
            _status = TestStatus.error;
            notifyListeners();
          },
          onDone: () {
            _status = TestStatus.completed;
            notifyListeners();
          },
        );
  }

  // DNS Lookup
  Future<void> dnsLookup(String domain) async {
    _status = TestStatus.running;
    _dnsResults = [];
    _errorMessage = null;
    notifyListeners();

    try {
      final results = await _dnsService.getAllRecords(domain);
      _dnsResults = results;
      _status = TestStatus.completed;
    } catch (e) {
      _errorMessage = e.toString();
      _status = TestStatus.error;
    }
    notifyListeners();
  }

  // Refresh network info
  Future<void> refreshNetworkInfo() async {
    _networkInfo = await _networkInfoService.getNetworkInfo(
      requestPermissions: true,
    );
    notifyListeners();
  }

  // Save results to history
  Future<void> _saveResults() async {
    if (_ttfbResults.isEmpty) return;

    final Map<String, List<TtfbResult>> groupedResults = {};
    for (final result in _ttfbResults) {
      groupedResults.putIfAbsent(result.url, () => []);
      groupedResults[result.url]!.add(result);
    }

    await _storageService.addToHistory({
      'session_id': _sessionId,
      'timestamp': DateTime.now().toIso8601String(),
      'contribution': {
        'submitted': _contributionSummary.submitted,
        'failed': _contributionSummary.failed,
        'total': _contributionSummary.total,
        'errors': _contributionSummary.errors,
      },
      'network_info': {
        'brand': _brand,
        'device_model': _networkInfo?.deviceModel,
        'battery_level': _networkInfo?.batteryLevel,
        'battery_charging': _networkInfo?.batteryCharging,
        'wifi_rssi': _networkInfo?.wifiRssi,
        'wifi_band': _networkInfo?.wifiBand,
        'wifi_channel': _networkInfo?.wifiChannel,
        'dns_primary': _networkInfo?.dnsPrimary,
        'dns_servers': _networkInfo?.dnsServers,
        'ssid': _networkInfo?.ssid,
        'public_ip': _networkInfo?.publicIp,
        'isp': _networkInfo?.isp,
        'connectivity_type': _networkInfo?.connectionType,
        'connection_type': _networkInfo?.connectionType,
        'ip_address': _networkInfo?.ipAddress,
        'location': {
          'city': _networkInfo?.location?.city,
          'region': _networkInfo?.location?.region,
          'country': _networkInfo?.location?.country,
          'lat': _networkInfo?.location?.latitude,
          'lon': _networkInfo?.location?.longitude,
          'accuracy': _networkInfo?.location?.accuracy,
        },
      },
      'results': groupedResults.entries.map((entry) {
        final results = entry.value;
        final validResults = results.where((r) => r.error == null);
        return {
          'url': entry.key,
          'samples': results.length,
          'avg_ttfb': validResults.isNotEmpty
              ? validResults.map((r) => r.ttfbMs).reduce((a, b) => a + b) /
                    validResults.length
              : 0,
          'lookup_ms_avg': validResults
              .where((r) => r.lookupMs != null)
              .map((r) => r.lookupMs!)
              .fold<double>(0, (sum, value) => sum + value),
          'min_ttfb': validResults.isNotEmpty
              ? validResults
                    .map((r) => r.ttfbMs)
                    .reduce((a, b) => a < b ? a : b)
              : 0,
          'max_ttfb': validResults.isNotEmpty
              ? validResults
                    .map((r) => r.ttfbMs)
                    .reduce((a, b) => a > b ? a : b)
              : 0,
          'errors': results.where((r) => r.error != null).length,
        };
      }).toList(),
    });
  }

  Future<void> _submitContributionForResult(TtfbResult result) async {
    final testStartTime = _testStartTime;
    final sessionId = _sessionId;
    if (testStartTime == null || sessionId == null) {
      return;
    }

    final contributionKey = _buildContributionKey(
      sessionId: sessionId,
      result: result,
    );
    if (_submittedContributionKeys.contains(contributionKey)) {
      return;
    }

    final row = _contributionService.buildContributionRow(
      result: result,
      sessionId: sessionId,
      testStartTime: testStartTime,
      testEndTime: DateTime.now(),
      allResults: _ttfbResults.where((item) => item.url == result.url).toList(),
      networkInfo: _networkInfo,
      brand: _brand,
      noInternetNumber: _noInternetNumber,
      sampleCount: _samplesPerTarget,
      delaySeconds: _delayBetweenSamples,
    );

    try {
      final contributionResult = await _contributionService.submitRow(row: row);
      final errors = List<String>.from(_contributionSummary.errors);

      if (contributionResult.success) {
        _submittedContributionKeys.add(contributionKey);
        _contributionSummary = ContributionSummary(
          submitted: _contributionSummary.submitted + 1,
          failed: _contributionSummary.failed,
          total: _contributionSummary.total,
          errors: errors,
        );
      } else {
        if (contributionResult.error != null &&
            contributionResult.error!.isNotEmpty) {
          errors.add(contributionResult.error!);
        }
        _contributionSummary = ContributionSummary(
          submitted: _contributionSummary.submitted,
          failed: _contributionSummary.failed + 1,
          total: _contributionSummary.total,
          errors: errors,
        );
      }
    } catch (error) {
      final errors = List<String>.from(_contributionSummary.errors)
        ..add(error.toString());
      _contributionSummary = ContributionSummary(
        submitted: _contributionSummary.submitted,
        failed: _contributionSummary.failed + 1,
        total: _contributionSummary.total,
        errors: errors,
      );
    }

    notifyListeners();
  }

  Future<void> _queueContributionForResult(TtfbResult result) {
    _contributionQueue = _contributionQueue.then((_) {
      return _submitContributionForResult(result);
    });
    return _contributionQueue;
  }

  Future<void> contributeCurrentResults() async {
    if (_ttfbResults.isEmpty) {
      return;
    }

    await _contributionQueue;

    _sessionId ??= DateTime.now().millisecondsSinceEpoch.toString();
    _testStartTime ??= _ttfbResults.first.timestamp;

    final pendingResults = _ttfbResults.where((result) {
      final contributionKey = _buildContributionKey(
        sessionId: _sessionId!,
        result: result,
      );
      return !_submittedContributionKeys.contains(contributionKey);
    }).toList();

    if (pendingResults.isEmpty) {
      notifyListeners();
      return;
    }

    _contributionSummary = ContributionSummary(
      submitted: 0,
      failed: 0,
      total: pendingResults.length,
      errors: const [],
    );
    notifyListeners();

    for (final result in pendingResults) {
      await _submitContributionForResult(result);
    }
  }

  String _buildContributionKey({
    required String sessionId,
    required TtfbResult result,
  }) {
    return '$sessionId|${result.url}|${result.sampleNumber}|${result.timestamp.toIso8601String()}';
  }

  // Get summaries for display
  List<TtfbTestSummary> getTtfbSummaries() {
    final Map<String, List<TtfbResult>> groupedResults = {};
    for (final result in _ttfbResults) {
      groupedResults.putIfAbsent(result.url, () => []);
      groupedResults[result.url]!.add(result);
    }

    return groupedResults.entries.map((entry) {
      return TtfbTestSummary(
        url: entry.key,
        results: entry.value,
        startTime: entry.value.first.timestamp,
        endTime: entry.value.last.timestamp,
      );
    }).toList();
  }

  PingTestSummary? getPingSummary() {
    if (_pingResults.isEmpty) return null;
    return PingTestSummary(
      host: _currentTarget,
      results: _pingResults,
      startTime: _pingResults.first.timestamp,
      endTime: _pingResults.last.timestamp,
    );
  }

  void clearResults() {
    _ttfbResults = [];
    _pingResults = [];
    _dnsResults = [];
    _submittedContributionKeys.clear();
    _status = TestStatus.idle;
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _testSubscription?.cancel();
    _ttfbService.dispose();
    _contributionService.dispose();
    _networkInfoService.dispose();
    super.dispose();
  }
}
