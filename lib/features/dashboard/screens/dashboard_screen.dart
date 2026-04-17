import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/tenant_service.dart';
import '../../../core/utils/ist_time.dart';
import '../../../core/utils/currency.dart';
import '../../../shared/widgets/widgets.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    Future.microtask(_fetch);
  }

  Future<void> _fetch() async {
    if (!mounted) return;
    debugPrint('Dashboard: [_fetch] starting...');
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = ref.read(authProvider);
      debugPrint('Dashboard: [_fetch] isDemoMode = ${auth.isDemoMode}');

      if (auth.isDemoMode) {
        debugPrint('Dashboard: [_fetch] entering Demo Mode mock branch');
        // Small delay to let UI settle
        await Future.delayed(const Duration(milliseconds: 100));

        if (!mounted) return;
        setState(() {
          _data = {
            'activeShifts': [
              {
                'id': 'demo-shift-1',
                'status': 'OPEN',
                'pump': {'name': 'Pump 1 (Petrol)'},
                'assigned_worker': {'full_name': 'Demo Worker'},
                'nozzle_entries': [{'sale_amount': 5000.0}]
              },
            ],
            'pendingSettlements': 2,
            'lowStockAlerts': 0,
            'totalCreditsPending': 5,
            'todayRevenue': 12450.0,
            'tanks': [
              {
                'id': 't1', 'name': 'Main Petrol', 'fuel_type': 'Petrol',
                'capacity_liters': 20000.0, 'computed_stock': 12000.0,
                'low_stock_threshold': 5000.0,
              },
            ],
            'lowTanks': [],
            'staff': [],
            'pumps': [],
            'managers': 1,
            'workers': 4,
          };
          _loading = false;
        });
        debugPrint('Dashboard: [_fetch] Demo Mode data applied.');
        return;
      }

      debugPrint('Dashboard: [_fetch] calling Supabase...');
      final db = TenantService.instance.client;
      final user = ref.read(currentUserProvider);
      
      if (user == null) {
        debugPrint('Dashboard: [_fetch] User is null, skipping fetch.');
        setState(() => _loading = false);
        return;
      }

      final results = await Future.wait([
        db
            .from('Shift')
            .select(
                'id, status, pump:Pump(id, name), assigned_worker:User(full_name), nozzle_entries:NozzleEntry(sale_amount)')
            .eq('station_id', user.stationId)
            .eq('status', 'OPEN'),
        db
            .from('Shift')
            .select('id')
            .eq('station_id', user.stationId)
            .eq('status', 'CLOSED'),
        db
            .from('Tank')
            .select('id, name, fuel_type, capacity_liters, low_stock_threshold')
            .eq('station_id', user.stationId)
            .eq('active', true),
        db
            .from('CreditCustomer')
            .select('id')
            .eq('station_id', user.stationId)
            .eq('active', true),
        db
            .from('Shift')
            .select('nozzle_entries:NozzleEntry(sale_amount)')
            .eq('station_id', user.stationId)
            .eq('status', 'SETTLED')
            .gte('closed_at', '${IstTime.todayDate()}T00:00:00+05:30'),
        db
            .from('User')
            .select('id, role')
            .eq('station_id', user.stationId)
            .eq('active', true)
            .neq('role', 'DEALER'),
        db
            .from('Pump')
            .select('id, name, provider_type, active')
            .eq('station_id', user.stationId)
            .eq('active', true),
        db
            .from('TankInitialStock')
            .select('tank_id, opening_litres')
            .eq('station_id', user.stationId),
        db
            .from('StockTransaction')
            .select('tank_id, quantity')
            .eq('station_id', user.stationId),
      ]);

      final activeShifts = results[0] as List;
      final pendingSettlements = results[1] as List;
      final tanks = results[2] as List;
      final credits = results[3] as List;
      final todayShifts = results[4] as List;
      final staff = results[5] as List;
      final pumps = results[6] as List;
      final initialStocks = {
        for (final s in results[7] as List)
          (s as Map)['tank_id']: double.tryParse(s['opening_litres']?.toString() ?? '0') ?? 0.0
      };
      final transactions = results[8] as List;

      final tankStocks = <String, double>{};
      for (final tRaw in tanks) {
        final t = Map<String, dynamic>.from(tRaw as Map);
        final tid = t['id'] as String;
        double stock = initialStocks[tid] ?? 0.0;
        for (final txRaw in transactions) {
          final tx = Map<String, dynamic>.from(txRaw as Map);
          if (tx['tank_id'] == tid) {
            stock += double.tryParse(tx['quantity']?.toString() ?? '0') ?? 0;
          }
        }
        tankStocks[tid] = stock;
      }
      final tanksWithStock = tanks
          .map((tRaw) {
            final t = Map<String, dynamic>.from(tRaw as Map);
            return {...t, 'computed_stock': tankStocks[t['id']] ?? 0.0};
          })
          .toList();

      final todayRevenue = todayShifts.fold<double>(0, (sum, sRaw) {
        final s = Map<String, dynamic>.from(sRaw as Map);
        final entries = (s['nozzle_entries'] as List? ?? []);
        return sum +
            entries.fold<double>(
                0,
                (es, eRaw) {
                  final e = Map<String, dynamic>.from(eRaw as Map);
                  return es + (double.tryParse(e['sale_amount']?.toString() ?? '0') ?? 0);
                });
      });

      final lowTanks = tanksWithStock.where((tRaw) {
        final t = Map<String, dynamic>.from(tRaw as Map);
        final cur = (t['computed_stock'] as double?) ?? 0;
        final reorder =
            double.tryParse(t['low_stock_threshold']?.toString() ?? '0') ?? 0;
        return reorder > 0 && cur <= reorder;
      }).toList();

      setState(() {
        _data = {
          'activeShifts': activeShifts,
          'pendingSettlements': pendingSettlements.length,
          'lowStockAlerts': lowTanks.length,
          'totalCreditsPending': credits.length,
          'todayRevenue': todayRevenue,
          'tanks': tanksWithStock,
          'lowTanks': lowTanks,
          'staff': staff,
          'pumps': pumps,
          'managers': staff.where((s) => (s as Map)['role'] == 'MANAGER').length,
          'workers': staff.where((s) => (s as Map)['role'] == 'PUMP_PERSON').length,
        };
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final stationName = ref.watch(stationNameProvider);

    if (_loading) return const LoadingView(message: 'Loading dashboard...');
    if (_error != null) return ErrorView(message: _error!, onRetry: _fetch);

    final d = _data!;
    final activeShifts = d['activeShifts'] as List;

    return RefreshIndicator(
      color: AppColors.blue,
      onRefresh: _fetch,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Good ${_greeting()}, ${user?.fullName.split(' ').first ?? ''}',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              stationName,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        IstTime.formatDate(DateTime.now().toUtc()),
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  if ((d['lowStockAlerts'] as int) > 0)
                    _AlertBanner(
                      message:
                          '⚠️ ${d['lowStockAlerts']} tank(s) below reorder level',
                      color: AppColors.amber,
                      onTap: () => context.push('/app/inventory'),
                    ),
                  if ((d['pendingSettlements'] as int) > 0)
                    _AlertBanner(
                      message:
                          '${d['pendingSettlements']} shift(s) pending settlement',
                      color: AppColors.blue,
                      onTap: () => context.push('/app/shifts'),
                    ),
                ],
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                mainAxisExtent: 100, // Fixed height for KPI cards to keep grid consistent
              ),
              delegate: SliverChildListDelegate([
                KpiCard.currency(
                  label: "Today's Revenue",
                  amount: d['todayRevenue'] as double,
                  icon: Icons.trending_up,
                  color: AppColors.green,
                  onTap: () => context.push('/app/reports'),
                ),
                KpiCard(
                  label: 'Active Shifts',
                  value: '${activeShifts.length}',
                  icon: Icons.swap_horiz,
                  color: AppColors.blue,
                  onTap: () => context.push('/app/shifts'),
                ),
                KpiCard(
                  label: 'Pending Settlement',
                  value: '${d['pendingSettlements']}',
                  icon: Icons.pending_actions,
                  color: AppColors.amber,
                  onTap: () => context.push('/app/shifts'),
                ),
                KpiCard(
                  label: 'Low Stock Alerts',
                  value: '${d['lowStockAlerts']}',
                  icon: Icons.warning_amber_outlined,
                  color: (d['lowStockAlerts'] as int) > 0
                      ? AppColors.red
                      : AppColors.textMuted,
                  onTap: () => context.push('/app/inventory'),
                ),
              ]),
            ),
          ),

          if (activeShifts.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeader(
                      title: 'Active Shifts',
                      action: 'View All',
                      onAction: () => context.push('/app/shifts'),
                    ),
                    const SizedBox(height: 12),
                    ...activeShifts.take(3).map((sRaw) {
                          final s = Map<String, dynamic>.from(sRaw as Map);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _ActiveShiftCard(
                              shift: s,
                              onTap: () {
                                final pumpData = s['pump'];
                                final pump = (pumpData is List && (pumpData as List).isNotEmpty)
                                    ? (pumpData as List).first as Map
                                    : (pumpData as Map?);
                                final pumpId = pump?['id'] as String? ?? '';
                                final role = user?.role ?? '';
                                if (pumpId.isNotEmpty) {
                                  if (role == 'PUMP_PERSON') {
                                    context.push('/worker/nozzle/$pumpId');
                                  } else {
                                    context.push('/app/shifts/execution/${s['id']}');
                                  }
                                }
                              },
                            ),
                          );
                        }),
                  ],
                ),
              ),
            ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: SectionHeader(
                title: 'Tank Status',
                action: 'Inventory',
                onAction: () => context.push('/app/inventory'),
              ),
            ),
          ),
          if ((d['tanks'] as List).isEmpty)
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 20),
              sliver: SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyView(
                  title: 'No tanks configured',
                  subtitle: 'Tank levels will appear here once configured',
                  icon: Icons.water_outlined,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) {
                    final tankRaw = (d['tanks'] as List)[i];
                    final tank = Map<String, dynamic>.from(tankRaw as Map);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _TankCard(tank: tank),
                    );
                  },
                  childCount: ((d['tanks'] as List)).length,
                ),
              ),
            ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: AppCard(
                child: Row(
                  children: [
                    _StatPill(
                      label: 'Managers',
                      value: '${d['managers']}',
                      color: AppColors.blue,
                    ),
                    const SizedBox(width: 12),
                    _StatPill(
                      label: 'Staff',
                      value: '${d['workers']}',
                      color: AppColors.green,
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => context.push('/app/staff'),
                      child: const Text('Manage →'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _greeting() {
    final h = IstTime.now().hour;
    if (h < 12) return 'morning';
    if (h < 17) return 'afternoon';
    return 'evening';
  }
}

class _AlertBanner extends StatelessWidget {
  final String message;
  final Color color;
  final VoidCallback onTap;

  const _AlertBanner(
      {required this.message, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                    color: color, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
            Icon(Icons.chevron_right, color: color, size: 16),
          ],
        ),
      ),
    );
  }
}

class _ActiveShiftCard extends StatelessWidget {
  final Map<String, dynamic> shift;
  final VoidCallback onTap;
  const _ActiveShiftCard({required this.shift, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final pumpData = shift['pump'];
    final pump = (pumpData is List && (pumpData as List).isNotEmpty)
        ? (pumpData as List).first as Map
        : (pumpData as Map?);
    final pumpName = pump?['name'] ?? 'Pump';
    
    final workerData = shift['assigned_worker'];
    final worker = (workerData is List && (workerData as List).isNotEmpty)
        ? (workerData as List).first as Map
        : (workerData as Map?);
    final workerName = worker?['full_name'] ?? 'Unassigned';
    final entries = shift['nozzle_entries'] as List? ?? [];
    final amount = entries.fold<double>(
        0,
        (s, e) =>
            s +
            (double.tryParse((e as Map)['sale_amount']?.toString() ?? '0') ??
                0));

    return AppCard(
      onTap: onTap,
      borderColor: AppColors.green.withValues(alpha: 0.2),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.green,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pumpName,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600)),
                Text(workerName,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          Text(
            IndianCurrency.formatCompact(amount),
            style: const TextStyle(
                color: AppColors.green,
                fontWeight: FontWeight.w700,
                fontSize: 15),
          ),
        ],
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
    final isLow = pct < 0.2;

    final fuelColor = switch (tank['fuel_type'] as String? ?? '') {
      'Petrol' => AppColors.petrol,
      'Diesel' => AppColors.diesel,
      'Power' => AppColors.power,
      'CNG' => AppColors.cng,
      _ => AppColors.textSecondary,
    };

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tank['name'] as String? ?? '',
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600),
                ),
              ),
              StatusBadge(
                label: tank['fuel_type'] as String? ?? '',
                tone: BadgeTone.info,
              ),
              if (isLow) ...[
                const SizedBox(width: 6),
                const StatusBadge(label: 'LOW', tone: BadgeTone.error),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: pct,
                    backgroundColor: AppColors.bgHover,
                    valueColor: AlwaysStoppedAnimation(
                        isLow ? AppColors.red : fuelColor),
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${(pct * 100).round()}%',
                style: TextStyle(
                  color: isLow ? AppColors.red : AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${IndianCurrency.formatLitres(cur)} of ${IndianCurrency.formatLitres(cap)}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatPill(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text('$value $label',
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      ],
    );
  }
}
