/// Form validation helpers used across all screens.
class Validators {
  Validators._();

  static String? required(String? v, [String field = 'This field']) {
    if (v == null || v.trim().isEmpty) return '$field is required';
    return null;
  }

  static String? phone(String? v) {
    if (v == null || v.trim().isEmpty) return 'Phone number is required';
    final digits = v.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) return 'Enter a valid 10-digit mobile number';
    return null;
  }

  static String? amount(String? v, {bool allowZero = false}) {
    if (v == null || v.trim().isEmpty) return 'Amount is required';
    final n = double.tryParse(v.replaceAll(',', '').replaceAll('₹', '').trim());
    if (n == null) return 'Enter a valid amount';
    if (!allowZero && n <= 0) return 'Amount must be greater than 0';
    return null;
  }

  static String? positiveNumber(String? v) {
    if (v == null || v.trim().isEmpty) return 'Value is required';
    final n = double.tryParse(v.trim());
    if (n == null || n <= 0) return 'Enter a valid positive number';
    return null;
  }

  static String? minLength(String? v, int min, [String field = 'Field']) {
    if (v == null || v.trim().length < min) {
      return '$field must be at least $min characters';
    }
    return null;
  }

  static String? stationCode(String? v) {
    if (v == null || v.trim().isEmpty) return 'Station code is required';
    if (v.trim().length < 4) return 'At least 4 characters';
    if (v.trim().contains(' ')) return 'No spaces allowed';
    return null;
  }

  static String? pin(String? v) {
    if (v == null || v.trim().isEmpty) return 'PIN is required';
    final digits = v.trim();
    if (digits.length < 4 || digits.length > 6) return 'PIN must be 4–6 digits';
    if (!RegExp(r'^\d+$').hasMatch(digits)) return 'PIN must be digits only';
    return null;
  }

  static String? password(String? v) {
    if (v == null || v.isEmpty) return 'Password is required';
    if (v.length < 6) return 'Minimum 6 characters';
    return null;
  }

  static String? supabaseUrl(String? v) {
    if (v == null || v.trim().isEmpty) return 'Supabase URL is required';
    if (!v.trim().contains('supabase.co')) return 'Enter a valid Supabase project URL';
    return null;
  }

  static String? email(String? v) {
    if (v == null || v.trim().isEmpty) return null; // email optional
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(v.trim())) {
      return 'Enter a valid email address';
    }
    return null;
  }

  /// Combine multiple validators — returns first error found
  static String? Function(String?) compose(
      List<String? Function(String?)> validators) {
    return (v) {
      for (final fn in validators) {
        final err = fn(v);
        if (err != null) return err;
      }
      return null;
    };
  }
}

/// WhatsApp share helpers
class WhatsAppShare {
  WhatsAppShare._();

  /// Format a shift summary message for WhatsApp
  static String shiftSummary({
    required String pumpName,
    required String workerName,
    required double saleAmount,
    required String date,
    required String stationName,
  }) {
    return '''🏪 *$stationName*
📅 $date

*Shift Closed*
⛽ Pump: $pumpName
👤 Staff: $workerName
💰 Sale: ₹${_fmt(saleAmount)}

_Powered by FuelOS_''';
  }

  static String creditReminder({
    required String customerName,
    required double outstanding,
    required String stationName,
  }) {
    return '''Dear $customerName,

You have an outstanding credit balance of *₹${_fmt(outstanding)}* at *$stationName*.

Please clear at your earliest convenience. Thank you!

_Sent via FuelOS_''';
  }

  static String inventorySummary({
    required List<Map<String, dynamic>> tanks,
    required String stationName,
  }) {
    final lines = tanks.map((t) {
      final name = t['name'] as String? ?? '';
      final fuel = t['fuel_type'] as String? ?? '';
      final cur = double.tryParse(t['']?.toString() ?? '0') ?? 0;
      final cap = double.tryParse(t['capacity_liters']?.toString() ?? '0') ?? 0;
      final pct = cap > 0 ? (cur / cap * 100).round() : 0;
      return '• $name ($fuel): ${cur.toStringAsFixed(0)}L ($pct%)';
    }).join('\n');

    return '''🏪 *$stationName*
🛢️ *Tank Status*

$lines

_Sent via FuelOS_''';
  }

  static String _fmt(double n) =>
      n.toStringAsFixed(2).replaceAllMapped(
        RegExp(r'(\d)(?=(\d{2})+(\d)(?!\d))'),
        (m) => '${m[1]},',
      );
}
