import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/constants/app_constants.dart';

class RuntimeSupportService {
  static const int _completionNotificationId = 1001;
  static const int _dailyReminderNotificationId = 1900;
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'test_status',
    'Test Status',
    description: 'Notifications for completed network tests',
    importance: Importance.high,
  );

  static const AndroidNotificationChannel _reminderChannel =
      AndroidNotificationChannel(
        'daily_reminder',
        'Daily Reminder',
        description: 'Daily reminder to run the TTFB test',
        importance: Importance.high,
      );

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  bool _isTimezoneInitialized = false;

  Future<void> ensureInitialized() async {
    if (_isInitialized) {
      return;
    }

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        defaultPresentAlert: true,
        defaultPresentBadge: true,
        defaultPresentSound: true,
      ),
    );

    await _notifications.initialize(initializationSettings);

    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);

    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_reminderChannel);

    await _configureLocalTimezone();

    _isInitialized = true;
  }

  Future<bool> requestNotificationPermissions() async {
    await ensureInitialized();

    final androidGranted = await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    final iosGranted = await _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    return (androidGranted ?? true) && (iosGranted ?? true);
  }

  Future<void> setKeepAwake(bool enabled) async {
    if (enabled) {
      await WakelockPlus.enable();
      return;
    }
    await WakelockPlus.disable();
  }

  Future<void> showCompletionNotification({
    required String title,
    required String body,
  }) async {
    await ensureInitialized();

    const notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        'test_status',
        'Test Status',
        channelDescription: 'Notifications for completed network tests',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _notifications.show(
      _completionNotificationId,
      title,
      body,
      notificationDetails,
    );
  }

  Future<bool> syncDailyTtfbReminder({
    required bool enabled,
    bool requestPermissions = false,
  }) async {
    await ensureInitialized();

    await _notifications.cancel(_dailyReminderNotificationId);
    if (!enabled) {
      return false;
    }

    if (requestPermissions) {
      final granted = await requestNotificationPermissions();
      if (!granted) {
        return false;
      }
    }

    final scheduledAt = _nextReminderDateTime();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'daily_reminder',
        'Daily Reminder',
        channelDescription: 'Daily reminder to run the TTFB test',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _notifications.zonedSchedule(
      _dailyReminderNotificationId,
      AppConstants.dailyReminderTitle,
      AppConstants.dailyReminderBody,
      scheduledAt,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );

    return true;
  }

  Future<void> _configureLocalTimezone() async {
    if (_isTimezoneInitialized) {
      return;
    }

    tz.initializeTimeZones();
    try {
      final timezoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezoneName));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }
    _isTimezoneInitialized = true;
  }

  tz.TZDateTime _nextReminderDateTime() {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      AppConstants.defaultDailyReminderHour,
      AppConstants.defaultDailyReminderMinute,
    );

    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    return scheduled;
  }
}
