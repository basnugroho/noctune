import 'dart:io';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart' as nip;
import 'package:permission_handler/permission_handler.dart';
import '../core/constants/app_constants.dart';
import '../models/test_models.dart';

class NetworkInfoService {
  static const MethodChannel _deviceChannel = MethodChannel(
    'noc_tune/device_info',
  );

  final Connectivity _connectivity = Connectivity();
  final nip.NetworkInfo _networkInfo = nip.NetworkInfo();
  final http.Client _client = http.Client();

  /// Get current network information
  Future<AppNetworkInfo> getNetworkInfo({
    bool requestPermissions = false,
  }) async {
    String? ssid;
    String? bssid;
    String? ipAddress;
    String? connectionType;
    bool locationPermissionGranted = false;
    AppLocationInfo? locationInfo;
    String? publicIp;
    String? isp;
    String? fallbackCity;
    String? fallbackRegion;
    String? fallbackCountry;
    String? deviceName;
    String? deviceModel;
    String? osName;
    String? osVersion;
    int? batteryLevel;
    bool? batteryCharging;
    int? wifiRssi;
    String? wifiBand;
    int? wifiChannel;
    List<String> dnsServers = const [];
    String? dnsPrimary;

    try {
      // Check connectivity type
      final connectivityResults = await _connectivity.checkConnectivity();
      final connectivityResult = _selectPrimaryConnectivity(
        connectivityResults,
      );
      connectionType = _mapConnectivityType(connectivityResult);

      // Get WiFi info (requires location permission on Android)
      if (connectivityResult == ConnectivityResult.wifi) {
        // Request location permission for WiFi info (required on Android)
        if (Platform.isAndroid) {
          final status = requestPermissions
              ? await Permission.location.request()
              : await Permission.location.status;
          if (status.isGranted) {
            locationPermissionGranted = true;
            ssid = await _networkInfo.getWifiName();
            bssid = await _networkInfo.getWifiBSSID();
          }
        } else {
          locationPermissionGranted = await _hasLocationPermission(
            requestPermissions: requestPermissions,
          );
          if (locationPermissionGranted) {
            final wifiIdentity = await _readWifiIdentity();
            ssid = wifiIdentity.$1;
            bssid = wifiIdentity.$2;
          }
        }

        // Clean SSID (remove quotes if present)
        if (ssid != null) {
          ssid = ssid.replaceAll('"', '');
        }
      }

      // Get IP address
      ipAddress = await _networkInfo.getWifiIP();

      final ipProfile = await _getPublicIpProfile();
      publicIp = ipProfile.ip;
      isp = ipProfile.isp;
      fallbackCity = ipProfile.city;
      fallbackRegion = ipProfile.region;
      fallbackCountry = ipProfile.country;

      final locationPayload = await _getCurrentLocation(
        requestPermissions: requestPermissions,
      );
      locationPermissionGranted =
          locationPermissionGranted || locationPayload.permissionGranted;
      locationInfo = locationPayload.location;

      if (connectivityResult == ConnectivityResult.wifi &&
          locationPermissionGranted &&
          (ssid == null || ssid.isEmpty)) {
        final wifiIdentity = await _readWifiIdentity();
        ssid = wifiIdentity.$1 ?? ssid;
        bssid = wifiIdentity.$2 ?? bssid;
      }

      if (locationInfo == null &&
          (fallbackCity != null ||
              fallbackRegion != null ||
              fallbackCountry != null)) {
        locationInfo = AppLocationInfo(
          city: fallbackCity,
          region: fallbackRegion,
          country: fallbackCountry,
          browserTimestamp: DateTime.now(),
          savedAt: DateTime.now(),
          source: 'ipwho.is',
          method: 'ip-geolocation',
          isPrecise: false,
        );
      }

      final deviceContext = await _getDeviceContext();
      deviceName = deviceContext.deviceName;
      deviceModel = deviceContext.deviceModel;
      osName = deviceContext.osName;
      osVersion = deviceContext.osVersion;
      ssid = deviceContext.ssid ?? ssid;
      bssid = deviceContext.bssid ?? bssid;
      connectionType = _preferConnectivityType(
        nativeType: deviceContext.connectivityType,
        flutterType: connectionType,
      );
      batteryLevel = deviceContext.batteryLevel;
      batteryCharging = deviceContext.batteryCharging;
      wifiRssi = deviceContext.wifiRssi;
      wifiBand = deviceContext.wifiBand;
      wifiChannel = deviceContext.wifiChannel;
      dnsServers = deviceContext.dnsServers;
      dnsPrimary = deviceContext.dnsPrimary;

      if (Platform.isIOS &&
          connectionType == 'WiFi' &&
          wifiBand == null &&
          ((ssid != null && ssid.isNotEmpty) || wifiRssi != null)) {
        wifiBand = 'Unavailable (iOS API limit)';
      }

      debugPrint(
        'Network info snapshot: os=$osName, deviceModel=$deviceModel, '
        'ssid=$ssid, batteryLevel=$batteryLevel, wifiBand=$wifiBand, '
        'locationCity=${locationInfo?.city}, locationLat=${locationInfo?.latitude}',
      );

      if ((connectionType == null || connectionType == 'Unknown') &&
          ((ssid != null && ssid.isNotEmpty) || wifiRssi != null)) {
        connectionType = 'WiFi';
      }

      connectionType = _resolveFinalConnectivityType(
        connectionType: connectionType,
        hasWifiIdentity: (ssid != null && ssid.isNotEmpty) || wifiRssi != null,
        hasInternetPath:
            (publicIp != null && publicIp.isNotEmpty) ||
            (ipAddress != null && ipAddress.isNotEmpty),
      );
    } catch (e) {
      // Silently handle errors
    }

    final signalStatus = _buildSignalStatus(
      connectionType: connectionType,
      hasLocalIp: ipAddress != null && ipAddress.isNotEmpty,
      wifiRssi: wifiRssi,
    );

    return AppNetworkInfo(
      deviceName:
          deviceName ??
          (Platform.isAndroid ? 'Android' : Platform.operatingSystem),
      deviceModel: deviceModel,
      osName:
          osName ?? (Platform.isAndroid ? 'Android' : Platform.operatingSystem),
      osVersion: osVersion ?? Platform.operatingSystemVersion,
      batteryLevel: batteryLevel,
      batteryCharging: batteryCharging,
      ssid: ssid,
      bssid: bssid,
      ipAddress: ipAddress,
      publicIp: publicIp,
      isp: isp,
      connectionType: connectionType,
      wifiRssi: wifiRssi,
      wifiBand: wifiBand,
      wifiChannel: wifiChannel,
      signalThreshold: AppConstants.defaultSignalThreshold,
      signalStatus: signalStatus,
      dnsServers: dnsServers,
      dnsPrimary: dnsPrimary,
      location: locationInfo,
      locationPermissionGranted: locationPermissionGranted,
      timestamp: DateTime.now(),
    );
  }

  /// Check if device is connected to the internet
  Future<bool> isConnected() async {
    final connectivityResults = await _connectivity.checkConnectivity();
    final result = connectivityResults.isNotEmpty
        ? connectivityResults.first
        : ConnectivityResult.none;
    return result != ConnectivityResult.none;
  }

  /// Listen to connectivity changes
  Stream<ConnectivityResult> get connectivityStream =>
      _connectivity.onConnectivityChanged.map(
        (results) =>
            results.isNotEmpty ? results.first : ConnectivityResult.none,
      );

  /// Get local IP address
  Future<String?> getLocalIpAddress() async {
    try {
      return await _networkInfo.getWifiIP();
    } catch (e) {
      return null;
    }
  }

  /// Get gateway IP address
  Future<String?> getGatewayIp() async {
    try {
      return await _networkInfo.getWifiGatewayIP();
    } catch (e) {
      return null;
    }
  }

  Future<_LocationPayload> _getCurrentLocation({
    required bool requestPermissions,
  }) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return const _LocationPayload(permissionGranted: false);
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && requestPermissions) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return const _LocationPayload(permissionGranted: false);
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      String? city;
      String? region;
      String? country;
      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final placemark = placemarks.first;
          city = placemark.locality ?? placemark.subAdministrativeArea;
          region = placemark.administrativeArea;
          country = placemark.country;
        }
      } catch (_) {}

      final now = DateTime.now();
      return _LocationPayload(
        permissionGranted: true,
        location: AppLocationInfo(
          latitude: position.latitude,
          longitude: position.longitude,
          accuracy: _sanitizeNonNegativeDouble(position.accuracy),
          altitude: position.altitude,
          altitudeAccuracy: _sanitizeNonNegativeDouble(
            position.altitudeAccuracy,
          ),
          heading: _sanitizeHeading(position.heading),
          speed: _sanitizeNonNegativeDouble(position.speed),
          city: city,
          region: region,
          country: country,
          browserTimestamp: position.timestamp,
          savedAt: now,
          source: 'device',
          method: 'geolocator',
          isPrecise: position.accuracy <= 50,
        ),
      );
    } catch (_) {
      return const _LocationPayload(permissionGranted: false);
    }
  }

  Future<bool> _hasLocationPermission({
    required bool requestPermissions,
  }) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && requestPermissions) {
        permission = await Geolocator.requestPermission();
      }

      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  Future<(String?, String?)> _readWifiIdentity() async {
    try {
      final wifiName = await _networkInfo.getWifiName();
      final wifiBssid = await _networkInfo.getWifiBSSID();
      final cleanedName = wifiName?.replaceAll('"', '');
      return (cleanedName, wifiBssid);
    } catch (_) {
      return (null, null);
    }
  }

  double? _sanitizeNonNegativeDouble(double value) {
    if (value.isNaN || value.isInfinite || value < 0) {
      return null;
    }
    return value;
  }

  double? _sanitizeHeading(double value) {
    if (value.isNaN || value.isInfinite || value < 0) {
      return null;
    }

    if (value >= 360) {
      return value % 360;
    }

    return value;
  }

  Future<_PublicIpProfile> _getPublicIpProfile() async {
    try {
      final response = await _client
          .get(
            Uri.parse('https://ipwho.is/'),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const _PublicIpProfile();
      }

      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) {
        return const _PublicIpProfile();
      }

      final connection = body['connection'];
      final connectionMap = connection is Map<String, dynamic>
          ? connection
          : const <String, dynamic>{};

      return _PublicIpProfile(
        ip: body['ip']?.toString(),
        isp: connectionMap['isp']?.toString(),
        city: body['city']?.toString(),
        region: body['region']?.toString(),
        country: body['country']?.toString(),
      );
    } catch (_) {
      return const _PublicIpProfile();
    }
  }

  Future<_DeviceContext> _getDeviceContext() async {
    try {
      final result = await _deviceChannel.invokeMapMethod<String, dynamic>(
        'getDeviceContext',
      );
      if (result == null) {
        return const _DeviceContext();
      }

      return _DeviceContext(
        deviceName: result['deviceName']?.toString(),
        deviceModel: result['deviceModel']?.toString(),
        osName: result['osName']?.toString(),
        osVersion: result['osVersion']?.toString(),
        connectivityType: result['connectivityType']?.toString(),
        batteryLevel: (result['batteryLevel'] as num?)?.toInt(),
        batteryCharging: result['batteryCharging'] as bool?,
        ssid: result['ssid']?.toString(),
        bssid: result['bssid']?.toString(),
        wifiRssi: (result['wifiRssi'] as num?)?.toInt(),
        wifiBand: result['wifiBand']?.toString(),
        wifiChannel: (result['wifiChannel'] as num?)?.toInt(),
        dnsPrimary: result['dnsPrimary']?.toString(),
        dnsServers: (result['dnsServers'] as List<dynamic>? ?? const [])
            .map((value) => value.toString())
            .where((value) => value.isNotEmpty)
            .toList(),
      );
    } catch (_) {
      return _DeviceContext(
        deviceName: Platform.operatingSystem,
        osName: Platform.operatingSystem,
        osVersion: Platform.operatingSystemVersion,
      );
    }
  }

  ConnectivityResult _selectPrimaryConnectivity(
    List<ConnectivityResult> connectivityResults,
  ) {
    if (connectivityResults.contains(ConnectivityResult.wifi)) {
      return ConnectivityResult.wifi;
    }
    if (connectivityResults.contains(ConnectivityResult.mobile)) {
      return ConnectivityResult.mobile;
    }
    if (connectivityResults.contains(ConnectivityResult.ethernet)) {
      return ConnectivityResult.ethernet;
    }
    if (connectivityResults.contains(ConnectivityResult.vpn)) {
      return ConnectivityResult.vpn;
    }
    if (connectivityResults.contains(ConnectivityResult.other)) {
      return ConnectivityResult.other;
    }
    return ConnectivityResult.none;
  }

  String? _preferConnectivityType({
    required String? nativeType,
    required String? flutterType,
  }) {
    if (nativeType == null || nativeType.isEmpty || nativeType == 'Unknown') {
      return flutterType;
    }
    return nativeType;
  }

  String? _resolveFinalConnectivityType({
    required String? connectionType,
    required bool hasWifiIdentity,
    required bool hasInternetPath,
  }) {
    if (hasWifiIdentity) {
      return 'WiFi';
    }

    if (connectionType == 'Cellular' || connectionType == 'Fixed') {
      return connectionType;
    }

    if (Platform.isAndroid && hasInternetPath) {
      return 'Cellular';
    }

    return connectionType;
  }

  String? _mapConnectivityType(ConnectivityResult connectivityResult) {
    switch (connectivityResult) {
      case ConnectivityResult.wifi:
        return 'WiFi';
      case ConnectivityResult.mobile:
        return 'Cellular';
      case ConnectivityResult.ethernet:
        return 'Fixed';
      case ConnectivityResult.none:
        return 'No Connection';
      default:
        return 'Unknown';
    }
  }

  String? _buildSignalStatus({
    required String? connectionType,
    required bool hasLocalIp,
    required int? wifiRssi,
  }) {
    if (connectionType == null || connectionType == 'No Connection') {
      return 'offline';
    }
    if (wifiRssi != null) {
      if (wifiRssi >= -60) {
        return 'strong';
      }
      if (wifiRssi >= AppConstants.defaultSignalThreshold) {
        return 'good';
      }
      return 'weak';
    }
    if (!hasLocalIp) {
      return 'unknown';
    }
    return 'connected';
  }

  void dispose() {
    _client.close();
  }
}

class _LocationPayload {
  final bool permissionGranted;
  final AppLocationInfo? location;

  const _LocationPayload({required this.permissionGranted, this.location});
}

class _PublicIpProfile {
  final String? ip;
  final String? isp;
  final String? city;
  final String? region;
  final String? country;

  const _PublicIpProfile({
    this.ip,
    this.isp,
    this.city,
    this.region,
    this.country,
  });
}

class _DeviceContext {
  final String? deviceName;
  final String? deviceModel;
  final String? osName;
  final String? osVersion;
  final String? connectivityType;
  final int? batteryLevel;
  final bool? batteryCharging;
  final String? ssid;
  final String? bssid;
  final int? wifiRssi;
  final String? wifiBand;
  final int? wifiChannel;
  final String? dnsPrimary;
  final List<String> dnsServers;

  const _DeviceContext({
    this.deviceName,
    this.deviceModel,
    this.osName,
    this.osVersion,
    this.connectivityType,
    this.batteryLevel,
    this.batteryCharging,
    this.ssid,
    this.bssid,
    this.wifiRssi,
    this.wifiBand,
    this.wifiChannel,
    this.dnsPrimary,
    this.dnsServers = const [],
  });
}
