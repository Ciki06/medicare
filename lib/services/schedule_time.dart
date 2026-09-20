import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// All care-circle schedules use Malaysia time, independent of phone settings.
class ScheduleTime {
  static const zone = 'Asia/Kuala_Lumpur';
  static const zoneLabel = 'Malaysia time (UTC+08:00)';
  static final tz.Location location = _location();
  static tz.Location _location() {
    tzdata.initializeTimeZones();
    return tz.getLocation(zone);
  }

  static tz.TZDateTime now() => tz.TZDateTime.now(location);
  static String today() => dateKey(now());
  static tz.TZDateTime startOfToday() {
    final current = now();
    return tz.TZDateTime(location, current.year, current.month, current.day);
  }

  static String dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static ({int hour, int minute})? parse(String value) {
    final match = RegExp(
      r'^(\d{1,2}):(\d{2})\s*(AM|PM)?$',
      caseSensitive: false,
    ).firstMatch(value.trim());
    if (match == null) return null;
    var hour = int.parse(match[1]!);
    final minute = int.parse(match[2]!);
    final period = match[3]?.toUpperCase();
    if (minute > 59 || (period == null ? hour > 23 : hour < 1 || hour > 12)) {
      return null;
    }
    if (period != null) hour = hour % 12 + (period == 'PM' ? 12 : 0);
    return (hour: hour, minute: minute);
  }

  static String normalize(String value) {
    final t = parse(value);
    return t == null
        ? value
        : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  static String display(String value) {
    final t = parse(value);
    if (t == null) return value;
    return '${t.hour % 12 == 0 ? 12 : t.hour % 12}:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  static tz.TZDateTime? onDate(String value, DateTime date) {
    final t = parse(value);
    return t == null
        ? null
        : tz.TZDateTime(
            location,
            date.year,
            date.month,
            date.day,
            t.hour,
            t.minute,
          );
  }
}
