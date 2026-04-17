import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/tenant_service.dart';
import '../../../core/services/export_service.dart';
import '../../../core/utils/currency.dart';
import '../../../shared/widgets/widgets.dart';

enum _ReportType { shift, payroll, inventory, credit, expenses }

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});
  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  _ReportType _activeReport = _ReportType.shift;
  bool _generating = false;
  String? _error;

  // Date range
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();
  String _monthValue = () {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}';
  }();

  String _ds(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static const _reportTypes = [
    (_ReportType.shift, 'Shifts', Icons.swap_horiz, AppColors.blue),
    (_ReportType.payroll, 'Payroll', Icons.payments_outlined, AppColors.purple),
    (
      _ReportType.inventory,
      'Inventory',
      Icons.local_gas_station_outlined,
      AppColors.green
    ),
    (_ReportType.credit, 'Credit', Icons.credit_card_outlined, AppColors.amber),
    (
      _ReportType.expenses,
      'Expenses',
      Icons.receipt_long_outlined,
      AppColors.red
    ),
  ];

  Future<Map<String, dynamic>> _fetchReportData() async {
    final db = TenantService.instance.client;
    final user = ref.read(currentUserProvider);
    if (user == null) return {};

    switch (_activeReport) {
      case _ReportType.shift:
        final shifts = await db
            .from('Shift')
            .select(
                'id, status, business_date, start_time, closed_at, pump:Pump(name), assigned_worker:User(full_name), nozzle_entries:NozzleEntry(sale_litres, sale_amount, rate, nozzle:Nozzle(fuel_type)), payment_record:PaymentRecord(upi_amount, card_amount, cash_to_collect, credit_amount, total_sale_amount, is_balanced)')
            .eq('station_id', user.stationId)
            .inFilter('status', ['CLOSED', 'SETTLED'])
            .gte('business_date', _ds(_from))
            .lte('business_date', _ds(_to))
            .order('business_date', ascending: false);

        final totalRevenue = (shifts as List).fold<double>(0, (s, sh) {
          final ne = (sh as Map)['nozzle_entries'] as List? ?? [];
          return s +
              ne.fold<double>(
                  0,
                  (es, e) =>
                      es +
                      (double.tryParse(
                              (e as Map)['sale_amount']?.toString() ?? '0') ??
                          0));
        });
        final totalLitres = (shifts as List).fold<double>(
            0,
            (s, sh) =>
                s +
                ((sh as Map)['nozzle_entries'] as List? ?? []).fold<double>(
                    0,
                    (ls, e) =>
                        ls +
                        (double.tryParse(
                                (e as Map)['sale_litres']?.toString() ?? '0') ??
                            0)));
        return {
          'shifts': shifts,
          'totalRevenue': totalRevenue,
          'totalLitres': totalLitres,
          'period': '${_ds(_from)} – ${_ds(_to)}'
        };

      case _ReportType.payroll:
        final payouts = await db
            .from('SalaryPayout')
            .select(
                'id, net_paid, base_salary_snapshot, incentives, other_deductions, period_label, month, year, status, created_at, user:User!SalaryPayout_user_id_fkey(full_name, role, employee_id)')
            .eq('station_id', user.stationId)
            .eq('month', int.parse(_monthValue.split('-')[1]))
            .eq('year', int.parse(_monthValue.split('-')[0]))
            .order('created_at', ascending: false);

        final totalPaid = (payouts as List).fold<double>(
            0,
            (s, p) =>
                s + (double.tryParse(p['net_paid']?.toString() ?? '0') ?? 0));
        return {
          'payouts': payouts,
          'totalPaid': totalPaid,
          'period': _monthValue
        };

      case _ReportType.inventory:
        final results = await Future.wait([
          db
              .from('Tank')
              .select(
                  'id, name, fuel_type, capacity_liters, low_stock_threshold')
              .eq('station_id', user.stationId)
              .eq('active', true),
          db
              .from('FuelOrder')
              .select('id, total_liters, total_amount, vendor, status, date')
              .eq('station_id', user.stationId)
              .gte('date', _ds(_from))
              .lte('date', _ds(_to))
              .order('date', ascending: false),
          db
              .from('DipReading')
              .select(
                  'id, tank:Tank(name, fuel_type), calculated_volume, created_at')
              .eq('station_id', user.stationId)
              .gte('created_at', '${_ds(_from)}T00:00:00Z')
              .lte('created_at', '${_ds(_to)}T23:59:59Z')
              .order('created_at', ascending: false)
              .limit(50),
        ]);
        final orders = results[1] as List;
        final totalOrdered = orders.fold<double>(
            0,
            (s, o) =>
                s +
                (double.tryParse(o['total_amount']?.toString() ?? '0') ?? 0));
        return {
          'tanks': results[0],
          'orders': orders,
          'dipReadings': results[2],
          'totalOrdered': totalOrdered,
          'period': '${_ds(_from)} – ${_ds(_to)}'
        };

      case _ReportType.credit:
        final customers = await db
            .from('CreditCustomer')
            .select(
                'id, full_name, phone_number, customer_code, advance_balance, active')
            .eq('station_id', user.stationId)
            .eq('active', true)
            .isFilter('deleted_at', null);
        final txns = await db
            .from('CreditTransaction')
            .select(
                'id, amount, liters, fuel_type, date, remaining_balance, customer:CreditCustomer(full_name)')
            .eq('station_id', user.stationId)
            .gte('date', _ds(_from))
            .lte('date', _ds(_to))
            .order('date', ascending: false);
        final payments = await db
            .from('CreditPayment')
            .select(
                'id, paid_amount, payment_mode, date, note, credit:CreditTransaction(customer:CreditCustomer(full_name))')
            .eq('station_id', user.stationId)
            .gte('date', _ds(_from))
            .lte('date', _ds(_to))
            .order('date', ascending: false);
        final totalCredit = (txns as List).fold<double>(
            0,
            (s, t) =>
                s + (double.tryParse(t['amount']?.toString() ?? '0') ?? 0));
        final totalRepaid = (payments as List).fold<double>(
            0,
            (s, p) =>
                s +
                (double.tryParse(p['paid_amount']?.toString() ?? '0') ?? 0));
        return {
          'customers': customers,
          'transactions': txns,
          'payments': payments,
          'totalCredit': totalCredit,
          'totalRepaid': totalRepaid,
          'net': totalCredit - totalRepaid,
          'period': '${_ds(_from)} – ${_ds(_to)}'
        };

      case _ReportType.expenses:
        final expenses = await db
            .from('DailyExpense')
            .select(
                'id, category, name, amount, expense_date, vendor_name, business_date')
            .eq('station_id', user.stationId)
            .isFilter('deleted_at', null)
            .gte('business_date', _ds(_from))
            .lte('business_date', _ds(_to))
            .order('expense_date', ascending: false);
        final total = (expenses as List).fold<double>(
            0,
            (s, e) =>
                s + (double.tryParse(e['amount']?.toString() ?? '0') ?? 0));
        final byCat = <String, double>{};
        for (final e in expenses) {
          final c = e['category'] as String? ?? 'misc';
          byCat[c] = (byCat[c] ?? 0) +
              (double.tryParse(e['amount']?.toString() ?? '0') ?? 0);
        }
        return {
          'expenses': expenses,
          'total': total,
          'byCat': byCat,
          'period': '${_ds(_from)} – ${_ds(_to)}'
        };
    }
  }

  Future<void> _generatePdf() async {
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final data = await _fetchReportData();
      final stationName = ref.read(stationNameProvider);
      File? pdf;

      switch (_activeReport) {
        case _ReportType.shift:
          pdf = await ExportService.instance.generateShiftReport(shiftData: {
            'shifts': data['shifts'],
            'totalRevenue': data['totalRevenue'],
            'totalLitres': data['totalLitres']
          }, stationName: stationName);
        case _ReportType.payroll:
          pdf = await ExportService.instance.generatePayrollReport(
              payouts: List<Map<String, dynamic>>.from(
                  (data['payouts'] as List).map((p) => {
                        'staff_name': (p['user'] as Map?)?['full_name'] ?? '',
                        'base_salary_snapshot': p['base_salary_snapshot'],
                        'advances': p['total_advances_deducted'] ?? 0,
                        'incentives': p['incentives'] ?? 0,
                        'other_deductions': p['other_deductions'] ?? 0,
                        'net_paid': p['net_paid']
                      })),
              period: data['period'] as String,
              totalPaid: data['totalPaid'] as double,
              stationName: stationName);
        case _ReportType.inventory:
          pdf = await ExportService.instance.generateInventoryReport(
              tanks: List<Map<String, dynamic>>.from(data['tanks'] as List),
              orders: List<Map<String, dynamic>>.from(data['orders'] as List),
              cheques: [],
              stationName: stationName);
        default:
          pdf = await ExportService.instance
              .generateShiftReport(shiftData: data, stationName: stationName);
      }

      if (mounted) {
        await ExportService.instance
            .sharePdf(pdf, subject: 'FuelOS Report — $stationName');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _generateCsv() async {
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final data = await _fetchReportData();
      final stationName = ref.read(stationNameProvider);
      late File csv;

      switch (_activeReport) {
        case _ReportType.shift:
          final shifts = data['shifts'] as List;
          csv = await ExportService.instance.exportCsv(
            headers: [
              'Date',
              'Pump',
              'Staff',
              'Status',
              'Sale Amount',
              'Litres'
            ],
            rows: shifts
                .map((s) => [
                      s['business_date'] as String? ?? '',
                      (s['pump'] as Map?)?['name'] as String? ?? '',
                      (s['assigned_worker'] as Map?)?['full_name'] as String? ??
                          'Unassigned',
                      s['status'] as String? ?? '',
                      ((s['nozzle_entries'] as List? ?? []).fold<double>(
                          0,
                          (es, e) =>
                              es +
                              (double.tryParse(
                                      (e as Map)['sale_amount']?.toString() ??
                                          '0') ??
                                  0))).toStringAsFixed(2),
                      ((s['nozzle_entries'] as List? ?? []).fold<double>(
                          0,
                          (ls, e) =>
                              ls +
                              (double.tryParse(
                                      (e as Map)['sale_litres']?.toString() ??
                                          '0') ??
                                  0))).toStringAsFixed(2),
                    ])
                .toList(),
            filename: 'fuelos_shifts_${_ds(_from)}_${_ds(_to)}',
          );
        case _ReportType.expenses:
          final expenses = data['expenses'] as List;
          csv = await ExportService.instance.exportCsv(
            headers: ['Date', 'Name', 'Category', 'Amount', 'Vendor'],
            rows: expenses
                .map((e) => [
                      e['expense_date'] as String? ?? '',
                      e['name'] as String? ?? '',
                      e['category'] as String? ?? '',
                      (double.tryParse(e['amount']?.toString() ?? '0') ?? 0)
                          .toStringAsFixed(2),
                      e['vendor_name'] as String? ?? ''
                    ])
                .toList(),
            filename: 'fuelos_expenses_${_ds(_from)}_${_ds(_to)}',
          );
        default:
          csv = await ExportService.instance.exportCsv(headers: [
            'Report'
          ], rows: [
            ['See PDF report']
          ], filename: 'fuelos_report');
      }

      if (mounted) {
        await Share.shareXFiles([XFile(csv.path)],
            subject: 'FuelOS CSV — $stationName');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _shareWhatsApp() async {
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final data = await _fetchReportData();
      final stationName = ref.read(stationNameProvider);
      String msg = '';

      switch (_activeReport) {
        case _ReportType.shift:
          msg =
              '🏪 *$stationName*\n📊 *Shift Report*\n📅 ${data['period']}\n\n💰 Revenue: ${IndianCurrency.format(data['totalRevenue'] as double)}\n⛽ Litres: ${IndianCurrency.formatLitres(data['totalLitres'] as double)}\n📋 Shifts: ${(data['shifts'] as List).length}\n\n_FuelOS_';
        case _ReportType.payroll:
          msg =
              '🏪 *$stationName*\n💸 *Payroll Report*\n📅 ${data['period']}\n\n✅ Total Paid: ${IndianCurrency.format(data['totalPaid'] as double)}\n👥 Staff: ${(data['payouts'] as List).length}\n\n_FuelOS_';
        case _ReportType.inventory:
          final tanks = data['tanks'] as List;
          final tankLines = tanks
              .map((t) => '• ${t['name']}: ${IndianCurrency.formatLitres(0.0)}')
              .join('\n');
          msg =
              '🏪 *$stationName*\n🛢️ *Inventory Report*\n📅 ${data['period']}\n\n$tankLines\n\n💰 Orders: ${IndianCurrency.format(data['totalOrdered'] as double)}\n\n_FuelOS_';
        case _ReportType.credit:
          msg =
              '🏪 *$stationName*\n💳 *Credit Report*\n📅 ${data['period']}\n\n📤 Credit Given: ${IndianCurrency.format(data['totalCredit'] as double)}\n📥 Repaid: ${IndianCurrency.format(data['totalRepaid'] as double)}\n⚖️ Net Outstanding: ${IndianCurrency.format(data['net'] as double)}\n\n_FuelOS_';
        case _ReportType.expenses:
          msg =
              '🏪 *$stationName*\n💸 *Expense Report*\n📅 ${data['period']}\n\n💵 Total: ${IndianCurrency.format(data['total'] as double)}\n📋 Entries: ${(data['expenses'] as List).length}\n\n_FuelOS_';
      }

      Share.share(msg);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Widget _buildPreview(Map<String, dynamic> data) {
    switch (_activeReport) {
      case _ReportType.shift:
        final shifts = data['shifts'] as List;
        return Column(children: [
          _StatRow(
              'Total Revenue',
              IndianCurrency.format(data['totalRevenue'] as double),
              AppColors.green),
          _StatRow(
              'Total Litres',
              IndianCurrency.formatLitres(data['totalLitres'] as double),
              AppColors.blue),
          _StatRow('Total Shifts', '${shifts.length}', AppColors.textPrimary),
          const Divider(height: 24, color: AppColors.border),
          ...shifts.take(10).map((s) => _PreviewRow(
              (s as Map)['business_date'] as String? ?? '',
              (s['pump'] as Map?)?['name'] as String? ?? '',
              IndianCurrency.format(
                  double.tryParse(s['sale_amount']?.toString() ?? '0') ?? 0))),
          if (shifts.length > 10)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('+${shifts.length - 10} more shifts',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 12))),
        ]);

      case _ReportType.payroll:
        final payouts = data['payouts'] as List;
        return Column(children: [
          _StatRow(
              'Total Paid',
              IndianCurrency.format(data['totalPaid'] as double),
              AppColors.green),
          _StatRow('Staff Paid', '${payouts.length}', AppColors.textPrimary),
          const Divider(height: 24, color: AppColors.border),
          ...payouts.take(10).map((p) => _PreviewRow(
              (p as Map)['period_label'] as String? ?? '',
              (p['user'] as Map?)?['full_name'] as String? ?? '',
              IndianCurrency.format(
                  double.tryParse(p['net_paid']?.toString() ?? '0') ?? 0))),
        ]);

      case _ReportType.inventory:
        final tanks = data['tanks'] as List;
        return Column(children: [
          _StatRow(
              'Orders Total',
              IndianCurrency.format(data['totalOrdered'] as double),
              AppColors.blue),
          _StatRow('Orders Count', '${(data['orders'] as List).length}',
              AppColors.textPrimary),
          const Divider(height: 24, color: AppColors.border),
          ...tanks.map((t) {
            final cap = double.tryParse(
                    (t as Map)['capacity_liters']?.toString() ?? '0') ??
                0;
            const cur = 0.0;
            final pct = cap > 0 ? (cur / cap * 100).round() : 0;
            return _PreviewRow(
                t['name'] as String? ?? '',
                t['fuel_type'] as String? ?? '',
                '$pct% — ${IndianCurrency.formatLitres(cur)}');
          }),
        ]);

      case _ReportType.credit:
        final txns = data['transactions'] as List;
        return Column(children: [
          _StatRow(
              'Credit Given',
              IndianCurrency.format(data['totalCredit'] as double),
              AppColors.red),
          _StatRow(
              'Repaid',
              IndianCurrency.format(data['totalRepaid'] as double),
              AppColors.green),
          _StatRow('Net Outstanding',
              IndianCurrency.format(data['net'] as double), AppColors.amber),
          const Divider(height: 24, color: AppColors.border),
          ...txns.take(8).map((t) => _PreviewRow(
              (t as Map)['date'] as String? ?? '',
              (t['customer'] as Map?)?['full_name'] as String? ?? '',
              IndianCurrency.format(
                  double.tryParse(t['amount']?.toString() ?? '0') ?? 0))),
        ]);

      case _ReportType.expenses:
        final byCat = data['byCat'] as Map<String, double>;
        return Column(children: [
          _StatRow('Total Expenses',
              IndianCurrency.format(data['total'] as double), AppColors.red),
          _StatRow('Entries', '${(data['expenses'] as List).length}',
              AppColors.textPrimary),
          const Divider(height: 24, color: AppColors.border),
          const Text('By Category',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ...byCat.entries.map(
              (e) => _PreviewRow(e.key, '', IndianCurrency.format(e.value))),
        ]);
    }
  }

  Future<Map<String, dynamic>>? _cachedFuture;
  _ReportType? _lastType;
  DateTime? _lastFrom;
  DateTime? _lastTo;
  String? _lastMonth;

  Future<Map<String, dynamic>> _getOrFetchData() {
    final typeChanged = _lastType != _activeReport;
    final dateChanged =
        _lastFrom != _from || _lastTo != _to || _lastMonth != _monthValue;
    if (_cachedFuture == null || typeChanged || dateChanged) {
      _lastType = _activeReport;
      _lastFrom = _from;
      _lastTo = _to;
      _lastMonth = _monthValue;
      _cachedFuture = _fetchReportData();
    }
    return _cachedFuture!;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgApp,
      body: Column(children: [
        Container(
            color: AppColors.bgSurface,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(children: [
              SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                      children: _reportTypes.map((rt) {
                    final (type, label, icon, color) = rt;
                    final sel = _activeReport == type;
                    return GestureDetector(
                        onTap: () => setState(() {
                              _activeReport = type;
                              _error = null;
                            }),
                        child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                                color: sel
                                    ? color.withValues(alpha: 0.15)
                                    : AppColors.bgCard,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: sel ? color : AppColors.border,
                                    width: sel ? 1.5 : 1)),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(icon,
                                  size: 14,
                                  color: sel ? color : AppColors.textMuted),
                              const SizedBox(width: 6),
                              Text(label,
                                  style: TextStyle(
                                      color:
                                          sel ? color : AppColors.textSecondary,
                                      fontSize: 12,
                                      fontWeight: sel
                                          ? FontWeight.w700
                                          : FontWeight.w400))
                            ])));
                  }).toList())),
              const SizedBox(height: 12),
              if (_activeReport == _ReportType.payroll) ...[
                Row(children: [
                  const Icon(Icons.calendar_month_outlined,
                      size: 14, color: AppColors.textMuted),
                  const SizedBox(width: 6),
                  const Text('Period:',
                      style:
                          TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Row(children: [
                    IconButton(
                        icon: const Icon(Icons.chevron_left,
                            size: 18, color: AppColors.textSecondary),
                        onPressed: () {
                          final p =
                              _monthValue.split('-').map(int.parse).toList();
                          final d = DateTime(p[0], p[1] - 1);
                          setState(() => _monthValue =
                              '${d.year}-${d.month.toString().padLeft(2, '0')}');
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints()),
                    const SizedBox(width: 8),
                    Text(_monthValue,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                    const SizedBox(width: 8),
                    IconButton(
                        icon: const Icon(Icons.chevron_right,
                            size: 18, color: AppColors.textSecondary),
                        onPressed: () {
                          final p =
                              _monthValue.split('-').map(int.parse).toList();
                          final d = DateTime(p[0], p[1] + 1);
                          setState(() => _monthValue =
                              '${d.year}-${d.month.toString().padLeft(2, '0')}');
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints()),
                  ])),
                ]),
              ] else ...[
                Row(children: [
                  Expanded(
                      child: _DatePickerBtn(
                          label: 'From: ${_ds(_from)}',
                          onTap: () async {
                            final d = await showDatePicker(
                                context: context,
                                initialDate: _from,
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now());
                            if (d != null) setState(() => _from = d);
                          })),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _DatePickerBtn(
                          label: 'To: ${_ds(_to)}',
                          onTap: () async {
                            final d = await showDatePicker(
                                context: context,
                                initialDate: _to,
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now());
                            if (d != null) setState(() => _to = d);
                          })),
                ]),
              ],
            ])),
        Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
          future: _generating ? _cachedFuture : _getOrFetchData(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting &&
                !_generating) {
              return const LoadingView(message: 'Loading report data...');
            }
            if (snap.hasError) {
              return ErrorView(
                  message: snap.error.toString(),
                  onRetry: () => setState(() {}));
            }
            final data = snap.data;
            return RefreshIndicator(
              onRefresh: () async => setState(() {}),
              color: AppColors.blue,
              child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  children: [
                    if (_error != null) ...[
                      Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: AppColors.redBg,
                              borderRadius: BorderRadius.circular(8)),
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: AppColors.red, fontSize: 12))),
                      const SizedBox(height: 16),
                    ],
                    if (data != null) ...[
                      AppCard(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            const SectionHeader(title: 'Report Preview'),
                            const SizedBox(height: 16),
                            _buildPreview(data),
                          ])),
                      const SizedBox(height: 16),
                    ],
                    const Text('EXPORT',
                        style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1)),
                    const SizedBox(height: 10),
                    AppButton(
                      label: 'Download PDF',
                      icon: Icons.picture_as_pdf,
                      onTap: _generating ? null : _generatePdf,
                      loading: _generating,
                      width: double.infinity,
                    ),
                    const SizedBox(height: 8),
                    AppButton(
                      label: 'Export CSV',
                      icon: Icons.table_chart,
                      secondary: true,
                      onTap: _generating ? null : _generateCsv,
                      width: double.infinity,
                    ),
                    const SizedBox(height: 8),
                    AppButton(
                      label: 'Share via WhatsApp',
                      icon: Icons.chat_outlined,
                      secondary: true,
                      onTap: _generating ? null : _shareWhatsApp,
                      width: double.infinity,
                    ),
                  ]),
            );
          },
        )),
      ]),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatRow(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label,
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        Text(value,
            style: TextStyle(
                color: color, fontSize: 14, fontWeight: FontWeight.w700)),
      ]));
}

class _PreviewRow extends StatelessWidget {
  final String col1;
  final String col2;
  final String col3;
  const _PreviewRow(this.col1, this.col2, this.col3);
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(
            flex: 2,
            child: Text(col1,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
                overflow: TextOverflow.ellipsis)),
        Expanded(
            flex: 2,
            child: Text(col2,
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 12),
                overflow: TextOverflow.ellipsis)),
        Text(col3,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ]));
}

class _DatePickerBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _DatePickerBtn({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border)),
          child: Row(children: [
            const Icon(Icons.calendar_today,
                size: 13, color: AppColors.textMuted),
            const SizedBox(width: 6),
            Expanded(
                child: Text(label,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)))
          ])));
}
