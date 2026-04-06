import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────
// THEME CONSTANTS
// ─────────────────────────────────────────────
const _bgColor = Color(0xFF0A0A0F);
const _sidebarColor = Color(0xFF0F0F1A);
const _cardColor = Color(0xFF12121F);
const _borderColor = Color(0xFF1E1E35);
const _neonCyan = Color(0xFF00F5FF);
const _neonPurple = Color(0xFF8B5CF6);
const _neonBlue = Color(0xFF3B82F6);
const _mutedText = Color(0xFF6B7280);
const _foreground = Color(0xFFF1F5F9);
const _primary = Color(0xFF8B5CF6);

// ─────────────────────────────────────────────
// NAV ITEM DATA
// ─────────────────────────────────────────────
class _NavItemData {
  final IconData icon;
  final String label;
  final String route;
  const _NavItemData({
    required this.icon,
    required this.label,
    required this.route,
  });
}

const _navItems = [
  _NavItemData(
    icon: Icons.dashboard_rounded,
    label: 'Dashboard',
    route: '/admin',
  ),
  _NavItemData(
    icon: Icons.people_rounded,
    label: 'Users',
    route: '/admin/users',
  ),
  _NavItemData(
    icon: Icons.menu_book_rounded,
    label: 'Activities',
    route: '/admin/activities',
  ),
  _NavItemData(
    icon: Icons.shield_rounded,
    label: 'Blockchain',
    route: '/admin/blockchain',
  ),
  _NavItemData(
    icon: Icons.settings_rounded,
    label: 'Settings',
    route: '/admin/settings',
  ),
];

// ─────────────────────────────────────────────
// ADMIN DASHBOARD LAYOUT
// ─────────────────────────────────────────────
class AdminDashboardLayout extends StatefulWidget {
  /// The screen content to render in the main area.
  final Widget child;

  /// Optional page title shown in the top bar.
  final String pageTitle;

  const AdminDashboardLayout({
    super.key,
    required this.child,
    this.pageTitle = 'Admin Dashboard',
  });

  @override
  State<AdminDashboardLayout> createState() => _AdminDashboardLayoutState();
}

class _AdminDashboardLayoutState extends State<AdminDashboardLayout> {
  bool _sidebarOpen = true;

  void _toggleSidebar() => setState(() => _sidebarOpen = !_sidebarOpen);

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 768;

    return Scaffold(
      backgroundColor: _bgColor,
      // Drawer for mobile — no nested Scaffold
      drawer: isWide
          ? null
          : Drawer(backgroundColor: _sidebarColor, child: _Sidebar(open: true)),
      body: Row(
        children: [
          // ── Desktop sidebar
          if (isWide) _Sidebar(open: _sidebarOpen),

          // ── Main content column
          Expanded(
            child: Column(
              children: [
                _TopBar(
                  pageTitle: widget.pageTitle,
                  sidebarOpen: _sidebarOpen,
                  onToggleSidebar: isWide ? _toggleSidebar : null,
                ),
                Expanded(child: widget.child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// SIDEBAR
// ─────────────────────────────────────────────
class _Sidebar extends StatelessWidget {
  final bool open;
  const _Sidebar({required this.open});

  @override
  Widget build(BuildContext context) {
    final currentRoute = ModalRoute.of(context)?.settings.name;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOut,
      width: open ? 240 : 64,
      decoration: const BoxDecoration(
        color: _sidebarColor,
        border: Border(right: BorderSide(color: _borderColor)),
      ),
      child: Column(
        children: [
          // ── Logo / brand
          _SidebarHeader(open: open),

          // ── Nav items
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              child: Column(
                children: _navItems.map((item) {
                  final isActive = currentRoute == item.route;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: _SidebarNavItem(
                      item: item,
                      isActive: isActive,
                      open: open,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // ── Logout
          _SidebarLogout(open: open),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// SIDEBAR HEADER
// ─────────────────────────────────────────────
class _SidebarHeader extends StatelessWidget {
  final bool open;
  const _SidebarHeader({required this.open});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Row(
        children: [
          // Logo icon
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: const LinearGradient(
                colors: [_neonPurple, _neonBlue],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset('assets/logo/logo.png', fit: BoxFit.cover),
            ),
          ),

          // Brand text — only when open
          if (open) ...[
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'UniTrack',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _foreground,
                    letterSpacing: 0.3,
                  ),
                ),
                Text(
                  'Admin Portal',
                  style: TextStyle(fontSize: 11, color: _mutedText),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// SIDEBAR NAV ITEM
// ─────────────────────────────────────────────
class _SidebarNavItem extends StatefulWidget {
  final _NavItemData item;
  final bool isActive;
  final bool open;

  const _SidebarNavItem({
    required this.item,
    required this.isActive,
    required this.open,
  });

  @override
  State<_SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<_SidebarNavItem> {
  bool _hovered = false;

  void _navigate(BuildContext context) {
    // Close drawer if on mobile
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    Navigator.of(context).pushReplacementNamed(widget.item.route);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.isActive;
    final open = widget.open;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => _navigate(context),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: active
                ? _primary.withValues(alpha: 0.15)
                : _hovered
                ? _primary.withValues(alpha: 0.07)
                : Colors.transparent,
            boxShadow: active
                ? [
                    BoxShadow(
                      color: _primary.withValues(alpha: 0.2),
                      blurRadius: 12,
                      spreadRadius: 0,
                    ),
                  ]
                : [],
            border: active
                ? Border.all(color: _primary.withValues(alpha: 0.25))
                : Border.all(color: Colors.transparent),
          ),
          child: Row(
            children: [
              // Left neon indicator bar
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 3,
                height: 18,
                margin: const EdgeInsets.only(right: 9),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: active ? _primary : Colors.transparent,
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: _primary.withValues(alpha: 0.7),
                            blurRadius: 8,
                          ),
                        ]
                      : [],
                ),
              ),

              // Icon
              Icon(
                widget.item.icon,
                size: 19,
                color: active
                    ? _primary
                    : _hovered
                    ? _foreground.withValues(alpha: 0.7)
                    : _mutedText,
              ),

              // Label — only when sidebar is open
              if (open) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.item.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      color: active
                          ? _primary
                          : _hovered
                          ? _foreground.withValues(alpha: 0.85)
                          : _mutedText,
                    ),
                  ),
                ),

                // Active dot indicator
                if (active)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _neonCyan,
                      boxShadow: [
                        BoxShadow(
                          color: _neonCyan.withValues(alpha: 0.8),
                          blurRadius: 6,
                        ),
                      ],
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

// ─────────────────────────────────────────────
// SIDEBAR LOGOUT
// ─────────────────────────────────────────────
class _SidebarLogout extends StatefulWidget {
  final bool open;
  const _SidebarLogout({required this.open});

  @override
  State<_SidebarLogout> createState() => _SidebarLogoutState();
}

class _SidebarLogoutState extends State<_SidebarLogout> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _borderColor)),
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: () async {
            await FirebaseAuth.instance.signOut();
            if (context.mounted) {
              Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: _hovered
                  ? Colors.red.withValues(alpha: 0.08)
                  : Colors.transparent,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.logout_rounded,
                  size: 19,
                  color: _hovered ? Colors.redAccent : _mutedText,
                ),
                if (widget.open) ...[
                  const SizedBox(width: 12),
                  Text(
                    'Logout',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _hovered ? Colors.redAccent : _mutedText,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// TOP BAR
// ─────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final String pageTitle;
  final bool sidebarOpen;
  final VoidCallback? onToggleSidebar;

  const _TopBar({
    required this.pageTitle,
    required this.sidebarOpen,
    this.onToggleSidebar,
  });

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 768;
    final isSmall = MediaQuery.of(context).size.width < 480;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: _cardColor.withValues(alpha: 0.55),
            border: const Border(bottom: BorderSide(color: _borderColor)),
          ),
          child: Row(
            children: [
              // ── Toggle button
              if (!isWide)
                Builder(
                  builder: (ctx) => _TopBarIconBtn(
                    icon: Icons.menu_rounded,
                    onTap: () => Scaffold.of(ctx).openDrawer(),
                  ),
                )
              else
                _TopBarIconBtn(
                  icon: sidebarOpen
                      ? Icons.chevron_left_rounded
                      : Icons.chevron_right_rounded,
                  onTap: onToggleSidebar,
                ),

              const SizedBox(width: 8),

              // ── Page title
              Text(
                pageTitle,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _mutedText,
                ),
              ),

              const Spacer(),

              // ── Network badge (desktop only)
              if (!isSmall) ...[_NetworkBadge(), const SizedBox(width: 8)],

              // ── Wallet chip
              _WalletChip(showLabel: !isSmall),
              const SizedBox(width: 8),

              // ── Avatar
              _AvatarBadge(initial: 'A'),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// TOP BAR — ICON BUTTON
// ─────────────────────────────────────────────
class _TopBarIconBtn extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _TopBarIconBtn({required this.icon, this.onTap});

  @override
  State<_TopBarIconBtn> createState() => _TopBarIconBtnState();
}

class _TopBarIconBtnState extends State<_TopBarIconBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: _hovered ? _borderColor : Colors.transparent,
        ),
        child: Icon(widget.icon, size: 18, color: _mutedText),
      ),
    ),
  );
}

// ─────────────────────────────────────────────
// NETWORK BADGE
// ─────────────────────────────────────────────
class _NetworkBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _neonCyan.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _neonCyan.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulsingDot(),
          const SizedBox(width: 6),
          const Text(
            'Network: Connected ✔',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: _neonCyan,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// WALLET CHIP
// ─────────────────────────────────────────────
class _WalletChip extends StatelessWidget {
  final bool showLabel;
  const _WalletChip({required this.showLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.account_balance_wallet_rounded,
            size: 15,
            color: _neonCyan,
          ),
          if (showLabel) ...[
            const SizedBox(width: 6),
            const Text(
              '0x7f...3a2b',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: _foreground,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// AVATAR BADGE
// ─────────────────────────────────────────────
class _AvatarBadge extends StatelessWidget {
  final String initial;
  const _AvatarBadge({required this.initial});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [_neonPurple, _neonBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: _neonPurple.withValues(alpha: 0.35),
            blurRadius: 8,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Center(
        child: Text(
          initial.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// PULSING DOT
// ─────────────────────────────────────────────
class _PulsingDot extends StatefulWidget {
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
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(
      begin: 0.25,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _neonCyan.withValues(alpha: _anim.value),
        boxShadow: [
          BoxShadow(
            color: _neonCyan.withValues(alpha: _anim.value * 0.7),
            blurRadius: 5,
            spreadRadius: 0,
          ),
        ],
      ),
    ),
  );
}
