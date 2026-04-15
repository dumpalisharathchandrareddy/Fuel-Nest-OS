import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';
import '../utils/ist_time.dart';
import '../utils/currency.dart';

/// Sends Discord webhook alerts directly from the Flutter app.
/// No server needed — just HTTP POST to Discord webhook URL.
/// Matches existing discord.ts service from web app.
class DiscordService {
  DiscordService._();
  static final instance = DiscordService._();

  String? _webhookUrl;
  bool _enabled = true;

  Future<void> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    _webhookUrl = prefs.getString('discord_url');
    _enabled = prefs.getBool('discord_webhook_enabled') ?? true;
  }

  Future<void> saveConfig({
    required String webhookUrl,
    required bool enabled,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('discord_url', webhookUrl);
    await prefs.setBool('discord_webhook_enabled', enabled);
    _webhookUrl = webhookUrl;
    _enabled = enabled;
  }

  bool get isConfigured => _webhookUrl != null && _webhookUrl!.isNotEmpty;
  bool get isEnabled => _enabled && isConfigured;

  // ── Alert senders ─────────────────────────────────────────────────────────

  Future<void> sendShiftClosed({
    required String pumpName,
    required double saleAmount,
    required String workerName,
    required String stationName,
  }) async {
    await _send({
      'embeds': [
        {
          'title': '🏪 Shift Closed',
          'color': 0x4ADE80, // green
          'fields': [
            {'name': 'Station', 'value': stationName, 'inline': true},
            {'name': 'Pump', 'value': pumpName, 'inline': true},
            {'name': 'Staff', 'value': workerName, 'inline': true},
            {
              'name': 'Sale Amount',
              'value': IndianCurrency.format(saleAmount),
              'inline': true,
            },
            {
              'name': 'Closed At',
              'value': IstTime.formatDateTime(DateTime.now().toUtc()),
              'inline': true,
            },
          ],
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        }
      ],
    });
  }

  Future<void> sendFuelDelivery({
    required String fuelType,
    required double quantity,
    required double amount,
    required String stationName,
  }) async {
    await _send({
      'embeds': [
        {
          'title': '⛽ Fuel Delivery',
          'color': 0x60A5FA, // blue
          'fields': [
            {'name': 'Station', 'value': stationName, 'inline': true},
            {'name': 'Fuel Type', 'value': fuelType, 'inline': true},
            {
              'name': 'Quantity',
              'value': IndianCurrency.formatLitres(quantity),
              'inline': true,
            },
            {
              'name': 'Amount',
              'value': IndianCurrency.format(amount),
              'inline': true,
            },
            {
              'name': 'Received At',
              'value': IstTime.formatDateTime(DateTime.now().toUtc()),
              'inline': true,
            },
          ],
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        }
      ],
    });
  }

  Future<void> sendLowTankAlert({
    required String tankName,
    required String fuelType,
    required double currentStock,
    required double capacity,
    required String stationName,
  }) async {
    final pct = (currentStock / capacity * 100).round();
    await _send({
      'embeds': [
        {
          'title': '⚠️ Low Tank Alert',
          'color': 0xFBBF24, // amber
          'fields': [
            {'name': 'Station', 'value': stationName, 'inline': true},
            {'name': 'Tank', 'value': tankName, 'inline': true},
            {'name': 'Fuel Type', 'value': fuelType, 'inline': true},
            {
              'name': 'Current Stock',
              'value': '${IndianCurrency.formatLitres(currentStock)} ($pct%)',
              'inline': true,
            },
          ],
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        }
      ],
    });
  }

  Future<void> sendPayrollSettlement({
    required String staffName,
    required double amount,
    required String period,
    required String stationName,
  }) async {
    await _send({
      'embeds': [
        {
          'title': '💰 Payroll Settlement',
          'color': 0xA78BFA, // purple
          'fields': [
            {'name': 'Station', 'value': stationName, 'inline': true},
            {'name': 'Staff', 'value': staffName, 'inline': true},
            {'name': 'Period', 'value': period, 'inline': true},
            {
              'name': 'Amount Paid',
              'value': IndianCurrency.format(amount),
              'inline': true,
            },
          ],
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        }
      ],
    });
  }

  Future<void> sendBackupComplete({
    required String fileName,
    required int fileSizeKb,
    required String driveLink,
  }) async {
    await _send({
      'embeds': [
        {
          'title': '✅ Backup Complete',
          'color': 0x4ADE80,
          'fields': [
            {'name': 'File', 'value': fileName, 'inline': true},
            {
              'name': 'Size',
              'value': '${(fileSizeKb / 1024).toStringAsFixed(1)} MB',
              'inline': true,
            },
            {'name': 'Drive Link', 'value': driveLink, 'inline': false},
          ],
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        }
      ],
    });
  }

  /// Send test message to verify webhook
  Future<bool> sendTest({required String stationName}) async {
    if (!isConfigured) return false;
    try {
      await _send({
        'embeds': [
          {
            'title': '✅ FuelOS Connected',
            'description':
                'Discord alerts are working for **$stationName**. You will receive notifications for shift closings, fuel deliveries, and more.',
            'color': 0x60A5FA,
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          }
        ],
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> sendStaffChange({
    required String action,
    required String staffName,
    required String role,
    required String stationName,
  }) async {
    await _send({
      'embeds': [
        {
          'title': '👤 Staff $action',
          'color': action == 'Created' ? 0x4ADE80 : 0x60A5FA,
          'fields': [
            {'name': 'Station', 'value': stationName, 'inline': true},
            {'name': 'Name', 'value': staffName, 'inline': true},
            {'name': 'Role', 'value': role, 'inline': true},
          ],
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        }
      ],
    });
  }

  Future<void> _send(Map<String, dynamic> payload) async {
    if (!isEnabled) return;
    try {
      await http.post(
        Uri.parse(_webhookUrl!),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
    } catch (_) {
      // Discord alerts are best-effort — don't crash the app
    }
  }
}
