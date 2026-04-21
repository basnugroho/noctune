import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/test_models.dart';

class TtfbService {
  final http.Client _client;

  TtfbService({http.Client? client}) : _client = client ?? http.Client();

  /// Measure TTFB for a single URL
  Future<TtfbResult> measureTtfb({
    required String url,
    required int sampleNumber,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final timestamp = DateTime.now();

    try {
      // Ensure URL has scheme
      String targetUrl = url;
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        targetUrl = 'https://$url';
      }

      final uri = Uri.parse(targetUrl);
      final host = uri.host;
      double? lookupMs;
      String? resolvedIp;
      String? digOutput;
      double? digQueryTimeMs;

      if (host.isNotEmpty) {
        final dnsStopwatch = Stopwatch()..start();
        final addresses = await InternetAddress.lookup(host);
        dnsStopwatch.stop();
        lookupMs = dnsStopwatch.elapsedMicroseconds / 1000;
        digQueryTimeMs = lookupMs;
        if (addresses.isNotEmpty) {
          resolvedIp = addresses.first.address;
          digOutput =
              'System DNS lookup for $host => ${addresses.map((addr) => addr.address).join(', ')}';
        } else {
          digOutput = 'System DNS lookup for $host returned no addresses';
        }
      }

      final connectMs = await _measureConnectTime(uri: uri, timeout: timeout);

      final stopwatch = Stopwatch()..start();

      final request = http.Request('GET', uri);
      request.headers['User-Agent'] = 'NOC Tune Mobile/1.0';

      final streamedResponse = await _client.send(request).timeout(timeout);

      // TTFB is the time to receive the first byte
      stopwatch.stop();
      final ttfbMs = stopwatch.elapsedMilliseconds.toDouble();

      // Drain the response to free resources
      await streamedResponse.stream.drain();

      return TtfbResult(
        url: targetUrl,
        sampleNumber: sampleNumber,
        ttfbMs: ttfbMs,
        statusCode: streamedResponse.statusCode,
        timestamp: timestamp,
        lookupMs: lookupMs,
        connectMs: connectMs,
        totalMs: ttfbMs,
        resolvedIp: resolvedIp,
        digOutput: digOutput,
        digQueryTimeMs: digQueryTimeMs,
      );
    } on SocketException catch (e) {
      return TtfbResult(
        url: url,
        sampleNumber: sampleNumber,
        ttfbMs: -1,
        statusCode: 0,
        timestamp: timestamp,
        totalMs: -1,
        error: 'Network error: ${e.message}',
      );
    } on HttpException catch (e) {
      return TtfbResult(
        url: url,
        sampleNumber: sampleNumber,
        ttfbMs: -1,
        statusCode: 0,
        timestamp: timestamp,
        totalMs: -1,
        error: 'HTTP error: ${e.message}',
      );
    } catch (e) {
      return TtfbResult(
        url: url,
        sampleNumber: sampleNumber,
        ttfbMs: -1,
        statusCode: 0,
        timestamp: timestamp,
        totalMs: -1,
        error: e.toString(),
      );
    }
  }

  /// Run full TTFB test with multiple samples
  Stream<TtfbResult> runTest({
    required String url,
    required int samples,
    required Duration delayBetweenSamples,
    int startSample = 1,
  }) async* {
    for (int i = startSample; i <= samples; i++) {
      final result = await measureTtfb(url: url, sampleNumber: i);
      yield result;

      if (i < samples) {
        await Future.delayed(delayBetweenSamples);
      }
    }
  }

  /// Run TTFB tests for multiple URLs
  Stream<TtfbResult> runMultiTargetTest({
    required List<String> urls,
    required int samplesPerTarget,
    required Duration delayBetweenSamples,
    int startTargetIndex = 0,
    int startSample = 1,
  }) async* {
    for (int index = startTargetIndex; index < urls.length; index++) {
      final url = urls[index];
      await for (final result in runTest(
        url: url,
        samples: samplesPerTarget,
        delayBetweenSamples: delayBetweenSamples,
        startSample: index == startTargetIndex ? startSample : 1,
      )) {
        yield result;
      }
    }
  }

  void dispose() {
    _client.close();
  }

  Future<double?> _measureConnectTime({
    required Uri uri,
    required Duration timeout,
  }) async {
    final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    final connectTimeout = timeout < const Duration(seconds: 10)
        ? timeout
        : const Duration(seconds: 10);
    final stopwatch = Stopwatch()..start();

    try {
      if (uri.scheme == 'https') {
        final socket = await SecureSocket.connect(
          uri.host,
          port,
          timeout: connectTimeout,
        );
        stopwatch.stop();
        await socket.close();
        return stopwatch.elapsedMicroseconds / 1000;
      }

      final socket = await Socket.connect(
        uri.host,
        port,
        timeout: connectTimeout,
      );
      stopwatch.stop();
      await socket.close();
      return stopwatch.elapsedMicroseconds / 1000;
    } catch (_) {
      return null;
    }
  }
}
