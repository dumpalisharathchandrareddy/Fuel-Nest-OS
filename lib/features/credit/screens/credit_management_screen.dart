import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/tenant_service.dart';
import '../../../core/utils/ist_time.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/widgets.dart';

class CreditManagementScreen extends ConsumerStatefulWidget {
  const CreditManagementScreen({super.key});
  @override
  ConsumerState<CreditManagementScreen> createState() =>
      _CreditManagementScreenState();
}

class _CreditManagementScreenState
    extends ConsumerState<CreditManagementScreen> {
  bool _loading = true;
  String? _error;
  List<dynamic> _customers = [];
  String _search = '';
  String _filter = 'ALL'; // ALL, OUTSTANDING, CLEARED
  Map<String, dynamic>? _selectedCustomer;
  List<dynamic> _txns = [];
  List<dynamic> _payments = [];
  bool _loadingLedger = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = TenantService.instance.client;
      final user = ref.read(currentUserProvider)!;

      // Get customers with computed totals
      final customers = await db
          .from('CreditCustomer')
          .select(
              'id, name, customer_code, phone_number, credit_limit, active, created_at')
          .eq('station_id', user.stationId)
          .order('name');

      // Compute outstanding per customer from CreditTransaction.remaining_balance
      // remaining_balance is maintained by the backend on each transaction.
      // We use the latest remaining_balance per customer as outstanding.
      final List<dynamic> enriched = [];
      for (final c in customers as List) {
        final cid = c['id'] as String;
        // Get latest transaction's remaining_balance (maintained by backend)
        final latestTx = await db
            .from('CreditTransaction')
            .select('remaining_balance')
            .eq('customer_id', cid)
            .eq('station_id', user.stationId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        final outstanding = latestTx != null
            ? double.tryParse(
                    latestTx['remaining_balance']?.toString() ?? '0') ??
                0
            : 0.0;
        enriched.add({
          ...Map<String, dynamic>.from(c as Map),
          'outstanding': outstanding
        });
      }

      // Sort by outstanding (highest first)
      enriched.sort((a, b) =>
          (b['outstanding'] as double).compareTo(a['outstanding'] as double));

      setState(() {
        _customers = enriched;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadLedger(Map<String, dynamic> customer) async {
    setState(() {
      _selectedCustomer = customer;
      _loadingLedger = true;
      _txns = [];
      _payments = [];
    });
    try {
      final db = TenantService.instance.client;
      final cid = customer['id'] as String;
      final results = await Future.wait([
        // CreditTransaction: amount, liters (NOT litres), date (NOT transaction_date)
        db
            .from('CreditTransaction')
            .select(
                'id, amount, liters, fuel_type, date, remaining_balance, status, created_at')
            .eq('customer_id', cid)
            .eq('station_id', user.stationId)
            .order('date', ascending: false),
        // CreditPayment: credit_id → CreditTransaction → customer
        // paid_amount (NOT amount), payment_mode (NOT payment_mode)
        db
            .from('CreditPayment')
            .select(
                'id, paid_amount, payment_mode, date, note, created_at, credit:CreditTransaction(customer_id)')
            .eq('station_id', user.stationId)
            .order('date', ascending: false),
      ]);
      setState(() {
        _txns = results[0] as List;
        _payments = results[1] as List;
        _loadingLedger = false;
      });
    } catch (e) {
      setState(() {
        _loadingLedger = false;
      });
    }
  }

  List<dynamic> get _filtered {
    return _customers.where((c) {
      final name = (c['full_name'] as String? ?? '').toLowerCase();
      final phone = c['phone_number'] as String? ?? '';
      final vehicle = c['customer_code'] as String? ?? '';
      final outstanding = c['outstanding'] as double? ?? 0;
      final matchSearch = _search.isEmpty ||
          name.contains(_search.toLowerCase()) ||
          phone.contains(_search) ||
          vehicle.toLowerCase().contains(_search.toLowerCase());
      final matchFilter = _filter == 'ALL' ||
          (_filter == 'OUTSTANDING' && outstanding > 0) ||
          (_filter == 'CLEARED' && outstanding <= 0);
      return matchSearch && matchFilter;
    }).toList();
  }

  double get _totalOutstanding =>
      _customers.fold(0, (s, c) => s + (c['outstanding'] as double? ?? 0));

  // ── Add credit entry ────────────────────────────────────────────────────────
  Future<void> _showAddCreditEntry(
      [Map<String, dynamic>? presetCustomer]) async {
    Map<String, dynamic>? selCustomer = presetCustomer;
    final amtCtrl = TextEditingController();
    final litresCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String fuelType = FuelTypes.all.first;
    bool submitting = false;
    String? err;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, ss) => Padding(
                padding: EdgeInsets.fromLTRB(
                    20, 20, 20, MediaQuery.viewInsetsOf(ctx).bottom + 24),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.add_card,
                            color: AppColors.red, size: 22),
                        const SizedBox(width: 10),
                        const Expanded(
                            child: Text('Add Credit Entry',
                                style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700))),
                        IconButton(
                            icon: const Icon(Icons.close,
                                size: 20, color: AppColors.textMuted),
                            onPressed: () => Navigator.pop(ctx)),
                      ]),
                      const SizedBox(height: 16),

                      // Customer selector or display
                      if (selCustomer != null)
                        Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: AppColors.bgCard,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.border)),
                            child: Row(children: [
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(selCustomer!['full_name'] as String,
                                        style: const TextStyle(
                                            color: AppColors.textPrimary,
                                            fontWeight: FontWeight.w600)),
                                    Text(
                                        selCustomer!['phone_number']
                                                as String? ??
                                            '',
                                        style: const TextStyle(
                                            color: AppColors.textMuted,
                                            fontSize: 12)),
                                  ])),
                              if (presetCustomer == null)
                                IconButton(
                                    icon: const Icon(Icons.close,
                                        size: 16, color: AppColors.textMuted),
                                    onPressed: () =>
                                        ss(() => selCustomer = null)),
                            ]))
                      else
                        DropdownButtonFormField<String>(
                          dropdownColor: AppColors.bgSurface,
                          style: const TextStyle(
                              color: AppColors.textPrimary, fontSize: 13),
                          decoration: InputDecoration(
                              labelText: 'Customer',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              filled: true,
                              fillColor: AppColors.bgCard),
                          hint: const Text('Select customer',
                              style: TextStyle(color: AppColors.textMuted)),
                          items: _customers
                              .map((c) => DropdownMenuItem<String>(
                                  value: c['id'] as String,
                                  child: Text(
                                      '${c['name']} (${c['phone_number']})')))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              ss(() {
                                final found = _customers
                                    .where((c) => c['id'] == v)
                                    .toList();
                                selCustomer = found.isNotEmpty
                                    ? Map<String, dynamic>.from(
                                        found.first as Map)
                                    : null;
                              });
                            }
                          },
                        ),

                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                            child: TextField(
                          controller: amtCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: InputDecoration(
                              labelText: 'Amount (₹)',
                              prefixText: '₹ ',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              filled: true,
                              fillColor: AppColors.bgCard),
                          onChanged: (_) => ss(() {}),
                        )),
                        const SizedBox(width: 8),
                        Expanded(
                            child: TextField(
                          controller: litresCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: InputDecoration(
                              labelText: 'Litres (optional)',
                              suffixText: 'L',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              filled: true,
                              fillColor: AppColors.bgCard),
                        )),
                      ]),
                      const SizedBox(height: 12),
                      const Text('Fuel Type',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 12)),
                      const SizedBox(height: 6),
                      Wrap(
                          spacing: 6,
                          children: FuelTypes.all.map((f) {
                            final sel = fuelType == f;
                            return GestureDetector(
                              onTap: () => ss(() => fuelType = f),
                              child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                      color: sel
                                          ? AppColors.blue
                                          : AppColors.bgCard,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                          color: sel
                                              ? AppColors.blue
                                              : AppColors.border)),
                                  child: Text(f,
                                      style: TextStyle(
                                          color: sel
                                              ? Colors.white
                                              : AppColors.textSecondary,
                                          fontSize: 12,
                                          fontWeight: sel
                                              ? FontWeight.w600
                                              : FontWeight.w400))),
                            );
                          }).toList()),
                      const SizedBox(height: 12),
                      TextField(
                          controller: noteCtrl,
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: InputDecoration(
                              labelText: 'Note (optional)',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              filled: true,
                              fillColor: AppColors.bgCard)),
                      if (err != null) ...[
                        const SizedBox(height: 8),
                        Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                                color: AppColors.redBg,
                                borderRadius: BorderRadius.circular(6)),
                            child: Text(err!,
                                style: const TextStyle(
                                    color: AppColors.red, fontSize: 12)))
                      ],
                      const SizedBox(height: 16),
                      AppButton(
                        label: 'Record Credit Entry',
                        loading: submitting,
                        width: double.infinity,
                        onTap: selCustomer == null || amtCtrl.text.isEmpty
                            ? null
                            : () async {
                                final amt = double.tryParse(amtCtrl.text);
                                if (amt == null || amt <= 0) {
                                  ss(() => err = 'Enter valid amount');
                                  return;
                                }
                                ss(() {
                                  submitting = true;
                                  err = null;
                                });
                                try {
                                  final db = TenantService.instance.client;
                                  final user = ref.read(currentUserProvider)!;
                                  final now =
                                      DateTime.now().toUtc().toIso8601String();
                                  await db.from('CreditTransaction').insert({
                                    'station_id': user.stationId,
                                    'customer_id': selCustomer!['id'],
                                    'amount': amt,
                                    'litres':
                                        double.tryParse(litresCtrl.text) ?? 0,
                                    'fuel_type': fuelType,
                                    // CreditTransaction has no notes column
                                    'date':
                                        now, // DipReading: date column (DateTime)
                                    'created_by_id': user.id,
                                    'created_at': now,
                                  });
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content:
                                                Text('✅ Credit entry recorded'),
                                            backgroundColor: AppColors.green));
                                    _fetch();
                                    if (_selectedCustomer?['id'] ==
                                        selCustomer!['id'])
                                      _loadLedger(selCustomer!);
                                  }
                                } catch (e) {
                                  ss(() {
                                    submitting = false;
                                    err = e.toString();
                                  });
                                }
                              },
                      ),
                    ]),
              )),
    );
    amtCtrl.dispose();
    litresCtrl.dispose();
    noteCtrl.dispose();
  }

  // ── Record payment ──────────────────────────────────────────────────────────
  Future<void> _showRecordPayment(Map<String, dynamic> customer) async {
    final amtCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String method = 'Cash';
    bool submitting = false;
    String? err;
    final outstanding = customer['outstanding'] as double? ?? 0;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, ss) => Padding(
                padding: EdgeInsets.fromLTRB(
                    20, 20, 20, MediaQuery.viewInsetsOf(ctx).bottom + 24),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.payments_outlined,
                            color: AppColors.green, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              const Text('Record Payment',
                                  style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700)),
                              Text(customer['full_name'] as String,
                                  style: const TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 12)),
                            ])),
                        IconButton(
                            icon: const Icon(Icons.close,
                                size: 20, color: AppColors.textMuted),
                            onPressed: () => Navigator.pop(ctx)),
                      ]),
                      const SizedBox(height: 4),
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                              color: AppColors.amberBg,
                              borderRadius: BorderRadius.circular(8)),
                          child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Outstanding',
                                    style: TextStyle(
                                        color: AppColors.amber, fontSize: 12)),
                                Text(IndianCurrency.format(outstanding),
                                    style: const TextStyle(
                                        color: AppColors.amber,
                                        fontWeight: FontWeight.w700)),
                              ])),
                      const SizedBox(height: 16),
                      TextField(
                          controller: amtCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w700),
                          decoration: InputDecoration(
                              labelText: 'Payment Amount (₹)',
                              prefixText: '₹ ',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              filled: true,
                              fillColor: AppColors.bgCard),
                          onChanged: (_) => ss(() {})),
                      const SizedBox(height: 4),
                      GestureDetector(
                          onTap: () => ss(() =>
                              amtCtrl.text = outstanding.toStringAsFixed(2)),
                          child: const Text('Full amount',
                              style: TextStyle(
                                  color: AppColors.blue, fontSize: 12))),
                      const SizedBox(height: 12),
                      const Text('Payment Method',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 12)),
                      const SizedBox(height: 6),
                      Wrap(
                          spacing: 6,
                          children: [
                            'Cash',
                            'GPay',
                            'PhonePe',
                            'Paytm',
                            'Card',
                            'NEFT'
                          ].map((m) {
                            final sel = method == m;
                            return GestureDetector(
                                onTap: () => ss(() => method = m),
                                child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                        color: sel
                                            ? AppColors.green
                                            : AppColors.bgCard,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                            color: sel
                                                ? AppColors.green
                                                : AppColors.border)),
                                    child: Text(m,
                                        style: TextStyle(
                                            color: sel
                                                ? Colors.white
                                                : AppColors.textSecondary,
                                            fontSize: 12,
                                            fontWeight: sel
                                                ? FontWeight.w600
                                                : FontWeight.w400))));
                          }).toList()),
                      const SizedBox(height: 12),
                      TextField(
                          controller: noteCtrl,
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: InputDecoration(
                              labelText: 'Note (optional)',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              filled: true,
                              fillColor: AppColors.bgCard)),
                      if (err != null) ...[
                        const SizedBox(height: 8),
                        Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                                color: AppColors.redBg,
                                borderRadius: BorderRadius.circular(6)),
                            child: Text(err!,
                                style: const TextStyle(
                                    color: AppColors.red, fontSize: 12)))
                      ],
                      const SizedBox(height: 16),
                      AppButton(
                        label: 'Record Payment',
                        loading: submitting,
                        width: double.infinity,
                        onTap: () async {
                          final amt = double.tryParse(amtCtrl.text);
                          if (amt == null || amt <= 0) {
                            ss(() => err = 'Enter valid amount');
                            return;
                          }
                          ss(() {
                            submitting = true;
                            err = null;
                          });
                          try {
                            final db = TenantService.instance.client;
                            final user = ref.read(currentUserProvider)!;
                            final now =
                                DateTime.now().toUtc().toIso8601String();
                            await db.from('CreditPayment').insert({
                              'station_id': user.stationId,
                              'customer_id': customer['id'],
                              'amount': amt,
                              'payment_mode': method,
                              // CreditTransaction has no notes column
                              'date': now.split('T')[0],
                              'created_by_id': user.id,
                              'created_at': now,
                            });
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text(
                                      '✅ Payment of ${IndianCurrency.format(amt)} recorded'),
                                  backgroundColor: AppColors.green));
                              _fetch();
                              if (_selectedCustomer?['id'] == customer['id'])
                                _loadLedger(customer);
                            }
                          } catch (e) {
                            ss(() {
                              submitting = false;
                              err = e.toString();
                            });
                          }
                        },
                      ),
                    ]),
              )),
    );
    amtCtrl.dispose();
    noteCtrl.dispose();
  }

  // ── Add customer ────────────────────────────────────────────────────────────
  Future<void> _showAddCustomer() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final vehicleCtrl = TextEditingController();
    final limitCtrl =
        TextEditingController(text: '0'); // CreditCustomer has no credit_limit
    bool submitting = false;
    String? err;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, ss) => Padding(
                padding: EdgeInsets.fromLTRB(
                    20, 20, 20, MediaQuery.viewInsetsOf(ctx).bottom + 24),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('New Credit Customer',
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 16),
                      TextField(
                          controller: nameCtrl,
                          textCapitalization: TextCapitalization.words,
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: InputDecoration(
                              labelText: 'Full Name *',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              filled: true,
                              fillColor: AppColors.bgCard)),
                      const SizedBox(height: 12),
                      TextField(
                          controller: phoneCtrl,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: InputDecoration(
                              labelText: 'Mobile Number *',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              filled: true,
                              fillColor: AppColors.bgCard)),
                      const SizedBox(height: 12),
                      TextField(
                          controller: vehicleCtrl,
                          textCapitalization: TextCapitalization.characters,
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: InputDecoration(
                              labelText: 'Vehicle Number (optional)',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              filled: true,
                              fillColor: AppColors.bgCard)),
                      const SizedBox(height: 12),
                      TextField(
                          controller: limitCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: InputDecoration(
                              labelText: 'Credit Limit (₹)',
                              prefixText: '₹ ',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              filled: true,
                              fillColor: AppColors.bgCard)),
                      if (err != null) ...[
                        const SizedBox(height: 8),
                        Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                                color: AppColors.redBg,
                                borderRadius: BorderRadius.circular(6)),
                            child: Text(err!,
                                style: const TextStyle(
                                    color: AppColors.red, fontSize: 12)))
                      ],
                      const SizedBox(height: 16),
                      AppButton(
                          label: 'Add Customer',
                          loading: submitting,
                          width: double.infinity,
                          onTap: () async {
                            if (nameCtrl.text.trim().isEmpty ||
                                phoneCtrl.text.trim().isEmpty) {
                              ss(() => err = 'Name and phone required');
                              return;
                            }
                            ss(() {
                              submitting = true;
                              err = null;
                            });
                            try {
                              final db = TenantService.instance.client;
                              final user = ref.read(currentUserProvider)!;
                              // CreditCustomer: full_name, phone_number, customer_code (unique per station)
                              // NO customer_code, NO credit_limit columns.
                              final code =
                                  'CC-${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}';
                              await db.from('CreditCustomer').insert({
                                'station_id': user.stationId,
                                'full_name': nameCtrl.text.trim(),
                                'phone_number': phoneCtrl.text.trim(),
                                'customer_code': code,
                                'active': true,
                                'is_walk_in': false,
                                'advance_balance': 0,
                                'created_by_id': user.id,
                                'created_at':
                                    DateTime.now().toUtc().toIso8601String(),
                                'updated_at':
                                    DateTime.now().toUtc().toIso8601String(),
                              });
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('✅ Customer added'),
                                        backgroundColor: AppColors.green));
                                _fetch();
                              }
                            } catch (e) {
                              ss(() {
                                submitting = false;
                                err = e.toString().contains('duplicate')
                                    ? 'This phone number already has a credit account'
                                    : e.toString();
                              });
                            }
                          }),
                    ]),
              )),
    );
    nameCtrl.dispose();
    phoneCtrl.dispose();
    vehicleCtrl.dispose();
    limitCtrl.dispose();
  }

  void _sendWhatsApp(Map<String, dynamic> customer) {
    final stationName = ref.read(stationNameProvider);
    final outstanding = customer['outstanding'] as double? ?? 0;
    final name = customer['full_name'] as String? ?? '';
    final phone = (customer['phone_number'] as String? ?? '')
        .replaceAll(RegExp(r'\D'), '');
    final msg =
        'Dear $name,\n\nYou have an outstanding credit balance of ${IndianCurrency.format(outstanding)} at *$stationName*.\n\nPlease clear at your earliest convenience. Thank you!\n\n_Sent via FuelOS_';
    final url = Uri.encodeFull('https://wa.me/91$phone?text=$msg');
    Share.share(msg);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final isManager = user?.isManagerOrDealer ?? false;
    final filtered = _filtered;

    if (_loading)
      return const Scaffold(
          backgroundColor: AppColors.bgApp, body: LoadingView());
    if (_error != null)
      return Scaffold(
          backgroundColor: AppColors.bgApp,
          body: ErrorView(message: _error!, onRetry: _fetch));

    // On wide screens: two panels; on narrow: ledger is a sheet
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width > 700;

    final customerList = Column(children: [
      // Summary
      Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border)),
        child: Row(children: [
          _StatPill('Customers', '${_customers.length}', AppColors.blue),
          Container(width: 1, height: 30, color: AppColors.border),
          _StatPill('Outstanding',
              IndianCurrency.formatCompact(_totalOutstanding), AppColors.amber),
          Container(width: 1, height: 30, color: AppColors.border),
          _StatPill(
              'With Balance',
              '${_customers.where((c) => (c['outstanding'] as double? ?? 0) > 0).length}',
              AppColors.red),
        ]),
      ),

      // Search + filter
      Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(children: [
            TextField(
              style:
                  const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search,
                      size: 18, color: AppColors.textMuted),
                  hintText: 'Search name, phone, vehicle...',
                  hintStyle:
                      const TextStyle(color: AppColors.textMuted, fontSize: 13),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  filled: true,
                  fillColor: AppColors.bgCard,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
              onChanged: (v) => setState(() => _search = v),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                    children: ['ALL', 'OUTSTANDING', 'CLEARED'].map((f) {
                  final sel = _filter == f;
                  return GestureDetector(
                      onTap: () => setState(() => _filter = f),
                      child: Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                              color: sel ? AppColors.blue : AppColors.bgCard,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color:
                                      sel ? AppColors.blue : AppColors.border)),
                          child: Text(f,
                              style: TextStyle(
                                  color: sel
                                      ? Colors.white
                                      : AppColors.textSecondary,
                                  fontSize: 12,
                                  fontWeight: sel
                                      ? FontWeight.w600
                                      : FontWeight.w400))));
                }).toList())),
          ])),

      // Customer list
      Expanded(
          child: filtered.isEmpty
              ? const EmptyView(
                  title: 'No customers found', icon: Icons.credit_card_outlined)
              : RefreshIndicator(
                  onRefresh: _fetch,
                  color: AppColors.blue,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final c = filtered[i] as Map<String, dynamic>;
                      final outstanding = c['outstanding'] as double? ?? 0;
                      const limit =
                          0.0; // CreditCustomer has no credit_limit column
                      final isOver = outstanding > limit;
                      return AppCard(
                        onTap: () {
                          if (isWide) {
                            _loadLedger(c);
                          } else {
                            _loadLedger(c);
                            _showLedgerSheet(c);
                          }
                        },
                        borderColor: isOver
                            ? AppColors.red.withOpacity(0.3)
                            : (outstanding > 0
                                ? AppColors.amber.withOpacity(0.2)
                                : null),
                        child: Row(children: [
                          Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                  color: outstanding > 0
                                      ? AppColors.amberBg
                                      : AppColors.greenBg,
                                  borderRadius: BorderRadius.circular(10)),
                              alignment: Alignment.center,
                              child: Text(
                                  (c['full_name'] as String? ?? 'C')[0]
                                      .toUpperCase(),
                                  style: TextStyle(
                                      color: outstanding > 0
                                          ? AppColors.amber
                                          : AppColors.green,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16))),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(c['full_name'] as String? ?? '',
                                    style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.w600)),
                                Text(
                                    '${c['phone_number'] ?? ''}${c['customer_code'] != null ? ' · ${c['customer_code']}' : ''}',
                                    style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12)),
                              ])),
                          Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(IndianCurrency.format(outstanding),
                                    style: TextStyle(
                                        color: outstanding > 0
                                            ? (isOver
                                                ? AppColors.red
                                                : AppColors.amber)
                                            : AppColors.green,
                                        fontWeight: FontWeight.w700)),
                                Text(
                                    'Limit: ${IndianCurrency.formatCompact(0)}',
                                    style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 11)),
                              ]),
                        ]),
                      );
                    },
                  ))),
    ]);

    return Scaffold(
      backgroundColor: AppColors.bgApp,
      floatingActionButton: isManager
          ? Column(mainAxisSize: MainAxisSize.min, children: [
              FloatingActionButton(
                  heroTag: 'add_entry',
                  onPressed: _showAddCreditEntry,
                  tooltip: 'Add Credit Entry',
                  backgroundColor: AppColors.blue,
                  child: const Icon(Icons.add_card)),
              const SizedBox(height: 8),
              FloatingActionButton(
                  heroTag: 'add_cust',
                  onPressed: _showAddCustomer,
                  tooltip: 'New Customer',
                  mini: true,
                  backgroundColor: AppColors.bgCard,
                  foregroundColor: AppColors.textPrimary,
                  child: const Icon(Icons.person_add_alt, size: 20)),
            ])
          : null,
      body: isWide
          ? Row(children: [
              SizedBox(
                  width: 380,
                  child: Column(children: [Expanded(child: customerList)])),
              const VerticalDivider(width: 1, color: AppColors.border),
              Expanded(
                  child: _selectedCustomer == null
                      ? const Center(
                          child: Text('Select a customer to view ledger',
                              style: TextStyle(color: AppColors.textMuted)))
                      : _buildLedger(_selectedCustomer!)),
            ])
          : customerList,
    );
  }

  void _showLedgerSheet(Map<String, dynamic> customer) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, ctrl) => _buildLedger(customer, scrollCtrl: ctrl),
      ),
    );
  }

  Widget _buildLedger(Map<String, dynamic> customer,
      {ScrollController? scrollCtrl}) {
    final outstanding = customer['outstanding'] as double? ?? 0;
    const limit = 0.0;
    final isManager = ref.read(currentUserProvider)?.isManagerOrDealer ?? false;

    // Build merged ledger
    final List<Map<String, dynamic>> ledger = [];
    for (final t in _txns) {
      ledger.add({...Map<String, dynamic>.from(t as Map), '_type': 'CREDIT'});
    }
    for (final p in _payments) {
      ledger.add({...Map<String, dynamic>.from(p as Map), '_type': 'PAYMENT'});
    }
    ledger.sort((a, b) =>
        (b['created_at'] as String).compareTo(a['created_at'] as String));

    return Column(children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(children: [
            Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            Row(children: [
              Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: AppColors.purpleBg,
                      borderRadius: BorderRadius.circular(10)),
                  alignment: Alignment.center,
                  child: Text(
                      (customer['full_name'] as String? ?? 'C')[0]
                          .toUpperCase(),
                      style: const TextStyle(
                          color: AppColors.purple,
                          fontWeight: FontWeight.w700,
                          fontSize: 16))),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(customer['full_name'] as String,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 16)),
                    Text(
                        '${customer['phone_number'] ?? ''} ${customer['customer_code'] != null ? '· ${customer['customer_code']}' : ''}',
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 12)),
                  ])),
              if (isManager) ...[
                IconButton(
                    icon: const Icon(Icons.add_card,
                        color: AppColors.red, size: 20),
                    onPressed: () => _showAddCreditEntry(customer),
                    tooltip: 'Add Credit'),
                IconButton(
                    icon: const Icon(Icons.payments_outlined,
                        color: AppColors.green, size: 20),
                    onPressed: () => _showRecordPayment(customer),
                    tooltip: 'Record Payment'),
                IconButton(
                    icon: const Icon(Icons.chat_bubble_outline,
                        color: AppColors.green, size: 18),
                    onPressed: () => _sendWhatsApp(customer),
                    tooltip: 'WhatsApp Reminder'),
              ],
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: outstanding > 0
                              ? AppColors.amberBg
                              : AppColors.greenBg,
                          borderRadius: BorderRadius.circular(8)),
                      child: Column(children: [
                        Text('Outstanding',
                            style: TextStyle(
                                color: outstanding > 0
                                    ? AppColors.amber
                                    : AppColors.green,
                                fontSize: 11)),
                        Text(IndianCurrency.format(outstanding),
                            style: TextStyle(
                                color: outstanding > 0
                                    ? AppColors.amber
                                    : AppColors.green,
                                fontWeight: FontWeight.w800,
                                fontSize: 18)),
                      ]))),
              const SizedBox(width: 8),
              Expanded(
                  child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: AppColors.bgCard,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border)),
                      child: Column(children: [
                        const Text('Credit Limit',
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 11)),
                        Text(IndianCurrency.format(limit),
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w700,
                                fontSize: 16)),
                      ]))),
            ]),
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.border),
          ])),
      Expanded(
          child: _loadingLedger
              ? const LoadingView()
              : ledger.isEmpty
                  ? const EmptyView(
                      title: 'No transactions yet',
                      icon: Icons.receipt_long_outlined)
                  : ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.all(16),
                      itemCount: ledger.length,
                      itemBuilder: (_, i) {
                        final entry = ledger[i];
                        final isCredit = entry['_type'] == 'CREDIT';
                        final amt = double.tryParse(
                                entry['amount']?.toString() ?? '0') ??
                            0;
                        final date = DateTime.tryParse(
                            entry['created_at'] as String? ?? '');
                        return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(children: [
                              Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                      color: isCredit
                                          ? AppColors.redBg
                                          : AppColors.greenBg,
                                      borderRadius: BorderRadius.circular(8)),
                                  child: Icon(
                                      isCredit
                                          ? Icons.arrow_upward
                                          : Icons.arrow_downward,
                                      size: 14,
                                      color: isCredit
                                          ? AppColors.red
                                          : AppColors.green)),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(
                                        isCredit
                                            ? '${entry['fuel_type'] ?? 'Credit'} — ${entry['litres'] != null ? IndianCurrency.formatLitres(double.tryParse(entry['litres']?.toString() ?? '0') ?? 0) : 'Manual'}'
                                            : (entry['payment_mode']
                                                    as String? ??
                                                'Payment'),
                                        style: const TextStyle(
                                            color: AppColors.textPrimary,
                                            fontWeight: FontWeight.w500,
                                            fontSize: 13)),
                                    if (date != null)
                                      Text(IstTime.formatDateTime(date),
                                          style: const TextStyle(
                                              color: AppColors.textMuted,
                                              fontSize: 11)),
                                  ])),
                              Text(
                                  '${isCredit ? '+' : '−'} ${IndianCurrency.format(amt)}',
                                  style: TextStyle(
                                      color: isCredit
                                          ? AppColors.red
                                          : AppColors.green,
                                      fontWeight: FontWeight.w600)),
                            ]));
                      },
                    )),
    ]);
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatPill(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
          child: Column(children: [
        Text(value,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w800, fontSize: 15)),
        Text(label,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 10))
      ]));
}
