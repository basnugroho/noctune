import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/constants/app_constants.dart';
import '../models/test_models.dart';

class ContributionSummary {
  final int submitted;
  final int failed;
  final int total;
  final List<String> errors;

  const ContributionSummary({
    required this.submitted,
    required this.failed,
    required this.total,
    required this.errors,
  });

  const ContributionSummary.empty()
    : submitted = 0,
      failed = 0,
      total = 0,
      errors = const [];
}

class ContributionResult {
  final bool success;
  final bool duplicate;
  final String? error;

  const ContributionResult({
    required this.success,
    this.duplicate = false,
    this.error,
  });
}

class ContributionService {
  static const Duration _requestTimeout = Duration(seconds: 45);
  static const List<Duration> _retryBackoff = [
    Duration.zero,
    Duration(seconds: 2),
    Duration(seconds: 5),
  ];

  final http.Client _client;

  ContributionService({http.Client? client})
    : _client = client ?? http.Client();

  Future<ContributionResult> submitRow({
    required Map<String, dynamic> row,
  }) async {
    final cleanedRow = _pruneNullValues(row);
    final payload = jsonEncode({'row': cleanedRow});
    Object? lastError;

    debugPrint(
      'Contribution request: connectivity_type=${cleanedRow['connectivity_type']}, '
      'url=${cleanedRow['url']}, sample_num=${cleanedRow['sample_num']}, '
      'session_id=${cleanedRow['session_id']}',
    );

    for (int attempt = 0; attempt < _retryBackoff.length; attempt++) {
      final waitDuration = _retryBackoff[attempt];
      if (waitDuration > Duration.zero) {
        await Future.delayed(waitDuration);
      }

      try {
        final response = await _client
            .post(
              Uri.parse(AppConstants.contributeApiUrl),
              headers: const {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
                'User-Agent': 'NOC-Tune-Mobile/1.0',
                'Connection': 'close',
              },
              body: payload,
            )
            .timeout(_requestTimeout);

        debugPrint(
          'Contribution response: status=${response.statusCode}, '
          'body=${response.body}',
        );

        if (response.statusCode >= 200 && response.statusCode < 300) {
          return const ContributionResult(success: true);
        }

        if (_isDuplicateContributionError(response.body)) {
          return const ContributionResult(success: true, duplicate: true);
        }

        return ContributionResult(
          success: false,
          error: 'HTTP ${response.statusCode}: ${response.body}',
        );
      } on TimeoutException {
        lastError =
            'Request timed out after ${_requestTimeout.inSeconds}s '
            '(attempt ${attempt + 1}/${_retryBackoff.length})';
        debugPrint('Contribution timeout: $lastError');
      } on SocketException catch (error) {
        lastError =
            'Network error while contacting QoSMic API '
            '(attempt ${attempt + 1}/${_retryBackoff.length}): ${error.message}';
        debugPrint('Contribution socket error: $lastError');
      } on http.ClientException catch (error) {
        lastError =
            'HTTP client error while contacting QoSMic API '
            '(attempt ${attempt + 1}/${_retryBackoff.length}): ${error.message}';
        debugPrint('Contribution client error: $lastError');
      } catch (error) {
        lastError =
            'Unexpected contribute error '
            '(attempt ${attempt + 1}/${_retryBackoff.length}): $error';
        debugPrint('Contribution unexpected error: $lastError');
      }
    }

    return ContributionResult(
      success: false,
      error: lastError?.toString() ?? 'Unknown contribution error',
    );
  }

  Map<String, dynamic> buildContributionRow({
    required TtfbResult result,
    required String sessionId,
    required DateTime testStartTime,
    required DateTime testEndTime,
    required List<TtfbResult> allResults,
    required AppNetworkInfo? networkInfo,
    required String brand,
    required String noInternetNumber,
    required int sampleCount,
    required int delaySeconds,
  }) {
    final validResults = allResults
        .where((item) => item.error == null)
        .toList();
    final ttfbValues = validResults.map((item) => item.ttfbMs).toList();

    double? meanTtfb;
    double? medianTtfb;
    double? stdTtfb;
    double? minTtfb;
    double? maxTtfb;

    if (ttfbValues.isNotEmpty) {
      meanTtfb =
          ttfbValues.reduce((left, right) => left + right) / ttfbValues.length;

      final sorted = [...ttfbValues]..sort();
      final mid = sorted.length ~/ 2;
      medianTtfb = sorted.length.isEven
          ? (sorted[mid - 1] + sorted[mid]) / 2
          : sorted[mid];

      final variance =
          ttfbValues
              .map((value) => (value - meanTtfb!) * (value - meanTtfb))
              .reduce((left, right) => left + right) /
          ttfbValues.length;
      stdTtfb = variance.sqrt();
      minTtfb = sorted.first;
      maxTtfb = sorted.last;
    }

    final timestamp = result.timestamp.toIso8601String();
    final normalizedUrl =
        result.url.startsWith('http://') || result.url.startsWith('https://')
        ? result.url
        : 'https://${result.url}';
    final location = networkInfo?.location;
    final dnsServerText =
        networkInfo != null && networkInfo.dnsServers.isNotEmpty
        ? networkInfo.dnsServers.join(';')
        : null;
    final connectivityType = _normalizeConnectivityType(
      networkInfo?.connectionType,
    );
    final cleanedBrand = brand.trim();
    final cleanedNoInternet = noInternetNumber.trim();

    return {
      'session_id': sessionId,
      'test_start_time': _normalizeSqlDatetime(testStartTime.toIso8601String()),
      'test_end_time': _normalizeSqlDatetime(testEndTime.toIso8601String()),
      'timestamp': _normalizeSqlDatetime(timestamp),
      'time_short': _formatTimeShort(result.timestamp),
      'target_name': normalizedUrl,
      'brand': cleanedBrand.isEmpty ? null : cleanedBrand,
      'is_mobile': 1,
      'no_internet': cleanedNoInternet.isEmpty ? null : cleanedNoInternet,
      'sample_num': result.sampleNumber,
      'url': normalizedUrl,
      'ttfb_ms': result.error == null ? result.ttfbMs : null,
      'lookup_ms': result.lookupMs,
      'connect_ms': result.connectMs,
      'total_ms':
          result.totalMs ?? (result.error == null ? result.ttfbMs : null),
      'http_code': result.statusCode,
      'status': _qualityToStatus(result.quality),
      'error': result.error,
      'device_name': networkInfo?.deviceName ?? 'Android',
      'device_model': networkInfo?.deviceModel,
      'os_name': networkInfo?.osName ?? 'Android',
      'os_version': networkInfo?.osVersion,
      'battery_level': networkInfo?.batteryLevel,
      'battery_charging': networkInfo?.batteryCharging,
      'wifi_ssid': networkInfo?.ssid,
      'wifi_ssid_method': networkInfo?.ssid != null
          ? 'network_info_plus'
          : 'unknown',
      'wifi_rssi': networkInfo?.wifiRssi,
      'wifi_band': networkInfo?.wifiBand,
      'wifi_channel': networkInfo?.wifiChannel,
      'connectivity_type': connectivityType,
      'signal_threshold': networkInfo?.signalThreshold,
      'signal_status': networkInfo?.signalStatus,
      'dns_primary': networkInfo?.dnsPrimary,
      'dns_servers': dnsServerText,
      'resolved_ip': result.resolvedIp,
      'dig_output': result.digOutput,
      'dig_query_time_ms': result.digQueryTimeMs,
      'location_city': location?.city,
      'location_region': location?.region,
      'location_country': location?.country,
      'location_lat': location?.latitude,
      'location_lon': location?.longitude,
      'location_accuracy': location?.accuracy,
      'location_altitude': location?.altitude,
      'location_altitude_accuracy': location?.altitudeAccuracy,
      'location_heading': location?.heading,
      'location_speed': location?.speed,
      'location_browser_timestamp': location?.browserTimestamp != null
          ? _normalizeSqlDatetime(location!.browserTimestamp!.toIso8601String())
          : null,
      'location_saved_at': location?.savedAt != null
          ? _normalizeSqlDatetime(location!.savedAt!.toIso8601String())
          : null,
      'location_source': location?.source,
      'location_method': location?.method,
      'location_is_precise': location?.isPrecise,
      'isp': networkInfo?.isp,
      'public_ip': networkInfo?.publicIp,
      'config_ttfb_good_ms': AppConstants.goodTtfbThreshold,
      'config_ttfb_warning_ms': AppConstants.warningTtfbThreshold,
      'config_sample_count': sampleCount,
      'config_delay_seconds': delaySeconds,
      'summary_mean_ttfb': meanTtfb != null
          ? double.parse(meanTtfb.toStringAsFixed(2))
          : null,
      'summary_median_ttfb': medianTtfb != null
          ? double.parse(medianTtfb.toStringAsFixed(2))
          : null,
      'summary_min_ttfb': minTtfb != null
          ? double.parse(minTtfb.toStringAsFixed(2))
          : null,
      'summary_max_ttfb': maxTtfb != null
          ? double.parse(maxTtfb.toStringAsFixed(2))
          : null,
      'summary_std_ttfb': stdTtfb != null
          ? double.parse(stdTtfb.toStringAsFixed(2))
          : null,
      'summary_good_count': validResults
          .where((item) => item.quality == ResultQuality.good)
          .length,
      'summary_warning_count': validResults
          .where((item) => item.quality == ResultQuality.warning)
          .length,
      'summary_poor_count': validResults
          .where((item) => item.quality == ResultQuality.poor)
          .length,
      'summary_total_tests': allResults.length,
      'summary_successful_tests': validResults.length,
      'summary_failed_tests': allResults.length - validResults.length,
    };
  }

  String _normalizeSqlDatetime(String value) {
    final parsed = DateTime.parse(value);
    final local = parsed.isUtc ? parsed.toLocal() : parsed;
    final fractional = local.millisecond.toString().padLeft(3, '0');
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}.$fractional';
  }

  String _formatTimeShort(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    final second = time.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  String _qualityToStatus(ResultQuality quality) {
    switch (quality) {
      case ResultQuality.good:
        return 'good';
      case ResultQuality.warning:
        return 'warning';
      case ResultQuality.poor:
        return 'poor';
    }
  }

  String? _normalizeConnectivityType(String? connectionType) {
    switch (connectionType) {
      case 'WiFi':
        return 'WiFi';
      case 'Cellular':
        return 'Cellular';
      case 'Mobile Data':
        return 'Cellular';
      case 'Fixed':
        return 'Fixed';
      case 'Ethernet':
        return 'Fixed';
      default:
        return null;
    }
  }

  bool _isDuplicateContributionError(String responseText) {
    final normalized = responseText.toLowerCase();
    return normalized.contains('duplicate entry') ||
        normalized.contains('integrity constraint violation') ||
        normalized.contains('uq_ttfb_results_row') ||
        normalized.contains('sqlstate[23000]');
  }

  Map<String, dynamic> _pruneNullValues(Map<String, dynamic> row) {
    final cleaned = <String, dynamic>{};
    for (final entry in row.entries) {
      final value = entry.value;
      if (value != null) {
        cleaned[entry.key] = value;
      }
    }
    return cleaned;
  }

  void dispose() {
    _client.close();
  }
}

extension on double {
  double sqrt() {
    if (this <= 0) return 0;
    double estimate = this / 2;
    for (int i = 0; i < 10; i++) {
      estimate = (estimate + this / estimate) / 2;
    }
    return estimate;
  }
}
