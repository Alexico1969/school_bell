import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/period.dart';
import 'services/location_service.dart';
import 'services/scheduler.dart';
import 'services/crash_logger.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<Period> _periods = [];
  double _lat = LocationService.defaultLat;
  double _lng = LocationService.defaultLng;
  double _radius = LocationService.defaultRadius;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final periods = await Scheduler.loadPeriods();
    setState(() {
      _periods = List.from(periods);
      _lat = prefs.getDouble('school_lat') ?? LocationService.defaultLat;
      _lng = prefs.getDouble('school_lng') ?? LocationService.defaultLng;
      _radius = prefs.getDouble('school_radius') ?? LocationService.defaultRadius;
      _loading = false;
    });
  }

  Future<void> _saveLocation() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('school_lat', _lat);
    await prefs.setDouble('school_lng', _lng);
    await prefs.setDouble('school_radius', _radius);
  }

  Future<void> _savePeriods() async {
    await Scheduler.savePeriods(_periods);
  }

  String _fmt(int hour, int minute) {
    final h = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    final m = minute.toString().padLeft(2, '0');
    final ampm = hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  Future<void> _showPeriodDialog({Period? existing, int? index}) async {
    final labelCtrl = TextEditingController(text: existing?.label ?? '');
    int hour = existing?.startHour ?? 8;
    int minute = existing?.startMinute ?? 0;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null ? 'Add Period' : 'Edit Period'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelCtrl,
                decoration: const InputDecoration(labelText: 'Label', hintText: 'e.g. Period 1'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Start time: ', style: TextStyle(fontSize: 16)),
                  TextButton(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: ctx,
                        initialTime: TimeOfDay(hour: hour, minute: minute),
                        builder: (c, child) => MediaQuery(
                          data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: false),
                          child: child!,
                        ),
                      );
                      if (picked != null) {
                        setLocal(() {
                          hour = picked.hour;
                          minute = picked.minute;
                        });
                      }
                    },
                    child: Text(
                      _fmt(hour, minute),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final label = labelCtrl.text.trim();
                if (label.isEmpty) return;
                final period = Period(label: label, startHour: hour, startMinute: minute);
                setState(() {
                  if (index != null) {
                    _periods[index] = period;
                  } else {
                    _periods.add(period);
                    _periods.sort((a, b) {
                      final aMin = a.startHour * 60 + a.startMinute;
                      final bMin = b.startHour * 60 + b.startMinute;
                      return aMin.compareTo(bMin);
                    });
                  }
                });
                _savePeriods();
                Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLocationDialog() async {
    final latCtrl = TextEditingController(text: _lat.toStringAsFixed(4));
    final lngCtrl = TextEditingController(text: _lng.toStringAsFixed(4));
    final radiusCtrl = TextEditingController(text: _radius.toStringAsFixed(0));

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('School Location'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: latCtrl,
              keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
              decoration: const InputDecoration(labelText: 'Latitude'),
            ),
            TextField(
              controller: lngCtrl,
              keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
              decoration: const InputDecoration(labelText: 'Longitude'),
            ),
            TextField(
              controller: radiusCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Radius (meters)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final lat = double.tryParse(latCtrl.text);
              final lng = double.tryParse(lngCtrl.text);
              final radius = double.tryParse(radiusCtrl.text);
              if (lat == null || lng == null || radius == null) return;
              setState(() {
                _lat = lat;
                _lng = lng;
                _radius = radius;
              });
              _saveLocation();
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _resetToDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Schedule?'),
        content: const Text('This will restore the default Molloy bell schedule.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
        ],
      ),
    );
    if (confirmed == true) {
      setState(() => _periods = List.from(Scheduler.molloyDefaults));
      await _savePeriods();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset to Molloy defaults',
            onPressed: _resetToDefaults,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showPeriodDialog(),
        tooltip: 'Add period',
        child: const Icon(Icons.add),
      ),
      body: ListView(
        children: [
          // Location tile
          ListTile(
            leading: const Icon(Icons.location_on),
            title: const Text('School Location'),
            subtitle: Text('${_lat.toStringAsFixed(4)}, ${_lng.toStringAsFixed(4)}  •  ${_radius.toStringAsFixed(0)}m radius'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showLocationDialog,
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Bell Schedule  (${_periods.length} periods)',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _periods.length,
            onReorderItem: (oldIndex, newIndex) {
              setState(() {
                final p = _periods.removeAt(oldIndex);
                _periods.insert(newIndex, p);
              });
              _savePeriods();
            },
            itemBuilder: (context, i) {
              final p = _periods[i];
              return ListTile(
                key: ValueKey('$i-${p.label}'),
                leading: const Icon(Icons.drag_handle),
                title: Text(p.label),
                subtitle: Text('${_fmt(p.startHour, p.startMinute)}  •  alert at ${_fmtAlert(p.startHour, p.startMinute)}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, size: 20),
                      onPressed: () => _showPeriodDialog(existing: p, index: i),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                      onPressed: () {
                        setState(() => _periods.removeAt(i));
                        _savePeriods();
                      },
                    ),
                  ],
                ),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.bug_report, color: Colors.red),
            title: const Text('Crash Log'),
            subtitle: const Text('View or clear recorded errors'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showCrashLog,
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Future<void> _showCrashLog() async {
    final log = await CrashLogger.read();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Crash Log'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: log.isEmpty
              ? const Center(child: Text('No crashes recorded.'))
              : SingleChildScrollView(
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
              Navigator.pop(ctx);
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () async {
              await CrashLogger.clear();
              Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Crash log cleared')),
                );
              }
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _fmtAlert(int hour, int minute) {
    final total = hour * 60 + minute - 3;
    final h = (total ~/ 60) > 12
        ? (total ~/ 60) - 12
        : (total ~/ 60 == 0 ? 12 : total ~/ 60);
    final m = (total % 60).toString().padLeft(2, '0');
    final ampm = (total ~/ 60) >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }
}
