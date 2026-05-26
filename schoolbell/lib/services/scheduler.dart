import 'package:shared_preferences/shared_preferences.dart';
import '../models/period.dart';
import 'location_service.dart';
import 'notification_service.dart';

class Scheduler {
  static const _periodsKey = 'periods';
  static const _alertedKey = 'alerted_periods';
  static const _alertedDateKey = 'alerted_date';

  // Real Archbishop Molloy HS bell schedule
  static const List<Period> molloyDefaults = [
    Period(label: 'Period 1', startHour: 8, startMinute: 0),
    Period(label: 'Homeroom', startHour: 8, startMinute: 45),
    Period(label: 'Period 2', startHour: 8, startMinute: 59),
    Period(label: 'Period 3', startHour: 9, startMinute: 44),
    Period(label: 'Period 4', startHour: 10, startMinute: 29),
    Period(label: 'Period 5', startHour: 11, startMinute: 14),
    Period(label: 'Period 6', startHour: 11, startMinute: 59),
    Period(label: 'Period 7', startHour: 12, startMinute: 44),
    Period(label: 'Period 8', startHour: 13, startMinute: 29),
  ];

  static Future<List<Period>> loadPeriods() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_periodsKey);
    if (raw == null) return molloyDefaults;
    try {
      return Period.listFromJsonString(raw);
    } catch (_) {
      return molloyDefaults;
    }
  }

  static Future<void> savePeriods(List<Period> periods) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_periodsKey, Period.listToJsonString(periods));
  }

  // Called every 30 seconds by the background service
  static Future<void> tick() async {
    final now = DateTime.now();

    // Only Mon–Fri
    if (now.weekday > DateTime.friday) return;

    // Only during school hours (7:30 AM – 3:00 PM)
    final minuteOfDay = now.hour * 60 + now.minute;
    if (minuteOfDay < 450 || minuteOfDay > 900) return;

    final atSchool = await LocationService.isAtSchool();
    if (!atSchool) return;

    final prefs = await SharedPreferences.getInstance();

    // Reset alerted list each new day
    final today = '${now.year}-${now.month}-${now.day}';
    if (prefs.getString(_alertedDateKey) != today) {
      await prefs.setStringList(_alertedKey, []);
      await prefs.setString(_alertedDateKey, today);
    }

    final alerted = prefs.getStringList(_alertedKey) ?? [];
    final periods = await loadPeriods();

    for (final period in periods) {
      if (alerted.contains(period.label)) continue;

      final alertTime = period.alertTimeFor(now);
      // Fire if we're within the 2-minute window after the alert time
      if (now.isAfter(alertTime) &&
          now.isBefore(alertTime.add(const Duration(minutes: 2)))) {
        await NotificationService.sendAlert(period.label);
        alerted.add(period.label);
        await prefs.setStringList(_alertedKey, alerted);
        break;
      }
    }
  }
}
