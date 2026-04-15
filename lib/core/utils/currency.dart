import 'package:intl/intl.dart';

/// Indian currency formatting utilities.
/// Always use ₹ symbol with Indian number system (lakhs, crores).
class IndianCurrency {
  IndianCurrency._();

  static final _currencyFmt = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  static final _currencyFmtNoDecimal = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  static final _litreFmt = NumberFormat('#,##0.00', 'en_IN');
  static final _numberFmt = NumberFormat('#,##,##0', 'en_IN');
  static final _compactFmt = NumberFormat.compact(locale: 'en_IN');

  /// "₹1,23,456.78"
  static String format(num amount) => _currencyFmt.format(amount);

  /// "₹1,23,456" (no decimal)
  static String formatInt(num amount) => _currencyFmtNoDecimal.format(amount);

  /// "₹1.2L", "₹3.4Cr" - for dashboard KPIs
  static String formatCompact(num amount) {
    if (amount.abs() >= 10000000) {
      return '₹${(amount / 10000000).toStringAsFixed(2)}Cr';
    }
    if (amount.abs() >= 100000) {
      return '₹${(amount / 100000).toStringAsFixed(2)}L';
    }
    if (amount.abs() >= 1000) {
      return '₹${(amount / 1000).toStringAsFixed(1)}K';
    }
    return format(amount);
  }

  /// "1,234.56 L" for fuel litres
  static String formatLitres(num litres) => '${_litreFmt.format(litres)} L';

  /// "1,23,456" for number (Indian format)
  static String formatNumber(num n) => _numberFmt.format(n);

  /// Parse "₹1,23,456.78" → 123456.78
  static double parse(String s) {
    final clean = s.replaceAll(RegExp(r'[₹,\s]'), '');
    return double.tryParse(clean) ?? 0.0;
  }

  /// Color for amount: green if positive, red if negative
  static bool isPositive(num amount) => amount >= 0;
}
