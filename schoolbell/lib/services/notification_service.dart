import 'dart:typed_data';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static const _alertChannelId = 'schoolbell_alerts';
  static final _plugin = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: androidSettings));

    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _alertChannelId,
          'SchoolBell Alerts',
          description: 'Vibration alerts 3 minutes before each class period',
          importance: Importance.high,
          enableVibration: true,
          playSound: false,
        ));
  }

  static Future<void> sendAlert(String periodLabel) async {
    final vibrationPattern = Int64List.fromList([0, 400, 200, 400, 200, 400]);
    await _plugin.show(
      1,
      'SchoolBell',
      '$periodLabel starts in 3 minutes',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _alertChannelId,
          'SchoolBell Alerts',
          importance: Importance.high,
          priority: Priority.high,
          enableVibration: true,
          vibrationPattern: vibrationPattern,
          playSound: false,
        ),
      ),
    );
  }
}
