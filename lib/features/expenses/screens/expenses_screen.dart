import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/tenant_service.dart';
import '../../../core/utils/ist_time.dart';
import '../../../core/utils/currency.dart';
import '../../../shared/widgets/widgets.dart';

const _kCategories = [
  ('electricity', 'Electricity', Icons.bolt, AppColors.amber),
  ('maintenance', 'Maintenance', Icons.build_outlined, Color(0xFFFB923C)),
  ('water', 'Water', Icons.water_drop_outlined, Color(0xFF22D3EE)),
  ('salaries', 'Salaries', Icons.people_outline, AppColors.purple),
  ('rent', 'Rent', Icons.home_outlined, Color(0xFFF472B6)),
  ('wifi', 'WiFi', Icons.wifi, AppColors.blue),
  ('misc', 'Misc', Icons.category_outlined, AppColors.textSecondary),
  ('custom', 'Custom', Icons.add, AppColors.textSecondary),
];

class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});
  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  bool _loading = true;
  String? _error;
  List<dynamic> _expenses = [];
  Map<String, dynamic>? _summary;
  String _period = 'month';
  DateTime _monthDate = DateTime.now();
  DateTime _dayDate = DateTime.now();
  String _catFilter = 'all';

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  String _monthStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';
  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = TenantService.instance.client;
      final user = ref.read(currentUserProvider)!;

      var query = db
          .from('DailyExpense')
          .select(
              'id, category, custom_category, name, amount, expense_date, description, vendor_name, is_system_generated, created_at, recorder:User(full_name)')
          .eq('station_id', user.stationId)
          .isFilter('deleted_at', null);

      if (_period == 'month') {
        query = query.like('business_date', '${_monthStr(_monthDate)}%');
      } else {
        query = query.eq('business_date', _dateStr(_dayDate));
      }

      if (_catFilter != 'all') {
        query = query.eq('category', _catFilter);
      }

      final data = await query
          .order('expense_date', ascending: false)
          .order('created_at', ascending: false);
      final expenses = data as List;

      // Compute summary
      final total = expenses.fold<double>(0,
          (s, e) => s + (double.tryParse(e['amount']?.toString() ?? '0') ?? 0));
      final today = _dateStr(DateTime.now());
      final todayTotal = expenses
          .where((e) => (e['expense_date'] as String? ?? '').startsWith(today))
          .fold<double>(
              0,
              (s, e) =>
                  s + (double.tryParse(e['amount']?.toString() ?? '0') ?? 0));

      setState(() {
        _expenses = expenses;
        _summary = {
          'total': total,
          'todayTotal': todayTotal,
          'count': expenses.length
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

  List<Map<String, dynamic>> get _grouped {
    final Map<String, List<dynamic>> byDate = {};
    for (final e in _expenses) {
      final date = (e['expense_date'] as String? ?? '').substring(0, 10);
      byDate.putIfAbsent(date, () => []).add(e);
    }
    return byDate.entries.map((entry) {
      final total = entry.value.fold<double>(
          0,
          (s, e) =>
              s +
              (double.tryParse((e as Map)['amount']?.toString() ?? '0') ?? 0));
      return {'date': entry.key, 'items': entry.value, 'total': total};
    }).toList()
      ..sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
  }

  Future<void> _showAddExpense({Map<String, dynamic>? existing}) async {
    final isEdit = existing != null;
    String category = existing?['category'] as String? ?? 'misc';
    final nameCtrl = TextEditingController(
        text: existing?['name'] as String? ?? _catLabel(category));
    final amtCtrl =
        TextEditingController(text: existing?['amount']?.toString() ?? '');
    final descCtrl =
        TextEditingController(text: existing?['description'] as String? ?? '');
    final vendorCtrl =
        TextEditingController(text: existing?['vendor_name'] as String? ?? '');
    final customCatCtrl = TextEditingController(
        text: existing?['custom_category'] as String? ?? '');
    DateTime expDate = existing != null
        ? DateTime.tryParse(existing['expense_date'] as String? ?? '') ??
            DateTime.now()
        : DateTime.now();
    bool submitting = false;
    String? err;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, ss) => SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                    20, 20, 20, MediaQuery.viewInsetsOf(ctx).bottom + 24),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(
                            isEdit
                                ? Icons.edit_outlined
                                : Icons.add_circle_outline,
                            color: AppColors.blue,
                            size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(isEdit ? 'Edit Expense' : 'Add Expense',
                                style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700))),
                        IconButton(
                            icon: const Icon(Icons.close,
                                size: 20, color: AppColors.textMuted),
                            onPressed: () => Navigator.pop(ctx)),
                      ]),
                      const SizedBox(height: 16),

                      // Category picker
                      const Text('CATEGORY',
                          style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1)),
                      const SizedBox(height: 8),
                      Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _kCategories.map((cat) {
                            final (key, label, icon, color) = cat;
                            final sel = category == key;
                            return GestureDetector(
                              onTap: () {
                                ss(() {
                                  category = key;
                                  if (key != 'custom') nameCtrl.text = label;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 7),
                                decoration: BoxDecoration(
                                    color: sel
                                        ? color.withOpacity(0.15)
                                        : AppColors.bgCard,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: sel ? color : AppColors.border,
                                        width: sel ? 1.5 : 1)),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(icon,
                                          size: 14,
                                          color: sel
                                              ? color
                                              : AppColors.textMuted),
                                      const SizedBox(width: 4),
                                      Text(label,
                                          style: TextStyle(
                                              color: sel
                                                  ? color
                                                  : AppColors.textSecondary,
                                              fontSize: 12,
                                              fontWeight: sel
                                                  ? FontWeight.w600
                                                  : FontWeight.w400)),
                                    ]),
                              ),
                            );
                          }).toList()),

                      if (category == 'custom') ...[
                        const SizedBox(height: 12),
                        _TF(
                            label: 'Custom Category Name',
                            ctrl: customCatCtrl,
                            capitalize: TextCapitalization.words),
                      ],
                      const SizedBox(height: 12),
                      _TF(
                          label: 'Expense Name',
                          ctrl: nameCtrl,
                          capitalize: TextCapitalization.sentences),
                      const SizedBox(height: 12),
                      _TF(
                          label: 'Amount (₹) *',
                          ctrl: amtCtrl,
                          keyboard: const TextInputType.numberWithOptions(
                              decimal: true)),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                            child: _TF(
                                label: 'Vendor / Supplier',
                                ctrl: vendorCtrl,
                                capitalize: TextCapitalization.words)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: GestureDetector(
                          onTap: () async {
                            final d = await showDatePicker(
                                context: context,
                                initialDate: expDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now());
                            if (d != null) ss(() => expDate = d);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 16),
                            decoration: BoxDecoration(
                                color: AppColors.bgCard,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.border)),
                            child: Row(children: [
                              const Icon(Icons.calendar_today,
                                  size: 16, color: AppColors.textMuted),
                              const SizedBox(width: 8),
                              Text(IstTime.formatShortDate(expDate),
                                  style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 13)),
                            ]),
                          ),
                        )),
                      ]),
                      const SizedBox(height: 12),
                      _TF(
                          label: 'Notes (optional)',
                          ctrl: descCtrl,
                          maxLines: 2),

                      if (err != null) ...[
                        const SizedBox(height: 10),
                        Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                                color: AppColors.redBg,
                                borderRadius: BorderRadius.circular(8)),
                            child: Text(err!,
                                style: const TextStyle(
                                    color: AppColors.red, fontSize: 12))),
                      ],
                      const SizedBox(height: 20),
                      AppButton(
                        label: isEdit ? 'Save Changes' : 'Add Expense',
                        loading: submitting,
                        width: double.infinity,
                        onTap: () async {
                          final amt =
                              double.tryParse(amtCtrl.text.replaceAll(',', ''));
                          if (amt == null || amt <= 0) {
                            ss(() => err = 'Enter a valid amount');
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
                            final payload = {
                              'station_id': user.stationId,
                              'category': category,
                              'custom_category': category == 'custom'
                                  ? customCatCtrl.text.trim()
                                  : null,
                              'name': nameCtrl.text.trim().isEmpty
                                  ? _catLabel(category)
                                  : nameCtrl.text.trim(),
                              'amount': amt,
                              'description': descCtrl.text.trim().isEmpty
                                  ? null
                                  : descCtrl.text.trim(),
                              'vendor_name': vendorCtrl.text.trim().isEmpty
                                  ? null
                                  : vendorCtrl.text.trim(),
                              'expense_date':
                                  '${expDate.year}-${expDate.month.toString().padLeft(2, '0')}-${expDate.day.toString().padLeft(2, '0')}T00:00:00.000Z',
                              'business_date':
                                  '${expDate.year}-${expDate.month.toString().padLeft(2, '0')}-${expDate.day.toString().padLeft(2, '0')}T00:00:00.000Z',
                              'recorded_at': now,
                              'is_system_generated': false,
                              'recorded_by': user
                                  .id, // DailyExpense.recorded_by = user_id directly
                              'updated_at': now,
                            };
                            if (isEdit) {
                              await db
                                  .from('DailyExpense')
                                  .update(payload)
                                  .eq('id', existing['id']);
                            } else {
                              await db
                                  .from('DailyExpense')
                                  .insert({...payload, 'created_at': now});
                            }
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(isEdit
                                          ? '✅ Expense updated'
                                          : '✅ Expense added'),
                                      backgroundColor: AppColors.green));
                              _fetch();
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
    for (final c in [nameCtrl, amtCtrl, descCtrl, vendorCtrl, customCatCtrl])
      c.dispose();
  }

  Future<void> _deleteExpense(String id) async {
    final ok = await showConfirmDialog(context,
        title: 'Delete Expense',
        message: 'This expense will be removed.',
        confirmLabel: 'Delete',
        isDanger: true);
    if (!ok) return;
    try {
      final db = TenantService.instance.client;
      await db.from('DailyExpense').update({
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);
      _fetch();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _shareWhatsApp() {
    final total = _summary?['total'] as double? ?? 0;
    final stationName = ref.read(stationNameProvider);
    final period =
        _period == 'month' ? _monthStr(_monthDate) : _dateStr(_dayDate);
    final lines = [
      '🏪 *$stationName* — Expense Summary',
      '📅 Period: $period',
      '💸 Total: ${IndianCurrency.format(total)}',
      '📋 Entries: ${_expenses.length}',
      '',
      '_FuelOS_'
    ];
    Share.share(lines.join('\n'));
  }

  String _catLabel(String key) {
    for (final (k, l, _, __) in _kCategories) {
      if (k == key) return l;
    }
    return key;
  }

  @override
  Widget build(BuildContext context) {
    final isManager =
        ref.watch(currentUserProvider)?.isManagerOrDealer ?? false;
    final grouped = _grouped;

    return Scaffold(
      backgroundColor: AppColors.bgApp,
      floatingActionButton: isManager
          ? FloatingActionButton.extended(
              onPressed: () => _showAddExpense(),
              icon: const Icon(Icons.add),
              label: const Text('Add Expense'),
              backgroundColor: AppColors.blue)
          : null,
      body: Column(children: [
        // Period selector + export
        Container(
            color: AppColors.bgSurface,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(children: [
              Row(children: [
                ...[('month', 'Monthly'), ('day', 'Daily')].map((p) {
                  final sel = _period == p.$1;
                  return GestureDetector(
                      onTap: () {
                        setState(() => _period = p.$1);
                        _fetch();
                      },
                      child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                              color: sel ? AppColors.blue : AppColors.bgCard,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color:
                                      sel ? AppColors.blue : AppColors.border)),
                          child: Text(p.$2,
                              style: TextStyle(
                                  color: sel
                                      ? Colors.white
                                      : AppColors.textSecondary,
                                  fontSize: 12,
                                  fontWeight: sel
                                      ? FontWeight.w600
                                      : FontWeight.w400))));
                }),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.share_outlined,
                        size: 18, color: AppColors.textSecondary),
                    onPressed: _shareWhatsApp,
                    tooltip: 'Share'),
                IconButton(
                    icon: const Icon(Icons.refresh,
                        size: 18, color: AppColors.textSecondary),
                    onPressed: _fetch),
              ]),
              const SizedBox(height: 8),
              // Date nav
              _period == 'month'
                  ? Row(children: [
                      IconButton(
                          icon: const Icon(Icons.chevron_left,
                              color: AppColors.textSecondary),
                          onPressed: () {
                            setState(() => _monthDate = DateTime(
                                _monthDate.year, _monthDate.month - 1));
                            _fetch();
                          }),
                      Expanded(
                          child: Text(_monthStr(_monthDate),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600))),
                      IconButton(
                          icon: const Icon(Icons.chevron_right,
                              color: AppColors.textSecondary),
                          onPressed: () {
                            setState(() => _monthDate = DateTime(
                                _monthDate.year, _monthDate.month + 1));
                            _fetch();
                          }),
                    ])
                  : Row(children: [
                      IconButton(
                          icon: const Icon(Icons.chevron_left,
                              color: AppColors.textSecondary),
                          onPressed: () {
                            setState(() => _dayDate =
                                _dayDate.subtract(const Duration(days: 1)));
                            _fetch();
                          }),
                      Expanded(
                          child: GestureDetector(
                              onTap: () async {
                                final d = await showDatePicker(
                                    context: context,
                                    initialDate: _dayDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now());
                                if (d != null) {
                                  setState(() => _dayDate = d);
                                  _fetch();
                                }
                              },
                              child: Text(IstTime.formatDate(_dayDate),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w600)))),
                      IconButton(
                          icon: const Icon(Icons.chevron_right,
                              color: AppColors.textSecondary),
                          onPressed: () {
                            setState(() => _dayDate =
                                _dayDate.add(const Duration(days: 1)));
                            _fetch();
                          }),
                    ]),
            ])),

        // Summary bar
        if (_summary != null)
          Container(
              color: AppColors.bgSurface,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(children: [
                _SumCell2(
                    'Total',
                    IndianCurrency.formatCompact(_summary!['total'] as double),
                    AppColors.red),
                Container(width: 1, height: 30, color: AppColors.border),
                _SumCell2(
                    'Today',
                    IndianCurrency.formatCompact(
                        _summary!['todayTotal'] as double),
                    AppColors.amber),
                Container(width: 1, height: 30, color: AppColors.border),
                _SumCell2('Entries', '${_summary!['count']}',
                    AppColors.textSecondary),
              ])),

        // Category chips
        Container(
            color: AppColors.bgSurface,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _CatChip('all', 'All', Icons.apps, _catFilter, (v) {
                    setState(() => _catFilter = v);
                    _fetch();
                  }),
                  ..._kCategories
                      .map((c) => _CatChip(c.$1, c.$2, c.$3, _catFilter, (v) {
                            setState(() => _catFilter = v);
                            _fetch();
                          })),
                ]))),

        // Expense list
        Expanded(
            child: _loading
                ? const LoadingView()
                : _error != null
                    ? ErrorView(message: _error!, onRetry: _fetch)
                    : RefreshIndicator(
                        onRefresh: _fetch,
                        color: AppColors.blue,
                        child: grouped.isEmpty
                            ? const EmptyView(
                                title: 'No expenses recorded',
                                subtitle: 'Tap + to add an expense',
                                icon: Icons.receipt_long_outlined)
                            : ListView.builder(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 12, 16, 80),
                                itemCount: grouped.length,
                                itemBuilder: (_, gi) {
                                  final group = grouped[gi];
                                  final items = group['items'] as List;
                                  final groupDate = group['date'] as String;
                                  final groupTotal = group['total'] as double;
                                  return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 8,
                                                top: gi == 0 ? 0 : 16),
                                            child: Row(children: [
                                              Text(
                                                  IstTime.formatDate(
                                                      DateTime.parse(groupDate +
                                                          'T00:00:00.000Z')),
                                                  style: const TextStyle(
                                                      color: AppColors
                                                          .textSecondary,
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w600)),
                                              const Spacer(),
                                              Text(
                                                  IndianCurrency.format(
                                                      groupTotal),
                                                  style: const TextStyle(
                                                      color: AppColors.red,
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w600)),
                                            ])),
                                        ...items.map((e) {
                                          final amt = double.tryParse(
                                                  (e as Map)['amount']
                                                          ?.toString() ??
                                                      '0') ??
                                              0;
                                          final cat =
                                              e['category'] as String? ??
                                                  'misc';
                                          final catData = _kCategories
                                              .firstWhere((c) => c.$1 == cat,
                                                  orElse: () =>
                                                      _kCategories.last);
                                          return Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 8),
                                              child: AppCard(
                                                  child: Row(children: [
                                                Container(
                                                    width: 38,
                                                    height: 38,
                                                    decoration: BoxDecoration(
                                                        color: catData.$4
                                                            .withOpacity(0.12),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(10)),
                                                    alignment: Alignment.center,
                                                    child: Icon(catData.$3,
                                                        size: 18,
                                                        color: catData.$4)),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                    child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                      Text(
                                                          e['name']
                                                                  as String? ??
                                                              '',
                                                          style: const TextStyle(
                                                              color: AppColors
                                                                  .textPrimary,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600)),
                                                      if (e['vendor_name'] !=
                                                          null)
                                                        Text(
                                                            e['vendor_name']
                                                                as String,
                                                            style: const TextStyle(
                                                                color: AppColors
                                                                    .textSecondary,
                                                                fontSize: 12)),
                                                      if (e['description'] !=
                                                          null)
                                                        Text(
                                                            e['description']
                                                                as String,
                                                            style: const TextStyle(
                                                                color: AppColors
                                                                    .textMuted,
                                                                fontSize: 11)),
                                                    ])),
                                                Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.end,
                                                    children: [
                                                      Text(
                                                          IndianCurrency.format(
                                                              amt),
                                                          style:
                                                              const TextStyle(
                                                                  color:
                                                                      AppColors
                                                                          .red,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                  fontSize:
                                                                      15)),
                                                      if (isManager)
                                                        Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              GestureDetector(
                                                                  onTap: () => _showAddExpense(
                                                                      existing: Map<
                                                                              String,
                                                                              dynamic>.from(
                                                                          e)),
                                                                  child: const Icon(
                                                                      Icons
                                                                          .edit_outlined,
                                                                      size: 14,
                                                                      color: AppColors
                                                                          .textMuted)),
                                                              const SizedBox(
                                                                  width: 8),
                                                              GestureDetector(
                                                                  onTap: () =>
                                                                      _deleteExpense(
                                                                          e['id']
                                                                              as String),
                                                                  child: const Icon(
                                                                      Icons
                                                                          .delete_outline,
                                                                      size: 14,
                                                                      color: AppColors
                                                                          .red)),
                                                            ]),
                                                    ]),
                                              ])));
                                        }),
                                      ]);
                                },
                              ))),
      ]),
    );
  }
}

class _TF extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final TextInputType? keyboard;
  final TextCapitalization capitalize;
  final int maxLines;
  const _TF(
      {required this.label,
      required this.ctrl,
      this.keyboard,
      this.capitalize = TextCapitalization.none,
      this.maxLines = 1});
  @override
  Widget build(BuildContext context) => TextField(
      controller: ctrl,
      keyboardType: keyboard,
      textCapitalization: capitalize,
      maxLines: maxLines,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          filled: true,
          fillColor: AppColors.bgCard,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12)));
}

class _SumCell2 extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _SumCell2(this.label, this.value, this.color);
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

class _CatChip extends StatelessWidget {
  final String key;
  final String label;
  final IconData icon;
  final String selected;
  final void Function(String) onTap;
  const _CatChip(this.key, this.label, this.icon, this.selected, this.onTap);
  @override
  Widget build(BuildContext context) {
    final sel = selected == key;
    return GestureDetector(
        onTap: () => onTap(key),
        child: Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
                color: sel ? AppColors.blue : AppColors.bgCard,
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: sel ? AppColors.blue : AppColors.border)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon,
                  size: 12, color: sel ? Colors.white : AppColors.textMuted),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      color: sel ? Colors.white : AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: sel ? FontWeight.w600 : FontWeight.w400))
            ])));
  }
}
