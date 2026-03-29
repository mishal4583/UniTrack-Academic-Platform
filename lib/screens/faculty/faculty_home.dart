// ═══════════════════════════════════════════════════════════════════════════════
// faculty_home.dart  —  Route: /faculty
// Real Firestore data, no mock, zero overflow, same architecture as student side.
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DESIGN TOKENS
// ─────────────────────────────────────────────────────────────────────────────
class _C {
  static const bg = Color(0xFF080D19);
  static const card = Color(0xFF111827);
  static const primary = Color(0xFF8B5CF6);
  static const neonBlue = Color(0xFF3B82F6);
  static const neonCyan = Color(0xFF06B6D4);
  static const neonGreen = Color(0xFF10B981);
  static const amber = Color(0xFFF59E0B);
  static const text = Color(0xFFEFF3F8);
  static const muted = Color(0xFF7E8A9A);
  static const border = Color(0xFF1F2937);
  static const secondary = Color(0xFF1A2235);
  static const yellow = Color(0xFFFBBF24);
}

// ─────────────────────────────────────────────────────────────────────────────
// DASHBOARD DATA MODEL
// ─────────────────────────────────────────────────────────────────────────────
class _FacultyData {
  final int activitiesCount;
  final int volunteeringCount;
  final int uniqueStudents;
  final int pendingVerifications;
  final List<_ActivityRow> recentActivities;
  final List<_PendingRow> pendingItems;
  final List<_VolRow> volunteeringRequests;

  const _FacultyData({
    required this.activitiesCount,
    required this.volunteeringCount,
    required this.uniqueStudents,
    required this.pendingVerifications,
    required this.recentActivities,
    required this.pendingItems,
    required this.volunteeringRequests,
  });
}

class _ActivityRow {
  final String id;
  final String title;
  final int enrolled;
  final int credits;
  final String date;
  final String status;
  const _ActivityRow({
    required this.id,
    required this.title,
    required this.enrolled,
    required this.credits,
    required this.date,
    required this.status,
  });
}

class _PendingRow {
  final String enrollmentId;
  final String userId;
  final String activityTitle;
  final String type; // "activity" | "volunteering"
  const _PendingRow({
    required this.enrollmentId,
    required this.userId,
    required this.activityTitle,
    required this.type,
  });
}

class _VolRow {
  final String id;
  final String title;
  final int applicants;
  final String status;
  const _VolRow({
    required this.id,
    required this.title,
    required this.applicants,
    required this.status,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// FIRESTORE SERVICE
// ─────────────────────────────────────────────────────────────────────────────
class _FacultyService {
  static final _db = FirebaseFirestore.instance;

  static Map<String, dynamic> _safe(DocumentSnapshot doc) =>
      (doc.data() as Map<String, dynamic>?) ?? {};

  static Future<_FacultyData> load(String uid, String facultyName) async {
    // ── Parallel top-level fetches ───────────────────────────────────────────
    final results = await Future.wait([
      // [0] activities where faculty field matches
      _db.collection('activities').where('createdBy', isEqualTo: uid).get(),
      // [1] volunteering where createdBy == uid
      _db.collection('volunteering').where('createdBy', isEqualTo: uid).get(),
      // [2] all enrollments (to find unique students + pending)
      _db.collection('enrollments').get(),
      // [3] all applications (to find unique students + pending)
      _db.collection('applications').get(),
    ]);

    final actSnap = results[0] as QuerySnapshot;
    final volSnap = results[1] as QuerySnapshot;
    final enrSnap = results[2] as QuerySnapshot;
    final appSnap = results[3] as QuerySnapshot;

    // ── Unique students ──────────────────────────────────────────────────────
    final actIds = actSnap.docs.map((d) => d.id).toSet();
    final volIds = volSnap.docs.map((d) => d.id).toSet();

    final studentSet = <String>{};
    for (final doc in enrSnap.docs) {
      final d = _safe(doc);
      if (actIds.contains((d['activityId'] as String?) ?? '')) {
        final uid2 = (d['userId'] as String?) ?? '';
        if (uid2.isNotEmpty) studentSet.add(uid2);
      }
    }
    for (final doc in appSnap.docs) {
      final d = _safe(doc);
      if (volIds.contains((d['volunteeringId'] as String?) ?? '')) {
        final uid2 = (d['userId'] as String?) ?? '';
        if (uid2.isNotEmpty) studentSet.add(uid2);
      }
    }

    // ── Pending verifications ────────────────────────────────────────────────
    final pendingItems = <_PendingRow>[];

    for (final doc in enrSnap.docs) {
      final d = _safe(doc);
      if ((d['status'] as String?) == 'Enrolled' &&
          actIds.contains((d['activityId'] as String?) ?? '')) {
        final actId = (d['activityId'] as String?) ?? '';
        final actDocList = actSnap.docs.where((a) => a.id == actId).toList();
        final actDoc = actDocList.isNotEmpty ? actDocList.first : null;
        pendingItems.add(
          _PendingRow(
            enrollmentId: doc.id,
            userId: (d['userId'] as String?) ?? '',
            activityTitle: actDoc != null
                ? (_safe(actDoc)['title'] as String?) ?? ''
                : actId,
            type: 'activity',
          ),
        );
      }
    }

    for (final doc in appSnap.docs) {
      final d = _safe(doc);
      if ((d['status'] as String?) == 'Applied' &&
          volIds.contains((d['volunteeringId'] as String?) ?? '')) {
        final volId = (d['volunteeringId'] as String?) ?? '';
        final volDoc = volSnap.docs.where((v) => v.id == volId).firstOrNull;
        pendingItems.add(
          _PendingRow(
            enrollmentId: doc.id,
            userId: (d['userId'] as String?) ?? '',
            activityTitle: volDoc != null
                ? (_safe(volDoc)['title'] as String?) ?? ''
                : volId,
            type: 'volunteering',
          ),
        );
      }
    }

    // ── Recent activities (up to 5, newest first) ────────────────────────────
    final sorted = [...actSnap.docs];
    sorted.sort((a, b) {
      final ta = _safe(a)['createdAt'];
      final tb = _safe(b)['createdAt'];
      if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
      return 0;
    });

    final recentActivities = sorted.take(5).map((doc) {
      final d = _safe(doc);
      return _ActivityRow(
        id: doc.id,
        title: (d['title'] as String?) ?? '',
        enrolled: (d['enrolled'] as int?) ?? 0,
        credits: (d['credits'] as int?) ?? 0,
        date: (d['date'] as String?) ?? '',
        status: (d['status'] as String?) ?? 'open',
      );
    }).toList();

    // ── Volunteering requests (up to 4) ──────────────────────────────────────
    final volRows = volSnap.docs.take(4).map((doc) {
      final d = _safe(doc);
      return _VolRow(
        id: doc.id,
        title: (d['title'] as String?) ?? '',
        applicants: (d['currentParticipants'] as int?) ?? 0,
        status: (d['status'] as String?) ?? 'open',
      );
    }).toList();

    return _FacultyData(
      activitiesCount: actSnap.docs.length,
      volunteeringCount: volSnap.docs.length,
      uniqueStudents: studentSet.length,
      pendingVerifications: pendingItems.length,
      recentActivities: recentActivities,
      pendingItems: pendingItems.take(5).toList(),
      volunteeringRequests: volRows,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VERIFY SERVICE
// ─────────────────────────────────────────────────────────────────────────────
class _VerifyService {
  static final _db = FirebaseFirestore.instance;

  static Future<void> approve(_PendingRow row) async {
    final col = row.type == 'activity' ? 'enrollments' : 'applications';
    await _db.collection(col).doc(row.enrollmentId).update({
      'status': row.type == 'activity' ? 'Completed' : 'Approved',
    });
  }

  static Future<void> reject(_PendingRow row) async {
    final col = row.type == 'activity' ? 'enrollments' : 'applications';
    await _db.collection(col).doc(row.enrollmentId).update({
      'status': 'Rejected',
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GRID PAINTER
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
// SHARED WIDGETS
// ─────────────────────────────────────────────────────────────────────────────
class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final Color? glowColor;

  const _Card({required this.child, this.padding, this.glowColor});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: padding ?? const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _C.card.withValues(alpha: 0.75),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _C.border),
      boxShadow: glowColor != null
          ? [
              BoxShadow(
                color: glowColor!.withValues(alpha: 0.2),
                blurRadius: 18,
                spreadRadius: 1,
              ),
            ]
          : [],
    ),
    child: child,
  );
}

class _BlockchainBadge extends StatelessWidget {
  final String status;
  const _BlockchainBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;
    final String label;
    switch (status.toLowerCase()) {
      case 'verified':
      case 'open':
        color = _C.neonCyan;
        icon = Icons.check_circle_rounded;
        label = 'Verified';
        break;
      case 'pending':
      case 'full':
        color = _C.yellow;
        icon = Icons.access_time_rounded;
        label = 'Pending';
        break;
      default:
        color = _C.muted;
        icon = Icons.shield_outlined;
        label = status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  const _GradientButton({required this.label, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_C.primary, _C.neonBlue]),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: Colors.white),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    ),
  );
}

class _SmallButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _SmallButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// STAT CARD
// ─────────────────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  final String? trend;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
    this.trend,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _C.card.withValues(alpha: 0.75),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _C.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                label.toUpperCase(),
                style: const TextStyle(
                  color: _C.muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 15),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: const TextStyle(
              color: _C.text,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (trend != null) ...[
          const SizedBox(height: 4),
          Text(
            trend!,
            style: const TextStyle(
              color: _C.neonCyan,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// PULSING DOT
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
// TOP BAR
// ─────────────────────────────────────────────────────────────────────────────
class _FacultyTopBar extends StatelessWidget {
  final String userName;
  const _FacultyTopBar({required this.userName});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, topPad + 8, 16, 10),
      decoration: BoxDecoration(
        color: _C.card.withValues(alpha: 0.7),
        border: const Border(bottom: BorderSide(color: _C.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_C.primary, _C.neonBlue]),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.shield_rounded,
              color: Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 8),
          const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'UniTrack',
                style: TextStyle(
                  color: _C.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              Text(
                'Faculty Portal',
                style: TextStyle(color: _C.muted, fontSize: 10),
              ),
            ],
          ),
          const Spacer(),
          // Network badge
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
                SizedBox(width: 6),
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
          // Avatar
          Container(
            width: 30,
            height: 30,
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
// BOTTOM NAV — Faculty
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

const _navItems = [
  _NavItem(label: 'Home', icon: Icons.dashboard_rounded, route: '/faculty'),
  _NavItem(
    label: 'Activities',
    icon: Icons.menu_book_rounded,
    route: '/faculty/create',
  ),
  _NavItem(
    label: 'Volunteer',
    icon: Icons.eco_rounded,
    route: '/faculty/volunteering/create',
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
];

class _FacultyBottomNav extends StatelessWidget {
  final String currentRoute;
  const _FacultyBottomNav({required this.currentRoute});

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: _C.card,
      border: Border(top: BorderSide(color: _C.border, width: 1)),
    ),
    child: SafeArea(
      top: false,
      child: SizedBox(
        height: 58,
        child: Row(
          children: _navItems.map((item) {
            final isActive = currentRoute == item.route;
            final color = isActive ? _C.primary : _C.muted;
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  if (currentRoute != item.route) {
                    Navigator.pushReplacementNamed(context, item.route);
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

// ─────────────────────────────────────────────────────────────────────────────
// SECTION: STAT GRID
// ─────────────────────────────────────────────────────────────────────────────
class _StatGrid extends StatelessWidget {
  final _FacultyData data;
  const _StatGrid({required this.data});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (ctx, c) {
      const gap = 10.0;
      final w = (c.maxWidth - gap) / 2;
      final stats = [
        (
          label: 'Activities',
          value: '${data.activitiesCount}',
          icon: Icons.menu_book_rounded,
          color: _C.primary,
          trend: 'total created',
        ),
        (
          label: 'Volunteering',
          value: '${data.volunteeringCount}',
          icon: Icons.eco_rounded,
          color: _C.neonGreen,
          trend: 'total created',
        ),
        (
          label: 'Students',
          value: '${data.uniqueStudents}',
          icon: Icons.people_rounded,
          color: _C.neonBlue,
          trend: 'participated',
        ),
        (
          label: 'Pending',
          value: '${data.pendingVerifications}',
          icon: Icons.pending_actions_rounded,
          color: _C.amber,
          trend: 'need action',
        ),
      ];
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: stats
            .map(
              (s) => SizedBox(
                width: w,
                child: _StatCard(
                  label: s.label,
                  value: s.value,
                  icon: s.icon,
                  iconColor: s.color,
                  trend: s.trend,
                ),
              ),
            )
            .toList(),
      );
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION: QUICK ACTIONS
// ─────────────────────────────────────────────────────────────────────────────
class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            color: _C.text,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (ctx, c) {
            const gap = 10.0;
            final w = (c.maxWidth - gap * 2) / 3;
            final actions = [
              (
                label: 'Create Activity',
                icon: Icons.add_circle_rounded,
                route: '/faculty/create',
                color: _C.primary,
              ),
              (
                label: 'Create Volunteer',
                icon: Icons.eco_rounded,
                route: '/faculty/volunteering/create',
                color: _C.neonGreen,
              ),
              (
                label: 'Verify Students',
                icon: Icons.fact_check_rounded,
                route: '/faculty/verify',
                color: _C.neonCyan,
              ),
            ];
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: actions
                  .map(
                    (a) => SizedBox(
                      width: w,
                      child: GestureDetector(
                        onTap: () =>
                            Navigator.pushReplacementNamed(context, a.route),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: a.color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: a.color.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(a.icon, color: a.color, size: 22),
                              const SizedBox(height: 6),
                              Text(
                                a.label,
                                style: TextStyle(
                                  color: a.color,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 2,
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION: RECENT ACTIVITIES TABLE
// ─────────────────────────────────────────────────────────────────────────────
class _RecentActivities extends StatelessWidget {
  final List<_ActivityRow> items;
  const _RecentActivities({required this.items});

  @override
  Widget build(BuildContext context) => _Card(
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Your Activities',
                  style: TextStyle(
                    color: _C.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/faculty/create'),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_C.primary, _C.neonBlue],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, color: Colors.white, size: 13),
                      SizedBox(width: 4),
                      Text(
                        'New',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Table header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: _C.secondary.withValues(alpha: 0.5),
            border: const Border(
              top: BorderSide(color: _C.border),
              bottom: BorderSide(color: _C.border),
            ),
          ),
          child: const Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  'ACTIVITY',
                  style: TextStyle(
                    color: _C.muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
              ),
              Expanded(
                flex: 1,
                child: Text(
                  'STUDENTS',
                  style: TextStyle(
                    color: _C.muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                flex: 1,
                child: Text(
                  'CREDITS',
                  style: TextStyle(
                    color: _C.muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                flex: 1,
                child: Text(
                  'STATUS',
                  style: TextStyle(
                    color: _C.muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text(
                'No activities yet. Create your first activity!',
                style: TextStyle(color: _C.muted, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          ...items.map(
            (act) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: _C.border, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          act.title,
                          style: const TextStyle(
                            color: _C.text,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (act.date.isNotEmpty)
                          Text(
                            act.date,
                            style: const TextStyle(
                              color: _C.muted,
                              fontSize: 10,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text(
                      '${act.enrolled}',
                      style: const TextStyle(color: _C.muted, fontSize: 12),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text(
                      '${act.credits}',
                      style: const TextStyle(
                        color: _C.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Center(child: _BlockchainBadge(status: act.status)),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION: PENDING VERIFICATIONS
// ─────────────────────────────────────────────────────────────────────────────
class _PendingVerifications extends StatefulWidget {
  final List<_PendingRow> items;
  final VoidCallback onRefresh;
  const _PendingVerifications({required this.items, required this.onRefresh});

  @override
  State<_PendingVerifications> createState() => _PendingVerificationsState();
}

class _PendingVerificationsState extends State<_PendingVerifications> {
  final _processing = <String>{};

  Future<void> _approve(_PendingRow row) async {
    setState(() => _processing.add(row.enrollmentId));
    try {
      await _VerifyService.approve(row);
      if (mounted) widget.onRefresh();
    } finally {
      if (mounted) setState(() => _processing.remove(row.enrollmentId));
    }
  }

  Future<void> _reject(_PendingRow row) async {
    setState(() => _processing.add(row.enrollmentId));
    try {
      await _VerifyService.reject(row);
      if (mounted) widget.onRefresh();
    } finally {
      if (mounted) setState(() => _processing.remove(row.enrollmentId));
    }
  }

  String _initial(String userId) =>
      userId.isNotEmpty ? userId[0].toUpperCase() : 'S';

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text(
        'Pending Verifications',
        style: TextStyle(
          color: _C.text,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
      const SizedBox(height: 10),
      if (widget.items.isEmpty)
        _Card(
          padding: const EdgeInsets.all(24),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  color: _C.neonGreen,
                  size: 32,
                ),
                SizedBox(height: 8),
                Text(
                  'All caught up!',
                  style: TextStyle(
                    color: _C.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'No pending verifications',
                  style: TextStyle(color: _C.muted, fontSize: 11),
                ),
              ],
            ),
          ),
        )
      else
        ...widget.items.map(
          (row) => _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_C.primary, _C.neonBlue],
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          _initial(row.userId),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            row.userId,
                            style: const TextStyle(
                              color: _C.text,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  row.activityTitle,
                                  style: const TextStyle(
                                    color: _C.muted,
                                    fontSize: 11,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: row.type == 'activity'
                                      ? _C.primary.withValues(alpha: 0.1)
                                      : _C.neonGreen.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  row.type == 'activity' ? 'Activity' : 'Vol.',
                                  style: TextStyle(
                                    color: row.type == 'activity'
                                        ? _C.primary
                                        : _C.neonGreen,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _processing.contains(row.enrollmentId)
                    ? const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _C.primary,
                          ),
                        ),
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: _SmallButton(
                              label: '✔ Verify',
                              color: _C.neonCyan,
                              onTap: () => _approve(row),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _SmallButton(
                              label: '✕ Reject',
                              color: _C.amber,
                              onTap: () => _reject(row),
                            ),
                          ),
                        ],
                      ),
              ],
            ),
          ),
        ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION: VOLUNTEERING REQUESTS
// ─────────────────────────────────────────────────────────────────────────────
class _VolunteeringRequests extends StatelessWidget {
  final List<_VolRow> items;
  const _VolunteeringRequests({required this.items});

  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Row(
          children: [
            Icon(Icons.eco_rounded, color: _C.neonGreen, size: 16),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                'Volunteering Requests',
                style: TextStyle(
                  color: _C.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                'No volunteering created yet.',
                style: TextStyle(color: _C.muted, fontSize: 12),
              ),
            ),
          )
        else
          ...items.map(
            (row) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _C.secondary.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _C.border.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          row.title,
                          style: const TextStyle(
                            color: _C.text,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${row.applicants} applicant${row.applicants == 1 ? '' : 's'}',
                          style: const TextStyle(color: _C.muted, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: row.status == 'full'
                          ? _C.muted.withValues(alpha: 0.1)
                          : _C.neonGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      row.status == 'full' ? 'Full' : 'Active',
                      style: TextStyle(
                        color: row.status == 'full' ? _C.muted : _C.neonGreen,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION: SMART CONTRACT CARD
// ─────────────────────────────────────────────────────────────────────────────
class _SmartContractCard extends StatelessWidget {
  const _SmartContractCard();

  @override
  Widget build(BuildContext context) => _Card(
    glowColor: _C.neonCyan,
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: _C.neonCyan.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.bolt_rounded, color: _C.neonCyan, size: 22),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Smart Contract',
                style: TextStyle(
                  color: _C.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: 2),
              Text(
                'Trigger credit distribution for verified activities',
                style: TextStyle(color: _C.muted, fontSize: 11),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _GradientButton(label: 'Execute', onTap: () {}),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION: MINI ANALYTICS
// ─────────────────────────────────────────────────────────────────────────────
class _MiniAnalytics extends StatelessWidget {
  final _FacultyData data;
  const _MiniAnalytics({required this.data});

  @override
  Widget build(BuildContext context) {
    final total = data.activitiesCount + data.volunteeringCount;
    final actPct = total > 0
        ? (data.activitiesCount / total).clamp(0.0, 1.0)
        : 0.0;
    final volPct = total > 0
        ? (data.volunteeringCount / total).clamp(0.0, 1.0)
        : 0.0;
    final stuPct = total > 0
        ? (data.uniqueStudents / (total * 10)).clamp(0.0, 1.0)
        : 0.0;

    final bars = [
      (label: 'Activities', pct: actPct, color: _C.primary),
      (label: 'Volunteering', pct: volPct, color: _C.neonGreen),
      (label: 'Students', pct: stuPct, color: _C.neonCyan),
    ];

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(Icons.bar_chart_rounded, color: _C.primary, size: 16),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Quick Stats',
                  style: TextStyle(
                    color: _C.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...bars.map(
            (b) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        b.label,
                        style: const TextStyle(color: _C.muted, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${(b.pct * 100).round()}%',
                      style: const TextStyle(
                        color: _C.text,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                LayoutBuilder(
                  builder: (ctx, c) => ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      width: c.maxWidth,
                      height: 5,
                      child: Stack(
                        children: [
                          Container(color: _C.secondary),
                          FractionallySizedBox(
                            widthFactor: b.pct,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    b.color,
                                    b.color.withValues(alpha: 0.6),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN — FACULTY HOME
// ─────────────────────────────────────────────────────────────────────────────
class FacultyHome extends StatefulWidget {
  const FacultyHome({super.key});

  @override
  State<FacultyHome> createState() => _FacultyHomeState();
}

class _FacultyHomeState extends State<FacultyHome> {
  late Future<_FacultyData> _future;
  String _displayName = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Load user profile first for faculty name (needed for activity query)
    FirebaseFirestore.instance.collection('users').doc(user.uid).get().then((
      doc,
    ) {
      final d = doc.data() ?? {};
      final name = (d['name'] as String?) ?? '';

      if (!mounted) return;

      setState(() {
        _displayName = name;
        _future = _FacultyService.load(user.uid, name);
      });
    });

    // Start with uid as faculty identifier fallback
    _future = _FacultyService.load(user.uid, user.uid);
  }

  void _refresh() => setState(_init);

  @override
  Widget build(BuildContext context) {
    final botPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: _C.bg,
      extendBody: true,
      bottomNavigationBar: const _FacultyBottomNav(currentRoute: '/faculty'),
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          Column(
            children: [
              _FacultyTopBar(userName: _displayName),
              Expanded(
                child: FutureBuilder<_FacultyData>(
                  future: _future,
                  builder: (context, snap) {
                    // ── Loading ──────────────────────────────────────────
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: _C.primary),
                      );
                    }

                    // ── Error ────────────────────────────────────────────
                    if (snap.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                color: Colors.redAccent,
                                size: 40,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Failed to load dashboard',
                                style: TextStyle(
                                  color: _C.text,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                snap.error.toString(),
                                style: const TextStyle(
                                  color: _C.muted,
                                  fontSize: 12,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),
                              _GradientButton(
                                label: 'Retry',
                                icon: Icons.refresh_rounded,
                                onTap: _refresh,
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    // ── Data ─────────────────────────────────────────────
                    final data = snap.data!;

                    return SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, botPad + 72),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── HEADER ──────────────────────────────────────
                          Text(
                            'Welcome, ${_displayName.isNotEmpty ? _displayName : 'Faculty'} 👋',
                            style: const TextStyle(
                              color: _C.text,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Manage activities, verify participation & trigger smart contracts',
                            style: TextStyle(color: _C.muted, fontSize: 12),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),

                          const SizedBox(height: 20),

                          // ── STAT GRID ────────────────────────────────────
                          _StatGrid(data: data),

                          const SizedBox(height: 20),

                          // ── QUICK ACTIONS ────────────────────────────────
                          const _QuickActions(),

                          const SizedBox(height: 8),

                          // ── RECENT ACTIVITIES TABLE ──────────────────────
                          _RecentActivities(items: data.recentActivities),

                          // ── SMART CONTRACT ───────────────────────────────
                          const _SmartContractCard(),

                          // ── VOLUNTEERING REQUESTS ────────────────────────
                          _VolunteeringRequests(
                            items: data.volunteeringRequests,
                          ),

                          const SizedBox(height: 8),

                          // ── PENDING VERIFICATIONS + MINI ANALYTICS ───────
                          _PendingVerifications(
                            items: data.pendingItems,
                            onRefresh: _refresh,
                          ),

                          _MiniAnalytics(data: data),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
