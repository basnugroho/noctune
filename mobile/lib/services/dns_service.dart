import 'dart:async';
import 'dart:io';
import '../models/test_models.dart';

class DnsService {
  /// Perform DNS lookup for a domain
  Future<DnsResult> lookup({
    required String domain,
    String queryType = 'A',
  }) async {
    final timestamp = DateTime.now();
    final stopwatch = Stopwatch()..start();

    try {
      // Clean domain (remove protocol if present)
      String cleanDomain = domain
          .replaceAll(RegExp(r'^https?://'), '')
          .split('/')[0];

      List<String> answers = [];

      switch (queryType.toUpperCase()) {
        case 'A':
          final addresses = await InternetAddress.lookup(cleanDomain);
          answers = addresses
              .where((addr) => addr.type == InternetAddressType.IPv4)
              .map((addr) => addr.address)
              .toList();
          break;
        case 'AAAA':
          final addresses = await InternetAddress.lookup(cleanDomain);
          answers = addresses
              .where((addr) => addr.type == InternetAddressType.IPv6)
              .map((addr) => addr.address)
              .toList();
          break;
        default:
          final addresses = await InternetAddress.lookup(cleanDomain);
          answers = addresses.map((addr) => addr.address).toList();
      }

      stopwatch.stop();

      return DnsResult(
        domain: cleanDomain,
        queryType: queryType,
        answers: answers,
        responseTimeMs: stopwatch.elapsedMicroseconds / 1000,
        dnsServer: 'System DNS',
        timestamp: timestamp,
      );
    } catch (e) {
      stopwatch.stop();
      return DnsResult(
        domain: domain,
        queryType: queryType,
        answers: [],
        responseTimeMs: stopwatch.elapsedMicroseconds / 1000,
        dnsServer: 'System DNS',
        timestamp: timestamp,
        error: e.toString(),
      );
    }
  }

  /// Perform reverse DNS lookup
  Future<DnsResult> reverseLookup(String ipAddress) async {
    final timestamp = DateTime.now();
    final stopwatch = Stopwatch()..start();

    try {
      final addr = InternetAddress(ipAddress);
      final result = await addr.reverse();

      stopwatch.stop();

      return DnsResult(
        domain: ipAddress,
        queryType: 'PTR',
        answers: [result.host],
        responseTimeMs: stopwatch.elapsedMicroseconds / 1000,
        dnsServer: 'System DNS',
        timestamp: timestamp,
      );
    } catch (e) {
      stopwatch.stop();
      return DnsResult(
        domain: ipAddress,
        queryType: 'PTR',
        answers: [],
        responseTimeMs: stopwatch.elapsedMicroseconds / 1000,
        dnsServer: 'System DNS',
        timestamp: timestamp,
        error: e.toString(),
      );
    }
  }

  /// Get all DNS records for a domain (A and AAAA)
  Future<List<DnsResult>> getAllRecords(String domain) async {
    final results = await Future.wait([
      lookup(domain: domain, queryType: 'A'),
      lookup(domain: domain, queryType: 'AAAA'),
    ]);
    return results;
  }
}
