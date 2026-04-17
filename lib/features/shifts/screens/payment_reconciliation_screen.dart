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
  Map<String, dynamic>? _paymentRecord;

  Map<String, dynamic>? _getMap(dynamic data) {
    if (data == null) return null;
    if (data is List) {
      if (data.isEmpty) return null;
      return Map<String, dynamic>.from(data.first as Map);
    }
    return Map<String, dynamic>.from(data as Map);
  }
  final _upiCtrl = TextEditingController(text: '0');
  final _cardCtrl = TextEditingController(text: '0');
  final _creditCtrl = TextEditingController(text: '0');
  final _actualCashCtrl = TextEditingController(text: '0');
  final _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _upiCtrl.dispose();
    _cardCtrl.dispose();
    _creditCtrl.dispose();
    _actualCashCtrl.dispose();
    _noteCtrl.dispose();
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
              'id, status, created_at, closed_at, pump:Pump(name), assigned_worker:User(full_name), nozzle_entries:NozzleEntry(id, nozzle_id, opening_reading, closing_reading, testing_quantity, sale_litres, sale_amount, rate, nozzle:Nozzle(label, fuel_type, tank_id)), payment_record:PaymentRecord(id, upi_amount, card_amount, credit_amount, cash_to_collect, actual_cash_collected_amount, total_sale_amount, is_balanced)')
          .eq('id', widget.shiftId)
          .single();

      // Fetch all credit transactions for this shift to get the real total
      final credits = await db
          .from('CreditTransaction')
          .select('amount')
          .eq('shift_id', widget.shiftId);
      
      final creditTotal = (credits as List).fold<double>(0, (sum, c) => sum + (double.tryParse(c['amount']?.toString() ?? '0') ?? 0));

      // PaymentRecord is one row per shift (not a list of per-method rows)
      // Display as single structured record with UPI/cash/card amounts
      final pr = _getMap(shift['payment_record']);
      if (pr != null) {
        _upiCtrl.text = pr['upi_amount']?.toString() ?? '0';
        _cardCtrl.text = pr['card_amount']?.toString() ?? '0';
        _creditCtrl.text = creditTotal > 0 ? creditTotal.toString() : (pr['credit_amount']?.toString() ?? '0');
        _actualCashCtrl.text = (pr['actual_cash_collected_amount'] ?? pr['cash_to_collect'] ?? 0).toString();
      } else {
        _creditCtrl.text = creditTotal.toString();
      }

      setState(() {
        _shift = shift;
        _paymentRecord = pr;
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
    if (_paymentRecord != null) {
      return double.tryParse(_paymentRecord!['total_sale_amount']?.toString() ?? '0') ?? 0;
    }
    return (_shift?['nozzle_entries'] as List? ?? []).fold<double>(
        0,
        (s, e) =>
            s +
            (double.tryParse((e as Map)['sale_amount']?.toString() ?? '0') ??
                0));
  }

  double get _upi => double.tryParse(_upiCtrl.text) ?? 0;
  double get _card => double.tryParse(_cardCtrl.text) ?? 0;
  double get _credit => double.tryParse(_creditCtrl.text) ?? 0;
  double get _actualCash => double.tryParse(_actualCashCtrl.text) ?? 0;

  double get _expectedCash => _totalSale - (_upi + _card + _credit);
  double get _totalCollected => _upi + _card + _credit + _actualCash;
  double get _difference => _totalCollected - _totalSale;

  Future<void> _settle() async {
    // Ensure nozzle readings are present
    final entries = _shift?['nozzle_entries'] as List? ?? [];
    if (entries.isEmpty || entries.any((e) => e['closing_reading'] == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Cannot settle shift: Nozzle readings are missing.'),
          action: SnackBarAction(
            label: 'Enter Readings',
            onPressed: () {
              final pump = _getMap(_shift!['pump']);
              final pumpId = pump?['id'] as String? ?? '';
              if (pumpId.isNotEmpty) {
                context.push('/app/shifts/nozzle/$pumpId');
              }
            },
          ),
        ),
      );
      return;
    }

    if (_difference.abs() > 1 && _noteCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide a note for the mismatch')),
      );
      return;
    }

    final confirmed = await showConfirmDialog(
      context,
      title: 'Settle Shift',
      message:
          'This will mark the shift as settled. Difference: ${IndianCurrency.format(_difference)}. Continue?',
      confirmLabel: 'Settle',
      isDanger: _difference.abs() > 10,
    );
    if (!confirmed) return;

    setState(() => _submitting = true);
    try {
      final db = TenantService.instance.client;
      final stationName = ref.read(stationNameProvider);
      final user = ref.read(currentUserProvider)!;

      if (_paymentRecord != null) {
        await db.from('PaymentRecord').update({
          'upi_amount': _upi,
          'card_amount': _card,
          'credit_amount': _credit,
          'cash_to_collect': _expectedCash,
          'actual_cash_collected_amount': _actualCash,
          'total_sale_amount': _totalSale,
          'is_balanced': _difference.abs() < 1,
          'mismatch_amount': _difference,
          'mismatch_resolution_note': _noteCtrl.text.trim().isNotEmpty ? _noteCtrl.text.trim() : null,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', _paymentRecord!['id']);
      }

      // 1. PERFORM TANK STOCK VALIDATION & DEDUCTION (ONLY IF TRANSITIONING TO CLOSED)
      if (_shift?['status'] != 'CLOSED') {
        final entries = _shift?['nozzle_entries'] as List? ?? [];
        
        // Group by tank
        final tankSales = <String, double>{};
        for (final e in entries) {
           final nozzle = _getMap(e['nozzle']);
           final tid = nozzle?['tank_id'] as String?;
           if (tid != null) {
             final qty = double.tryParse(e['sale_litres']?.toString() ?? '0') ?? 0;
             tankSales[tid] = (tankSales[tid] ?? 0) + qty;
           }
        }

        // Validate stock
        for (final tid in tankSales.keys) {
           final needed = tankSales[tid]!;
           if (needed <= 0) continue;

           final stockData = await Future.wait<dynamic>([
             db.from('TankInitialStock').select('opening_litres').eq('tank_id', tid).eq('station_id', user.stationId).maybeSingle(),
             db.from('StockTransaction').select('quantity').eq('tank_id', tid).eq('station_id', user.stationId),
           ]);

           double currentStock = double.tryParse(stockData[0]?['opening_litres']?.toString() ?? '0') ?? 0;
           for (final tx in stockData[1] as List) {
             currentStock += double.tryParse(tx['quantity']?.toString() ?? '0') ?? 0;
           }

           if (currentStock < needed) {
             throw 'Insufficient stock in tank. Available: ${currentStock.toStringAsFixed(2)}L, Needed: ${needed.toStringAsFixed(2)}L';
           }
        }

        // Deduct stock (Insert StockTransaction)
        for (final tid in tankSales.keys) {
          final qty = tankSales[tid]!;
          if (qty <= 0) continue;

          await db.from('StockTransaction').insert({
            'station_id': user.stationId,
            'tank_id': tid,
            'type': 'SALE',
            'quantity': -qty,
            'reference_id': widget.shiftId,
            'created_at': DateTime.now().toUtc().toIso8601String(),
            'created_by_id': user.id,
          });
        }
      }

      // Close the shift
      await db.from('Shift').update({
        'status': 'CLOSED',
        'closed_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', widget.shiftId);

      // Discord alert
      await DiscordService.instance.sendShiftClosed(
        pumpName:
            (_getMap(_shift!['pump']))?['name'] as String? ?? 'Unknown Pump',
        saleAmount: _totalSale,
        workerName:
            (_getMap(_shift!['assigned_worker']))?['full_name'] as String? ??
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
        if (mounted) context.pop();
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
    final isSettled = status == 'CLOSED' || status == 'SETTLED';
    
    final user = ref.read(currentUserProvider);
    final isDealer = user?.role == 'DEALER';
    final canEdit = !isSettled || (isSettled && isDealer);

    return Scaffold(
      backgroundColor: AppColors.bgApp,
      appBar: AppBar(
        title: Text('Reconcile — $pumpName'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => context.pop(),
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
                const SectionHeader(title: 'Payment Details'),
                const SizedBox(height: 12),

                AppCard(
                  child: Column(
                    children: [
                      _PaymentInput(
                        label: 'UPI Amount',
                        controller: _upiCtrl,
                        enabled: canEdit,
                        onChanged: (_) => setState(() {}),
                      ),
                      const Divider(height: 24, color: AppColors.border),
                      _PaymentInput(
                        label: 'Card Amount',
                        controller: _cardCtrl,
                        enabled: canEdit,
                        onChanged: (_) => setState(() {}),
                      ),
                      const Divider(height: 24, color: AppColors.border),
                      _PaymentInput(
                        label: 'Credit Amount',
                        controller: _creditCtrl,
                        enabled: canEdit,
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                const SectionHeader(title: 'Cash Reconciliation'),
                const SizedBox(height: 12),

                AppCard(
                  child: Column(
                    children: [
                      _InfoRow('Total Sales', IndianCurrency.format(_totalSale)),
                      _InfoRow('Non-Cash Total', IndianCurrency.format(_upi + _card + _credit)),
                      const Divider(height: 24, color: AppColors.border),
                      _InfoRow(
                        'Expected Cash',
                        IndianCurrency.format(_expectedCash),
                        valueStyle: const TextStyle(
                          color: AppColors.blue,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'ACTUAL CASH COLLECTED',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _actualCashCtrl,
                        enabled: canEdit,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textAlign: TextAlign.center,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                        decoration: InputDecoration(
                          prefixText: '₹ ',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: AppColors.bgSurface,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),
                AppCard(
                  borderColor: _difference.abs() < 1
                      ? AppColors.green.withValues(alpha: 0.3)
                      : AppColors.red.withValues(alpha: 0.3),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Final Mismatch',
                              style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w700)),
                          Text(
                            IndianCurrency.format(_difference),
                            style: TextStyle(
                              color: _difference.abs() < 1
                                  ? AppColors.green
                                  : AppColors.red,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                      if (_difference.abs() > 1) ...[
                        const SizedBox(height: 16),
                        const Divider(height: 1, color: AppColors.border),
                        const SizedBox(height: 16),
                        const Text(
                          'MISMATCH RESOLUTION NOTE',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _noteCtrl,
                          enabled: canEdit,
                          maxLines: 2,
                          decoration: InputDecoration(
                            hintText: 'Explain the difference (mandatory)',
                            hintStyle: const TextStyle(fontSize: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            filled: true,
                            fillColor: AppColors.bgSurface,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (canEdit)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: AppColors.bgSurface,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: AppButton(
                label: isSettled ? 'Update Settlement' : 'Settle Shift',
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
  final TextStyle? valueStyle;
  const _InfoRow(this.label, this.value, {this.valueStyle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
          Text(value,
              style: valueStyle ?? const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _PaymentInput extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  const _PaymentInput({
    required this.label,
    required this.controller,
    required this.enabled,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(label,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
        ),
        Expanded(
          flex: 3,
          child: TextFormField(
            controller: controller,
            enabled: enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.right,
            onChanged: onChanged,
            style: const TextStyle(
                color: AppColors.textPrimary, 
                fontSize: 14,
                fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              prefixText: '₹ ',
              prefixStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.border)),
            ),
          ),
        ),
      ],
    );
  }
}

