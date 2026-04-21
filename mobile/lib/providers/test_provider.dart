import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../models/test_models.dart';
import '../services/contribution_service.dart';
import '../services/dns_service.dart';
import '../services/network_info_service.dart';
import '../services/ping_service.dart';
import '../services/runtime_support_service.dart';
import '../services/storage_service.dart';
import '../services/ttfb_service.dart';

enum _TestRunKind { ttfb, ping, dns }

class TestProvider extends ChangeNotifier {
  static const List<String> iosWifiBandOptions = <String>['2.4GHz', '5GHz'];

  final TtfbService _ttfbService = TtfbService();
  final PingService _pingService = PingService();
  final DnsService _dnsService = DnsService();
  final ContributionService _contributionService = ContributionService();
  final NetworkInfoService _networkInfoService = NetworkInfoService();
  final StorageService _storageService = StorageService();
  final RuntimeSupportService _runtimeSupportService = RuntimeSupportService();

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
  bool _dailyReminderEnabled = AppConstants.defaultDailyReminderEnabled;
  String? _sessionId;
  DateTime? _testStartTime;
  ContributionSummary _contributionSummary = const ContributionSummary.empty();
  final Set<String> _submittedContributionKeys = <String>{};
  bool _isInitializing = true;
  double _initializationProgress = 0;
  String _initializationMessage = 'Preparing app...';
  final List<String> _startupLogs = <String>[];

  int _samplesPerTarget = AppConstants.defaultSamplesPerTarget;
  int _delayBetweenSamples = AppConstants.defaultDelayBetweenSamples;
  int _pingCount = AppConstants.defaultPingCount;
  String _brand = '';
  String _noInternetNumber = '';
  bool _dnsOverrideEnabled = true;
  List<String> _customDnsServers = List<String>.from(
    AppConstants.defaultDnsServers,
  );

  StreamSubscription? _testSubscription;
  Future<void> _contributionQueue = Future.value();
  _TestRunKind? _activeTestKind;
  String? _activeTestLabel;
  String? _pauseMessage;
  String? _manualWifiBandOverride;
  String? _manualWifiBandSsid;

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
  bool get dailyReminderEnabled => _dailyReminderEnabled;
  int get samplesPerTarget => _samplesPerTarget;
  int get delayBetweenSamples => _delayBetweenSamples;
  int get pingCount => _pingCount;
  String get brand => _brand;
  String get noInternetNumber => _noInternetNumber;
  bool get dnsOverrideEnabled => _dnsOverrideEnabled;
  List<String> get customDnsServers => _customDnsServers;
  ContributionSummary get contributionSummary => _contributionSummary;
  bool get isInitializing => _isInitializing;
  double get initializationProgress => _initializationProgress;
  String get initializationMessage => _initializationMessage;
  List<String> get startupLogs => List.unmodifiable(_startupLogs);
  bool get hasPausedTest =>
      _status == TestStatus.paused && _activeTestKind != null;
  String? get pauseMessage => _pauseMessage;
  bool get showKeepAppOpenNotice =>
      _status == TestStatus.running || hasPausedTest;
  String get keepAppOpenNotice {
    if (hasPausedTest) {
      return _pauseMessage ??
          'Tes dipause karena app keluar ke background. Masuk lagi dan tekan Resume untuk melanjutkan.';
    }
    return 'Jangan tutup atau pindahkan app ke background saat tes berjalan. Jika terpaksa keluar, tes akan dipause otomatis dan bisa dilanjutkan saat app dibuka lagi.';
  }

  bool get canResumeTtfb =>
      hasPausedTest && _activeTestKind == _TestRunKind.ttfb;
  bool get canResumePing =>
      hasPausedTest && _activeTestKind == _TestRunKind.ping;
  bool get canResumeDns => hasPausedTest && _activeTestKind == _TestRunKind.dns;
  String? get manualWifiBandOverride => _manualWifiBandOverride;
  bool get shouldPromptManualWifiBand =>
      Platform.isIOS && _needsManualWifiBand(_networkInfo);
  String? get displayedWifiBand =>
      _manualWifiBandOverride ?? _networkInfo?.wifiBand;

  double get progress {
    if (_totalSamples == 0) {
      return 0;
    }
    return _ttfbResults.length / _totalSamples;
  }

  AppNetworkInfo? get effectiveNetworkInfo {
    if (_networkInfo == null) {
      return null;
    }

    final resolvedDnsServers =
        _dnsOverrideEnabled && _customDnsServers.isNotEmpty
        ? _customDnsServers
        : _networkInfo!.dnsServers;
    final resolvedDnsPrimary = resolvedDnsServers.isNotEmpty
        ? resolvedDnsServers.first
        : _networkInfo!.dnsPrimary;

    return AppNetworkInfo(
      connectionType: _networkInfo!.connectionType,
      ssid: _networkInfo!.ssid,
      bssid: _networkInfo!.bssid,
      ipAddress: _networkInfo!.ipAddress,
      publicIp: _networkInfo!.publicIp,
      isp: _networkInfo!.isp,
      wifiRssi: _networkInfo!.wifiRssi,
      wifiBand: displayedWifiBand,
      wifiChannel: _networkInfo!.wifiChannel,
      signalThreshold: _networkInfo!.signalThreshold,
      signalStatus: _networkInfo!.signalStatus,
      dnsPrimary: resolvedDnsPrimary,
      dnsServers: resolvedDnsServers,
      deviceName: _networkInfo!.deviceName,
      deviceModel: _networkInfo!.deviceModel,
      osName: _networkInfo!.osName,
      osVersion: _networkInfo!.osVersion,
      batteryLevel: _networkInfo!.batteryLevel,
      batteryCharging: _networkInfo!.batteryCharging,
      location: _networkInfo!.location,
      locationPermissionGranted: _networkInfo!.locationPermissionGranted,
      timestamp: _networkInfo!.timestamp,
    );
  }

  Future<void> init() async {
    await _runtimeSupportService.ensureInitialized();

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

    _dailyReminderEnabled = await _storageService.getDailyReminderEnabled();
    final reminderSynced = await _runtimeSupportService.syncDailyTtfbReminder(
      enabled: _dailyReminderEnabled,
    );
    if (_dailyReminderEnabled && reminderSynced) {
      _addStartupLog('Daily reminder scheduled for 19:00 local time');
    }

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
    _syncManualWifiBandOverride();
    _addStartupLog('Network: ${_networkInfo?.connectionType ?? 'Unknown'}');

    await _restorePausedSession();

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

  Future<void> updateSettings({
    int? samplesPerTarget,
    int? delayBetweenSamples,
    int? pingCount,
    String? brand,
    String? noInternetNumber,
    bool? dnsOverrideEnabled,
    List<String>? customDnsServers,
  }) async {
    await saveSettings(
      samplesPerTarget: samplesPerTarget ?? _samplesPerTarget,
      delayBetweenSamples: delayBetweenSamples ?? _delayBetweenSamples,
      pingCount: pingCount ?? _pingCount,
      brand: brand ?? _brand,
      noInternetNumber: noInternetNumber ?? _noInternetNumber,
      dnsOverrideEnabled: dnsOverrideEnabled ?? _dnsOverrideEnabled,
      customDnsServers: customDnsServers ?? _customDnsServers,
    );
  }

  Future<void> saveSettings({
    required int samplesPerTarget,
    required int delayBetweenSamples,
    required int pingCount,
    required String brand,
    required String noInternetNumber,
    bool? dnsOverrideEnabled,
    List<String>? customDnsServers,
  }) async {
    _samplesPerTarget = samplesPerTarget;
    _delayBetweenSamples = delayBetweenSamples;
    _pingCount = pingCount;
    _brand = brand.trim();
    _noInternetNumber = noInternetNumber.trim();
    if (dnsOverrideEnabled != null) {
      _dnsOverrideEnabled = dnsOverrideEnabled;
    }
    if (customDnsServers != null) {
      _customDnsServers = customDnsServers;
    }

    await _storageService.saveSettings(_buildSettingsPayload());
    notifyListeners();
  }

  Future<void> setDnsOverride({
    required bool enabled,
    List<String>? customServers,
  }) async {
    _dnsOverrideEnabled = enabled;
    if (customServers != null && customServers.isNotEmpty) {
      _customDnsServers = customServers;
    }
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
    _dnsOverrideEnabled = settings.containsKey('dns_override_enabled')
        ? settings['dns_override_enabled'] == true
        : true;
    final rawDns = settings['custom_dns_servers']?.toString() ?? '';
    _customDnsServers = rawDns.isNotEmpty
        ? rawDns.split(RegExp(r'[,;\s]+')).where((s) => s.isNotEmpty).toList()
        : List<String>.from(AppConstants.defaultDnsServers);
  }

  void _applyDefaultSettings() {
    _samplesPerTarget = AppConstants.defaultSamplesPerTarget;
    _delayBetweenSamples = AppConstants.defaultDelayBetweenSamples;
    _pingCount = AppConstants.defaultPingCount;
    _brand = '';
    _noInternetNumber = '';
    _dnsOverrideEnabled = true;
    _customDnsServers = List<String>.from(AppConstants.defaultDnsServers);
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
      'dns_override_enabled': _dnsOverrideEnabled,
      'custom_dns_servers': _customDnsServers.join(', '),
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

  Future<void> setDailyReminderEnabled(bool value) async {
    final enabled = await _runtimeSupportService.syncDailyTtfbReminder(
      enabled: value,
      requestPermissions: value,
    );

    _dailyReminderEnabled = enabled;
    await _storageService.setDailyReminderEnabled(enabled);
    notifyListeners();
  }

  Future<void> handleAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      await _pauseActiveTestForBackground();
    }
  }

  Future<void> _prepareForTestRun(_TestRunKind kind, String label) async {
    _activeTestKind = kind;
    _activeTestLabel = label;
    _pauseMessage = null;
    await _storageService.clearPausedSession();
    await _runtimeSupportService.requestNotificationPermissions();
    await _runtimeSupportService.setKeepAwake(true);
  }

  Future<void> _finishTestRun({
    required bool notifyCompletion,
    String? body,
  }) async {
    await _runtimeSupportService.setKeepAwake(false);
    await _storageService.clearPausedSession();

    final label = _activeTestLabel;
    _activeTestKind = null;
    _activeTestLabel = null;
    _pauseMessage = null;

    if (!notifyCompletion || label == null) {
      return;
    }

    await _runtimeSupportService.showCompletionNotification(
      title: '$label selesai',
      body: body ?? '$label selesai dijalankan.',
    );
  }

  Future<void> _pauseActiveTestForBackground() async {
    if (_status != TestStatus.running || _activeTestKind == null) {
      return;
    }

    if (_activeTestKind == _TestRunKind.ttfb ||
        _activeTestKind == _TestRunKind.ping) {
      await _testSubscription?.cancel();
      _testSubscription = null;
    }

    await _contributionQueue;
    await _runtimeSupportService.setKeepAwake(false);

    _status = TestStatus.paused;
    _pauseMessage =
        'Tes dipause karena app berpindah ke background. Kembali ke app lalu tekan Resume untuk melanjutkan dari progress terakhir.';
    await _persistPausedSession();
    notifyListeners();
  }

  Future<void> resumePausedTest() async {
    final snapshot = await _storageService.getPausedSession();
    if (snapshot == null) {
      return;
    }

    final kindValue = snapshot['kind']?.toString();
    if (kindValue == 'ttfb') {
      await _resumePausedTtfb(snapshot);
      return;
    }
    if (kindValue == 'ping') {
      await _resumePausedPing(snapshot);
      return;
    }
    if (kindValue == 'dns') {
      await _resumePausedDns(snapshot);
    }
  }

  Future<void> _restorePausedSession() async {
    final snapshot = await _storageService.getPausedSession();
    if (snapshot == null) {
      return;
    }

    final kindValue = snapshot['kind']?.toString();
    _pauseMessage =
        snapshot['pause_message']?.toString() ??
        'Tes dipause saat app keluar. Tekan Resume untuk melanjutkan.';

    switch (kindValue) {
      case 'ttfb':
        _activeTestKind = _TestRunKind.ttfb;
        _activeTestLabel = 'TTFB test';
        _ttfbResults = (snapshot['ttfb_results'] as List<dynamic>? ?? const [])
            .map((item) => TtfbResult.fromJson(Map<String, dynamic>.from(item)))
            .toList();
        _targetUrls = (snapshot['target_urls'] as List<dynamic>? ?? const [])
            .map((item) => item.toString())
            .toList();
        _sessionId = snapshot['session_id']?.toString();
        final startTime = snapshot['test_start_time']?.toString();
        _testStartTime = startTime != null
            ? DateTime.tryParse(startTime)
            : null;
        _currentTarget = snapshot['current_target']?.toString() ?? '';
        _currentSample = (snapshot['current_sample'] as num?)?.toInt() ?? 0;
        _totalSamples =
            (snapshot['total_samples'] as num?)?.toInt() ??
            _targetUrls.length * _samplesPerTarget;
        _restoreContributionSummary(snapshot['contribution_summary']);
        _restoreSubmittedKeys(snapshot['submitted_keys']);
        _status = TestStatus.paused;
        break;
      case 'ping':
        _activeTestKind = _TestRunKind.ping;
        _activeTestLabel = 'Ping test';
        _currentTarget = snapshot['host']?.toString() ?? '';
        _pingResults = (snapshot['ping_results'] as List<dynamic>? ?? const [])
            .map((item) => PingResult.fromJson(Map<String, dynamic>.from(item)))
            .toList();
        _status = TestStatus.paused;
        break;
      case 'dns':
        _activeTestKind = _TestRunKind.dns;
        _activeTestLabel = 'DNS lookup';
        _currentTarget = snapshot['domain']?.toString() ?? '';
        _dnsResults = (snapshot['dns_results'] as List<dynamic>? ?? const [])
            .map((item) => DnsResult.fromJson(Map<String, dynamic>.from(item)))
            .toList();
        _status = TestStatus.paused;
        break;
      default:
        await _storageService.clearPausedSession();
        break;
    }
  }

  void _restoreContributionSummary(dynamic rawSummary) {
    final summary = rawSummary is Map<String, dynamic>
        ? rawSummary
        : rawSummary is Map
        ? Map<String, dynamic>.from(rawSummary)
        : const <String, dynamic>{};
    _contributionSummary = ContributionSummary(
      submitted: (summary['submitted'] as num?)?.toInt() ?? 0,
      failed: (summary['failed'] as num?)?.toInt() ?? 0,
      total: (summary['total'] as num?)?.toInt() ?? 0,
      errors: (summary['errors'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
    );
  }

  void _restoreSubmittedKeys(dynamic rawKeys) {
    _submittedContributionKeys
      ..clear()
      ..addAll(
        (rawKeys as List<dynamic>? ?? const []).map((item) => item.toString()),
      );
  }

  Future<void> _persistPausedSession() async {
    if (_activeTestKind == null) {
      return;
    }

    final payload = <String, dynamic>{
      'kind': _activeTestKind!.name,
      'pause_message': _pauseMessage,
    };

    switch (_activeTestKind!) {
      case _TestRunKind.ttfb:
        final cursor = _nextTtfbCursor();
        payload.addAll({
          'target_urls': _targetUrls,
          'ttfb_results': _ttfbResults.map((item) => item.toJson()).toList(),
          'session_id': _sessionId,
          'test_start_time': _testStartTime?.toIso8601String(),
          'current_target': _currentTarget,
          'current_sample': _currentSample,
          'total_samples': _totalSamples,
          'next_target_index': cursor.$1,
          'next_sample': cursor.$2,
          'contribution_summary': {
            'submitted': _contributionSummary.submitted,
            'failed': _contributionSummary.failed,
            'total': _contributionSummary.total,
            'errors': _contributionSummary.errors,
          },
          'submitted_keys': _submittedContributionKeys.toList(),
        });
        break;
      case _TestRunKind.ping:
        payload.addAll({
          'host': _currentTarget,
          'ping_results': _pingResults.map((item) => item.toJson()).toList(),
        });
        break;
      case _TestRunKind.dns:
        payload.addAll({
          'domain': _currentTarget,
          'dns_results': _dnsResults.map((item) => item.toJson()).toList(),
        });
        break;
    }

    await _storageService.savePausedSession(payload);
  }

  (int, int) _nextTtfbCursor() {
    for (int index = 0; index < _targetUrls.length; index++) {
      final count = _ttfbResults
          .where((item) => item.url == _targetUrls[index])
          .length;
      if (count < _samplesPerTarget) {
        return (index, count + 1);
      }
    }
    return (_targetUrls.length, 1);
  }

  Future<void> _resumePausedTtfb(Map<String, dynamic> snapshot) async {
    _targetUrls = (snapshot['target_urls'] as List<dynamic>? ?? const [])
        .map((item) => item.toString())
        .toList();
    _ttfbResults = (snapshot['ttfb_results'] as List<dynamic>? ?? const [])
        .map((item) => TtfbResult.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    _sessionId = snapshot['session_id']?.toString();
    final startTime = snapshot['test_start_time']?.toString();
    _testStartTime = startTime != null ? DateTime.tryParse(startTime) : null;
    _currentTarget = snapshot['current_target']?.toString() ?? '';
    _currentSample = (snapshot['current_sample'] as num?)?.toInt() ?? 0;
    _totalSamples =
        (snapshot['total_samples'] as num?)?.toInt() ??
        _targetUrls.length * _samplesPerTarget;
    _restoreContributionSummary(snapshot['contribution_summary']);
    _restoreSubmittedKeys(snapshot['submitted_keys']);
    _contributionQueue = Future.value();
    _status = TestStatus.running;

    await _prepareForTestRun(_TestRunKind.ttfb, 'TTFB test');
    _networkInfo = await _networkInfoService.getNetworkInfo(
      requestPermissions: true,
    );
    _syncManualWifiBandOverride();
    notifyListeners();

    final nextTargetIndex =
        (snapshot['next_target_index'] as num?)?.toInt() ?? 0;
    final nextSample = (snapshot['next_sample'] as num?)?.toInt() ?? 1;
    _startTtfbStream(
      startTargetIndex: nextTargetIndex,
      startSample: nextSample,
    );
  }

  Future<void> _resumePausedPing(Map<String, dynamic> snapshot) async {
    _currentTarget = snapshot['host']?.toString() ?? '';
    _pingResults = (snapshot['ping_results'] as List<dynamic>? ?? const [])
        .map((item) => PingResult.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    _status = TestStatus.running;

    await _prepareForTestRun(_TestRunKind.ping, 'Ping test');
    notifyListeners();

    final nextSequence = _pingResults.length + 1;
    final remaining = _pingCount - _pingResults.length;
    if (remaining <= 0) {
      await _completePingRun();
      return;
    }

    _startPingStream(
      host: _currentTarget,
      count: remaining,
      startSequence: nextSequence,
    );
  }

  Future<void> _resumePausedDns(Map<String, dynamic> snapshot) async {
    final domain = snapshot['domain']?.toString() ?? _currentTarget;
    await _prepareForTestRun(_TestRunKind.dns, 'DNS lookup');
    await dnsLookup(domain);
  }

  String _buildTtfbCompletionMessage() {
    final completedSamples = _ttfbResults.length;
    return 'TTFB selesai: $completedSamples dari $_totalSamples sampel terkumpul.';
  }

  String _buildPingCompletionMessage() {
    return 'Ping selesai: ${_pingResults.length} sampel untuk $_currentTarget.';
  }

  String _buildDnsCompletionMessage(String domain) {
    return 'DNS lookup selesai untuk $domain dengan ${_dnsResults.length} record.';
  }

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

    await _prepareForTestRun(_TestRunKind.ttfb, 'TTFB test');

    _networkInfo = await _networkInfoService.getNetworkInfo(
      requestPermissions: true,
    );
    _syncManualWifiBandOverride();
    notifyListeners();

    _startTtfbStream();
  }

  void _startTtfbStream({int startTargetIndex = 0, int startSample = 1}) {
    _testSubscription = _ttfbService
        .runMultiTargetTest(
          urls: _targetUrls,
          samplesPerTarget: _samplesPerTarget,
          delayBetweenSamples: Duration(seconds: _delayBetweenSamples),
          startTargetIndex: startTargetIndex,
          startSample: startSample,
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
            unawaited(_finishTestRun(notifyCompletion: false));
            notifyListeners();
          },
          onDone: () {
            unawaited(_completeTtfbRun());
          },
        );
  }

  Future<void> _completeTtfbRun() async {
    await _contributionQueue;
    if (_autoContribute) {
      await _submitPendingContributionResults(resetSummary: false);
    }
    _status = TestStatus.completed;
    await _saveResults();
    await _finishTestRun(
      notifyCompletion: true,
      body: _buildTtfbCompletionMessage(),
    );
    notifyListeners();
  }

  void stopTest() {
    _testSubscription?.cancel();
    _testSubscription = null;
    _status = TestStatus.idle;
    _activeTestKind = null;
    _activeTestLabel = null;
    _pauseMessage = null;
    unawaited(_storageService.clearPausedSession());
    unawaited(_finishTestRun(notifyCompletion: false));
    notifyListeners();
  }

  Future<void> startPingTest(String host) async {
    _status = TestStatus.running;
    _pingResults = [];
    _errorMessage = null;
    _currentTarget = host;

    await _prepareForTestRun(_TestRunKind.ping, 'Ping test');
    notifyListeners();

    _startPingStream(host: host, count: _pingCount, startSequence: 1);
  }

  void _startPingStream({
    required String host,
    required int count,
    required int startSequence,
  }) {
    _testSubscription = _pingService
        .ping(host: host, count: count, startSequence: startSequence)
        .listen(
          (result) {
            _pingResults.add(result);
            notifyListeners();
          },
          onError: (error) {
            _errorMessage = error.toString();
            _status = TestStatus.error;
            unawaited(_finishTestRun(notifyCompletion: false));
            notifyListeners();
          },
          onDone: () {
            unawaited(_completePingRun());
          },
        );
  }

  Future<void> _completePingRun() async {
    _status = TestStatus.completed;
    await _finishTestRun(
      notifyCompletion: true,
      body: _buildPingCompletionMessage(),
    );
    notifyListeners();
  }

  Future<void> dnsLookup(String domain) async {
    _status = TestStatus.running;
    _dnsResults = [];
    _errorMessage = null;
    _currentTarget = domain;

    await _prepareForTestRun(_TestRunKind.dns, 'DNS lookup');
    notifyListeners();

    try {
      final results = await _dnsService.getAllRecords(domain);
      _dnsResults = results;
      _status = TestStatus.completed;
      await _finishTestRun(
        notifyCompletion: true,
        body: _buildDnsCompletionMessage(domain),
      );
    } catch (e) {
      _errorMessage = e.toString();
      _status = TestStatus.error;
      await _finishTestRun(notifyCompletion: false);
    }
    notifyListeners();
  }

  Future<void> refreshNetworkInfo() async {
    _networkInfo = await _networkInfoService.getNetworkInfo(
      requestPermissions: true,
    );
    _syncManualWifiBandOverride();
    notifyListeners();
  }

  void setManualWifiBandOverride(String? value) {
    if (!Platform.isIOS || !_needsManualWifiBand(_networkInfo)) {
      return;
    }

    if (value != null && !iosWifiBandOptions.contains(value)) {
      return;
    }

    _manualWifiBandOverride = value;
    _manualWifiBandSsid = value == null ? null : _networkInfo?.ssid;
    debugPrint(
      'Manual Wi-Fi band override updated: value=$_manualWifiBandOverride, '
      'ssid=$_manualWifiBandSsid',
    );
    notifyListeners();
  }

  bool _needsManualWifiBand(AppNetworkInfo? info) {
    if (info == null || info.connectionType != 'WiFi') {
      return false;
    }

    final band = info.wifiBand?.trim();
    return band == null ||
        band.isEmpty ||
        band == 'Unavailable (iOS API limit)';
  }

  void _syncManualWifiBandOverride() {
    if (!Platform.isIOS || !_needsManualWifiBand(_networkInfo)) {
      _manualWifiBandOverride = null;
      _manualWifiBandSsid = null;
      return;
    }

    if (_manualWifiBandOverride == null) {
      return;
    }

    final currentSsid = _networkInfo?.ssid;
    if (_manualWifiBandSsid != null &&
        currentSsid != null &&
        _manualWifiBandSsid != currentSsid) {
      _manualWifiBandOverride = null;
      _manualWifiBandSsid = null;
    }
  }

  Future<void> _saveResults() async {
    if (_ttfbResults.isEmpty) {
      return;
    }

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
        'device_model': effectiveNetworkInfo?.deviceModel,
        'battery_level': effectiveNetworkInfo?.batteryLevel,
        'battery_charging': effectiveNetworkInfo?.batteryCharging,
        'wifi_rssi': effectiveNetworkInfo?.wifiRssi,
        'wifi_band': effectiveNetworkInfo?.wifiBand,
        'wifi_channel': effectiveNetworkInfo?.wifiChannel,
        'dns_primary': effectiveNetworkInfo?.dnsPrimary,
        'dns_servers': effectiveNetworkInfo?.dnsServers,
        'ssid': effectiveNetworkInfo?.ssid,
        'public_ip': effectiveNetworkInfo?.publicIp,
        'isp': effectiveNetworkInfo?.isp,
        'connectivity_type': effectiveNetworkInfo?.connectionType,
        'connection_type': effectiveNetworkInfo?.connectionType,
        'ip_address': effectiveNetworkInfo?.ipAddress,
        'location': {
          'city': effectiveNetworkInfo?.location?.city,
          'region': effectiveNetworkInfo?.location?.region,
          'country': effectiveNetworkInfo?.location?.country,
          'lat': effectiveNetworkInfo?.location?.latitude,
          'lon': effectiveNetworkInfo?.location?.longitude,
          'accuracy': effectiveNetworkInfo?.location?.accuracy,
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
      networkInfo: effectiveNetworkInfo,
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

  Future<void> _submitPendingContributionResults({
    required bool resetSummary,
  }) async {
    if (_ttfbResults.isEmpty) {
      return;
    }

    final pendingResults = _ttfbResults.where((result) {
      final contributionKey = _buildContributionKey(
        sessionId: _sessionId!,
        result: result,
      );
      return !_submittedContributionKeys.contains(contributionKey);
    }).toList();

    if (pendingResults.isEmpty) {
      return;
    }

    if (resetSummary) {
      _contributionSummary = ContributionSummary(
        submitted: 0,
        failed: 0,
        total: pendingResults.length,
        errors: const [],
      );
      notifyListeners();
    }

    for (final result in pendingResults) {
      await _submitContributionForResult(result);
    }
  }

  Future<void> contributeCurrentResults() async {
    if (_ttfbResults.isEmpty) {
      return;
    }

    await _contributionQueue;

    _sessionId ??= DateTime.now().millisecondsSinceEpoch.toString();
    _testStartTime ??= _ttfbResults.first.timestamp;
    await _submitPendingContributionResults(resetSummary: true);
  }

  String _buildContributionKey({
    required String sessionId,
    required TtfbResult result,
  }) {
    return '$sessionId|${result.url}|${result.sampleNumber}|${result.timestamp.toIso8601String()}';
  }

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
    if (_pingResults.isEmpty) {
      return null;
    }
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
    _activeTestKind = null;
    _activeTestLabel = null;
    _pauseMessage = null;
    unawaited(_storageService.clearPausedSession());
    notifyListeners();
  }

  @override
  void dispose() {
    _testSubscription?.cancel();
    unawaited(_runtimeSupportService.setKeepAwake(false));
    _ttfbService.dispose();
    _contributionService.dispose();
    _networkInfoService.dispose();
    super.dispose();
  }
}
