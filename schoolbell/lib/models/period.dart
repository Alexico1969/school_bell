import 'dart:convert';

class Period {
  final String label;
  final int startHour;
  final int startMinute;

  const Period({
    required this.label,
    required this.startHour,
    required this.startMinute,
  });

  DateTime alertTimeFor(DateTime date) {
    return DateTime(date.year, date.month, date.day, startHour, startMinute)
        .subtract(const Duration(minutes: 3));
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'startHour': startHour,
        'startMinute': startMinute,
      };

  factory Period.fromJson(Map<String, dynamic> json) => Period(
        label: json['label'] as String,
        startHour: json['startHour'] as int,
        startMinute: json['startMinute'] as int,
      );

  static List<Period> listFromJsonString(String s) =>
      (jsonDecode(s) as List).map((e) => Period.fromJson(e as Map<String, dynamic>)).toList();

  static String listToJsonString(List<Period> periods) =>
      jsonEncode(periods.map((p) => p.toJson()).toList());
}
