import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'services/notification_service.dart';
import 'services/scheduler.dart';
import 'services/crash_logger.dart';
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

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      CrashLogger.log(details.exception, details.stack ?? StackTrace.current);
    };

    ErrorWidget.builder = (details) => _CrashScreen(details: details);

    await NotificationService.init();
    await _initBackgroundService();
    runApp(const SchoolBellApp());
  }, (error, stack) {
    CrashLogger.log(error, stack);
  });
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

class _CrashScreen extends StatelessWidget {
  final FlutterErrorDetails details;
  const _CrashScreen({required this.details});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.red.shade50,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              const Text(
                'SchoolBell crashed',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                details.exceptionAsString(),
                style: TextStyle(fontSize: 14, color: Colors.red.shade800),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    details.stack.toString(),
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Error saved to crash log in Settings.\nRestart the app to continue.',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
