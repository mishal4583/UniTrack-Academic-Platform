// ═══════════════════════════════════════════════════════════════════════════════
// faculty_dashboard_layout.dart   v4  (added Manage nav item)
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class _C {
  static const bg = Color(0xFF080D19);
  static const card = Color(0xFF111827);
  static const primary = Color(0xFF8B5CF6);
  static const neonBlue = Color(0xFF3B82F6);
  static const neonCyan = Color(0xFF06B6D4);
  static const text = Color(0xFFEFF3F8);
  static const muted = Color(0xFF7E8A9A);
  static const border = Color(0xFF1F2937);
  static const secondary = Color(0xFF1A2235);
}

class _NavItem {
  final String label;
  final IconData icon;
  final String route;
  final bool isPeer;
  const _NavItem({
    required this.label,
    required this.icon,
    required this.route,
    this.isPeer = true,
  });
}

// Sidebar items — Manage added between Verify and Analytics
const _sidebarItems = [
  _NavItem(
    label: 'Dashboard',
    icon: Icons.dashboard_rounded,
    route: '/faculty',
  ),
  _NavItem(
    label: 'Create Activity',
    icon: Icons.add_circle_rounded,
    route: '/faculty/create',
    isPeer: false,
  ),
  _NavItem(
    label: 'Create Volunteering',
    icon: Icons.eco_rounded,
    route: '/faculty/volunteering/create',
    isPeer: false,
  ),
  _NavItem(
    label: 'Manage',
    icon: Icons.folder_open_rounded,
    route: '/faculty/manage',
  ),
  _NavItem(
    label: 'Verify',
    icon: Icons.fact_check_rounded,
    route: '/faculty/verify',
  ),
  _NavItem(
    label: 'Analytics',
    icon: Icons.bar_chart_rounded,
    route: '/faculty/analytics',
  ),
  _NavItem(
    label: 'Profile',
    icon: Icons.person_rounded,
    route: '/faculty/profile',
  ),
];

// Bottom nav — Manage replaces one slot (5-item limit for mobile readability)
const _bottomNavItems = [
  _NavItem(label: 'Home', icon: Icons.dashboard_rounded, route: '/faculty'),
  _NavItem(
    label: 'Manage',
    icon: Icons.folder_open_rounded,
    route: '/faculty/manage',
  ),
  _NavItem(
    label: 'Verify',
    icon: Icons.fact_check_rounded,
    route: '/faculty/verify',
  ),
  _NavItem(
    label: 'Analytics',
    icon: Icons.bar_chart_rounded,
    route: '/faculty/analytics',
  ),
  _NavItem(
    label: 'Profile',
    icon: Icons.person_rounded,
    route: '/faculty/profile',
  ),
];

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _anim = Tween(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _anim,
    child: Container(
      width: 7,
      height: 7,
      decoration: const BoxDecoration(
        color: _C.neonCyan,
        shape: BoxShape.circle,
      ),
    ),
  );
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF1F2937).withValues(alpha: 0.3)
      ..strokeWidth = 0.8;
    for (double x = 0; x < size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(CustomPainter _) => false;
}

class _SidebarContent extends StatelessWidget {
  final String currentRoute;
  final bool expanded;
  final String userName;
  final VoidCallback? onItemTap;

  const _SidebarContent({
    required this.currentRoute,
    required this.expanded,
    required this.userName,
    this.onItemTap,
  });

  void _navigate(BuildContext context, _NavItem item) {
    onItemTap?.call();
    if (currentRoute == item.route) return;
    if (item.isPeer) {
      Navigator.pushReplacementNamed(context, item.route);
    } else {
      Navigator.pushNamed(context, item.route);
    }
  }

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _C.border)),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_C.primary, _C.neonBlue],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset('assets/logo/logo.png', fit: BoxFit.cover),
              ),
            ),
            if (expanded) ...[
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'UniTrack',
                      style: TextStyle(
                        color: _C.text,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Faculty Portal',
                      style: TextStyle(color: _C.muted, fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),

      Expanded(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          children: _sidebarItems.map((item) {
            // Highlight manage item also when on detail screen
            final isActive =
                currentRoute == item.route ||
                (item.route == '/faculty/manage' &&
                    currentRoute == '/faculty/manage/detail');
            return GestureDetector(
              onTap: () => _navigate(context, item),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: 3),
                padding: EdgeInsets.symmetric(
                  horizontal: expanded ? 12 : 8,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: isActive
                      ? _C.primary.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: _C.primary.withValues(alpha: 0.15),
                            blurRadius: 8,
                          ),
                        ]
                      : [],
                ),
                child: Row(
                  children: [
                    Icon(
                      item.icon,
                      size: 20,
                      color: isActive ? _C.primary : _C.muted,
                    ),
                    if (expanded) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item.label,
                          style: TextStyle(
                            color: isActive ? _C.primary : _C.muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),

      Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: _C.border)),
        ),
        child: GestureDetector(
          onTap: () => _logout(context),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: expanded ? 12 : 8,
              vertical: 11,
            ),
            child: Row(
              children: [
                const Icon(Icons.logout_rounded, size: 20, color: _C.muted),
                if (expanded) ...[
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Logout',
                      style: TextStyle(
                        color: _C.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

class _BottomNav extends StatelessWidget {
  final String currentRoute;
  const _BottomNav({required this.currentRoute});

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: _C.card,
      border: Border(top: BorderSide(color: _C.border)),
    ),
    child: SafeArea(
      top: false,
      child: SizedBox(
        height: 58,
        child: Row(
          children: _bottomNavItems.map((item) {
            final isActive =
                currentRoute == item.route ||
                (item.route == '/faculty/manage' &&
                    currentRoute == '/faculty/manage/detail');
            final color = isActive ? _C.primary : _C.muted;
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  if (currentRoute == item.route) return;
                  if (item.isPeer) {
                    Navigator.pushReplacementNamed(context, item.route);
                  } else {
                    Navigator.pushNamed(context, item.route);
                  }
                },
                behavior: HitTestBehavior.opaque,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(item.icon, size: 21, color: color),
                    const SizedBox(height: 3),
                    Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        color: color,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  final String pageTitle, userName;
  final bool isMobile, sidebarExpanded;
  final VoidCallback onMenuTap;

  const _Header({
    required this.pageTitle,
    required this.userName,
    required this.isMobile,
    required this.sidebarExpanded,
    required this.onMenuTap,
  });

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(14, topPad + 8, 14, 10),
      decoration: BoxDecoration(
        color: _C.card.withValues(alpha: 0.7),
        border: const Border(bottom: BorderSide(color: _C.border)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onMenuTap,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _C.secondary,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _C.border),
              ),
              child: Icon(
                isMobile
                    ? Icons.menu_rounded
                    : (sidebarExpanded
                          ? Icons.chevron_left_rounded
                          : Icons.chevron_right_rounded),
                color: _C.muted,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              pageTitle,
              style: const TextStyle(
                color: _C.text,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _C.neonCyan.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _C.neonCyan.withValues(alpha: 0.3)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PulsingDot(),
                SizedBox(width: 5),
                Text(
                  'Connected ✔',
                  style: TextStyle(
                    color: _C.neonCyan,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [_C.primary, _C.neonBlue]),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                userName.isNotEmpty ? userName[0].toUpperCase() : 'F',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PUBLIC LAYOUT WIDGET
// ─────────────────────────────────────────────────────────────────────────────
class FacultyDashboardLayout extends StatefulWidget {
  final String currentRoute;
  final String userName;
  final Widget child;

  const FacultyDashboardLayout({
    super.key,
    required this.currentRoute,
    required this.userName,
    required this.child,
  });

  @override
  State<FacultyDashboardLayout> createState() => _FacultyDashboardLayoutState();
}

class _FacultyDashboardLayoutState extends State<FacultyDashboardLayout> {
  bool _sidebarExpanded = true;
  bool _mobileDrawerOpen = false;

  String get _pageTitle {
    switch (widget.currentRoute) {
      case '/faculty':
        return 'Dashboard';
      case '/faculty/create':
        return 'Create Activity';
      case '/faculty/volunteering/create':
        return 'Create Volunteering';
      case '/faculty/manage':
        return 'Manage';
      case '/faculty/manage/detail':
        return 'Item Detail';
      case '/faculty/verify':
        return 'Verification Panel';
      case '/faculty/analytics':
        return 'Analytics & Reports';
      case '/faculty/profile':
        return 'Faculty Profile';
      default:
        return 'Faculty Portal';
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final isMobile = screenW < 768;

    return Scaffold(
      backgroundColor: _C.bg,
      bottomNavigationBar: isMobile
          ? _BottomNav(currentRoute: widget.currentRoute)
          : null,
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _GridPainter())),

          Row(
            children: [
              if (!isMobile)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  width: _sidebarExpanded ? 220 : 60,
                  decoration: BoxDecoration(
                    color: _C.card.withValues(alpha: 0.8),
                    border: const Border(right: BorderSide(color: _C.border)),
                  ),
                  child: _SidebarContent(
                    currentRoute: widget.currentRoute,
                    expanded: _sidebarExpanded,
                    userName: widget.userName,
                  ),
                ),

              Expanded(
                child: Column(
                  children: [
                    _Header(
                      pageTitle: _pageTitle,
                      userName: widget.userName,
                      isMobile: isMobile,
                      sidebarExpanded: _sidebarExpanded,
                      onMenuTap: isMobile
                          ? () => setState(() => _mobileDrawerOpen = true)
                          : () => setState(
                              () => _sidebarExpanded = !_sidebarExpanded,
                            ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          16,
                          16,
                          isMobile ? 80 : 24,
                        ),
                        child: widget.child,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (_mobileDrawerOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _mobileDrawerOpen = false),
                child: Container(color: Colors.black.withValues(alpha: 0.5)),
              ),
            ),

          if (_mobileDrawerOpen)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 220,
              child: Container(
                decoration: BoxDecoration(
                  color: _C.card.withValues(alpha: 0.97),
                  border: const Border(right: BorderSide(color: _C.border)),
                ),
                child: _SidebarContent(
                  currentRoute: widget.currentRoute,
                  expanded: true,
                  userName: widget.userName,
                  onItemTap: () => setState(() => _mobileDrawerOpen = false),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
