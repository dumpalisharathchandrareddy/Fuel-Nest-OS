import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/auth_user.dart';
import '../../../core/services/registry_service.dart';
import '../../../core/services/tenant_service.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/ist_time.dart';
import '../../../shared/widgets/widgets.dart';

enum _CreditorStep { enterStation, enterPhone, viewBalance }

class CreditorPortalScreen extends ConsumerStatefulWidget {
  const CreditorPortalScreen({super.key});

  @override
  ConsumerState<CreditorPortalScreen> createState() =>
      _CreditorPortalScreenState();
}

class _CreditorPortalScreenState extends ConsumerState<CreditorPortalScreen> {
  _CreditorStep _step = _CreditorStep.enterStation;
  bool _loading = false;
  String? _error;

  // Step 1 – station
  final _stationCtrl = TextEditingController();
  String? _stationName;

  // Step 2 – phone
  final _phoneCtrl = TextEditingController();

  // Isolated client for this creditor lookup — never touches the app-wide tenant.
  SupabaseClient? _creditorClient;
  StationRegistryEntry? _creditorEntry;

  // Step 3 – data
  Map<String, dynamic>? _customer;
  List<dynamic> _transactions = [];
  List<dynamic> _payments = [];

  @override
  void dispose() {
    _stationCtrl.dispose();
    _phoneCtrl.dispose();
    _creditorClient = null;
    super.dispose();
  }

  Future<void> _lookupStation() async {
    if (_stationCtrl.text.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entry = await RegistryService.instance
          .lookupStation(_stationCtrl.text.trim().toUpperCase());
      if (entry == null) throw Exception('Station not found');
      _creditorClient = TenantService.instance.createTemporaryClient(entry);
      _creditorEntry = entry;
      setState(() {
        _stationName = entry.stationName;
        _step = _CreditorStep.enterPhone;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _lookupPhone() async {
    if (_phoneCtrl.text.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = _creditorClient!;
      final phone = _phoneCtrl.text.trim();
      final stationCode = _creditorEntry!.stationCode;

      final result = await db.rpc('fuelos_creditor_portal_data', params: {
        'p_station_code': stationCode,
        'p_phone': phone,
      }) as Map<String, dynamic>?;

      if (result == null || result['found'] != true) {
        throw Exception(
            'No credit account found for $phone at ${_stationName ?? "this station"}');
      }

      final customer =
          Map<String, dynamic>.from(result['customer'] as Map);
      final txList = (result['transactions'] as List?) ?? [];
      final pyList = (result['payments'] as List?) ?? [];

      final latestTx = txList.isNotEmpty ? txList.first as Map : null;
      customer['total_due'] = latestTx != null
          ? double.tryParse(
                  latestTx['remaining_balance']?.toString() ?? '0') ??
              0
          : 0.0;

      setState(() {
        _customer = customer;
        _transactions = txList;
        _payments = pyList;
        _step = _CreditorStep.viewBalance;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _reset() {
    _creditorClient = null;
    _creditorEntry = null;
    setState(() {
      _step = _CreditorStep.enterStation;
      _stationCtrl.clear();
      _phoneCtrl.clear();
      _customer = null;
      _transactions = [];
      _payments = [];
      _error = null;
      _stationName = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width > 600;

    return Scaffold(
      backgroundColor: AppColors.bgApp,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isWide ? size.width * 0.25 : 24,
              vertical: 32,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.purpleBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color:
                                AppColors.textPrimary.withOpacity(0.1)),
                      ),
                      child: const Icon(Icons.credit_card,
                          color: AppColors.purple, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Credit Account',
                            style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w800)),
                        Text('Check your balance',
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 12)),
                      ],
                    ),
                    const Spacer(),
                    if (_step != _CreditorStep.enterStation)
                      GestureDetector(
                        onTap: _reset,
                        child: const Text('Reset',
                            style:
                                TextStyle(color: AppColors.blue, fontSize: 13)),
                      ),
                  ],
                ),
                const SizedBox(height: 32),

                if (_step == _CreditorStep.enterStation) ..._buildStep1(),
                if (_step == _CreditorStep.enterPhone) ..._buildStep2(),
                if (_step == _CreditorStep.viewBalance) ..._buildBalance(),

                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.redBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppColors.red.withOpacity(0.3)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline,
                          color: AppColors.red, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: AppColors.red, fontSize: 13))),
                    ]),
                  ),
                ],

                const SizedBox(height: 24),
                if (_step != _CreditorStep.viewBalance)
                  Center(
                    child: TextButton(
                      onPressed: () => context.pop(),
                      child: const Text('Staff / Manager? Sign in here',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 12)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildStep1() => [
        const Text('Enter Station Code',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text(
            'Enter the code for the fuel station where you have a credit account.',
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 13, height: 1.5)),
        const SizedBox(height: 24),
        AppTextField(
          label: 'Station Code',
          controller: _stationCtrl,
          hint: 'e.g. STATION001',
          prefixIcon: Icons.store_outlined,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _lookupStation(),
        ),
        const SizedBox(height: 20),
        AppButton(
          label: 'Continue',
          onTap: _lookupStation,
          loading: _loading,
          width: double.infinity,
        ),
      ];

  List<Widget> _buildStep2() => [
        Text('${_stationName ?? "Station"} Found',
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('Enter your registered mobile number to view your balance.',
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 13, height: 1.5)),
        const SizedBox(height: 24),
        AppTextField(
          label: 'Mobile Number',
          controller: _phoneCtrl,
          hint: '10-digit mobile number',
          prefixIcon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _lookupPhone(),
        ),
        const SizedBox(height: 20),
        AppButton(
          label: 'View Balance',
          onTap: _lookupPhone,
          loading: _loading,
          width: double.infinity,
        ),
      ];

  List<Widget> _buildBalance() {
    final totalDue = _customer!['total_due'] as double? ?? 0.0;
    final limit = double.tryParse('0') ?? 0;
    final isOverLimit = totalDue > limit;
    final pct = limit > 0 ? (totalDue / limit).clamp(0.0, 1.0) : 0.0;

    return [
      // Customer summary card
      AppCard(
        borderColor: isOverLimit
            ? AppColors.red.withOpacity(0.3)
            : AppColors.green.withOpacity(0.2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.purpleBg,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                (_customer!['full_name'] as String? ?? 'C')[0].toUpperCase(),
                style: const TextStyle(
                    color: AppColors.purple,
                    fontSize: 18,
                    fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_customer!['full_name'] as String? ?? '',
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 16)),
                  if (_customer!['customer_code'] != null)
                    Text(_customer!['customer_code'] as String,
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
            if (isOverLimit)
              const StatusBadge(label: 'OVER LIMIT', tone: BadgeTone.error),
          ]),
          const SizedBox(height: 20),

          // Due amount — big
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Amount Due',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 2),
                Text(
                  IndianCurrency.format(totalDue),
                  style: TextStyle(
                    color: isOverLimit ? AppColors.red : AppColors.amber,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ]),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                const Text('Station Advance',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 2),
                Text(IndianCurrency.format(limit),
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ]),
            ],
          ),
          const SizedBox(height: 12),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: AppColors.bgHover,
              valueColor: AlwaysStoppedAnimation(
                  isOverLimit ? AppColors.red : AppColors.amber),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${(pct * 100).round()}% used',
                style: TextStyle(
                    color: isOverLimit ? AppColors.red : AppColors.textMuted,
                    fontSize: 11),
              ),
              Text(
                'Available: ${IndianCurrency.format((limit - totalDue).clamp(0, double.infinity))}',
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
            ],
          ),
        ]),
      ),
      const SizedBox(height: 24),

      // Recent transactions
      SectionHeader(
        title: 'Credit Transactions (${_transactions.length})',
      ),
      const SizedBox(height: 12),
      if (_transactions.isEmpty)
        const Center(
            child: Text('No transactions yet',
                style: TextStyle(color: AppColors.textMuted))),
      ..._transactions.take(10).map((t) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: AppColors.redBg,
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.arrow_upward,
                      color: AppColors.red, size: 14),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${t['fuel_type'] ?? 'Fuel'} — ${IndianCurrency.formatLitres(double.tryParse(t['liters']?.toString() ?? '0') ?? 0)}',
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w500,
                              fontSize: 13),
                        ),
                        Text(
                          IstTime.formatDate(DateTime.parse(
                              t['created_at'] as String? ??
                                  DateTime.now().toIso8601String())),
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 11),
                        ),
                      ]),
                ),
                Text(
                  IndianCurrency.format(
                      double.tryParse(t['amount']?.toString() ?? '0') ?? 0),
                  style: const TextStyle(
                      color: AppColors.red, fontWeight: FontWeight.w600),
                ),
              ]),
            ),
          )),

      if (_payments.isNotEmpty) ...[
        const SizedBox(height: 20),
        SectionHeader(title: 'Payments Made (${_payments.length})'),
        const SizedBox(height: 12),
        ..._payments.take(10).map((p) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: AppColors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4)),
                    child: const Icon(Icons.arrow_downward,
                        color: AppColors.green, size: 14),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p['payment_mode'] as String? ?? 'Payment',
                            style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w500,
                                fontSize: 13),
                          ),
                          Text(
                            IstTime.formatDate(DateTime.parse(
                                p['created_at'] as String? ??
                                    DateTime.now().toIso8601String())),
                            style: const TextStyle(
                                color: AppColors.textMuted, fontSize: 11),
                          ),
                        ]),
                  ),
                  Text(
                    '+ ${IndianCurrency.format(double.tryParse(p['paid_amount']?.toString() ?? '0') ?? 0)}',
                    style: const TextStyle(
                        color: AppColors.green, fontWeight: FontWeight.w600),
                  ),
                ]),
              ),
            )),
      ],
    ];
  }
}
