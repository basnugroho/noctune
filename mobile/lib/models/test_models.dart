import '../core/constants/app_constants.dart';

class TtfbResult {
  final String url;
  final int sampleNumber;
  final double ttfbMs;
  final int statusCode;
  final DateTime timestamp;
  final double? lookupMs;
  final double? connectMs;
  final double? totalMs;
  final String? resolvedIp;
  final String? digOutput;
  final double? digQueryTimeMs;
  final String? error;

  TtfbResult({
    required this.url,
    required this.sampleNumber,
    required this.ttfbMs,
    required this.statusCode,
    required this.timestamp,
    this.lookupMs,
    this.connectMs,
    this.totalMs,
    this.resolvedIp,
    this.digOutput,
    this.digQueryTimeMs,
    this.error,
  });

  ResultQuality get quality {
    if (error != null) return ResultQuality.poor;
    if (ttfbMs <= AppConstants.goodTtfbThreshold) return ResultQuality.good;
    if (ttfbMs <= AppConstants.warningTtfbThreshold)
      return ResultQuality.warning;
    return ResultQuality.poor;
  }

  Map<String, dynamic> toJson() => {
    'url': url,
    'sample_number': sampleNumber,
    'ttfb_ms': ttfbMs,
    'status_code': statusCode,
    'timestamp': timestamp.toIso8601String(),
    'lookup_ms': lookupMs,
    'connect_ms': connectMs,
    'total_ms': totalMs,
    'resolved_ip': resolvedIp,
    'dig_output': digOutput,
    'dig_query_time_ms': digQueryTimeMs,
    'error': error,
  };

  factory TtfbResult.fromJson(Map<String, dynamic> json) => TtfbResult(
    url: json['url'],
    sampleNumber: json['sample_number'],
    ttfbMs: (json['ttfb_ms'] as num).toDouble(),
    statusCode: json['status_code'],
    timestamp: DateTime.parse(json['timestamp']),
    lookupMs: (json['lookup_ms'] as num?)?.toDouble(),
    connectMs: (json['connect_ms'] as num?)?.toDouble(),
    totalMs: (json['total_ms'] as num?)?.toDouble(),
    resolvedIp: json['resolved_ip'],
    digOutput: json['dig_output'],
    digQueryTimeMs: (json['dig_query_time_ms'] as num?)?.toDouble(),
    error: json['error'],
  );
}

class TtfbTestSummary {
  final String url;
  final List<TtfbResult> results;
  final DateTime startTime;
  final DateTime? endTime;

  TtfbTestSummary({
    required this.url,
    required this.results,
    required this.startTime,
    this.endTime,
  });

  double get avgTtfb {
    if (results.isEmpty) return 0;
    final validResults = results.where((r) => r.error == null);
    if (validResults.isEmpty) return 0;
    return validResults.map((r) => r.ttfbMs).reduce((a, b) => a + b) /
        validResults.length;
  }

  double get minTtfb {
    if (results.isEmpty) return 0;
    final validResults = results.where((r) => r.error == null);
    if (validResults.isEmpty) return 0;
    return validResults.map((r) => r.ttfbMs).reduce((a, b) => a < b ? a : b);
  }

  double get maxTtfb {
    if (results.isEmpty) return 0;
    final validResults = results.where((r) => r.error == null);
    if (validResults.isEmpty) return 0;
    return validResults.map((r) => r.ttfbMs).reduce((a, b) => a > b ? a : b);
  }

  int get successCount => results.where((r) => r.error == null).length;
  int get errorCount => results.where((r) => r.error != null).length;

  ResultQuality get overallQuality {
    if (avgTtfb <= AppConstants.goodTtfbThreshold) return ResultQuality.good;
    if (avgTtfb <= AppConstants.warningTtfbThreshold)
      return ResultQuality.warning;
    return ResultQuality.poor;
  }
}

class DnsResult {
  final String domain;
  final String queryType;
  final List<String> answers;
  final double responseTimeMs;
  final String dnsServer;
  final DateTime timestamp;
  final String? error;

  DnsResult({
    required this.domain,
    required this.queryType,
    required this.answers,
    required this.responseTimeMs,
    required this.dnsServer,
    required this.timestamp,
    this.error,
  });

  Map<String, dynamic> toJson() => {
    'domain': domain,
    'query_type': queryType,
    'answers': answers,
    'response_time_ms': responseTimeMs,
    'dns_server': dnsServer,
    'timestamp': timestamp.toIso8601String(),
    'error': error,
  };
}

class PingResult {
  final String host;
  final int sequenceNumber;
  final double latencyMs;
  final int ttl;
  final DateTime timestamp;
  final String? error;

  PingResult({
    required this.host,
    required this.sequenceNumber,
    required this.latencyMs,
    required this.ttl,
    required this.timestamp,
    this.error,
  });

  Map<String, dynamic> toJson() => {
    'host': host,
    'sequence': sequenceNumber,
    'latency_ms': latencyMs,
    'ttl': ttl,
    'timestamp': timestamp.toIso8601String(),
    'error': error,
  };
}

class PingTestSummary {
  final String host;
  final List<PingResult> results;
  final DateTime startTime;
  final DateTime? endTime;

  PingTestSummary({
    required this.host,
    required this.results,
    required this.startTime,
    this.endTime,
  });

  double get avgLatency {
    if (results.isEmpty) return 0;
    final validResults = results.where((r) => r.error == null);
    if (validResults.isEmpty) return 0;
    return validResults.map((r) => r.latencyMs).reduce((a, b) => a + b) /
        validResults.length;
  }

  double get minLatency {
    if (results.isEmpty) return 0;
    final validResults = results.where((r) => r.error == null);
    if (validResults.isEmpty) return 0;
    return validResults.map((r) => r.latencyMs).reduce((a, b) => a < b ? a : b);
  }

  double get maxLatency {
    if (results.isEmpty) return 0;
    final validResults = results.where((r) => r.error == null);
    if (validResults.isEmpty) return 0;
    return validResults.map((r) => r.latencyMs).reduce((a, b) => a > b ? a : b);
  }

  int get sent => results.length;
  int get received => results.where((r) => r.error == null).length;
  double get packetLoss => sent > 0 ? ((sent - received) / sent) * 100 : 0;
}

class AppNetworkInfo {
  final String? deviceName;
  final String? deviceModel;
  final String? osName;
  final String? osVersion;
  final int? batteryLevel;
  final bool? batteryCharging;
  final String? ssid;
  final String? bssid;
  final String? ipAddress;
  final String? publicIp;
  final String? isp;
  final String? connectionType;
  final int? wifiRssi;
  final String? wifiBand;
  final int? wifiChannel;
  final int? signalThreshold;
  final String? signalStatus;
  final List<String> dnsServers;
  final String? dnsPrimary;
  final AppLocationInfo? location;
  final bool locationPermissionGranted;
  final DateTime timestamp;

  AppNetworkInfo({
    this.deviceName,
    this.deviceModel,
    this.osName,
    this.osVersion,
    this.batteryLevel,
    this.batteryCharging,
    this.ssid,
    this.bssid,
    this.ipAddress,
    this.publicIp,
    this.isp,
    this.connectionType,
    this.wifiRssi,
    this.wifiBand,
    this.wifiChannel,
    this.signalThreshold,
    this.signalStatus,
    this.dnsServers = const [],
    this.dnsPrimary,
    this.location,
    this.locationPermissionGranted = false,
    required this.timestamp,
  });
}

class AppLocationInfo {
  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final double? altitude;
  final double? altitudeAccuracy;
  final double? heading;
  final double? speed;
  final String? city;
  final String? region;
  final String? country;
  final DateTime? browserTimestamp;
  final DateTime? savedAt;
  final String? source;
  final String? method;
  final bool? isPrecise;

  const AppLocationInfo({
    this.latitude,
    this.longitude,
    this.accuracy,
    this.altitude,
    this.altitudeAccuracy,
    this.heading,
    this.speed,
    this.city,
    this.region,
    this.country,
    this.browserTimestamp,
    this.savedAt,
    this.source,
    this.method,
    this.isPrecise,
  });
}
