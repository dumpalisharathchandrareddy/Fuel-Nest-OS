import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/utils/ist_time.dart';

class _NavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final String path;
  final List<String> roles; // empty = all manager roles

  const _NavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.path,
  });
}

const _navItems = [
  _NavItem(
    label: 'Dashboard',
    icon: Icons.dashboard_outlined,
    activeIcon: Icons.dashboard,
    path: '/app/dashboard',
  ),
  _NavItem(
    label: 'Shifts',
    icon: Icons.swap_horiz_outlined,
    activeIcon: Icons.swap_horiz,
    path: '/app/shifts',
  ),
  _NavItem(
    label: 'Inventory',
    icon: Icons.local_gas_station_outlined,
    activeIcon: Icons.local_gas_station,
    path: '/app/inventory',
  ),
  _NavItem(
    label: 'Credit',
    icon: Icons.credit_card_outlined,
    activeIcon: Icons.credit_card,
    path: '/app/credit',
  ),
  _NavItem(
    label: 'Payroll',
    icon: Icons.payments_outlined,
    activeIcon: Icons.payments,
    path: '/app/payroll',
  ),
  _NavItem(
    label: 'Staff',
    icon: Icons.people_outline,
    activeIcon: Icons.people,
    path: '/app/staff',
  ),
  _NavItem(
    label: 'Reports',
    icon: Icons.bar_chart_outlined,
    activeIcon: Icons.bar_chart,
    path: '/app/reports',
  ),
  _NavItem(
    label: 'Expenses',
    icon: Icons.receipt_long_outlined,
    activeIcon: Icons.receipt_long,
    path: '/app/expenses',
  ),
  _NavItem(
    label: 'Rates',
    icon: Icons.local_offer_outlined,
    activeIcon: Icons.local_offer,
    path: '/app/rates',
  ),
  _NavItem(
    label: 'Hardware',
    icon: Icons.settings_input_component_outlined,
    activeIcon: Icons.settings_input_component,
    path: '/app/hardware',
  ),
  _NavItem(
    label: 'Settings',
    icon: Icons.settings_outlined,
    activeIcon: Icons.settings,
    path: '/app/settings',
  ),
];

// Bottom nav shows only the most important items (mobile)
const _bottomNavPaths = [
  '/app/dashboard',
  '/app/shifts',
  '/app/inventory',
  '/app/credit',
  '/app/reports',
];

class MainShell extends ConsumerStatefulWidget {
  final Widget child;
  final GoRouterState state;
  const MainShell({super.key, required this.child, required this.state});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  bool _sidebarExpanded = true;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isDesktop = size.width >= 900;
    final isTablet = size.width >= 600 && size.width < 900;

    if (isDesktop) return _buildDesktopLayout(context);
    if (isTablet) return _buildTabletLayout(context);
    return _buildMobileLayout(context);
  }

  // ── Desktop: full sidebar ─────────────────────────────────────────────────
  Widget _buildDesktopLayout(BuildContext context) {
    final loc = widget.state.matchedLocation;
    final user = ref.watch(currentUserProvider);
    return Scaffold(
      backgroundColor: AppColors.bgApp,
      body: Row(
        children: [
          _Sidebar(
            loc: loc,
            expanded: _sidebarExpanded,
            onToggle: () =>
                setState(() => _sidebarExpanded = !_sidebarExpanded),
          ),
          const VerticalDivider(width: 1, color: AppColors.border),
          Expanded(
            child: user == null
                ? const Center(child: CircularProgressIndicator())
                : widget.child,
          ),
        ],
      ),
    );
  }

  // ── Tablet: rail navigation ───────────────────────────────────────────────
  Widget _buildTabletLayout(BuildContext context) {
    final loc = widget.state.matchedLocation;
    final user = ref.watch(currentUserProvider);
    final selectedIdx = _navItems.indexWhere((i) => i.path == loc);

    return Scaffold(
      backgroundColor: AppColors.bgApp,
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selectedIdx < 0 ? 0 : selectedIdx,
            onDestinationSelected: (i) => context.go(_navItems[i].path),
            labelType: NavigationRailLabelType.selected,
            destinations: _navItems
                .map((item) => NavigationRailDestination(
                      icon: Icon(item.icon),
                      selectedIcon: Icon(item.activeIcon),
                      label: Text(item.label),
                    ))
                .toList(),
            leading: const _AppLogo(collapsed: true),
            trailing: const _UserChip(collapsed: true),
          ),
          const VerticalDivider(width: 1, color: AppColors.border),
          Expanded(
            child: user == null
                ? const Center(child: CircularProgressIndicator())
                : widget.child,
          ),
        ],
      ),
    );
  }

  // ── Mobile: bottom navigation ─────────────────────────────────────────────
  Widget _buildMobileLayout(BuildContext context) {
    final loc = widget.state.matchedLocation;
    final user = ref.watch(currentUserProvider);
    final bottomItems =
        _navItems.where((i) => _bottomNavPaths.contains(i.path)).toList();
    final selectedIdx = bottomItems.indexWhere((i) => i.path == loc);

    return Scaffold(
      backgroundColor: AppColors.bgApp,
      appBar: _MobileAppBar(currentPath: loc),
      body: user == null
          ? const Center(child: CircularProgressIndicator())
          : widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIdx < 0 ? 0 : selectedIdx,
        onDestinationSelected: (i) => context.go(bottomItems[i].path),
        destinations: bottomItems
            .map((item) => NavigationDestination(
                  icon: Icon(item.icon),
                  selectedIcon: Icon(item.activeIcon),
                  label: item.label,
                ))
            .toList(),
      ),
      drawer: _MobileDrawer(currentPath: loc),
    );
  }
}

// ── Desktop Sidebar ───────────────────────────────────────────────────────────

class _Sidebar extends ConsumerWidget {
  final String loc;
  final bool expanded;
  final VoidCallback onToggle;

  const _Sidebar(
      {required this.loc, required this.expanded, required this.onToggle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = expanded ? 210.0 : 52.0;
    final user = ref.watch(currentUserProvider);
    final stationName = ref.watch(stationNameProvider);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: width,
      color: AppColors.bgSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo + toggle
          SizedBox(
            height: 56,
            child: Row(
              children: [
                const SizedBox(width: 14),
                const Icon(Icons.local_gas_station,
                    color: AppColors.blue, size: 20),
                if (expanded) ...[
                  const SizedBox(width: 10),
                  const Text(
                    'FuelOS',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
                const Spacer(),
                IconButton(
                  icon: Icon(
                    expanded ? Icons.chevron_left : Icons.chevron_right,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                  onPressed: onToggle,
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),

          // Station name
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                stationName.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

          // Nav items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
              children: _navItems.map((item) {
                final active = loc == item.path;
                return _SidebarItem(
                  item: item,
                  active: active,
                  expanded: expanded,
                  onTap: () => context.go(item.path),
                );
              }).toList(),
            ),
          ),

          const Divider(height: 1, color: AppColors.border),

          // User + IST clock
          _SidebarUser(
              user: user, expanded: expanded, stationName: stationName),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final _NavItem item;
  final bool active;
  final bool expanded;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.item,
    required this.active,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: expanded ? '' : item.label,
      preferBelow: false,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(
            horizontal: expanded ? 12 : 14,
            vertical: 9,
          ),
          decoration: BoxDecoration(
            color: active ? AppColors.bgActive : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: active
                ? Border.all(color: AppColors.purple.withValues(alpha: 0.1))
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active ? item.activeIcon : item.icon,
                size: 18,
                color: active ? AppColors.blue : AppColors.textMuted,
              ),
              if (expanded) ...[
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      color: active
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarUser extends ConsumerWidget {
  final dynamic user;
  final bool expanded;
  final String stationName;

  const _SidebarUser(
      {required this.user, required this.expanded, required this.stationName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.blueBg,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              (user?.fullName ?? 'U').substring(0, 1).toUpperCase(),
              style: const TextStyle(
                color: AppColors.blue,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (expanded) ...[
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    user?.fullName ?? '',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    user?.displayRole ?? '',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.logout,
                  size: 16, color: AppColors.textMuted),
              onPressed: () => _confirmLogout(context, ref),
              padding: EdgeInsets.zero,
              tooltip: 'Logout',
            ),
          ],
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(authProvider.notifier).logout();
            },
            child: const Text('Logout', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
  }
}

// ── Mobile components ─────────────────────────────────────────────────────────

class _MobileAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final String currentPath;
  const _MobileAppBar({required this.currentPath});

  @override
  Size get preferredSize => const Size.fromHeight(56);

  String _title() {
    final item = _navItems.firstWhere(
      (i) => i.path == currentPath,
      orElse: () => _navItems.first,
    );
    return item.label;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stationName = ref.watch(stationNameProvider);

    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_title(),
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          Text(stationName,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ],
      ),
      actions: [
        _IstClock(),
        const SizedBox(width: 8),
        Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu, color: AppColors.textSecondary),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
      ],
    );
  }
}

class _MobileDrawer extends ConsumerWidget {
  final String currentPath;
  const _MobileDrawer({required this.currentPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final stationName = ref.watch(stationNameProvider);

    return Drawer(
      backgroundColor: AppColors.bgSurface,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.blueBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      (user?.fullName ?? 'U').substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                          color: AppColors.blue,
                          fontSize: 16,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user?.fullName ?? '',
                            style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700)),
                        Text(
                          '${user?.displayRole} · $stationName',
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Nav items
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                children: _navItems.map((item) {
                  final active = currentPath == item.path;
                  return ListTile(
                    onTap: () {
                      Navigator.pop(context);
                      context.go(item.path);
                    },
                    leading: Icon(
                      active ? item.activeIcon : item.icon,
                      size: 20,
                      color: active ? AppColors.blue : AppColors.textSecondary,
                    ),
                    title: Text(
                      item.label,
                      style: TextStyle(
                        color: active
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        fontSize: 14,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    selected: active,
                    selectedTileColor: AppColors.bgActive,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  );
                }).toList(),
              ),
            ),

            // Logout
            const Divider(height: 1, color: AppColors.border),
            ListTile(
              onTap: () async {
                Navigator.pop(context);
                await ref.read(authProvider.notifier).logout();
              },
              leading: const Icon(Icons.logout,
                  size: 20, color: AppColors.textMuted),
              title: const Text('Logout',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── IST Clock ─────────────────────────────────────────────────────────────────

class _IstClock extends StatefulWidget {
  @override
  State<_IstClock> createState() => _IstClockState();
}

class _IstClockState extends State<_IstClock> {
  late String _time;

  @override
  void initState() {
    super.initState();
    _updateTime();
    // Update every minute
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 30));
      if (mounted) setState(() => _updateTime());
      return mounted;
    });
  }

  void _updateTime() {
    _time = IstTime.formatTime(DateTime.now().toUtc());
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _time,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
          const Text('IST',
              style: TextStyle(color: AppColors.textMuted, fontSize: 9)),
        ],
      ),
    );
  }
}

class _AppLogo extends StatelessWidget {
  final bool collapsed;
  const _AppLogo({this.collapsed = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_gas_station, color: AppColors.blue, size: 20),
          if (!collapsed) ...[
            const SizedBox(width: 8),
            const Text('FuelOS',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
          ],
        ],
      ),
    );
  }
}

class _UserChip extends ConsumerWidget {
  final bool collapsed;
  const _UserChip({this.collapsed = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const SizedBox.shrink();
  }
}
