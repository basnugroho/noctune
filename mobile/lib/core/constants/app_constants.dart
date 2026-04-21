// App Constants
class AppConstants {
  static const String appName = 'NOC Tune';
  static const String appVersion = '1.0.1';
  static const String releaseDate = 'April 20, 2026';

  // Default test settings
  static const int defaultSamplesPerTarget = 10;
  static const int defaultDelayBetweenSamples = 30; // seconds
  static const int defaultPingDuration = 60; // seconds
  static const int defaultPingCount = 60;
  static const bool defaultAutoContribute = true;
  static const bool defaultDailyReminderEnabled = false;
  static const int defaultSignalThreshold = -65;
  static const List<String> defaultDnsServers = ['8.8.8.8', '8.8.4.4'];
  static const int defaultDailyReminderHour = 19;
  static const int defaultDailyReminderMinute = 0;
  static const String dailyReminderTitle = 'Reminder TTFB Harian';
  static const String dailyReminderBody =
      'Sudahkah anda lakukan TTFB hari ini? Yuk! Tes dulu!';

  // Thresholds (ms)
  static const int goodTtfbThreshold = 600;
  static const int warningTtfbThreshold = 800;

  // Default targets
  static const List<String> defaultTargets = [
    'https://www.instagram.com',
    'https://qt-google-cloud-cdn.bronze.systems',
  ];

  // Legacy defaults used by the first mobile draft, kept for migration.
  static const List<String> legacyDefaultTargets = [
    'https://www.google.com',
    'https://www.cloudflare.com',
    'https://www.amazon.com',
  ];
  static const int legacyDefaultDelayBetweenSamples = 5;
  static const int legacyDefaultPingCount = 10;
  static const int legacyWarningTtfbThreshold = 1500;

  // API
  static const String contributeApiUrl =
      'https://qosmic.solusee.id/api/ttfb-results/insert';
}

// Network test status
enum TestStatus { idle, running, paused, completed, error }

// Result quality
enum ResultQuality { good, warning, poor }
