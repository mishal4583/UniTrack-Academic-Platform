// ═══════════════════════════════════════════════════════════════════════════════
// student_dashboard_layout.dart
//
// Reusable layout for ALL student pages.
// Usage:
//   return StudentDashboardLayout(
//     currentRoute: '/student/certificates',
//     userName: _userName,
//     child: Column(mainAxisSize: MainAxisSize.min, children: [...]),
//   );
//
// Rules:
//   • child MUST NOT contain a Scaffold
//   • child MUST NOT contain Expanded / Flexible at the root level
//   • child MUST use Column(mainAxisSize: MainAxisSize.min)
//   • The layout owns the Scaffold + SingleChildScrollView
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DESIGN TOKENS  (unchanged)
// ─────────────────────────────────────────────────────────────────────────────
class _C {
  static const bg = Color(0xFF080D19);
  static const card = Color(0xFF111827);
  static const primary = Color(0xFF8B5CF6);
  static const neonBlue = Color(0xFF3B82F6);
  static const neonCyan = Color(0xFF06B6D4);
  static const neonGreen = Color(0xFF10B981);
  static const text = Color(0xFFEFF3F8);
  static const muted = Color(0xFF7E8A9A);
  static const border = Color(0xFF1F2937);
  static const secondary = Color(0xFF1A2235);
}

// ─────────────────────────────────────────────────────────────────────────────
// NAV ITEM DATA  (unchanged)
// ─────────────────────────────────────────────────────────────────────────────
class _NavItem {
  final String label;
  final IconData icon;
  final String route;
  const _NavItem({
    required this.label,
    required this.icon,
    required this.route,
  });
}

const _sidebarItems = [
  _NavItem(
    label: 'Dashboard',
    icon: Icons.dashboard_rounded,
    route: '/student',
  ),
  _NavItem(
    label: 'Volunteering',
    icon: Icons.eco_rounded,
    route: '/student/volunteering',
  ),
  _NavItem(
    label: 'Activities',
    icon: Icons.menu_book_rounded,
    route: '/student/activities',
  ),
  _NavItem(
    label: 'My Progress',
    icon: Icons.timeline_rounded,
    route: '/student/my-progress',
  ),
  _NavItem(
    label: 'Certificates',
    icon: Icons.workspace_premium_rounded,
    route: '/student/certificates',
  ),
  _NavItem(
    label: 'Profile',
    icon: Icons.person_rounded,
    route: '/student/profile',
  ),
  _NavItem(
    label: 'For You',
    icon: Icons.auto_awesome_rounded,
    route: '/student/recommendations',
  ),
];

const _bottomNavItems = [
  _NavItem(label: 'Home', icon: Icons.dashboard_rounded, route: '/student'),
  _NavItem(
    label: 'Volunteer',
    icon: Icons.eco_rounded,
    route: '/student/volunteering',
  ),
  _NavItem(
    label: 'Activities',
    icon: Icons.menu_book_rounded,
    route: '/student/activities',
  ),
  _NavItem(
    label: 'Progress',
    icon: Icons.timeline_rounded,
    route: '/student/my-progress',
  ),
  _NavItem(
    label: 'Profile',
    icon: Icons.person_rounded,
    route: '/student/profile',
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// GRID BACKGROUND  (unchanged)
// ─────────────────────────────────────────────────────────────────────────────
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

// ─────────────────────────────────────────────────────────────────────────────
// PULSING DOT  (unchanged)
// ─────────────────────────────────────────────────────────────────────────────
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

// ─────────────────────────────────────────────────────────────────────────────
// SIDEBAR CONTENT
//
// FIX A — _navigate: close drawer AFTER scheduling navigation via addPostFrameCallback.
//         This prevents setState-during-dispose when the route change tears down
//         the parent widget while drawer-close setState is still pending.
//
// FIX B — _logout: do NOT call onItemTap before signOut.
//         Capture navigator + mounted check BEFORE the async gap.
//         After signOut, use the captured navigator reference so we never
//         touch a potentially-disposed BuildContext.
// ─────────────────────────────────────────────────────────────────────────────
class _SidebarContent extends StatelessWidget {
  final String currentRoute;
  final bool expanded;
  final String userName;
  // FIX A: callback now receives the destination route so the parent can
  // close the drawer AND navigate in the correct order.
  final void Function(String route)? onNavigate;
  // FIX B: separate logout callback — parent handles drawer close + signout
  final VoidCallback? onLogout;

  const _SidebarContent({
    required this.currentRoute,
    required this.expanded,
    required this.userName,
    this.onNavigate,
    this.onLogout,
  });

  @override
  Widget build(BuildContext context) => Column(
    children: [
      // ── Logo / brand ──────────────────────────────────────────────────────
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
                      'Student Portal',
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

      // ── Nav items ─────────────────────────────────────────────────────────
      Expanded(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          children: _sidebarItems.map((item) {
            final isActive = currentRoute == item.route;
            return GestureDetector(
              // FIX A: delegate navigation to parent via onNavigate callback
              onTap: () {
                if (currentRoute == item.route) return;
                onNavigate?.call(item.route);
              },
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
                      if (isActive)
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: _C.primary,
                            shape: BoxShape.circle,
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

      // ── User + Logout ──────────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: _C.border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (expanded && userName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [_C.primary, _C.neonBlue],
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          userName[0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        userName,
                        style: const TextStyle(
                          color: _C.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            // FIX B: logout calls parent callback — parent owns signOut logic
            GestureDetector(
              onTap: onLogout,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: expanded ? 12 : 8,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.logout_rounded, size: 20, color: _C.muted),
                    if (expanded) ...[
                      const SizedBox(width: 10),
                      const Text(
                        'Logout',
                        style: TextStyle(
                          color: _C.muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// TOP HEADER  (unchanged visually)
// ─────────────────────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final String pageTitle;
  final String userName;
  final bool isMobile;
  final bool sidebarExpanded;
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
          const SizedBox(width: 8),
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [_C.primary, _C.neonBlue]),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                userName.isNotEmpty ? userName[0].toUpperCase() : 'S',
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
// BOTTOM NAV  (unchanged)
// ─────────────────────────────────────────────────────────────────────────────
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
            final isActive = currentRoute == item.route;
            final color = isActive ? _C.primary : _C.muted;
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  if (currentRoute == item.route) return;
                  Navigator.pushReplacementNamed(context, item.route);
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

// ─────────────────────────────────────────────────────────────────────────────
// PUBLIC LAYOUT WIDGET
//
// All mobile navigation fixes live here. The layout is the single owner of:
//   • drawer open/close state
//   • navigation execution
//   • logout execution
//
// FIX A — _handleNavigate: close drawer first, then navigate on the next frame.
//         Prevents "setState called after dispose" when pushReplacementNamed
//         tears down this widget while the drawer-close setState is still queued.
//
// FIX B — _handleLogout: never call setState after an async gap without a
//         mounted check on THIS widget. signOut is awaited, then we use
//         Navigator.of(context, rootNavigator: true) to escape any nested
//         navigator context and reach the MaterialApp-level router.
//
// FIX C — drawer overlay: wrap setState in a mounted guard via a local
//         captured reference so tap-to-close never fires on a dead state.
// ─────────────────────────────────────────────────────────────────────────────
class StudentDashboardLayout extends StatefulWidget {
  final String currentRoute;
  final String userName;
  final Widget child;

  const StudentDashboardLayout({
    super.key,
    required this.currentRoute,
    required this.userName,
    required this.child,
  });

  @override
  State<StudentDashboardLayout> createState() => _StudentDashboardLayoutState();
}

class _StudentDashboardLayoutState extends State<StudentDashboardLayout> {
  bool _sidebarExpanded = true;
  bool _mobileDrawerOpen = false;
  // FIX B: track logout in-progress to prevent double-tap / re-entrant calls
  bool _loggingOut = false;

  String get _pageTitle {
    switch (widget.currentRoute) {
      case '/student':
        return 'Dashboard';
      case '/student/volunteering':
        return 'Volunteering';
      case '/student/activities':
        return 'Activities';
      case '/student/my-progress':
        return 'My Progress';
      case '/student/certificates':
        return 'Certificate Wallet';
      case '/student/profile':
        return 'Profile';
      default:
        return 'Student Portal';
    }
  }

  // FIX A: close drawer first, navigate on next frame
  void _handleNavigate(String route) {
    if (!mounted) return;
    if (_mobileDrawerOpen) {
      setState(() => _mobileDrawerOpen = false);
      // Navigate after the drawer-close rebuild completes
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, route);
      });
    } else {
      Navigator.pushReplacementNamed(context, route);
    }
  }

  // FIX B: close drawer first, then sign out, then navigate using root navigator
  Future<void> _handleLogout() async {
    if (_loggingOut || !mounted) return;
    _loggingOut = true;

    // Close drawer synchronously before any async work
    if (_mobileDrawerOpen && mounted) {
      setState(() => _mobileDrawerOpen = false);
    }

    // Capture navigator before the async gap
    final nav = Navigator.of(context, rootNavigator: true);

    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint('Logout error: $e');
      if (mounted) _loggingOut = false;
      return;
    }

    // Use the captured navigator — never touch context after async gap without check
    nav.pushNamedAndRemoveUntil('/', (route) => false);
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
          // Grid background
          Positioned.fill(child: CustomPaint(painter: _GridPainter())),

          // Main layout
          Row(
            children: [
              // ── Desktop pinned sidebar ─────────────────────────────────────
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
                    onNavigate: _handleNavigate,
                    onLogout: _handleLogout,
                  ),
                ),

              // ── Content column ─────────────────────────────────────────────
              Expanded(
                child: Column(
                  children: [
                    _Header(
                      pageTitle: _pageTitle,
                      userName: widget.userName,
                      isMobile: isMobile,
                      sidebarExpanded: _sidebarExpanded,
                      onMenuTap: isMobile
                          ? () {
                              if (mounted)
                                setState(() => _mobileDrawerOpen = true);
                            }
                          : () {
                              if (mounted)
                                setState(
                                  () => _sidebarExpanded = !_sidebarExpanded,
                                );
                            },
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

          // ── Mobile drawer overlay ──────────────────────────────────────────
          // FIX C: use local 'this' capture — setState only if still mounted
          if (_mobileDrawerOpen) ...[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (mounted) setState(() => _mobileDrawerOpen = false);
                },
                child: Container(color: Colors.black.withValues(alpha: 0.5)),
              ),
            ),
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
                  onNavigate: _handleNavigate,
                  onLogout: _handleLogout,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
