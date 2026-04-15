// payment_reconciliation_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/tenant_service.dart';
import '../../../core/services/discord_service.dart';
import '../../../core/utils/ist_time.dart';
import '../../../core/utils/currency.dart';
import '../../../shared/widgets/widgets.dart';

class PaymentReconciliationScreen extends ConsumerStatefulWidget {
  final String shiftId;
  const PaymentReconciliationScreen({super.key, required this.shiftId});

  @override
  ConsumerState<PaymentReconciliationScreen> createState() =>
      _PaymentReconciliationScreenState();
}

class _PaymentReconciliationScreenState
    extends ConsumerState<PaymentReconciliationScreen> {
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  Map<String, dynamic>? _shift;
  List<dynamic> _paymentRecords = [];
  final Map<String, TextEditingController> _amountControllers = {};

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    for (final c in _amountControllers.values) c.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = TenantService.instance.client;
      final shift = await db
          .from('Shift')
          .select(
              'id, status, sale_amount, created_at, closed_at, pump:Pump(name), assigned_worker:User(full_name), nozzle_entries:NozzleEntry(id, opening_reading, closing_reading, nozzle:Nozzle(label, fuel_type)), payment_records:PaymentRecord(id, payment_mode, amount, status, mismatch_reason)')
          .eq('id', widget.shiftId)
          .single();

      // PaymentRecord is one row per shift (not a list of per-method rows)
      // Display as single structured record with UPI/cash/card amounts
      final pr = shift['payment_record'] as Map<String, dynamic>?;
      if (pr != null) {
        final prId = pr['id'] as String;
        _amountControllers[prId] = TextEditingController(
          text: (pr['actual_cash_collected_amount'] ?? pr['cash_to_collect'])
                  ?.toString() ??
              '0',
        );
      }

      setState(() {
        _shift = shift;
        _paymentRecords = pr != null ? [pr] : [];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  double get _totalSale {
    final pr = _shift?['payment_record'] as Map?;
    if (pr != null)
      return double.tryParse(pr['total_sale_amount']?.toString() ?? '0') ?? 0;
    // Fallback: sum nozzle entries
    return (_shift?['nozzle_entries'] as List? ?? []).fold<double>(
        0,
        (s, e) =>
            s +
            (double.tryParse((e as Map)['sale_amount']?.toString() ?? '0') ??
                0));
  }

  double get _totalCollected => _amountControllers.values
      .fold(0, (sum, c) => sum + (double.tryParse(c.text) ?? 0));

  double get _difference => _totalCollected - _totalSale;

  Future<void> _settle() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Settle Shift',
      message:
          'This will mark the shift as settled. Difference: ${IndianCurrency.format(_difference)}. Continue?',
      confirmLabel: 'Settle',
      isDanger: _difference.abs() > 100,
    );
    if (!confirmed) return;

    setState(() => _submitting = true);
    try {
      final db = TenantService.instance.client;
      final user = ref.read(currentUserProvider)!;
      final stationName = ref.read(stationNameProvider);

      // Update payment records
      for (final p in _paymentRecords) {
        final key = p['id'] as String;
        final amount =
            double.tryParse(_amountControllers[key]?.text ?? '0') ?? 0;
        // PaymentRecord settlement: mark as balanced
        // (actual update logic depends on which payment type)
      }

      // Close the shift
      await db.from('Shift').update({
        'status': 'SETTLED',
        'closed_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', widget.shiftId);

      // Discord alert
      await DiscordService.instance.sendShiftClosed(
        pumpName:
            (_shift!['pump'] as Map?)?['name'] as String? ?? 'Unknown Pump',
        saleAmount: _totalSale,
        workerName:
            (_shift!['assigned_worker'] as Map?)?['full_name'] as String? ??
                'Unknown',
        stationName: stationName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Shift settled successfully'),
            backgroundColor: AppColors.green,
          ),
        );
        context.go('/app/shifts');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingView());
    if (_error != null)
      return Scaffold(body: ErrorView(message: _error!, onRetry: _fetch));

    final pumpName =
        (_shift!['pump'] as Map?)?['name'] as String? ?? 'Unknown Pump';
    final workerName =
        (_shift!['assigned_worker'] as Map?)?['full_name'] as String? ??
            'Unassigned';
    final status = _shift!['status'] as String? ?? '';
    final isSettled = status == 'SETTLED';

    return Scaffold(
      backgroundColor: AppColors.bgApp,
      appBar: AppBar(
        title: Text('Reconcile — $pumpName'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => context.go('/app/shifts'),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Shift summary
                AppCard(
                  child: Column(
                    children: [
                      _InfoRow('Worker', workerName),
                      _InfoRow('Status', status),
                      _InfoRow(
                          'Started',
                          IstTime.formatDateTime(
                              DateTime.parse(_shift!['created_at']))),
                      if (_shift!['closed_at'] != null)
                        _InfoRow(
                            'Closed',
                            IstTime.formatDateTime(
                                DateTime.parse(_shift!['closed_at']))),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Nozzle totals
                const SectionHeader(title: 'Nozzle Summary'),
                const SizedBox(height: 12),
                ...(_shift!['nozzle_entries'] as List? ?? []).map((e) {
                  final opening = double.tryParse(
                          e['opening_reading']?.toString() ?? '0') ??
                      0;
                  final closing = double.tryParse(
                          e['closing_reading']?.toString() ?? '0') ??
                      0;
                  final vol = (closing - opening).clamp(0, double.infinity);
                  final nozzle = e['nozzle'] as Map? ?? {};
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(nozzle['label'] as String? ?? '',
                                    style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.w600)),
                                Text(nozzle['fuel_type'] as String? ?? '',
                                    style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 12)),
                              ],
                            ),
                          ),
                          Text(IndianCurrency.formatLitres(vol),
                              style: const TextStyle(
                                  color: AppColors.blue,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  );
                }),

                const SizedBox(height: 16),
                const SectionHeader(title: 'Payment Collection'),
                const SizedBox(height: 12),

                // Payment method inputs
                ..._paymentRecords.map((p) {
                  final key = p['id'] as String;
                  final method = p['payment_mode'] as String? ?? '';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(method,
                              style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w500)),
                        ),
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: _amountControllers[key],
                            enabled: !isSettled,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            textAlign: TextAlign.right,
                            onChanged: (_) => setState(() {}),
                            style: const TextStyle(
                                color: AppColors.textPrimary, fontSize: 14),
                            decoration: InputDecoration(
                              prefixText: '₹ ',
                              prefixStyle:
                                  const TextStyle(color: AppColors.textMuted),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                      color: AppColors.border)),
                              enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                      color: AppColors.border)),
                              focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                      color: AppColors.blue, width: 1.5)),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              filled: true,
                              fillColor: AppColors.bgCard,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),

                // Totals
                const SizedBox(height: 8),
                AppCard(
                  borderColor: _difference.abs() < 1
                      ? AppColors.green.withValues(alpha: 0.3)
                      : AppColors.amber.withValues(alpha: 0.3),
                  child: Column(
                    children: [
                      _InfoRow('Total Sale', IndianCurrency.format(_totalSale)),
                      _InfoRow('Total Collected',
                          IndianCurrency.format(_totalCollected)),
                      const Divider(color: AppColors.border, height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Difference',
                              style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w700)),
                          Text(
                            IndianCurrency.format(_difference),
                            style: TextStyle(
                              color: _difference.abs() < 1
                                  ? AppColors.green
                                  : AppColors.amber,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!isSettled)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: AppColors.bgSurface,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: AppButton(
                label: 'Settle Shift',
                onTap: _settle,
                loading: _submitting,
                width: double.infinity,
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
          Text(value,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

double _d(dynamic v) {
  if (v == null) return 0.0;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0.0;
}
