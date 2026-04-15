// ─── payroll_dashboard_screen.dart ───────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/tenant_service.dart';
import '../../../core/services/discord_service.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/ist_time.dart';
import '../../../shared/widgets/widgets.dart';

class PayrollDashboardScreen extends ConsumerStatefulWidget {
  const PayrollDashboardScreen({super.key});
  @override
  ConsumerState<PayrollDashboardScreen> createState() => _PayrollDashboardScreenState();
}

class _PayrollDashboardScreenState extends ConsumerState<PayrollDashboardScreen> {
  bool _loading = true;
  String? _error;
  List<dynamic> _staff = [];
  List<dynamic> _payouts = [];
  Map<String, dynamic>? _summary;

  @override
  void initState() { super.initState(); _fetch(); }

  Future<void> _fetch() async {
    setState(() { _loading = true; _error = null; });
    try {
      final db = TenantService.instance.client;
      final user = ref.read(currentUserProvider)!;
      final results = await Future.wait([
        db.from('User').select('id, full_name, role, employee_id').eq('station_id', user.stationId).eq('active', true).neq('role', 'DEALER'),
        db.from('SalaryConfig').select('user_id, base_monthly_salary, effective_from').eq('station_id', user.stationId),
        db.from('SalaryPayout').select('id, user_id, net_paid, period_label, month, year, base_salary_snapshot, incentives, other_deductions, total_advances_deducted, status, created_at, user:User(full_name, role, employee_id)').eq('station_id', user.stationId).order('created_at', ascending: false).limit(20),
        db.from('StaffAdvance').select('amount').eq('station_id', user.stationId),
      ]);
      final configMap = {for (final c in results[1] as List) (c as Map)['user_id'] as String: c};
      final staffWithConfig = (results[0] as List).where((s) => configMap.containsKey((s as Map)['id'])).toList();
      final totalPayouts = (results[2] as List).fold<double>(0, (s, p) => s + (double.tryParse((p as Map)['net_paid']?.toString() ?? '0') ?? 0));
      setState(() {
        _staff = staffWithConfig;
        _payouts = results[2] as List;
        _summary = {'total_payouts': totalPayouts, 'config_map': configMap, 'advances': results[3]};
        _loading = false;
      });
    } catch (e) { setState(() { _error = e.toString(); _loading = false; }); }
  }

  Future<void> _recordPayout(Map<String, dynamic> staffMember) async {
    final config = (_summary!['config_map'] as Map)[staffMember['id'] as String] as Map?;
    if (config == null) return;
    final baseSalary = double.tryParse(config['base_monthly_salary']?.toString() ?? '0') ?? 0;
    final bonusCtrl = TextEditingController();
    final penaltyCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: Text('Payout — ${staffMember['full_name']}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Base Salary: ${IndianCurrency.format(baseSalary)}', style: const TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 16),
        TextField(controller: bonusCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Bonus (₹)', prefixText: '₹ ')),
        const SizedBox(height: 8),
        TextField(controller: penaltyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Penalty (₹)', prefixText: '₹ ')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Pay Now', style: TextStyle(color: AppColors.green))),
      ],
    ));

    if (confirmed != true) return;
    final bonus = double.tryParse(bonusCtrl.text) ?? 0;
    final penalty = double.tryParse(penaltyCtrl.text) ?? 0;
    final netPay = baseSalary + bonus - penalty;

    try {
      final db = TenantService.instance.client;
      final user = ref.read(currentUserProvider)!;
      final stationName = ref.read(stationNameProvider);
      final now = IstTime.now();
      final period = '${_monthName(now.month)} ${now.year}';

      await db.from('SalaryPayout').insert({
        'station_id': user.stationId,
        'user_id': staffMember['id'],
        'base_salary_snapshot': baseSalary,
        'incentives': bonus,
        'other_deductions': penalty,
        'net_paid': netPay,
        'period_label': period,
        'month': now.month,
        'year': now.year,
        'status': 'PAID',
        'paid_at': DateTime.now().toUtc().toIso8601String(),
        'paid_by_id': user.id,
        'generated_by_id': user.id,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      await DiscordService.instance.sendPayrollSettlement(
        staffName: staffMember['full_name'] as String,
        amount: netPay, period: period, stationName: stationName);

      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ Paid ${IndianCurrency.format(netPay)} to ${staffMember['full_name']}'), backgroundColor: AppColors.green)); _fetch(); }
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'))); }
  }

  String _monthName(int m) {
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return m >= 1 && m <= 12 ? months[m] : 'Month';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: AppColors.bgApp, body: LoadingView());
    if (_error != null) return Scaffold(backgroundColor: AppColors.bgApp, body: ErrorView(message: _error!, onRetry: _fetch));

    return Scaffold(
      backgroundColor: AppColors.bgApp,
      body: RefreshIndicator(onRefresh: _fetch, color: AppColors.blue, child: ListView(padding: const EdgeInsets.all(16), children: [
        // Summary
        AppCard(child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Total Paid (All Time)', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 4),
            Text(IndianCurrency.formatCompact(_summary!['total_payouts'] as double), style: const TextStyle(color: AppColors.green, fontSize: 22, fontWeight: FontWeight.w800)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${_staff.length} staff', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            Text('${(_summary!['advances'] as List).length} advances', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ]),
        ])),
        const SizedBox(height: 20),
        const SectionHeader(title: 'Staff — Pay Now'),
        const SizedBox(height: 12),
        ..._staff.map((s) {
          final config = (_summary!['config_map'] as Map)[(s as Map)['id'] as String] as Map?;
          return Padding(padding: const EdgeInsets.only(bottom: 10), child: AppCard(child: Row(children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.blueBg, borderRadius: BorderRadius.circular(10)), alignment: Alignment.center, child: Text((s['full_name'] as String).substring(0, 1).toUpperCase(), style: const TextStyle(color: AppColors.blue, fontWeight: FontWeight.w700, fontSize: 16))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s['full_name'] as String, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
              Text(config != null ? 'Base: ${IndianCurrency.format(double.tryParse(config['base_monthly_salary']?.toString() ?? '0') ?? 0)}' : 'No salary config', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ])),
            if (config != null) IconButton(icon: const Icon(Icons.payments, color: AppColors.green, size: 22), onPressed: () => _recordPayout(s), tooltip: 'Record Payout'),
          ])));
        }),
        const SizedBox(height: 20),
        const SectionHeader(title: 'Recent Payouts'),
        const SizedBox(height: 12),
        ..._payouts.take(10).map((p) => Padding(padding: const EdgeInsets.only(bottom: 8), child: AppCard(child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((p['user'] as Map?)?['full_name'] as String? ?? '', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
            Text(p['period_label'] as String? ?? '', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(IndianCurrency.format(double.tryParse(p['net_paid']?.toString() ?? '0') ?? 0), style: const TextStyle(color: AppColors.green, fontWeight: FontWeight.w600)),
            StatusBadge.fromStatus(p['status'] as String? ?? ''),
          ]),
        ])))),
      ])),
    );
  }
}
