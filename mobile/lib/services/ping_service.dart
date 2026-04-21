import 'dart:async';
import 'package:dart_ping/dart_ping.dart';
import '../models/test_models.dart';

class PingService {
  /// Ping a host and return results as a stream
  Stream<PingResult> ping({
    required String host,
    required int count,
    Duration interval = const Duration(seconds: 1),
    Duration timeout = const Duration(seconds: 5),
    int startSequence = 1,
  }) async* {
    final ping = Ping(
      host,
      count: count,
      interval: interval.inSeconds,
      timeout: timeout.inSeconds,
    );

    int sequence = startSequence - 1;

    await for (final response in ping.stream) {
      sequence++;

      if (response.response != null) {
        yield PingResult(
          host: host,
          sequenceNumber: sequence,
          latencyMs:
              response.response!.time?.inMicroseconds.toDouble() ?? 0 / 1000,
          ttl: response.response!.ttl ?? 0,
          timestamp: DateTime.now(),
        );
      } else if (response.error != null) {
        yield PingResult(
          host: host,
          sequenceNumber: sequence,
          latencyMs: -1,
          ttl: 0,
          timestamp: DateTime.now(),
          error: response.error.toString(),
        );
      }
    }
  }

  /// Get ping summary after test completes
  Future<PingTestSummary> runPingTest({
    required String host,
    required int count,
    Duration interval = const Duration(seconds: 1),
  }) async {
    final startTime = DateTime.now();
    final results = <PingResult>[];

    await for (final result in ping(
      host: host,
      count: count,
      interval: interval,
    )) {
      results.add(result);
    }

    return PingTestSummary(
      host: host,
      results: results,
      startTime: startTime,
      endTime: DateTime.now(),
    );
  }

  /// Simple ping check to see if host is reachable
  Future<bool> isReachable(
    String host, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      final ping = Ping(host, count: 1, timeout: timeout.inSeconds);
      final result = await ping.stream.first;
      return result.response != null;
    } catch (e) {
      return false;
    }
  }
}
