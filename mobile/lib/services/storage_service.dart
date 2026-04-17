import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _targetsKey = 'target_urls';
  static const String _settingsKey = 'test_settings';
  static const String _historyKey = 'test_history';
  static const String _autoContributeKey = 'auto_contribute';

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  bool hasTargets() {
    return _prefs.containsKey(_targetsKey);
  }

  bool hasSettings() {
    return _prefs.containsKey(_settingsKey);
  }

  bool hasAutoContributePreference() {
    return _prefs.containsKey(_autoContributeKey);
  }

  // Target URLs
  Future<List<String>> getTargets() async {
    final data = _prefs.getStringList(_targetsKey);
    return data ?? [];
  }

  Future<void> saveTargets(List<String> targets) async {
    await _prefs.setStringList(_targetsKey, targets);
  }

  Future<void> addTarget(String url) async {
    final targets = await getTargets();
    if (!targets.contains(url)) {
      targets.add(url);
      await saveTargets(targets);
    }
  }

  Future<void> removeTarget(String url) async {
    final targets = await getTargets();
    targets.remove(url);
    await saveTargets(targets);
  }

  // Test Settings
  Future<Map<String, dynamic>> getSettings() async {
    final data = _prefs.getString(_settingsKey);
    if (data == null) {
      return {
        'samples_per_target': 10,
        'delay_between_samples': 30,
        'ping_count': 60,
        'ping_duration_seconds': 60,
        'good_ttfb_threshold': 600,
        'warning_ttfb_threshold': 800,
        'signal_threshold': -65,
        'dns_override_enabled': false,
        'custom_dns_servers': '8.8.8.8, 8.8.4.4',
        'brand': '',
        'no_internet_number': '',
      };
    }
    return jsonDecode(data);
  }

  Future<void> saveSettings(Map<String, dynamic> settings) async {
    await _prefs.setString(_settingsKey, jsonEncode(settings));
  }

  // Auto Contribute
  Future<bool> getAutoContribute() async {
    return _prefs.getBool(_autoContributeKey) ?? true;
  }

  Future<void> setAutoContribute(bool value) async {
    await _prefs.setBool(_autoContributeKey, value);
  }

  // Test History
  Future<List<Map<String, dynamic>>> getHistory() async {
    final data = _prefs.getStringList(_historyKey);
    if (data == null) return [];
    return data
        .map((item) => jsonDecode(item) as Map<String, dynamic>)
        .toList();
  }

  Future<void> addToHistory(Map<String, dynamic> result) async {
    final history = await getHistory();
    history.insert(0, result);

    // Keep only last 100 entries
    if (history.length > 100) {
      history.removeRange(100, history.length);
    }

    await _prefs.setStringList(
      _historyKey,
      history.map((item) => jsonEncode(item)).toList(),
    );
  }

  Future<void> clearHistory() async {
    await _prefs.remove(_historyKey);
  }
}
