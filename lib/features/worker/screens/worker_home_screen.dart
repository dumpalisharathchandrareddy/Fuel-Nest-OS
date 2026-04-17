// ─── worker_home_screen.dart ──────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/tenant_service.dart';
import '../../../core/utils/ist_time.dart';
import '../../../core/utils/currency.dart';
import '../../../shared/widgets/widgets.dart';

class WorkerHomeScreen extends ConsumerStatefulWidget {
  const WorkerHomeScreen({super.key});

  @override
  ConsumerState<WorkerHomeScreen> createState() => _WorkerHomeScreenState();
}

class _WorkerHomeScreenState extends ConsumerState<WorkerHomeScreen> {
  bool _loading = true;
  String? _error;
  List<dynamic> _pumps = [];
  List<dynamic> _activeShifts = [];

  Map<String, dynamic>? _getMap(dynamic data) {
    if (data == null) return null;
    if (data is List) {
      if (data.isEmpty) return null;
      return Map<String, dynamic>.from(data.first as Map);
    }
    return Map<String, dynamic>.from(data as Map);
  }

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
      final user = ref.read(currentUserProvider);

      if (user == null) {
        setState(() => _loading = false);
        return;
      }

      final pumps = await db
          .from('Pump')
          .select(
              'id, name, provider_type, nozzles:Nozzle(id, label, fuel_type)')
          .eq('station_id', user.stationId)
          .eq('active', true)
          .order('name');

      // Check if user has an active/submitted shift
      final activeShifts = await db
          .from('Shift')
          .select(
              'id, status, start_time, pump:Pump(name), assigned_worker:User(full_name), nozzle_entries:NozzleEntry(id, nozzle:Nozzle(label, fuel_type), opening_reading, closing_reading, sale_litres, rate, sale_amount)')
          .eq('station_id', user.stationId)
          .eq('assigned_user_id', user.id)
          .inFilter('status', ['OPEN', 'SUBMITTED'])
          .order('created_at', ascending: false)
          .limit(1);

      setState(() {
        _activeShifts = activeShifts;
        if (user.role == 'PUMP_PERSON') {
          // Only show pumps that have an active shift assigned to this worker
          final activePumpIds = activeShifts
              .map((s) => _getMap(s['pump'])?['id'])
              .where((id) => id != null)
              .toSet();
          _pumps = pumps.where((p) => activePumpIds.contains(p['id'])).toList();
        } else {
          _pumps = pumps;
        }
        _loading = false;
      });

      // Redirect workers directly if they have exactly one active shift
      if (activeShifts.length == 1 && user.role == 'PUMP_PERSON') {
        context.go('/worker/shift/${activeShifts.first['id']}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final stationName = ref.watch(stationNameProvider);

    return Scaffold(
      backgroundColor: AppColors.bgApp,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user?.fullName ?? '',
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            Text(stationName,
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 11)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_balance_wallet_outlined, size: 20),
            onPressed: () => context.push('/worker/earnings'),
            tooltip: 'My Earnings',
          ),
          IconButton(
            icon:
                const Icon(Icons.logout, size: 18, color: AppColors.textMuted),
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
            },
            tooltip: 'Logout',
          ),
        ],
      ),
      body: _loading
          ? const LoadingView(message: 'Loading pumps...')
          : _error != null
              ? ErrorView(message: _error!, onRetry: _fetch)
              : RefreshIndicator(
                  onRefresh: _fetch,
                  color: AppColors.blue,
                  child: CustomScrollView(
                    slivers: [
                      // Active shift banners
                      ..._activeShifts.map((shift) => SliverToBoxAdapter(
                            child: GestureDetector(
                              onTap: () => context
                                  .push('/worker/shift/${shift['id']}'),
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: shift['status'] == 'SUBMITTED' 
                                    ? AppColors.blue.withValues(alpha: 0.1)
                                    : AppColors.greenBg,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: (shift['status'] == 'SUBMITTED' ? AppColors.blue : AppColors.green).withValues(alpha: 0.1)),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: shift['status'] == 'SUBMITTED' ? AppColors.blue : AppColors.green,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${shift['status'] == 'SUBMITTED' ? 'Submitted' : 'Active'} Shift — ${(_getMap(shift['pump']))?['name'] ?? ''}',
                                            style: TextStyle(
                                              color: shift['status'] == 'SUBMITTED' ? AppColors.blue : AppColors.green,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          Text(
                                            'Started ${IstTime.formatRelativeDate(DateTime.parse(shift['start_time'] as String? ?? shift['created_at'] as String))}',
                                            style: const TextStyle(
                                                color: AppColors.textSecondary,
                                                fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text('Continue →',
                                        style: TextStyle(
                                            color: shift['status'] == 'SUBMITTED' ? AppColors.blue : AppColors.green,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          )),

                      if (user?.role != 'PUMP_PERSON')
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(20, 4, 20, 16),
                            child: Text(
                              'Select Pump to Start Entry',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),

                      if (_pumps.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: EmptyView(
                            title: user?.role == 'PUMP_PERSON' ? 'No active shift assigned' : 'No pumps available',
                            subtitle: user?.role == 'PUMP_PERSON' 
                              ? 'Contact your manager to assign a shift'
                              : 'No active pumps are assigned to this station',
                            icon: Icons.local_gas_station_outlined,
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverGrid(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount:
                                  MediaQuery.sizeOf(context).width > 500 ? 3 : 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 1.1,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (_, i) => _PumpCard(
                                pump: _pumps[i],
                                hasActiveShift: _activeShifts.isNotEmpty,
                                onTap: () => context
                                    .push('/worker/nozzle/${_pumps[i]['id']}'),
                              ),
                              childCount: _pumps.length,
                            ),
                          ),
                        ),
                      const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
                    ],
                  ),
                ),
    );
  }
}

class _PumpCard extends StatelessWidget {
  final Map<String, dynamic> pump;
  final bool hasActiveShift;
  final VoidCallback onTap;

  const _PumpCard({
    required this.pump,
    required this.hasActiveShift,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final nozzles = pump['nozzles'] as List? ?? [];
    final fuelTypes = nozzles.map((n) {
      final nm = n is Map ? n : {};
      return nm['fuel_type'];
    }).where((f) => f != null).toSet().join(', ');

    return AppCard(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.blueBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.local_gas_station,
                color: AppColors.blue, size: 22),
          ),
          const SizedBox(height: 10),
          Text(
            pump['name'] as String? ?? 'Pump',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            fuelTypes,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            '${nozzles.length} nozzle${nozzles.length != 1 ? 's' : ''}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

// ─── nozzle_entry_screen.dart ─────────────────────────────────────────────────

class NozzleEntryScreen extends ConsumerStatefulWidget {
  final String pumpId;
  const NozzleEntryScreen({super.key, required this.pumpId});

  @override
  ConsumerState<NozzleEntryScreen> createState() => _NozzleEntryScreenState();
}

class _NozzleEntryScreenState extends ConsumerState<NozzleEntryScreen> {
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  Map<String, dynamic>? _shift;
  List<Map<String, dynamic>> _readings = [];
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, TextEditingController> _testingControllers = {};
  final Map<String, TextEditingController> _reasonControllers = {};
  final Map<String, double> _defaultTestings = {};
  final Map<String, double> _tankStocks = {};

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
    for (final c in _testingControllers.values) {
      c.dispose();
    }
    for (final c in _reasonControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _fetch() async {
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

      // Get any active or recently finished shift for this pump
      final shifts = await db
          .from('Shift')
          .select(
              'id, status, created_at, nozzle_entries:NozzleEntry(id, nozzle_id, opening_reading, closing_reading, testing_quantity, testing_override_reason, rate, nozzle:Nozzle(label, fuel_type, tank_id, default_testing))')
          .eq('pump_id', widget.pumpId)
          .eq('station_id', user.stationId)
          .order('created_at', ascending: false)
          .limit(1);

      if (shifts.isEmpty) {
        setState(() {
          _error = 'No active shift found for this pump. Ask your manager to open a shift.';
          _loading = false;
        });
        return;
      }

      final shift = shifts.first;
      final entries = shift['nozzle_entries'] as List? ?? [];

      if (entries.isEmpty) {
        setState(() {
          _error = 'No nozzles assigned to this pump.';
          _loading = false;
        });
        return;
      }

      // Fetch global settings for fallback testing qty
      final settings = await db
          .from('StationSettings')
          .select('testing_fuel_default')
          .eq('station_id', user.stationId)
          .maybeSingle();
      final globalDefaultTesting = double.tryParse(settings?['testing_fuel_default']?.toString() ?? '5') ?? 5.0;

      // Extract unique tanks to fetch stock
      final tankIds = entries.map((e) {
        final nozzle = _getMap(e['nozzle']);
        return nozzle?['tank_id'] as String?;
      }).where((id) => id != null).cast<String>().toSet().toList();
      
      final stockData = await Future.wait([
        db.from('TankInitialStock').select('tank_id, opening_litres').inFilter('tank_id', tankIds).eq('station_id', user.stationId),
        db.from('StockTransaction').select('tank_id, quantity').inFilter('tank_id', tankIds).eq('station_id', user.stationId),
      ]);

      final initialStocks = { for (final s in stockData[0] as List) s['tank_id']: double.tryParse(s['opening_litres']?.toString() ?? '0') ?? 0.0 };
      final transactions = stockData[1] as List;
      
      final calculatedStocks = <String, double>{};
      for (final tid in tankIds) {
        double stock = initialStocks[tid] ?? 0;
        for (final tx in transactions) {
          if (tx['tank_id'] == tid) {
            stock += double.tryParse(tx['quantity']?.toString() ?? '0') ?? 0.0;
          }
        }
        calculatedStocks[tid] = stock;
      }

      final readings = entries.map<Map<String, dynamic>>((e) {
        final nozzle = _getMap(e['nozzle']) ?? {};
        final dTesting = double.tryParse(nozzle['default_testing']?.toString() ?? '') ?? globalDefaultTesting;
        
        return {
          'nozzle_id': e['nozzle_id'],
          'entry_id': e['id'],
          'label': nozzle['label'] ?? '',
          'fuel_type': nozzle['fuel_type'] ?? '',
          'tank_id': nozzle['tank_id'],
          'opening_reading': e['opening_reading'],
          'closing_reading': e['closing_reading'],
          'testing_quantity': e['testing_quantity'],
          'testing_override_reason': e['testing_override_reason'],
          'rate': e['rate'],
          'default_testing': dTesting,
        };
      }).toList();

      for (final r in readings) {
        final key = r['nozzle_id'] as String;
        _controllers[key] = TextEditingController(text: r['closing_reading']?.toString() ?? '');
        _testingControllers[key] = TextEditingController(text: r['testing_quantity']?.toString() ?? r['default_testing'].toString());
        _reasonControllers[key] = TextEditingController(text: r['testing_override_reason'] ?? '');
        _defaultTestings[key] = r['default_testing'];
      }

      setState(() {
        _shift = shift;
        _readings = readings;
        _tankStocks.addAll(calculatedStocks);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Map<String, dynamic>? _getMap(dynamic data) {
    if (data == null) return null;
    if (data is List) {
      if (data.isEmpty) return null;
      return Map<String, dynamic>.from(data.first as Map);
    }
    return Map<String, dynamic>.from(data as Map);
  }

  Future<void> _submit() async {
    // Validate all readings
    for (final r in _readings) {
      final key = r['nozzle_id'] as String;
      final val = double.tryParse(_controllers[key]?.text ?? '');
      final opening = double.tryParse(r['opening_reading']?.toString() ?? '0') ?? 0;
      final testing = double.tryParse(_testingControllers[key]?.text ?? '0') ?? 0;
      final defaultTesting = _defaultTestings[key] ?? 0;
      final reason = _reasonControllers[key]?.text.trim() ?? '';
      
      if (val == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Enter closing reading for ${r['label']}')),
        );
        return;
      }
      if (val < opening) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Closing reading must be >= opening for ${r['label']}')),
        );
        return;
      }
      if (testing > (val - opening)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Testing qty exceeds sales for ${r['label']}')),
        );
        return;
      }
      if (testing != defaultTesting && reason.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reason required for non-default testing on ${r['label']}')),
        );
        return;
      }
    }

    final confirmed = await showConfirmDialog(
      context,
      title: 'Submit Readings',
      message: 'Are you sure you want to submit all nozzle readings?',
      confirmLabel: 'Submit',
    );
    if (!confirmed) return;

    setState(() => _submitting = true);
    try {
      final db = TenantService.instance.client;

      // Update each nozzle entry with closing reading and calculated sales
      for (final r in _readings) {
        final key = r['nozzle_id'] as String;
        final closing = double.parse(_controllers[key]!.text);
        final testing = double.tryParse(_testingControllers[key]!.text) ?? 0;
        final opening = double.tryParse(r['opening_reading']?.toString() ?? '0') ?? 0;
        final rate = double.tryParse(r['rate']?.toString() ?? '0') ?? 0;
        
        final saleLitres = (closing - opening - testing);
        final saleAmount = saleLitres * rate;
        final reason = _reasonControllers[key]?.text.trim();

        await db.from('NozzleEntry').update({
          'closing_reading': closing,
          'testing_quantity': testing,
          'testing_override_reason': testing != _defaultTestings[key] ? (reason?.isNotEmpty == true ? reason : null) : null,
          'sale_litres': saleLitres,
          'sale_amount': saleAmount,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', r['entry_id']);
      }

      if (_shift == null) return;

      // Update shift status to SUBMITTED
      await db.from('Shift').update({
        'status': 'SUBMITTED',
        'submitted_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', _shift!['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Readings submitted successfully'),
            backgroundColor: AppColors.green,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgApp,
      appBar: AppBar(
        title: const Text('Nozzle Entry'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => context.pop(),
        ),
      ),
      body: _loading
          ? const LoadingView(message: 'Loading shift data...')
          : _error != null
              ? ErrorView(message: _error!)
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          if (_shift!['status'] != 'OPEN' && _shift!['status'] != 'SUBMITTED')
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: AppCard(
                                child: Row(
                                  children: [
                                    const Icon(Icons.lock_outline,
                                        color: AppColors.amber, size: 18),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Shift is ${_shift!['status']}. View-only mode.',
                                      style: const TextStyle(
                                          color: AppColors.amber,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          // Shift info
                          AppCard(
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline,
                                    color: AppColors.blue, size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Shift started ${IstTime.formatRelativeDate(DateTime.parse(_shift!['created_at']))}',
                                    style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 13),
                                  ),
                                ),
                                if (_shift!['status'] == 'SUBMITTED')
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.blue.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'SUBMITTED',
                                      style: TextStyle(
                                        color: AppColors.blue,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          ..._readings.map((r) {
                            final key = r['nozzle_id'] as String;
                            final opening = double.tryParse(
                                    r['opening_reading']?.toString() ?? '0') ??
                                0;
                            final fuelColor =
                                switch (r['fuel_type'] as String) {
                              'Petrol' => AppColors.petrol,
                              'Diesel' => AppColors.diesel,
                              'Power' => AppColors.power,
                              _ => AppColors.blue,
                            };

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: AppCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: fuelColor.withValues(
                                                alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            r['fuel_type'] as String,
                                            style: TextStyle(
                                              color: fuelColor,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          r['label'] as String,
                                          style: const TextStyle(
                                            color: AppColors.textPrimary,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (_tankStocks[r['tank_id']] != null && _tankStocks[r['tank_id']]! < 1000)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: AppColors.amber.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.inventory_2_outlined, color: AppColors.amber, size: 12),
                                              const SizedBox(width: 6),
                                              Text(
                                                'Current Tank Stock: ${_tankStocks[r['tank_id']]!.toStringAsFixed(0)}L',
                                                style: const TextStyle(
                                                  color: AppColors.amber,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text('Opening Reading',
                                                  style: TextStyle(
                                                      color:
                                                          AppColors.textMuted,
                                                      fontSize: 11)),
                                              const SizedBox(height: 4),
                                              Text(
                                                opening.toStringAsFixed(2),
                                                style: const TextStyle(
                                                  color: AppColors.textPrimary,
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Icon(Icons.arrow_forward,
                                            color: AppColors.textMuted,
                                            size: 20),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              const Text('Closing Reading',
                                                  style: TextStyle(
                                                      color:
                                                          AppColors.textMuted,
                                                      fontSize: 11)),
                                              const SizedBox(height: 4),
                                              SizedBox(
                                                width: 140,
                                                child: TextFormField(
                                                  controller: _controllers[key],
                                                  keyboardType:
                                                      const TextInputType
                                                          .numberWithOptions(
                                                          decimal: true),
                                                  textAlign: TextAlign.right,
                                                  enabled: !(_shift!['status'] == 'CLOSED' || _submitting),
                                                  onChanged: (_) => setState(() {}),
                                                  style: const TextStyle(
                                                    color: AppColors.textPrimary,
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                  decoration: InputDecoration(
                                                    border: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                      borderSide:
                                                          const BorderSide(
                                                              color: AppColors
                                                                  .border),
                                                    ),
                                                    enabledBorder:
                                                        OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                      borderSide:
                                                          const BorderSide(
                                                              color: AppColors
                                                                  .border),
                                                    ),
                                                    focusedBorder:
                                                        OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                      borderSide:
                                                          const BorderSide(
                                                              color: AppColors
                                                                  .blue,
                                                              width: 1.5),
                                                    ),
                                                    contentPadding:
                                                        const EdgeInsets
                                                            .symmetric(
                                                            horizontal: 10,
                                                            vertical: 10),
                                                    filled: true,
                                                    fillColor:
                                                        AppColors.bgSurface,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        const Expanded(
                                          child: Text(
                                            'Testing / Calibration Qty',
                                            style: TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          width: 80,
                                          child: TextFormField(
                                            controller: _testingControllers[key],
                                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                            textAlign: TextAlign.right,
                                            onChanged: (_) => setState(() {}),
                                            enabled: !(_shift!['status'] == 'CLOSED' || _submitting),
                                            style: const TextStyle(
                                              color: AppColors.textPrimary,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            decoration: InputDecoration(
                                              suffixText: ' L',
                                              suffixStyle: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              border: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.border)),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    if (double.tryParse(_testingControllers[key]!.text) != _defaultTestings[key])
                                      Padding(
                                        padding: const EdgeInsets.only(top: 12),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text('Override Reason', style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
                                            const SizedBox(height: 4),
                                            TextFormField(
                                              controller: _reasonControllers[key],
                                              enabled: !(_shift!['status'] == 'CLOSED' || _submitting),
                                              style: const TextStyle(fontSize: 12),
                                              decoration: const InputDecoration(
                                                isDense: true,
                                                hintText: 'Required: Why is testing qty different?',
                                                hintStyle: TextStyle(fontSize: 11),
                                                border: OutlineInputBorder(),
                                                contentPadding: EdgeInsets.all(8),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    // Live preview
                                    Builder(
                                      builder: (context) {
                                        final closing = double.tryParse(_controllers[key]!.text) ?? 0;
                                        final testing = double.tryParse(_testingControllers[key]!.text) ?? 0;
                                        final rate = double.tryParse(r['rate']?.toString() ?? '0') ?? 0;
                                        
                                        if (closing <= opening) return const SizedBox.shrink();
                                        
                                        final netLitres = (closing - opening - testing).clamp(0, double.infinity);
                                        final amount = netLitres * rate;
                                        
                                        return Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: AppColors.blue.withValues(alpha: 0.05),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: AppColors.blue.withValues(alpha: 0.1)),
                                          ),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const Text('Net Sales (Litres)', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                                                  Text(IndianCurrency.formatLitres(netLitres), style: const TextStyle(color: AppColors.blue, fontWeight: FontWeight.w700, fontSize: 16)),
                                                ],
                                              ),
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.end,
                                                children: [
                                                  const Text('Estimated Sale', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                                                  Text(IndianCurrency.format(amount), style: const TextStyle(color: AppColors.green, fontWeight: FontWeight.w700, fontSize: 16)),
                                                ],
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),

                    // Submit button
                    if (_shift!['status'] == 'OPEN')
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: const BoxDecoration(
                          color: AppColors.bgSurface,
                          border:
                              Border(top: BorderSide(color: AppColors.border)),
                        ),
                        child: AppButton(
                          label: 'Submit Readings',
                          onTap: _submit,
                          loading: _submitting,
                          width: double.infinity,
                        ),
                      ),
                  ],
                ),
    );
  }
}

// ─── shift_execution_screen.dart ──────────────────────────────────────────────

class ShiftExecutionScreen extends ConsumerStatefulWidget {
  final String shiftId;
  const ShiftExecutionScreen({super.key, required this.shiftId});

  @override
  ConsumerState<ShiftExecutionScreen> createState() =>
      _ShiftExecutionScreenState();
}

class _ShiftExecutionScreenState extends ConsumerState<ShiftExecutionScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _shift;
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, TextEditingController> _testingControllers = {};
  final Map<String, TextEditingController> _reasonControllers = {};
  final Map<String, double> _defaultTestings = {};
  bool _submitting = false;

  Map<String, dynamic>? _getMap(dynamic data) {
    if (data == null) return null;
    if (data is List) {
      if (data.isEmpty) return null;
      return Map<String, dynamic>.from(data.first as Map);
    }
    return Map<String, dynamic>.from(data as Map);
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final c in _testingControllers.values) {
      c.dispose();
    }
    for (final c in _reasonControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

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
      final shift = await db
          .from('Shift')
          .select(
              'id, status, created_at, business_date, pump:Pump(id, name, station_id), assigned_worker:User(full_name), nozzle_entries:NozzleEntry(id, nozzle_id, opening_reading, closing_reading, testing_quantity, testing_override_reason, sale_litres, sale_amount, rate, nozzle:Nozzle(label, fuel_type, default_testing))')
          .eq('id', widget.shiftId)
          .single();

      final entries = shift['nozzle_entries'] as List? ?? [];
      
      // Fetch global settings for default testing if needed
      double globalDefaultTesting = 5.0;
      if (entries.isNotEmpty) {
        final pump = _getMap(shift['pump']);
        final stationId = pump?['station_id'];
        final settings = await db
            .from('StationSettings')
            .select('testing_fuel_default')
            .eq('station_id', stationId)
            .maybeSingle();
        globalDefaultTesting = double.tryParse(settings?['testing_fuel_default']?.toString() ?? '5') ?? 5.0;
      }

      if (mounted) {
        // Initialize controllers
        final pump = _getMap(shift['pump']);
        for (final e in entries) {
           final key = e['nozzle_id'] as String;
           _controllers[key] = TextEditingController(text: e['closing_reading']?.toString() ?? '');
           
           final dTesting = double.tryParse((_getMap(e['nozzle']))?['default_testing']?.toString() ?? '') ?? globalDefaultTesting;
           _defaultTestings[key] = dTesting;
           
           _testingControllers[key] = TextEditingController(text: e['testing_quantity']?.toString() ?? dTesting.toString());
           _reasonControllers[key] = TextEditingController(text: e['testing_override_reason'] ?? '');
        }

        setState(() {
          _shift = shift;
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _submitOrUpdate() async {
    final entries = _shift!['nozzle_entries'] as List? ?? [];
    
    // Validate
    for (final e in entries) {
      final key = e['nozzle_id'] as String;
      final val = double.tryParse(_controllers[key]?.text ?? '');
      final opening = double.tryParse(e['opening_reading']?.toString() ?? '0') ?? 0;
      final testing = double.tryParse(_testingControllers[key]?.text ?? '0') ?? 0;
      final reason = _reasonControllers[key]?.text.trim() ?? '';
      
      if (val == null) continue; // Skip unentered if not worker
      
      if (val < opening) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Closing reading must be >= opening for ${e['nozzle']?['label'] ?? ''}')));
        return;
      }
      if (testing != _defaultTestings[key] && reason.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reason required for non-default testing on ${e['nozzle']?['label'] ?? ''}')));
        return;
      }
    }

    final confirmed = await showConfirmDialog(
      context,
      title: 'Update Readings',
      message: 'Are you sure you want to save nozzle readings?',
    );
    if (!confirmed) return;

    setState(() => _submitting = true);
    try {
      final db = TenantService.instance.client;

      for (final e in entries) {
        final key = e['nozzle_id'] as String;
        final valText = _controllers[key]!.text.trim();
        if (valText.isEmpty) continue;

        final closing = double.parse(valText);
        final testing = double.tryParse(_testingControllers[key]!.text) ?? 0;
        final opening = double.tryParse(e['opening_reading']?.toString() ?? '0') ?? 0;
        final rate = double.tryParse(e['rate']?.toString() ?? '0') ?? 0;
        final saleLitres = (closing - opening - testing);
        final saleAmount = saleLitres * rate;
        final reason = _reasonControllers[key]?.text.trim();

        await db.from('NozzleEntry').update({
          'closing_reading': closing,
          'testing_quantity': testing,
          'testing_override_reason': testing != _defaultTestings[key] ? (reason?.isNotEmpty == true ? reason : null) : null,
          'sale_litres': saleLitres,
          'sale_amount': saleAmount,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', e['id']);
      }

      // If transition from OPEN -> SUBMITTED (admin path or worker path)
      if (_shift!['status'] == 'OPEN') {
        await db.from('Shift').update({
          'status': 'SUBMITTED',
          'submitted_at': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', _shift!['id']);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Shift updated successfully'), backgroundColor: AppColors.green));
        _fetch();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
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

    final entries = _shift!['nozzle_entries'] as List? ?? [];
    // Shift has no sale_amount column — compute from nozzle entries
    final entries_ = _shift!['nozzle_entries'] as List? ?? [];
    final totalSale = entries_.fold<double>(
        0,
        (s, e) =>
            s +
            (double.tryParse((e as Map)['sale_amount']?.toString() ?? '0') ??
                0));
    final status = _shift!['status'] as String? ?? '';
    final pumpName = (_shift!['pump'] as Map?)?['name'] as String? ?? '';
    final workerName =
        (_shift!['assigned_worker'] as Map?)?['full_name'] as String? ?? 'Me';

    return Scaffold(
      backgroundColor: AppColors.bgApp,
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Shift — $pumpName',
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          Text(workerName,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ]),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 18),
            onPressed: () => context.pop()),
        actions: [
          StatusBadge.fromStatus(status),
          const SizedBox(width: 12),
        ],
      ),
      body: RefreshIndicator(
          onRefresh: _fetch,
          color: AppColors.blue,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Summary card
              AppCard(
                  child: Row(children: [
                _InfoCell('Status', status),
                _InfoCell('Sale', IndianCurrency.formatCompact(totalSale),
                    color: AppColors.green),
                _InfoCell('Entries', '${entries.length}',
                    color: AppColors.blue),
              ])),
              const SizedBox(height: 20),

              // Nozzle entries
              const SectionHeader(title: 'Nozzle Readings'),
              const SizedBox(height: 12),
              ...entries.map((e) {
                    final entry = e as Map;
                    final nozzle = _getMap(entry['nozzle']) ?? {};
                    final nozzleId = entry['nozzle_id'] as String;
                    final opening = double.tryParse(
                        entry['opening_reading']?.toString() ?? '0') ??
                    0;
                    
                    final user = ref.read(currentUserProvider);
                    final isManagerOrDealer = user?.role == 'MANAGER' || user?.role == 'DEALER';
                    final canEdit = isManagerOrDealer && status != 'CLOSED';
                    
                    final closing = double.tryParse(
                        _controllers[nozzleId]?.text ?? entry['closing_reading']?.toString() ?? '0') ??
                    0;
                    final hasReading = entry['closing_reading'] != null || _controllers[nozzleId]?.text.isNotEmpty == true;
                    
                    final litres =
                        double.tryParse(entry['sale_litres']?.toString() ?? '0') ??
                            0;
                    final rate =
                        double.tryParse(entry['rate']?.toString() ?? '0') ?? 0;
                final fuel = nozzle['fuel_type'] as String? ?? '';
                final fuelColor = switch (fuel) {
                  'Petrol' => AppColors.petrol,
                  'Diesel' => AppColors.diesel,
                  'Power' => AppColors.power,
                  _ => AppColors.blue,
                };
                return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      borderColor: hasReading
                          ? AppColors.green.withValues(alpha: 0.2)
                          : null,
                      child: Column(children: [
                        Row(children: [
                          Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                  color: fuelColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6)),
                              child: Text(fuel,
                                  style: TextStyle(
                                      color: fuelColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600))),
                          const SizedBox(width: 8),
                          Text(nozzle['label'] as String? ?? '',
                              style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15)),
                          const Spacer(),
                          if (hasReading)
                            const Icon(Icons.check_circle,
                                color: AppColors.green, size: 16)
                          else
                            const Icon(Icons.pending,
                                color: AppColors.amber, size: 16),
                        ]),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                              child: _ReadingCol(
                                  'Opening', opening.toStringAsFixed(2))),
                          const Icon(Icons.arrow_forward,
                              size: 16, color: AppColors.textMuted),
                          Expanded(
                              child: canEdit 
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      const Text('Closing', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                                      const SizedBox(height: 4),
                                      SizedBox(
                                        width: 100,
                                        child: TextFormField(
                                          controller: _controllers[nozzleId],
                                          textAlign: TextAlign.right,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                                          onChanged: (_) => setState(() {}),
                                          decoration: InputDecoration(
                                            isDense: true,
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : _ReadingCol('Closing',
                                  hasReading ? closing.toStringAsFixed(2) : '—',
                                  color: hasReading
                                      ? AppColors.textPrimary
                                      : AppColors.textMuted,
                                  align: TextAlign.right)),
                        ]),
                        if (canEdit) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Text('Testing', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 60,
                                child: TextFormField(
                                  controller: _testingControllers[nozzleId],
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(fontSize: 13),
                                  onChanged: (_) => setState(() {}),
                                  decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.all(4)),
                                ),
                              ),
                              const Spacer(),
                              if (double.tryParse(_testingControllers[nozzleId]?.text ?? '') != _defaultTestings[nozzleId])
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 12),
                                    child: TextFormField(
                                      controller: _reasonControllers[nozzleId],
                                      style: const TextStyle(fontSize: 11),
                                      decoration: const InputDecoration(hintText: 'Reason', isDense: true),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                        if (hasReading) ...[
                          const Divider(height: 16, color: AppColors.border),
                          Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                    '${IndianCurrency.formatLitres(litres)} @ ₹${rate.toStringAsFixed(2)}/L',
                                    style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 12)),
                                if (double.tryParse(entry['testing_quantity']?.toString() ?? '0') != 0)
                                  Text(
                                    ' (Test: ${IndianCurrency.formatLitres(double.parse(entry['testing_quantity'].toString()))})',
                                    style: const TextStyle(
                                        color: AppColors.amber,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600)),
                                const Spacer(),
                                Builder(builder: (context) {
                                  // Live compute for preview
                                  final r = entry;
                                  final nozzleId = r['nozzle_id'] as String;
                                  final cText = _controllers[nozzleId]?.text ?? '';
                                  final curClosing = double.tryParse(cText) ?? double.tryParse(r['closing_reading']?.toString() ?? '0') ?? 0;
                                  final curTesting = double.tryParse(_testingControllers[nozzleId]?.text ?? '') ?? double.tryParse(r['testing_quantity']?.toString() ?? '0') ?? 0;
                                  final curOpening = double.tryParse(r['opening_reading']?.toString() ?? '0') ?? 0;
                                  final curRate = double.tryParse(r['rate']?.toString() ?? '0') ?? 0;
                                  
                                  final curLitres = (curClosing - curOpening - curTesting).clamp(0, double.infinity);
                                  final curAmount = curLitres * curRate;
                                  
                                  return Text(IndianCurrency.format(curAmount),
                                      style: const TextStyle(
                                          color: AppColors.green,
                                          fontWeight: FontWeight.w700));
                                }),
                              ]),
                        ],
                      ]),
                    ));
              }),

              const SizedBox(height: 16),
              if ((ref.watch(currentUserProvider)?.role == 'MANAGER' || ref.watch(currentUserProvider)?.role == 'DEALER') && status != 'CLOSED')
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AppButton(
                    label: status == 'OPEN' ? 'Submit Readings' : 'Update Readings',
                    icon: Icons.save_outlined,
                    loading: _submitting,
                    width: double.infinity,
                    onTap: _submitOrUpdate,
                  ),
                ),
              if (status == 'SUBMITTED') ...[
                AppButton(
                  label: 'Reconcile & Settle',
                  icon: Icons.account_balance_wallet_outlined,
                  width: double.infinity,
                  onTap: () => context.push(
                      '/app/shifts/payment/${_shift!['id']}'),
                ),
                const SizedBox(height: 12),
              ],
            ],
          )),
    );
  }
}

class _InfoCell extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _InfoCell(this.label, this.value, {this.color = AppColors.textPrimary});
  @override
  Widget build(BuildContext context) => Expanded(
          child: Column(children: [
        Text(value,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w800, fontSize: 16)),
        Text(label,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
      ]));
}

class _ReadingCol extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final TextAlign align;
  const _ReadingCol(this.label, this.value,
      {this.color = AppColors.textPrimary, this.align = TextAlign.left});
  @override
  Widget build(BuildContext context) => Column(
          crossAxisAlignment: align == TextAlign.right
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(label,
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 11)),
            const SizedBox(height: 2),
            Text(value,
                style: TextStyle(
                    color: color, fontSize: 18, fontWeight: FontWeight.w700),
                textAlign: align),
          ]);
}

// ─── my_earnings_screen.dart ──────────────────────────────────────────────────

class MyEarningsScreen extends ConsumerStatefulWidget {
  const MyEarningsScreen({super.key});

  @override
  ConsumerState<MyEarningsScreen> createState() => _MyEarningsScreenState();
}

class _MyEarningsScreenState extends ConsumerState<MyEarningsScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

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
      final user = ref.read(currentUserProvider);

      if (user == null) {
        setState(() => _loading = false);
        return;
      }

      final results = await Future.wait([
        db
            .from('SalaryConfig')
            .select('base_monthly_salary, effective_from')
            .eq('user_id', user.id)
            .maybeSingle(),
        db
            .from('StaffAdvance')
            .select('amount, reason, created_at')
            .eq('user_id', user.id)
            .order('created_at', ascending: false)
            .limit(10),
        db
            .from('SalaryPayout')
            .select('net_paid, period_label, paid_at, status')
            .eq('user_id', user.id)
            .order('paid_at', ascending: false)
            .limit(6),
      ]);

      setState(() {
        _data = {
          'config': results[0],
          'advances': results[1],
          'payouts': results[2],
        };
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

    return Scaffold(
      backgroundColor: AppColors.bgApp,
      appBar: AppBar(
        title: const Text('My Earnings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => context.pop(),
        ),
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _fetch)
              : RefreshIndicator(
                  onRefresh: _fetch,
                  color: AppColors.blue,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      // Config card
                      if (_data!['config'] != null) ...[
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SectionHeader(title: 'My Salary'),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Base Salary',
                                      style: TextStyle(
                                          color: AppColors.textSecondary)),
                                  Text(
                                    IndianCurrency.format(double.tryParse(
                                            _data!['config']
                                                        ['base_monthly_salary']
                                                    ?.toString() ??
                                                '0') ??
                                        0),
                                    style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 18),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Type',
                                      style: TextStyle(
                                          color: AppColors.textSecondary)),
                                  StatusBadge(
                                    label: 'Monthly',
                                    tone: BadgeTone.info,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Recent payouts
                      const SectionHeader(title: 'Recent Payouts'),
                      const SizedBox(height: 12),
                      ...(_data!['payouts'] as List).map((p) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: AppCard(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(p['period_label'] ?? '',
                                            style: const TextStyle(
                                                color: AppColors.textPrimary,
                                                fontWeight: FontWeight.w600)),
                                        Text(
                                          p['created_at'] != null
                                              ? IstTime.formatDate(
                                                  DateTime.parse(
                                                      p['created_at']))
                                              : 'Pending',
                                          style: const TextStyle(
                                              color: AppColors.textMuted,
                                              fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        IndianCurrency.format(double.tryParse(
                                                p['net_paid']?.toString() ??
                                                    '0') ??
                                            0),
                                        style: const TextStyle(
                                            color: AppColors.green,
                                            fontWeight: FontWeight.w700),
                                      ),
                                      StatusBadge.fromStatus(
                                          p['status'] ?? 'PENDING'),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          )),

                      // Advances
                      if ((_data!['advances'] as List).isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const SectionHeader(title: 'Advance History'),
                        const SizedBox(height: 12),
                        ...(_data!['advances'] as List).map((a) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: AppCard(
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(a['reason'] ?? 'Advance',
                                              style: const TextStyle(
                                                  color: AppColors.textPrimary,
                                                  fontWeight: FontWeight.w500)),
                                          Text(
                                            IstTime.formatDate(DateTime.parse(
                                                a['created_at'])),
                                            style: const TextStyle(
                                                color: AppColors.textMuted,
                                                fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      '− ${IndianCurrency.format(double.tryParse(a['amount']?.toString() ?? '0') ?? 0)}',
                                      style: const TextStyle(
                                          color: AppColors.red,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                            )),
                      ],
                    ],
                  ),
                ),
    );
  }
}
