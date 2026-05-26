import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'services/notification_service.dart';
import 'services/scheduler.dart';
import 'home_screen.dart';

@pragma('vm:entry-point')
void onBackgroundServiceStart(ServiceInstance service) async {
  await NotificationService.init();

  service.on('stopService').listen((_) => service.stopSelf());

  // Check schedule every 30 seconds
  Timer.periodic(const Duration(seconds: 30), (_) async {
    await Scheduler.tick();
  });
}

Future<void> _initBackgroundService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onBackgroundServiceStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'schoolbell_service',
      initialNotificationTitle: 'SchoolBell',
      initialNotificationContent: 'Monitoring class schedule',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(autoStart: false),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  await _initBackgroundService();
  runApp(const SchoolBellApp());
}

class SchoolBellApp extends StatelessWidget {
  const SchoolBellApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SchoolBell',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
