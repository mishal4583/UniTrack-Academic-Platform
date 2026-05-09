// ═══════════════════════════════════════════════════════════════════════════════
// student_activities_screen.dart   Route: /student/activities
//
// Architecture:
//   • Wrapped in StudentDashboardLayout — NO Scaffold
//   • StreamBuilder for activities feed (real-time)
//   • Future.wait for enrollment map (userId → {activityId: status})
//   • Card button changes based on enrollment status
//   • All navigation uses pushReplacementNamed or pushNamed to detail
//   • No mock data
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:unitrack_flutter/screens/student/student_dashboard_layout.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DESIGN TOKENS
// ─────────────────────────────────────────────────────────────────────────────
class _C {
  static const card = Color(0xFF111827);
  static const primary = Color(0xFF8B5CF6);
  static const neonBlue = Color(0xFF3B82F6);
  static const neonCyan = Color(0xFF06B6D4);
  static const neonGreen = Color(0xFF10B981);
  static const amber = Color(0xFFF59E0B);
  static const rose = Color(0xFFF43F5E);
  static const text = Color(0xFFEFF3F8);
  static const muted = Color(0xFF7E8A9A);
  static const border = Color(0xFF1F2937);
  static const secondary = Color(0xFF1A2235);
}

// ─────────────────────────────────────────────────────────────────────────────
// ACTIVITY MODEL (exported so detail screen can import)
// ─────────────────────────────────────────────────────────────────────────────
class ActivityModel {
  final String id, title, description, type, department, faculty;
  final String date, duration, status;
  final int credits, capacity, enrolled;
  final bool blockchainVerified;

  const ActivityModel({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.department,
    required this.faculty,
    required this.date,
    required this.duration,
    required this.status,
    required this.credits,
    required this.capacity,
    required this.enrolled,
    required this.blockchainVerified,
  });

  factory ActivityModel.fromDoc(DocumentSnapshot doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? {};
    return ActivityModel(
      id: doc.id,
      title: (d['title'] as String?) ?? '',
      description: (d['description'] as String?) ?? '',
      type: (d['type'] as String?) ?? '',
      department: (d['department'] as String?) ?? '',
      faculty: (d['faculty'] as String?) ?? '',
      date: (d['date'] as String?) ?? '',
      duration: (d['duration'] as String?) ?? '',
      status: (d['status'] as String?) ?? 'open',
      credits: (d['credits'] as int?) ?? 0,
      capacity: (d['capacity'] as int?) ?? 0,
      enrolled: (d['enrolled'] as int?) ?? 0,
      blockchainVerified: (d['blockchainVerified'] as bool?) ?? false,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ENROLLMENT MAP MODEL  activityId → enrollmentStatus
// ─────────────────────────────────────────────────────────────────────────────
class _EnrMap {
  final Map<String, String> data; // activityId → status
  const _EnrMap(this.data);
  String? statusOf(String activityId) => data[activityId];
  bool isEnrolled(String activityId) => data.containsKey(activityId);
}

// ─────────────────────────────────────────────────────────────────────────────
// TYPE COLOR
// ─────────────────────────────────────────────────────────────────────────────
Color _typeColor(String type) {
  switch (type) {
    case 'Workshop':
      return _C.primary;
    case 'Bootcamp':
      return _C.neonBlue;
    case 'Research':
      return _C.amber;
    case 'Event':
      return _C.neonCyan;
    case 'Certification':
      return _C.neonGreen;
    case 'Seminar':
      return _C.rose;
    default:
      return _C.muted;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STATUS COLOR
// ─────────────────────────────────────────────────────────────────────────────
Color _statusColor(String s) {
  switch (s.toLowerCase()) {
    case 'enrolled':
      return _C.primary;
    case 'approved':
      return _C.neonBlue;
    case 'completed':
      return _C.amber;
    case 'verified':
      return _C.neonGreen;
    default:
      return _C.muted;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED WIDGETS
// ─────────────────────────────────────────────────────────────────────────────
class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final VoidCallback? onTap;
  const _GlassCard({required this.child, this.padding, this.onTap});

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _C.card.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.border),
      ),
      child: child,
    );
    return onTap == null ? box : GestureDetector(onTap: onTap, child: box);
  }
}

Widget _blockchainBadge() => Container(
  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
  decoration: BoxDecoration(
    color: _C.neonCyan.withValues(alpha: 0.1),
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: _C.neonCyan.withValues(alpha: 0.4)),
  ),
  child: const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.verified_rounded, size: 10, color: _C.neonCyan),
      SizedBox(width: 3),
      Text(
        'On-Chain',
        style: TextStyle(
          color: _C.neonCyan,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  ),
);

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 11, color: color),
      const SizedBox(width: 3),
      Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    ],
  );
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? color;
  final bool outlined;
  final bool disabled;
  final VoidCallback? onTap;
  const _ActionBtn({
    required this.label,
    required this.icon,
    this.color,
    this.outlined = false,
    this.disabled = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: disabled ? null : onTap,
    child: Opacity(
      opacity: disabled ? 0.5 : 1.0,
      child: Container(
        height: 40,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          gradient: outlined
              ? null
              : LinearGradient(colors: [color ?? _C.primary, _C.neonBlue]),
          borderRadius: BorderRadius.circular(10),
          border: outlined
              ? Border.all(color: color ?? _C.primary, width: 1.3)
              : null,
          color: outlined ? null : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: outlined ? (color ?? _C.primary) : Colors.white,
              size: 15,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: outlined ? (color ?? _C.primary) : Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// STATS STRIP
// ─────────────────────────────────────────────────────────────────────────────
class _StatsStrip extends StatelessWidget {
  final List<ActivityModel> items;
  const _StatsStrip({required this.items});

  @override
  Widget build(BuildContext context) {
    final openCount = items.where((a) => a.status == 'open').length;
    final totalCr = items.fold(0, (s, a) => s + a.credits);
    final verifiedCnt = items.where((a) => a.blockchainVerified).length;

    return LayoutBuilder(
      builder: (_, c) {
        final w = (c.maxWidth - 20) / 3;
        return Row(
          children: [
            SizedBox(
              width: w,
              child: _StatMini(
                icon: Icons.menu_book_rounded,
                color: _C.primary,
                value: '$openCount',
                label: 'Open',
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: w,
              child: _StatMini(
                icon: Icons.star_rounded,
                color: _C.neonCyan,
                value: '$totalCr',
                label: 'Credits',
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: w,
              child: _StatMini(
                icon: Icons.verified_rounded,
                color: _C.neonGreen,
                value: '$verifiedCnt',
                label: 'Verified',
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatMini extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value, label;
  const _StatMini({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
    decoration: BoxDecoration(
      color: _C.card.withValues(alpha: 0.75),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _C.border),
    ),
    child: Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: _C.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Text(
                label,
                style: const TextStyle(color: _C.muted, fontSize: 9),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// ACTIVITY CARD
// ─────────────────────────────────────────────────────────────────────────────
class _ActivityCard extends StatelessWidget {
  final ActivityModel activity;
  final String? enrollmentStatus; // null = not enrolled
  final VoidCallback onTap;
  const _ActivityCard({
    required this.activity,
    required this.onTap,
    this.enrollmentStatus,
  });

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final color = _typeColor(a.type);
    final isFull = a.status == 'full';
    final fillPct = a.capacity > 0
        ? (a.enrolled / a.capacity).clamp(0.0, 1.0)
        : 0.0;
    final enrStat = enrollmentStatus;

    return _GlassCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Type pill + blockchain badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Text(
                  a.type,
                  style: TextStyle(
                    color: color,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              if (a.blockchainVerified) _blockchainBadge(),
            ],
          ),
          const SizedBox(height: 10),

          // Title
          Text(
            a.title,
            style: const TextStyle(
              color: _C.text,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),

          // Dept + faculty
          Text(
            '${a.department} · ${a.faculty}',
            style: const TextStyle(color: _C.muted, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),

          // Description
          Text(
            a.description,
            style: const TextStyle(color: _C.muted, fontSize: 12, height: 1.45),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),

          // Meta chips
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _MetaChip(
                icon: Icons.calendar_today_rounded,
                label: a.date,
                color: _C.muted,
              ),
              _MetaChip(
                icon: Icons.schedule_rounded,
                label: a.duration,
                color: _C.muted,
              ),
              _MetaChip(
                icon: Icons.star_rounded,
                label: '${a.credits} cr',
                color: _C.primary,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Capacity bar
          Row(
            children: [
              const Icon(Icons.people_rounded, size: 11, color: _C.muted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${a.enrolled} / ${a.capacity} enrolled',
                  style: const TextStyle(color: _C.muted, fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${(fillPct * 100).round()}%',
                style: const TextStyle(color: _C.muted, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 5),
          LayoutBuilder(
            builder: (_, c) => ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 5,
                width: c.maxWidth,
                child: Stack(
                  children: [
                    Container(color: _C.secondary),
                    FractionallySizedBox(
                      widthFactor: fillPct,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isFull
                                ? [_C.muted, _C.muted]
                                : [_C.primary, _C.neonBlue],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Action button — changes based on enrollment
          if (enrStat != null)
            _ActionBtn(
              label: enrStat,
              icon: enrStat == 'Verified'
                  ? Icons.verified_rounded
                  : enrStat == 'Completed'
                  ? Icons.task_alt_rounded
                  : Icons.check_circle_rounded,
              color: _statusColor(enrStat),
              outlined: true,
              onTap: onTap,
            )
          else
            _ActionBtn(
              label: isFull ? 'Fully Booked' : 'View & Enroll',
              icon: isFull ? Icons.block_rounded : Icons.arrow_forward_rounded,
              disabled: isFull,
              outlined: isFull,
              onTap: onTap,
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class StudentActivitiesScreen extends StatefulWidget {
  const StudentActivitiesScreen({super.key});
  @override
  State<StudentActivitiesScreen> createState() =>
      _StudentActivitiesScreenState();
}

class _StudentActivitiesScreenState extends State<StudentActivitiesScreen> {
  String _search = '';
  String _selectedType = 'All';
  String _userName = '';
  String _uid = '';
  _EnrMap _enrMap = const _EnrMap({});

  final _searchCtrl = TextEditingController();

  static const _types = [
    'All',
    'Workshop',
    'Bootcamp',
    'Research',
    'Event',
    'Certification',
    'Seminar',
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(_init);
  }

  void _init() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) return;
    _uid = user.uid;

    // Fetch display name + enrollments in parallel
    final results = await Future.wait([
      FirebaseFirestore.instance.collection('users').doc(_uid).get(),
      FirebaseFirestore.instance
          .collection('enrollments')
          .where('userId', isEqualTo: _uid)
          .get(),
    ]);

    if (!mounted) return;
    final userDoc = results[0] as DocumentSnapshot;
    final enrSnap = results[1] as QuerySnapshot;

    final name = ((userDoc.data() as Map?) ?? {})['name'] as String? ?? '';
    final enrData = <String, String>{};
    for (final doc in enrSnap.docs) {
      final d = (doc.data() as Map<String, dynamic>?) ?? {};
      final aid = (d['activityId'] as String?) ?? '';
      final st = (d['status'] as String?) ?? 'Enrolled';
      if (aid.isNotEmpty) enrData[aid] = st;
    }

    setState(() {
      _userName = name;
      _enrMap = _EnrMap(enrData);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<ActivityModel> _filter(List<ActivityModel> items) => items.where((a) {
    final matchType = _selectedType == 'All' || a.type == _selectedType;
    final matchSrch =
        _search.isEmpty ||
        a.title.toLowerCase().contains(_search.toLowerCase()) ||
        a.department.toLowerCase().contains(_search.toLowerCase());
    return matchType && matchSrch;
  }).toList();

  void _goToDetail(ActivityModel activity) {
    Navigator.pushNamed(
      context,
      '/student/activity-detail',
      arguments: activity,
    );
  }

  @override
  Widget build(BuildContext context) => StudentDashboardLayout(
    currentRoute: '/student/activities',
    userName: _userName,
    child: StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('activities')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 80),
            child: Center(child: CircularProgressIndicator(color: _C.primary)),
          );
        }
        if (snap.hasError) {
          return _GlassCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: Colors.redAccent,
                    size: 32,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    snap.error.toString(),
                    style: const TextStyle(color: _C.muted, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        final allItems = (snap.data?.docs ?? [])
            .map(ActivityModel.fromDoc)
            .toList();
        final filtered = _filter(allItems);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Heading
            const Text(
              'Academic Activities',
              style: TextStyle(
                color: _C.text,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Workshops, bootcamps, seminars & blockchain-verified credits',
              style: TextStyle(color: _C.muted, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),

            // Search bar
            Container(
              height: 42,
              decoration: BoxDecoration(
                color: _C.card.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _C.border),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  const Icon(Icons.search_rounded, color: _C.muted, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(color: _C.text, fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'Search activities...',
                        hintStyle: TextStyle(color: _C.muted, fontSize: 13),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (v) => setState(() => _search = v),
                    ),
                  ),
                  if (_search.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _searchCtrl.clear();
                        setState(() => _search = '');
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Icon(
                          Icons.close_rounded,
                          color: _C.muted,
                          size: 16,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Volunteering CTA
            _GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.eco_rounded, color: _C.neonGreen, size: 16),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '🌱 Volunteering opportunities are also available for community engagement.',
                      style: TextStyle(color: _C.muted, fontSize: 11),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () =>
                        Navigator.pushNamed(context, '/student/volunteering'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _C.primary.withValues(alpha: 0.5),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Browse',
                        style: TextStyle(
                          color: _C.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Stats strip
            _StatsStrip(items: allItems),
            const SizedBox(height: 14),

            // Type filter chips
            Row(
              children: [
                const Icon(
                  Icons.filter_list_rounded,
                  color: _C.muted,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 32,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _types.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (_, i) {
                        final t = _types[i];
                        final isActive = _selectedType == t;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedType = t),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? _C.primary.withValues(alpha: 0.15)
                                  : _C.secondary,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isActive
                                    ? _C.primary.withValues(alpha: 0.5)
                                    : _C.border,
                              ),
                            ),
                            child: Text(
                              t,
                              style: TextStyle(
                                color: isActive ? _C.primary : _C.muted,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Cards or empty
            if (filtered.isEmpty)
              _GlassCard(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.menu_book_rounded,
                        color: _C.muted,
                        size: 40,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No activities found',
                        style: TextStyle(
                          color: _C.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _search.isNotEmpty || _selectedType != 'All'
                            ? 'Try adjusting your search or filter'
                            : 'Check back later for new activities',
                        style: const TextStyle(color: _C.muted, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              ...filtered.map(
                (a) => _ActivityCard(
                  activity: a,
                  enrollmentStatus: _enrMap.statusOf(a.id),
                  onTap: () => _goToDetail(a),
                ),
              ),
          ],
        );
      },
    ),
  );
}
