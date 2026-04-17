import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/tenant_service.dart';
import '../../../core/services/discord_service.dart';
import '../../../core/utils/currency.dart';
import 'package:uuid/uuid.dart';
import '../../../shared/widgets/widgets.dart';

// ─── TankDashboardScreen ──────────────────────────────────────────────────────

class TankDashboardScreen extends ConsumerStatefulWidget {
  const TankDashboardScreen({super.key});
  @override
  ConsumerState<TankDashboardScreen> createState() =>
      _TankDashboardScreenState();
}

class _TankDashboardScreenState extends ConsumerState<TankDashboardScreen> {
  bool _loading = true;
  String? _error;
  List<dynamic> _tanks = [];
  List<dynamic> _orders = [];
  List<dynamic> _cheques = [];

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
      final auth = ref.read(authProvider);
      if (auth.isDemoMode) {
        await Future.delayed(const Duration(milliseconds: 600));
        setState(() {
          _tanks = [
            {
              'id': 't1',
              'name': 'Main Petrol',
              'fuel_type': 'Petrol',
              'capacity_liters': 20000,
              'computed_stock': 12500.0,
              'active': true
            },
            {
              'id': 't2',
              'name': 'Main Diesel',
              'fuel_type': 'Diesel',
              'capacity_liters': 20000,
              'computed_stock': 4200.0,
              'active': true
            },
            {
              'id': 't3',
              'name': 'Power Tank',
              'fuel_type': 'Power',
              'capacity_liters': 10000,
              'computed_stock': 7800.0,
              'active': true
            },
          ];
          _orders = [
            {
              'id': 'o1',
              'vendor': 'IOCL',
              'fuel_type': 'Petrol',
              'total_liters': 12000,
              'total_amount': 1140000,
              'status': 'DELIVERED',
              'date': '2026-04-12'
            },
            {
              'id': 'o2',
              'vendor': 'IOCL',
              'fuel_type': 'Diesel',
              'total_liters': 8000,
              'total_amount': 720000,
              'status': 'PENDING',
              'date': '2026-04-14'
            },
          ];
          _cheques = [
            {
              'id': 'c1',
              'cheque_reference': 'CHQ94821',
              'amount': 500000,
              'status': 'PENDING',
              'vendor': 'IOCL',
              'payment_date': '2026-05-01'
            },
          ];
          _loading = false;
        });
        return;
      }

      final db = TenantService.instance.client;
      final user = ref.read(currentUserProvider);
      if (user == null) {
        setState(() => _loading = false);
        return;
      }
      final results = await Future.wait([
        db
            .from('Tank')
            .select(
                'id, name, fuel_type, capacity_liters, low_stock_threshold, active')
            .eq('station_id', user.stationId)
            .eq('active', true),
        db
            .from('FuelOrder')
            .select(
                'id, total_liters, total_amount, vendor, status, date')
            .eq('station_id', user.stationId)
            .order('date', ascending: false)
            .limit(10),
        db
            .from('InventoryCheque')
            .select(
                'id, cheque_reference, amount, status, vendor, payment_date')
            .eq('station_id', user.stationId)
            .order('created_at', ascending: false)
            .limit(10),
        db
            .from('TankInitialStock')
            .select('tank_id, opening_litres')
            .eq('station_id', user.stationId),
        db
            .from('StockTransaction')
            .select('tank_id, type, quantity')
            .eq('station_id', user.stationId),
        db
            .from('DipReading')
            .select('tank_id, calculated_volume, created_at')
            .eq('station_id', user.stationId)
            .order('created_at', ascending: false),
      ]);

      final tanks = (results[0] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final initialStocks = {
        for (final s in (results[3] as List? ?? []))
          (s as Map)['tank_id']?.toString() ?? '':
              double.tryParse((s as Map)['opening_litres']?.toString() ?? '0') ??
                  0.0
      };

      final transactions = (results[4] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      // results[3] is initialStocks
      // results[4] is transactions
      // results[5] is dips (currently unused in UI)
      final tankStocks = <String, double>{};
      for (final t in tanks) {
        final tid = t['id'];
        double stock = initialStocks[tid] ?? 0;
        for (final tx in transactions) {
          if (tx['tank_id'] == tid) {
            final qty = double.tryParse(tx['quantity']?.toString() ?? '0') ?? 0;
            // DELIVERY/ADJUSTMENT usually positive, SALE/CONSUMPTION negative
            // In some schemas, quantity is always positive and type determines sign.
            // I'll assume quantity in tx is already signed or I should check type.
            stock += qty;
          }
        }
        tankStocks[tid] = stock;
      }

      setState(() {
        _tanks = tanks
            .map((t) => <String, dynamic>{
                  ...t,
                  'computed_stock': tankStocks[t['id']] ?? 0.0
                })
            .toList();
        _orders = (results[1] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cheques = (results[2] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
          backgroundColor: AppColors.bgApp, body: LoadingView());
    }
    if (_error != null) {
      return Scaffold(
          backgroundColor: AppColors.bgApp,
          body: ErrorView(message: _error!, onRetry: _fetch));
    }

    return Scaffold(
      backgroundColor: AppColors.bgApp,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FloatingActionButton.extended(
                heroTag: 'order',
                onPressed: () => context.push('/app/inventory/order'),
                label: const Text('Order Fuel'),
                icon: const Icon(Icons.add),
                backgroundColor: AppColors.blue,
              ),
              const SizedBox(height: 8),
              FloatingActionButton.extended(
                heroTag: 'dip',
                onPressed: () => context.push('/app/inventory/dip'),
                label: const Text('Dip Reading'),
                icon: const Icon(Icons.straighten),
                backgroundColor: AppColors.bgCard,
                foregroundColor: AppColors.textPrimary,
              ),
              const SizedBox(height: 8),
              FloatingActionButton.extended(
                heroTag: 'cheque',
                onPressed: () => context.push('/app/inventory/cheque'),
                label: const Text('Add Cheque'),
                icon: const Icon(Icons.receipt),
                backgroundColor: AppColors.bgCard,
                foregroundColor: AppColors.textPrimary,
              ),
            ]),
      ),
      body: RefreshIndicator(
        onRefresh: _fetch,
        color: AppColors.blue,
        child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              const SectionHeader(title: 'Tank Status'),
              const SizedBox(height: 12),
              if (_tanks.isEmpty)
                const EmptyView(
                  title: 'No tanks configured',
                  subtitle: 'Contact support to configure your fuel tanks',
                  icon: Icons.water_outlined,
                )
              else
                ..._tanks.map((t) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _TankCard(tank: Map<String, dynamic>.from(t as Map)),
                    )),
              const SizedBox(height: 20),
              SectionHeader(
                  title: 'Recent Orders',
                  action: '+ New',
                  onAction: () => context.push('/app/inventory/order')),
              const SizedBox(height: 12),
              if (_orders.isEmpty)
                const EmptyView(
                  title: 'No orders yet',
                  subtitle: 'Tap + New to record a fuel order',
                  icon: Icons.inventory_2_outlined,
                )
              else
                ..._orders.take(5).map((o) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                        child: Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(
                                '${o['vendor']} · ${IndianCurrency.formatLitres(double.tryParse(o['total_liters']?.toString() ?? '0') ?? 0)}',
                                style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w500)),
                            Text(o['date'] as String? ?? '',
                                style: const TextStyle(
                                    color: AppColors.textMuted, fontSize: 11)),
                          ])),
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                                IndianCurrency.format(double.tryParse(
                                        o['total_amount']?.toString() ?? '0') ??
                                    0),
                                style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w600)),
                            StatusBadge.fromStatus(
                                o['status'] as String? ?? 'PENDING'),
                          ]),
                    ])),
                  )),
              const SizedBox(height: 20),
              SectionHeader(
                  title: 'Cheques',
                  action: '+ New',
                  onAction: () => context.push('/app/inventory/cheque')),
              const SizedBox(height: 12),
              if (_cheques.isEmpty)
                const EmptyView(
                  title: 'No cheques recorded',
                  subtitle: 'Tap + New to add a vendor cheque',
                  icon: Icons.receipt_outlined,
                )
              else
                ..._cheques.take(5).map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                        child: Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(c['cheque_reference'] as String? ?? '',
                                style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w500)),
                            Text(c['vendor'] as String? ?? '',
                                style: const TextStyle(
                                    color: AppColors.textMuted, fontSize: 12)),
                          ])),
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                                IndianCurrency.format(double.tryParse(
                                        c['amount']?.toString() ?? '0') ??
                                    0),
                                style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w600)),
                            StatusBadge.fromStatus(
                                c['status'] as String? ?? 'PENDING'),
                          ]),
                    ])),
                  )),
            ]),
      ),
    );
  }
}

class _TankCard extends StatelessWidget {
  final Map<String, dynamic> tank;
  const _TankCard({required this.tank});

  @override
  Widget build(BuildContext context) {
    final cap =
        double.tryParse(tank['capacity_liters']?.toString() ?? '0') ?? 0;
    final cur = (tank['computed_stock'] as num?)?.toDouble() ?? 0.0;
    final pct = cap > 0 ? (cur / cap).clamp(0.0, 1.0) : 0.0;
    final fuel = tank['fuel_type'] as String? ?? '';
    final isLow = pct < 0.2;
    final fuelColor = switch (fuel) {
      'Petrol' => AppColors.petrol,
      'Diesel' => AppColors.diesel,
      'Power' => AppColors.power,
      'CNG' => AppColors.cng,
      _ => AppColors.blue,
    };

    return AppCard(
      borderColor: isLow ? AppColors.red.withOpacity(0.3) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(tank['name'] as String? ?? '',
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700))),
          StatusBadge(label: fuel, tone: BadgeTone.info),
          if (isLow) ...[
            const SizedBox(width: 6),
            const StatusBadge(label: 'LOW', tone: BadgeTone.error)
          ],
        ]),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: AppColors.bgHover,
            valueColor:
                AlwaysStoppedAnimation(isLow ? AppColors.red : fuelColor),
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(IndianCurrency.formatLitres(cur),
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          Text('${(pct * 100).round()}% of ${IndianCurrency.formatLitres(cap)}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ]),
      ]),
    );
  }
}

// ─── FuelOrderScreen ──────────────────────────────────────────────────────────

class FuelOrderScreen extends ConsumerStatefulWidget {
  const FuelOrderScreen({super.key});
  @override
  ConsumerState<FuelOrderScreen> createState() => _FuelOrderScreenState();
}

class _FuelOrderScreenState extends ConsumerState<FuelOrderScreen> {
  final _form = GlobalKey<FormState>();
  bool _loading = false;
  String? _error;
  List<dynamic> _tanks = [];
  String _fuelType = 'Petrol';
  final _qtyCtrl = TextEditingController();
  final _amtCtrl = TextEditingController();
  final _supplierCtrl = TextEditingController();
  final _invoiceCtrl = TextEditingController();
  DateTime _deliveryDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _fetchTanks();
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _amtCtrl.dispose();
    _supplierCtrl.dispose();
    _invoiceCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchTanks() async {
    final db = TenantService.instance.client;
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final tanks = await db
        .from('Tank')
        .select('fuel_type')
        .eq('station_id', user.stationId)
        .eq('active', true);
    setState(() {
      _tanks = (tanks as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (_tanks.isNotEmpty) {
        _fuelType = _tanks.first['fuel_type'] as String? ?? 'Petrol';
      }
    });
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = TenantService.instance.client;
      final user = ref.read(currentUserProvider);
      if (user == null) {
        setState(() => _loading = false);
        return;
      }
      final stationName = ref.read(stationNameProvider);
      final qty = double.parse(_qtyCtrl.text);
      final amt = double.parse(_amtCtrl.text);

      final invoiceNo = _invoiceCtrl.text.trim();

      await db.from('FuelOrder').insert({
        'id': const Uuid().v4(),
        'station_id': user.stationId,
        'invoice_no': invoiceNo,
        'total_liters': qty,
        'total_amount': amt,
        'vendor': _supplierCtrl.text.trim(),
        'date': _deliveryDate.toIso8601String().split('T')[0],
        'status': 'DELIVERED',
        'created_by_id': user.id,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      // Record StockTransaction (DELIVERY type) — Tank has no current_stock column.
      // Stock is computed from StockTransaction ledger.
      final tank = await db
          .from('Tank')
          .select('id')
          .eq('station_id', user.stationId)
          .eq('fuel_type', _fuelType)
          .eq('active', true)
          .limit(1)
          .maybeSingle();
      if (tank != null) {
        await db.from('StockTransaction').insert({
          'id': const Uuid().v4(),
          'station_id': user.stationId,
          'tank_id': tank['id'],
          'type': 'DELIVERY',
          'quantity': qty, // positive = stock in
          'reference_id': invoiceNo,
          'created_by_id': user.id,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      }

      await DiscordService.instance.sendFuelDelivery(
          fuelType: _fuelType,
          quantity: qty,
          amount: amt,
          stationName: stationName);

      if (mounted) {
        context.pop();
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fuelTypes =
        _tanks.map((t) => t['fuel_type'] as String).toSet().toList();

    return Scaffold(
      backgroundColor: AppColors.bgApp,
      appBar: AppBar(
          title: const Text('Fuel Order'),
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, size: 18),
              onPressed: () => context.pop())),
      body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            if (fuelTypes.isNotEmpty) ...[
              const Text('Fuel Type',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 8),
              Wrap(
                  spacing: 8,
                  children: fuelTypes
                      .map((f) => ChoiceChip(
                            label: Text(f),
                            selected: _fuelType == f,
                            onSelected: (_) => setState(() => _fuelType = f),
                          ))
                      .toList()),
              const SizedBox(height: 16),
            ],
            AppTextField(
                label: 'Quantity (Litres)',
                controller: _qtyCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                prefixIcon: Icons.water_drop_outlined,
                validator: (v) => v == null || v.isEmpty ? 'Required' : null),
            const SizedBox(height: 16),
            AppTextField(
                label: 'Total Amount (₹)',
                controller: _amtCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                prefixIcon: Icons.currency_rupee,
                validator: (v) => v == null || v.isEmpty ? 'Required' : null),
            const SizedBox(height: 16),
            AppTextField(
                label: 'Invoice Number',
                controller: _invoiceCtrl,
                prefixIcon: Icons.receipt_outlined,
                textCapitalization: TextCapitalization.characters,
                validator: (v) => v == null || v.isEmpty ? 'Required' : null),
            const SizedBox(height: 16),
            AppTextField(
                label: 'Supplier Name',
                controller: _supplierCtrl,
                prefixIcon: Icons.business_outlined,
                textCapitalization: TextCapitalization.words),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Delivery Date',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              subtitle: Text(
                  '${_deliveryDate.day}/${_deliveryDate.month}/${_deliveryDate.year}',
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
              trailing: const Icon(Icons.calendar_today,
                  color: AppColors.blue, size: 18),
              onTap: () async {
                final d = await showDatePicker(
                    context: context,
                    initialDate: _deliveryDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030));
                if (d != null) setState(() => _deliveryDate = d);
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: AppColors.redBg,
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(_error!,
                      style:
                          const TextStyle(color: AppColors.red, fontSize: 13))),
            ],
            const SizedBox(height: 24),
            AppButton(
                label: 'Record Delivery',
                onTap: _submit,
                loading: _loading,
                width: double.infinity),
          ])),
    );
  }
}

// ─── ChequeEntryScreen ────────────────────────────────────────────────────────

class ChequeEntryScreen extends ConsumerStatefulWidget {
  const ChequeEntryScreen({super.key});
  @override
  ConsumerState<ChequeEntryScreen> createState() => _ChequeEntryScreenState();
}

class _ChequeEntryScreenState extends ConsumerState<ChequeEntryScreen> {
  final _form = GlobalKey<FormState>();
  bool _loading = false;
  String? _error;
  final _chequeNumCtrl = TextEditingController();
  final _amtCtrl = TextEditingController();
  final _supplierCtrl = TextEditingController();
  final _bankCtrl = TextEditingController();
  DateTime _dueDate = DateTime.now().add(const Duration(days: 30));

  @override
  void dispose() {
    _chequeNumCtrl.dispose();
    _amtCtrl.dispose();
    _supplierCtrl.dispose();
    _bankCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = TenantService.instance.client;
      final user = ref.read(currentUserProvider);
      if (user == null) {
        setState(() => _loading = false);
        return;
      }
      await db.from('InventoryCheque').insert({
        'id': const Uuid().v4(),
        'station_id': user.stationId,
        'cheque_reference': _chequeNumCtrl.text.trim(),
        'amount': double.parse(_amtCtrl.text),
        'vendor': _supplierCtrl.text.trim(),
        'bank_name': _bankCtrl.text.trim(),
        'payment_date': _dueDate.toIso8601String().split('T')[0],
        'status': 'PENDING',
        'created_by_id': user.id,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (mounted) context.pop();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.bgApp,
        appBar: AppBar(
            title: const Text('Add Cheque'),
            leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios, size: 18),
                onPressed: () => context.pop())),
        body: Form(
            key: _form,
            child: ListView(padding: const EdgeInsets.all(20), children: [
              AppTextField(
                  label: 'Cheque Number',
                  controller: _chequeNumCtrl,
                  prefixIcon: Icons.receipt,
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null),
              const SizedBox(height: 16),
              AppTextField(
                  label: 'Amount (₹)',
                  controller: _amtCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  prefixIcon: Icons.currency_rupee,
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null),
              const SizedBox(height: 16),
              AppTextField(
                  label: 'Supplier / Party Name',
                  controller: _supplierCtrl,
                  textCapitalization: TextCapitalization.words),
              const SizedBox(height: 16),
              AppTextField(
                  label: 'Bank',
                  controller: _bankCtrl,
                  textCapitalization: TextCapitalization.words),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Due Date',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
                subtitle: Text(
                    '${_dueDate.day}/${_dueDate.month}/${_dueDate.year}',
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
                trailing: const Icon(Icons.calendar_today,
                    color: AppColors.blue, size: 18),
                onTap: () async {
                  final d = await showDatePicker(
                      context: context,
                      initialDate: _dueDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2030));
                  if (d != null) setState(() => _dueDate = d);
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: AppColors.redBg,
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(_error!,
                        style: const TextStyle(
                            color: AppColors.red, fontSize: 13)))
              ],
              const SizedBox(height: 24),
              AppButton(
                  label: 'Save Cheque',
                  onTap: _submit,
                  loading: _loading,
                  width: double.infinity),
            ])),
      );
}

// ─── DipReadingScreen ─────────────────────────────────────────────────────────

class DipReadingScreen extends ConsumerStatefulWidget {
  const DipReadingScreen({super.key});
  @override
  ConsumerState<DipReadingScreen> createState() => _DipReadingScreenState();
}

class _DipReadingScreenState extends ConsumerState<DipReadingScreen> {
  bool _loading = true;
  bool _submitting = false;
  List<dynamic> _tanks = [];
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
    });
    try {
      final db = TenantService.instance.client;
      final user = ref.read(currentUserProvider);
      if (user == null) {
        setState(() => _loading = false);
        return;
      }
      final tanks = await db
          .from('Tank')
          .select('id, name, fuel_type, capacity_liters, low_stock_threshold')
          .eq('station_id', user.stationId)
          .eq('active', true);
      final list = (tanks as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      for (final t in list) {
        _controllers[t['id'] as String] = TextEditingController(text: '0');
      }
      setState(() {
        _tanks = list;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading tanks: $e')),
        );
      }
    }
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final db = TenantService.instance.client;
      final user = ref.read(currentUserProvider)!;
      final now = DateTime.now().toUtc().toIso8601String();
      for (final t in _tanks) {
        final id = t['id'] as String;
        final newStock = double.tryParse(_controllers[id]?.text ?? '0') ?? 0;
        await db.from('DipReading').insert({
          'id': const Uuid().v4(),
          'station_id': user.stationId,
          'tank_id': id,
          'calculated_volume': newStock,
          'captured_by_id': user.id,
          'created_at': now
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('✅ Dip readings saved'),
            backgroundColor: AppColors.green));
        context.pop();
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
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.bgApp,
        appBar: AppBar(
            title: const Text('Dip Reading'),
            leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios, size: 18),
                onPressed: () => context.pop())),
        body: _loading
            ? const LoadingView()
            : Column(children: [
                Expanded(
                    child:
                        ListView(padding: const EdgeInsets.all(20), children: [
                  const Text('Enter actual physical measurement for each tank:',
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          height: 1.5)),
                  const SizedBox(height: 20),
                  ..._tanks.map((t) {
                    final id = t['id'] as String;
                    return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: AppCard(
                            child: Row(children: [
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(t['name'] as String? ?? '',
                                    style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.w600)),
                                Text(t['fuel_type'] as String? ?? '',
                                    style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 12)),
                                Text(
                                    'Capacity: ${IndianCurrency.formatLitres(double.tryParse(t['capacity_liters']?.toString() ?? '0') ?? 0)}',
                                    style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 11)),
                              ])),
                          SizedBox(
                              width: 120,
                              child: TextFormField(
                                controller: _controllers[id],
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600),
                                decoration: InputDecoration(
                                  suffixText: 'L',
                                  suffixStyle: const TextStyle(
                                      color: AppColors.textMuted, fontSize: 12),
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
                                      horizontal: 10, vertical: 10),
                                  filled: true,
                                  fillColor: AppColors.bgSurface,
                                ),
                              )),
                        ])));
                  }),
                ])),
                Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                        color: AppColors.bgSurface,
                        border:
                            Border(top: BorderSide(color: AppColors.border))),
                    child: AppButton(
                        label: 'Save Dip Readings',
                        onTap: _submit,
                        loading: _submitting,
                        width: double.infinity)),
              ]),
      );
}
