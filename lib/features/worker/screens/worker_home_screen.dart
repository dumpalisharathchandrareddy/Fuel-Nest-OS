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
  Map<String, dynamic>? _activeShift;

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

      // Check if user has an active shift
      final activeShifts = await db
          .from('Shift')
          .select(
              'id, status, start_time, pump:Pump(name), assigned_worker:User(full_name), nozzle_entries:NozzleEntry(id, nozzle:Nozzle(label, fuel_type), opening_reading, closing_reading, sale_litres, rate, sale_amount)')
          .eq('station_id', user.stationId)
          .eq('assigned_user_id', user.id)
          .eq('status', 'OPEN')
          .limit(1);

      setState(() {
        _pumps = pumps;
        _activeShift = activeShifts.isNotEmpty ? activeShifts.first : null;
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
                      // Active shift banner
                      if (_activeShift != null)
                        SliverToBoxAdapter(
                          child: GestureDetector(
                            onTap: () => context
                                .push('/worker/shift/${_activeShift!['id']}'),
                            child: Container(
                              margin: const EdgeInsets.all(16),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.greenBg,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: AppColors.green.withValues(alpha: 0.1)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: const BoxDecoration(
                                      color: AppColors.green,
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
                                          'Active Shift — ${(_activeShift!['pump'] as Map?)?['name'] ?? ''}',
                                          style: const TextStyle(
                                            color: AppColors.green,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          'Started ${IstTime.formatRelativeDate(DateTime.parse(_activeShift!['start_time'] as String? ?? _activeShift!['created_at'] as String))}',
                                          style: const TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Text('Continue →',
                                      style: TextStyle(
                                          color: AppColors.green,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                        ),

                      // Date + greeting
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

                      // Pump cards
                      if (_pumps.isEmpty)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: EmptyView(
                            title: 'No pumps available',
                            subtitle:
                                'No active pumps are assigned to this station',
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
                                hasActiveShift: _activeShift != null,
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
    final fuelTypes = nozzles.map((n) => n['fuel_type']).toSet().join(', ');

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
              'id, status, created_at, nozzle_entries:NozzleEntry(id, nozzle_id, opening_reading, closing_reading, testing_quantity, rate, nozzle:Nozzle(label, fuel_type))')
          .eq('pump_id', widget.pumpId)
          .eq('station_id', user.stationId)
          .order('created_at', ascending: false)
          .limit(1);

      if (shifts.isEmpty) {
        // No active shift — show message
        setState(() {
          _error =
              'No active shift found for this pump. Ask your manager to open a shift.';
          _loading = false;
        });
        return;
      }

      final shift = shifts.first;
      final entries = shift['nozzle_entries'] as List? ?? [];

      if (entries.isEmpty) {
        setState(() {
          _error = 'No nozzles assigned to this pump. Only pumps with configured nozzles can accept entries.';
          _loading = false;
        });
        return;
      }

      final readings = entries.map<Map<String, dynamic>>((e) {
        final nozzle = e['nozzle'] as Map<String, dynamic>? ?? {};
        return {
          'nozzle_id': e['nozzle_id'],
          'entry_id': e['id'],
          'label': nozzle['label'] ?? '',
          'fuel_type': nozzle['fuel_type'] ?? '',
          'opening_reading': e['opening_reading'],
          'closing_reading': e['closing_reading'],
          'testing_quantity': e['testing_quantity'],
          'rate': e['rate'],
        };
      }).toList();

      // Create controllers for closing readings
      for (final r in readings) {
        final key = r['nozzle_id'] as String;
        _controllers[key] = TextEditingController(
          text: r['closing_reading']?.toString() ?? '',
        );
        _testingControllers[key] = TextEditingController(
          text: r['testing_quantity']?.toString() ?? '0',
        );
      }

      setState(() {
        _shift = shift;
        _readings = readings;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    // Validate all readings
    for (final r in _readings) {
      final key = r['nozzle_id'] as String;
      final val = double.tryParse(_controllers[key]?.text ?? '');
      final opening =
          double.tryParse(r['opening_reading']?.toString() ?? '0') ?? 0;
      final testing = double.tryParse(_testingControllers[key]?.text ?? '0') ?? 0;
      
      if (val == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Enter closing reading for ${r['label']}')),
        );
        return;
      }
      if (val < opening) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Closing reading must be >= opening for ${r['label']}')),
        );
        return;
      }
      if (testing > (val - opening)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Testing qty (${testing.toStringAsFixed(2)}) exceeds sales (${(val - opening).toStringAsFixed(2)}) for ${r['label']}')),
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

        await db.from('NozzleEntry').update({
          'closing_reading': closing,
          'testing_quantity': testing,
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
                          if (_shift!['status'] != 'OPEN')
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
                                Text(
                                  'Shift started ${IstTime.formatRelativeDate(DateTime.parse(_shift!['created_at']))}',
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 13),
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
                                                  enabled: !(_shift!['status'] != 'OPEN' || _submitting),
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
              'id, status, created_at, business_date, pump:Pump(id, name), assigned_worker:User(full_name), nozzle_entries:NozzleEntry(id, opening_reading, closing_reading, testing_quantity, sale_litres, sale_amount, rate, nozzle:Nozzle(label, fuel_type))')
          .eq('id', widget.shiftId)
          .single();
      setState(() {
        _shift = shift;
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
                final nozzle = entry['nozzle'] as Map? ?? {};
                final opening = double.tryParse(
                        entry['opening_reading']?.toString() ?? '0') ??
                    0;
                final closing = double.tryParse(
                        entry['closing_reading']?.toString() ?? '0') ??
                    0;
                final litres =
                    double.tryParse(entry['sale_litres']?.toString() ?? '0') ??
                        0;
                final amount =
                    double.tryParse(entry['sale_amount']?.toString() ?? '0') ??
                        0;
                final rate =
                    double.tryParse(entry['rate']?.toString() ?? '0') ?? 0;
                final hasReading = entry['closing_reading'] != null;
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
                              child: _ReadingCol('Closing',
                                  hasReading ? closing.toStringAsFixed(2) : '—',
                                  color: hasReading
                                      ? AppColors.textPrimary
                                      : AppColors.textMuted,
                                  align: TextAlign.right)),
                        ]),
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
                                Text(IndianCurrency.format(amount),
                                    style: const TextStyle(
                                        color: AppColors.green,
                                        fontWeight: FontWeight.w700)),
                              ]),
                        ],
                      ]),
                    ));
              }),

              const SizedBox(height: 16),
              if (status == 'OPEN')
                AppButton(
                  label: 'Enter Nozzle Readings',
                  icon: Icons.edit_outlined,
                  width: double.infinity,
                  onTap: () {
                    final pumpId = (_shift!['pump'] as Map?)?['id'] as String? ?? '';
                    if (pumpId.isNotEmpty) {
                      final user = ref.read(currentUserProvider);
                      final isWorker = user?.role == 'PUMP_PERSON';
                      final base = isWorker ? '/worker' : '/app/shifts';
                      context.push('$base/nozzle/$pumpId');
                    }
                  },
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
                AppButton(
                  label: 'View Readings',
                  secondary: true,
                  icon: Icons.visibility_outlined,
                  width: double.infinity,
                  onTap: () {
                    final pumpId = (_shift!['pump'] as Map?)?['id'] as String? ?? '';
                    if (pumpId.isNotEmpty) {
                      final user = ref.read(currentUserProvider);
                      final isWorker = user?.role == 'PUMP_PERSON';
                      final base = isWorker ? '/worker' : '/app/shifts';
                      context.push('$base/nozzle/$pumpId');
                    }
                  },
                ),
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
