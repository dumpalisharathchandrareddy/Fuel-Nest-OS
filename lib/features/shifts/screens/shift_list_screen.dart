import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/tenant_service.dart';
import '../../../core/utils/ist_time.dart';
import '../../../core/utils/currency.dart';
import 'package:uuid/uuid.dart';
import '../../../shared/widgets/widgets.dart';

enum _StatusFilter { active, closed, all }

enum _DateTab { daily, weekly, monthly, custom }

class ShiftListScreen extends ConsumerStatefulWidget {
  const ShiftListScreen({super.key});
  @override
  ConsumerState<ShiftListScreen> createState() => _ShiftListScreenState();
}

class _ShiftListScreenState extends ConsumerState<ShiftListScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  String? _error;
  List<dynamic> _shifts = [];
  List<dynamic> _pumps = [];
  List<dynamic> _workers = [];
  _StatusFilter _statusFilter = _StatusFilter.active;
  _DateTab _dateTab = _DateTab.daily;
  DateTime _dailyDate = DateTime.now();
  DateTime _weekAnchor = DateTime.now();
  late String _monthValue;
  DateTime _customFrom = DateTime.now().subtract(const Duration(days: 7));
  DateTime _customTo = DateTime.now();
  late TabController _tabCtrl;
  static final _litresFmt = NumberFormat('#,##,##0.00', 'en_IN');

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _monthValue = '${n.year}-${n.month.toString().padLeft(2, '0')}';
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(() {
      if (_tabCtrl.indexIsChanging) return;
      setState(() => _statusFilter = _StatusFilter.values[_tabCtrl.index]);
      _fetch();
    });
    _fetch();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  String _ds(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  (String, String) _weekBounds(DateTime anchor) {
    final dow = anchor.weekday;
    final mon = anchor.subtract(Duration(days: dow - 1));
    final sun = mon.add(const Duration(days: 6));
    return (_ds(mon), _ds(sun));
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
          _pumps = [
            {'id': 'p1', 'name': 'Pump 1'},
            {'id': 'p2', 'name': 'Pump 2'},
          ];
          _workers = [
            {'id': 'w1', 'full_name': 'Worker A', 'role': 'PUMP_PERSON'},
            {'id': 'w2', 'full_name': 'Worker B', 'role': 'PUMP_PERSON'},
          ];
          _shifts = [
            {
              'id': 's1',
              'status': 'OPEN',
              'business_date': _ds(DateTime.now()),
              'start_time': DateTime.now().toIso8601String(),
              'pump': {'id': 'p1', 'name': 'Pump 1'},
              'assigned_worker': {'id': 'w1', 'full_name': 'Worker A'},
              'nozzle_entries': [
                {
                  'sale_litres': 45.5,
                  'sale_amount': 4500.0,
                  'rate': 102.5,
                  'nozzle': {'fuel_type': 'Petrol'}
                }
              ]
            },
            {
              'id': 's2',
              'status': 'CLOSED',
              'business_date': _ds(DateTime.now()),
              'start_time': DateTime.now()
                  .subtract(const Duration(hours: 8))
                  .toIso8601String(),
              'closed_at': DateTime.now()
                  .subtract(const Duration(hours: 1))
                  .toIso8601String(),
              'pump': {'id': 'p2', 'name': 'Pump 2'},
              'assigned_worker': {'id': 'w2', 'full_name': 'Worker B'},
              'nozzle_entries': [
                {
                  'sale_litres': 120.0,
                  'sale_amount': 11000.0,
                  'rate': 92.5,
                  'nozzle': {'fuel_type': 'Diesel'}
                }
              ]
            },
          ];
          _loading = false;
        });
        return;
      }

      final db = TenantService.instance.client;
      final user = ref.read(currentUserProvider)!;

      var query = db
          .from('Shift')
          .select(
              'id, status, business_date, start_time, closed_at, pump:Pump(id,name), assigned_worker:User(id,full_name), nozzle_entries:NozzleEntry(sale_litres,sale_amount,rate,nozzle:Nozzle(fuel_type))')
          .eq('station_id', user.stationId);

      if (_statusFilter == _StatusFilter.active) {
        query = query.eq('status', 'OPEN');
      } else if (_statusFilter == _StatusFilter.closed) {
        query = query.inFilter('status', ['CLOSED', 'SETTLED']);
        switch (_dateTab) {
          case _DateTab.daily:
            query = query.eq('business_date', _ds(_dailyDate));
          case _DateTab.weekly:
            final b = _weekBounds(_weekAnchor);
            query = query.gte('business_date', b.$1).lte('business_date', b.$2);
          case _DateTab.monthly:
            query = query.like('business_date', '$_monthValue%');
          case _DateTab.custom:
            query = query
                .gte('business_date', _ds(_customFrom))
                .lte('business_date', _ds(_customTo));
        }
      }

      if (_pumps.isEmpty) {
        final results = await Future.wait([
          query.order('created_at', ascending: false).limit(100),
          db
              .from('Pump')
              .select('id, name')
              .eq('station_id', user.stationId)
              .eq('active', true),
          db
              .from('User')
              .select('id, full_name, role')
              .eq('station_id', user.stationId)
              .eq('active', true)
              .not('role', 'in', '("DEALER","MANAGER")'),
        ]);
        setState(() {
          _shifts = results[0] as List;
          _pumps = results[1] as List;
          _workers = results[2] as List;
          _loading = false;
        });
      } else {
        final data =
            await query.order('created_at', ascending: false).limit(100);
        setState(() {
          _shifts = data;
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

  Future<void> _showLaunchDialog() async {
    String? selPumpId;
    String? selWorkerId;
    bool launching = false;
    String? launchErr;

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
                        const Icon(Icons.play_circle_outline,
                            color: AppColors.blue, size: 22),
                        const SizedBox(width: 10),
                        const Expanded(
                            child: Text('Open New Shift',
                                style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700))),
                        IconButton(
                            icon: const Icon(Icons.close,
                                size: 20, color: AppColors.textMuted),
                            onPressed: () => Navigator.pop(ctx)),
                      ]),
                      const SizedBox(height: 4),
                      const Text('Select pump and assign a staff member',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 13)),
                      const SizedBox(height: 20),
                      const Text('PUMP',
                          style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1)),
                      const SizedBox(height: 8),
                      if (_pumps.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                              color: AppColors.bgSurface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.border)),
                          child: Column(children: [
                            const Text('No active pumps configured',
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13)),
                            const SizedBox(height: 12),
                            AppButton(
                                label: 'Add Pump',
                                onTap: () {
                                  Navigator.pop(ctx);
                                  context.go('/hardware');
                                }),
                          ]),
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _pumps.map((p) {
                            final id = p['id'] as String;
                            final sel = selPumpId == id;
                            return GestureDetector(
                              onTap: () => ss(() => selPumpId = id),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: sel ? AppColors.blue : AppColors.bgCard,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: sel
                                        ? AppColors.blue
                                        : AppColors.border),
                              ),
                              child: Text(p['name'] as String? ?? '',
                                  style: TextStyle(
                                      color: sel
                                          ? Colors.white
                                          : AppColors.textSecondary,
                                      fontWeight: FontWeight.w600)),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      const Text('ASSIGN STAFF (OPTIONAL)',
                          style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1)),
                      const SizedBox(height: 8),
                      if (_workers.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                              color: AppColors.bgSurface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.border)),
                          child: Column(children: [
                            const Text('No eligible staff members available',
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13)),
                            const SizedBox(height: 12),
                            AppButton(
                                label: 'Add Staff',
                                onTap: () {
                                  Navigator.pop(ctx);
                                  context.go('/staff');
                                }),
                          ]),
                        )
                      else
                        DropdownButtonFormField<String>(
                          value: selWorkerId,
                          dropdownColor: AppColors.bgSurface,
                          style: const TextStyle(
                              color: AppColors.textPrimary, fontSize: 13),
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    const BorderSide(color: AppColors.border)),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    const BorderSide(color: AppColors.border)),
                            filled: true,
                            fillColor: AppColors.bgCard,
                            hintText: 'Select Staff Member',
                          ),
                          hint: const Text('Any staff member',
                              style: TextStyle(
                                  color: AppColors.textMuted, fontSize: 13)),
                          items: [
                            const DropdownMenuItem(
                                value: null, child: Text('Unassigned')),
                            ..._workers.map((w) => DropdownMenuItem<String>(
                                value: w['id'] as String,
                                child: Text(
                                    '${w['full_name']} (${w['role'] == 'PUMP_PERSON' ? 'Staff' : w['role']})'))),
                          ],
                          onChanged: (v) => ss(() => selWorkerId = v),
                        ),
                      if (launchErr != null) ...[
                        const SizedBox(height: 12),
                        Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                                color: AppColors.redBg,
                                borderRadius: BorderRadius.circular(8)),
                            child: Text(launchErr!,
                                style: const TextStyle(
                                    color: AppColors.red, fontSize: 12))),
                      ],
                      const SizedBox(height: 20),
                      Row(children: [
                        Expanded(
                            child: AppButton(
                                label: 'Cancel',
                                secondary: true,
                                onTap: () => Navigator.pop(ctx))),
                        const SizedBox(width: 12),
                        Expanded(
                            child: AppButton(
                          label: 'Open Shift',
                          loading: launching,
                          onTap: selPumpId == null
                              ? null
                              : () async {
                                  ss(() {
                                    launching = true;
                                    launchErr = null;
                                  });
                                  try {
                                    final db = TenantService.instance.client;
                                    final user = ref.read(currentUserProvider)!;
                                    final now = DateTime.now()
                                        .toUtc()
                                        .toIso8601String();
                                    final n = IstTime.now();
                                    final bDate =
                                        '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';

                                    final nozzles = await db
                                        .from('Nozzle')
                                        .select(
                                            'id, fuel_type, default_testing, tank_id')
                                        .eq('pump_id', selPumpId!)
                                        .eq('active', true);
                                    final rates = await db
                                        .from('FuelRate')
                                        .select('fuel_type, rate')
                                        .eq('station_id', user.stationId);
                                    final rateMap = {
                                      for (final r in rates as List)
                                        r['fuel_type'] as String: r['rate']
                                    };

                                    final newShift = await db
                                        .from('Shift')
                                        .insert({
                                          'id': const Uuid().v4(),
                                          'station_id': user.stationId,
                                          'pump_id': selPumpId,
                                          if (selWorkerId != null)
                                            'assigned_user_id': selWorkerId,
                                          'status': 'OPEN',
                                          'business_date': bDate,
                                          'created_at': now,
                                          'updated_at': now,
                                        })
                                        .select('id')
                                        .single();

                                    for (final nozzle in nozzles as List) {
                                      final fuelType =
                                          nozzle['fuel_type'] as String;
                                      final activeRate = rateMap[fuelType] ?? 0;
                                      await db.from('NozzleEntry').insert({
                                        'id': const Uuid().v4(),
                                        'station_id': user.stationId,
                                        'shift_id': newShift['id'],
                                        'nozzle_id': nozzle['id'],
                                        'opening_reading': 0,
                                        'testing_quantity':
                                            nozzle['default_testing'] ?? 0,
                                        'rate': activeRate,
                                        'created_at': now,
                                        'updated_at': now,
                                      });
                                    }
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    if (mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                              content: Text('✅ Shift opened'),
                                              backgroundColor:
                                                  AppColors.green));
                                      _fetch();
                                    }
                                  } catch (e) {
                                    ss(() {
                                      launching = false;
                                      launchErr = e
                                          .toString()
                                          .replaceAll('Exception: ', '');
                                    });
                                  }
                                },
                        )),
                      ]),
                    ]),
              )),
    );
  }

  Widget _buildDateBar() {
    if (_statusFilter == _StatusFilter.active) return const SizedBox.shrink();
    return Container(
      color: AppColors.bgSurface,
      child: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: _DateTab.values.map((t) {
              final lbl = switch (t) {
                _DateTab.daily => 'Daily',
                _DateTab.weekly => 'Weekly',
                _DateTab.monthly => 'Monthly',
                _DateTab.custom => 'Custom'
              };
              final sel = _dateTab == t;
              return GestureDetector(
                onTap: () {
                  setState(() => _dateTab = t);
                  _fetch();
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                      border: Border(
                          bottom: BorderSide(
                              color: sel ? AppColors.blue : Colors.transparent,
                              width: 2))),
                  child: Text(lbl,
                      style: TextStyle(
                          color: sel ? AppColors.blue : AppColors.textMuted,
                          fontSize: 13,
                          fontWeight: sel ? FontWeight.w600 : FontWeight.w400)),
                ),
              );
            }).toList(),
          ),
        ),
        _buildDatePicker(),
      ]),
    );
  }

  Widget _buildDatePicker() {
    return switch (_dateTab) {
      _DateTab.daily => _NavRow(
          label: IstTime.formatDate(_dailyDate),
          onPrev: () {
            setState(() =>
                _dailyDate = _dailyDate.subtract(const Duration(days: 1)));
            _fetch();
          },
          onNext: () {
            setState(
                () => _dailyDate = _dailyDate.add(const Duration(days: 1)));
            _fetch();
          },
          onTap: () async {
            final d = await showDatePicker(
                context: context,
                initialDate: _dailyDate,
                firstDate: DateTime(2020),
                lastDate: DateTime.now());
            if (d != null) {
              setState(() => _dailyDate = d);
              _fetch();
            }
          },
        ),
      _DateTab.weekly => () {
          final b = _weekBounds(_weekAnchor);
          return _NavRow(
            label: '${b.$1.substring(5)} – ${b.$2.substring(5)}',
            onPrev: () {
              setState(() =>
                  _weekAnchor = _weekAnchor.subtract(const Duration(days: 7)));
              _fetch();
            },
            onNext: () {
              setState(
                  () => _weekAnchor = _weekAnchor.add(const Duration(days: 7)));
              _fetch();
            },
          );
        }(),
      _DateTab.monthly => _NavRow(
          label: _monthValue,
          onPrev: () {
            final p = _monthValue.split('-').map(int.parse).toList();
            final d = DateTime(p[0], p[1] - 1);
            setState(() => _monthValue =
                '${d.year}-${d.month.toString().padLeft(2, '0')}');
            _fetch();
          },
          onNext: () {
            final p = _monthValue.split('-').map(int.parse).toList();
            final d = DateTime(p[0], p[1] + 1);
            setState(() => _monthValue =
                '${d.year}-${d.month.toString().padLeft(2, '0')}');
            _fetch();
          },
        ),
      _DateTab.custom => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Expanded(
                child: _DateBtn(
                    label: 'From: ${_ds(_customFrom)}',
                    onTap: () async {
                      final d = await showDatePicker(
                          context: context,
                          initialDate: _customFrom,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now());
                      if (d != null) {
                        setState(() => _customFrom = d);
                        _fetch();
                      }
                    })),
            const SizedBox(width: 8),
            Expanded(
                child: _DateBtn(
                    label: 'To: ${_ds(_customTo)}',
                    onTap: () async {
                      final d = await showDatePicker(
                          context: context,
                          initialDate: _customTo,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now());
                      if (d != null) {
                        setState(() => _customTo = d);
                        _fetch();
                      }
                    })),
          ]),
        ),
    };
  }

  Widget _buildSummary() {
    if (_shifts.isEmpty) return const SizedBox.shrink();
    final total = _shifts.fold<double>(0, (s, sh) {
      final entries = (sh as Map)['nozzle_entries'] as List? ?? [];
      return s +
          entries.fold<double>(
              0,
              (es, e) =>
                  es +
                  (double.tryParse(
                          (e as Map)['sale_amount']?.toString() ?? '0') ??
                      0));
    });
    final litres = _shifts.fold<double>(
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
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border)),
      child: Row(children: [
        _SumCell('Shifts', '${_shifts.length}'),
        Container(width: 1, height: 32, color: AppColors.border),
        _SumCell('Revenue', IndianCurrency.formatCompact(total),
            color: AppColors.green),
        Container(width: 1, height: 32, color: AppColors.border),
        _SumCell('Litres', '${litres.toStringAsFixed(0)}L',
            color: AppColors.blue),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    return Scaffold(
      backgroundColor: AppColors.bgApp,
      floatingActionButton: user?.isManagerOrDealer == true
          ? FloatingActionButton.extended(
              onPressed: _showLaunchDialog,
              icon: const Icon(Icons.add),
              label: const Text('Open Shift'),
              backgroundColor: AppColors.blue)
          : null,
      body: Column(children: [
        Container(
            color: AppColors.bgSurface,
            child: TabBar(
              controller: _tabCtrl,
              labelColor: AppColors.blue,
              unselectedLabelColor: AppColors.textMuted,
              indicatorColor: AppColors.blue,
              tabs: const [
                Tab(text: 'Active'),
                Tab(text: 'Closed'),
                Tab(text: 'All')
              ],
            )),
        _buildDateBar(),
        Expanded(
          child: _loading
              ? const LoadingView(message: 'Loading shifts...')
              : _error != null
                  ? ErrorView(message: _error!, onRetry: _fetch)
                  : RefreshIndicator(
                      onRefresh: _fetch,
                      color: AppColors.blue,
                      child: CustomScrollView(slivers: [
                        SliverToBoxAdapter(child: _buildSummary()),
                        if (_shifts.isEmpty)
                          const SliverFillRemaining(
                              child: EmptyView(
                                  title: 'No shifts found',
                                  subtitle:
                                      'Shifts will appear here once opened',
                                  icon: Icons.swap_horiz_outlined))
                        else
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                            sliver: SliverList(
                                delegate: SliverChildBuilderDelegate(
                              (_, i) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _ShiftCard(
                                    shift: _shifts[i],
                                    onTap: () {
                                      final status = (_shifts[i]
                                              as Map)['status'] as String? ??
                                          '';
                                      final pumpId =
                                          ((_shifts[i] as Map)['pump']
                                                  as Map?)?['id'] as String? ??
                                              '';
                                      if (status == 'OPEN') {
                                        context.go('/worker/nozzle/$pumpId');
                                      } else {
                                        context.go(
                                            '/app/shifts/payment/${(_shifts[i] as Map)['id']}');
                                      }
                                    },
                                  )),
                              childCount: _shifts.length,
                            )),
                          ),
                      ])),
        ),
      ]),
    );
  }
}

class _ShiftCard extends StatelessWidget {
  final Map<String, dynamic> shift;
  final VoidCallback onTap;
  const _ShiftCard({required this.shift, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final pump = (shift['pump'] as Map?)?.cast<String, dynamic>() ?? {};
    final worker =
        (shift['assigned_worker'] as Map?)?.cast<String, dynamic>() ?? {};
    final status = shift['status'] as String? ?? '';
    final entries = shift['nozzle_entries'] as List? ?? [];
    final amount = entries.fold<double>(
        0,
        (s, e) =>
            s +
            (double.tryParse((e as Map)['sale_amount']?.toString() ?? '0') ??
                0));
    final litres = entries.fold<double>(
        0,
        (s, e) =>
            s +
            (double.tryParse((e as Map)['sale_litres']?.toString() ?? '0') ??
                0));
    final isOpen = status == 'OPEN';

    return AppCard(
      onTap: onTap,
      borderColor: isOpen ? AppColors.green.withValues(alpha: 0.25) : null,
      child: Column(children: [
        Row(children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: isOpen ? AppColors.green : AppColors.textMuted,
                  shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(pump['name'] as String? ?? 'Pump',
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
                Text(worker['full_name'] as String? ?? 'Unassigned',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
              ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(IndianCurrency.format(amount),
                style: const TextStyle(
                    color: AppColors.green,
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
            StatusBadge.fromStatus(status),
          ]),
        ]),
        if (litres > 0 || !isOpen) ...[
          const SizedBox(height: 8),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 8),
          Row(children: [
            if (litres > 0) ...[
              const Icon(Icons.water_drop_outlined,
                  size: 12, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Text(IndianCurrency.formatLitres(litres),
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 11)),
              const SizedBox(width: 12)
            ],
            const Icon(Icons.schedule, size: 12, color: AppColors.textMuted),
            const SizedBox(width: 4),
            Text(
                IstTime.formatDateTime(DateTime.parse(
                    shift['start_time'] as String? ??
                        shift['created_at'] as String)),
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 11)),
            const Spacer(),
            Text(isOpen ? 'Enter readings →' : 'Settle →',
                style: const TextStyle(
                    color: AppColors.blue,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ]),
        ],
      ]),
    );
  }
}

class _NavRow extends StatelessWidget {
  final String label;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback? onTap;
  const _NavRow(
      {required this.label,
      required this.onPrev,
      required this.onNext,
      this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(children: [
          IconButton(
              icon: const Icon(Icons.chevron_left,
                  color: AppColors.textSecondary),
              onPressed: onPrev),
          Expanded(
              child: GestureDetector(
                  onTap: onTap,
                  child: Text(label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)))),
          IconButton(
              icon: const Icon(Icons.chevron_right,
                  color: AppColors.textSecondary),
              onPressed: onNext),
        ]),
      );
}

class _DateBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _DateBtn({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border)),
          child: Text(label,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500),
              textAlign: TextAlign.center)));
}

class _SumCell extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _SumCell(this.label, this.value, {this.color = AppColors.textPrimary});
  @override
  Widget build(BuildContext context) => Expanded(
          child: Column(children: [
        Text(value,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w800, fontSize: 16)),
        Text(label,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11))
      ]));
}
