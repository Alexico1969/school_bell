import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/scheduler.dart';
import 'services/notification_service.dart';
import 'services/crash_logger.dart';
import 'models/period.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isRunning = false;
  List<Period> _periods = [];

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _refresh();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkCrashLog());
  }

  Future<void> _checkCrashLog() async {
    final log = await CrashLogger.read();
    if (log.isEmpty || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('App crashed last time'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: SingleChildScrollView(
            child: SelectableText(
              log,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: log));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard')),
              );
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () async {
              await CrashLogger.clear();
              Navigator.pop(ctx);
            },
            child: const Text('Clear & dismiss', style: TextStyle(color: Colors.red)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }

  Future<void> _requestPermissions() async {
    await Permission.notification.request();
    await Permission.location.request();
    await Permission.locationAlways.request();
  }

  Future<void> _refresh() async {
    final running = await FlutterBackgroundService().isRunning();
    final periods = await Scheduler.loadPeriods();
    setState(() {
      _isRunning = running;
      _periods = periods;
    });
  }

  Future<void> _toggle() async {
    final service = FlutterBackgroundService();
    if (_isRunning) {
      service.invoke('stopService');
    } else {
      await service.startService();
    }
    await Future.delayed(const Duration(milliseconds: 500));
    await _refresh();
  }

  String _fmt(int hour, int minute) {
    final h = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    final m = minute.toString().padLeft(2, '0');
    final ampm = hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  String _alertFmt(int hour, int minute) {
    final total = hour * 60 + minute - 3;
    final h = (total ~/ 60) > 12
        ? (total ~/ 60) - 12
        : (total ~/ 60 == 0 ? 12 : total ~/ 60);
    final m = (total % 60).toString().padLeft(2, '0');
    final ampm = (total ~/ 60) >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('SchoolBell'),
        backgroundColor: cs.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              await _refresh();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Status card
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            decoration: BoxDecoration(
              color: _isRunning ? Colors.green.shade50 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isRunning ? Colors.green.shade300 : Colors.grey.shade300,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  _isRunning ? Icons.notifications_active : Icons.notifications_off,
                  size: 56,
                  color: _isRunning ? Colors.green.shade700 : Colors.grey,
                ),
                const SizedBox(height: 12),
                Text(
                  _isRunning ? 'Active' : 'Inactive',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: _isRunning ? Colors.green.shade700 : Colors.grey.shade600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isRunning
                      ? 'Buzzing when you\'re at school'
                      : 'Tap below to enable',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _toggle,
                  icon: Icon(_isRunning ? Icons.stop_circle : Icons.play_circle),
                  label: Text(_isRunning ? 'Disable' : 'Enable'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isRunning ? Colors.red.shade400 : Colors.green.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    await NotificationService.sendAlert('Test Period');
                  },
                  icon: const Icon(Icons.vibration, size: 18),
                  label: const Text('Test alert'),
                ),
              ],
            ),
          ),

          // Schedule list header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                const Text(
                  'Today\'s Schedule',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Spacer(),
                Text(
                  'Alert fires 3 min early',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),

          // Period list
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).padding.bottom + 24,
              ),
              itemCount: _periods.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final p = _periods[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: cs.primaryContainer,
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(color: cs.onPrimaryContainer, fontSize: 12),
                    ),
                  ),
                  title: Text(p.label),
                  subtitle: Text('Starts ${_fmt(p.startHour, p.startMinute)}'),
                  trailing: Chip(
                    label: Text(
                      _alertFmt(p.startHour, p.startMinute),
                      style: const TextStyle(fontSize: 12),
                    ),
                    backgroundColor: Colors.amber.shade50,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
