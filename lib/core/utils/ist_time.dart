import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

/// India Standard Time utility.
/// ALL business dates/times must use this class.
/// Store UTC in DB, display IST everywhere.
class IstTime {
  IstTime._();

  static bool _initialized = false;
  static late tz.Location _ist;

  static void init() {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    _ist = tz.getLocation('Asia/Kolkata');
    _initialized = true;
  }

  /// Current IST time
  static tz.TZDateTime now() {
    init();
    return tz.TZDateTime.now(_ist);
  }

  /// Convert UTC DateTime to IST
  static tz.TZDateTime toIst(DateTime utc) {
    init();
    return tz.TZDateTime.from(utc, _ist);
  }

  /// Parse ISO string (UTC) and convert to IST
  static tz.TZDateTime parseUtc(String iso) {
    final utc = DateTime.parse(iso).toUtc();
    return toIst(utc);
  }

  /// Today's date in IST as business date string "YYYY-MM-DD"
  static String todayDate() {
    final n = now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  // ── Formatters ────────────────────────────────────────────────────────────

  /// "15 Jan 2025"
  static String formatDate(DateTime utc) {
    final ist = toIst(utc);
    return DateFormat('dd MMM yyyy').format(ist);
  }

  /// "15 Jan 2025, 2:30 PM"
  static String formatDateTime(DateTime utc) {
    final ist = toIst(utc);
    return DateFormat('dd MMM yyyy, h:mm a').format(ist);
  }

  /// "2:30 PM"
  static String formatTime(DateTime utc) {
    final ist = toIst(utc);
    return DateFormat('h:mm a').format(ist);
  }

  /// "Jan 2025"
  static String formatMonthYear(DateTime utc) {
    final ist = toIst(utc);
    return DateFormat('MMM yyyy').format(ist);
  }

  /// "15 Jan" (short, for reports)
  static String formatShortDate(DateTime utc) {
    final ist = toIst(utc);
    return DateFormat('dd MMM').format(ist);
  }

  /// "Today", "Yesterday", or "15 Jan"
  static String formatRelativeDate(DateTime utc) {
    final ist = toIst(utc);
    final todayIst = now();
    final diffDays = todayIst.difference(ist).inDays;
    if (diffDays == 0) return 'Today';
    if (diffDays == 1) return 'Yesterday';
    return DateFormat('dd MMM').format(ist);
  }

  /// Duration between two UTC times, formatted as "2h 30m"
  static String formatDuration(DateTime start, DateTime? end) {
    final endTime = end ?? DateTime.now().toUtc();
    final diff = endTime.difference(start);
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  /// For report headers - "Period: 01 Jan – 31 Jan 2025"
  static String formatPeriod(DateTime from, DateTime to) {
    return '${formatShortDate(from)} – ${formatDate(to)}';
  }
}
