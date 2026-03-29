// ═══════════════════════════════════════════════════════════════════════════════
// student_activities_screen.dart
//
// Route: /student/activities
// Architecture mirrors volunteering module exactly.
//
// Firestore:
//   activities/{id}   → title, description, type, department, faculty,
//                        credits, date, duration, capacity, enrolled,
//                        status ("open"|"full"), blockchainVerified, createdAt
//   enrollments/{id}  → userId, activityId, status, appliedAt
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'activity_detail_screen.dart';

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
  static const rose = Color(0xFFF43F5E);
  static const text = Color(0xFFEFF3F8);
  static const muted = Color(0xFF7E8A9A);
  static const border = Color(0xFF1F2937);
  static const secondary = Color(0xFF1A2235);
}

// ─────────────────────────────────────────────────────────────────────────────
// ACTIVITY MODEL
// ─────────────────────────────────────────────────────────────────────────────
class ActivityModel {
  final String id;
  final String title;
  final String description;
  final String type;
  final String department;
  final String faculty;
  final int credits;
  final String date;
  final String duration;
  final int capacity;
  final int enrolled;
  final String status; // "open" | "full"
  final bool blockchainVerified;

  const ActivityModel({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.department,
    required this.faculty,
    required this.credits,
    required this.date,
    required this.duration,
    required this.capacity,
    required this.enrolled,
    required this.status,
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
      credits: (d['credits'] as int?) ?? 0,
      date: (d['date'] as String?) ?? '',
      duration: (d['duration'] as String?) ?? '',
      capacity: (d['capacity'] as int?) ?? 0,
      enrolled: (d['enrolled'] as int?) ?? 0,
      status: (d['status'] as String?) ?? 'open',
      blockchainVerified: (d['blockchainVerified'] as bool?) ?? false,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TYPE → COLOR
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
// SHARED WIDGETS
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

class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final VoidCallback? onTap;

  const _GlassCard({required this.child, this.padding, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _C.card.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.border),
        boxShadow: [],
      ),
      child: child,
    ),
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
    switch (status) {
      case 'verified':
        color = _C.neonCyan;
        icon = Icons.check_circle_rounded;
        label = 'Verified on Chain';
        break;
      case 'pending':
        color = const Color(0xFFFBBF24);
        icon = Icons.access_time_rounded;
        label = 'Pending';
        break;
      default:
        color = _C.muted;
        icon = Icons.shield_outlined;
        label = 'Not Verified';
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
  final VoidCallback? onTap;
  final bool outlined;
  final bool disabled;

  const _GradientButton({
    required this.label,
    this.icon,
    this.onTap,
    this.outlined = false,
    this.disabled = false,
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
              : const LinearGradient(colors: [_C.primary, _C.neonBlue]),
          borderRadius: BorderRadius.circular(10),
          border: outlined ? Border.all(color: _C.primary, width: 1.3) : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: outlined ? _C.primary : Colors.white, size: 15),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: outlined ? _C.primary : Colors.white,
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

class _EmptyState extends StatelessWidget {
  final String msg;
  final String sub;
  const _EmptyState({required this.msg, required this.sub});

  @override
  Widget build(BuildContext context) => _GlassCard(
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.menu_book_rounded, color: _C.muted, size: 40),
        const SizedBox(height: 12),
        Text(
          msg,
          style: const TextStyle(
            color: _C.text,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          sub,
          style: const TextStyle(color: _C.muted, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

class _ErrorState extends StatelessWidget {
  final String msg;
  const _ErrorState({required this.msg});

  @override
  Widget build(BuildContext context) => _GlassCard(
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.error_outline_rounded,
          color: Colors.redAccent,
          size: 36,
        ),
        const SizedBox(height: 10),
        const Text(
          'Something went wrong',
          style: TextStyle(
            color: _C.text,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          msg,
          style: const TextStyle(color: _C.muted, fontSize: 11),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// STATS ROW MODEL — computed from stream data
// ─────────────────────────────────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  final List<ActivityModel> items;
  const _StatsRow({required this.items});

  @override
  Widget build(BuildContext context) {
    final openCount = items.where((a) => a.status == 'open').length;
    final totalCredits = items.fold(0, (s, a) => s + a.credits);
    final verifiedCount = items.where((a) => a.blockchainVerified).length;

    return LayoutBuilder(
      builder: (ctx, c) {
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
                value: '$totalCredits',
                label: 'Credits',
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: w,
              child: _StatMini(
                icon: Icons.verified_rounded,
                color: _C.neonGreen,
                value: '$verifiedCount',
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
  final String value;
  final String label;
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
  final VoidCallback onTap;
  const _ActivityCard({required this.activity, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final color = _typeColor(a.type);
    final isFull = a.status == 'full';
    final fillPct = a.capacity > 0
        ? (a.enrolled / a.capacity).clamp(0.0, 1.0)
        : 0.0;

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
              if (a.blockchainVerified)
                const _BlockchainBadge(status: 'verified'),
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

          // Dept + Faculty
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

          // Meta chips — use Wrap to prevent overflow
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

          // Capacity progress bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
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
                    '${(fillPct * 100).round()}% filled',
                    style: const TextStyle(color: _C.muted, fontSize: 10),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              LayoutBuilder(
                builder: (ctx, c) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      width: c.maxWidth,
                      height: 5,
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
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Action button
          _GradientButton(
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

// ─────────────────────────────────────────────────────────────────────────────
// TOP BAR
// ─────────────────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;

  const _TopBar({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(16, topPad + 10, 16, 12),
      decoration: BoxDecoration(
        color: _C.card.withValues(alpha: 0.7),
        border: const Border(bottom: BorderSide(color: _C.border)),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _C.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: _C.muted, fontSize: 11),
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
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN — ACTIVITIES FEED
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
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<ActivityModel> _filter(List<ActivityModel> items) {
    return items.where((a) {
      final matchType = _selectedType == 'All' || a.type == _selectedType;
      final matchSrch =
          _search.isEmpty ||
          a.title.toLowerCase().contains(_search.toLowerCase()) ||
          a.department.toLowerCase().contains(_search.toLowerCase());
      return matchType && matchSrch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final botPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: _C.bg,
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          Column(
            children: [
              _TopBar(
                title: 'Academic Activities',
                subtitle:
                    'Workshops, bootcamps, seminars & blockchain-verified credits',
                icon: Icons.menu_book_rounded,
                iconColor: _C.primary,
              ),

              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('activities')
                      .orderBy('createdAt', descending: true)
                      .snapshots(),
                  builder: (context, snap) {
                    // ── Loading ───────────────────────────────────────────
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: _C.primary),
                      );
                    }

                    // ── Error ─────────────────────────────────────────────
                    if (snap.hasError) {
                      return SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(16, 16, 16, botPad + 24),
                        child: _ErrorState(msg: snap.error.toString()),
                      );
                    }

                    // ── Parse ─────────────────────────────────────────────
                    final allItems = (snap.data?.docs ?? [])
                        .map(ActivityModel.fromDoc)
                        .toList();

                    final filtered = _filter(allItems);

                    return SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, botPad + 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Search bar ────────────────────────────────
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
                                const Icon(
                                  Icons.search_rounded,
                                  color: _C.muted,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _searchCtrl,
                                    style: const TextStyle(
                                      color: _C.text,
                                      fontSize: 13,
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: 'Search activities...',
                                      hintStyle: TextStyle(
                                        color: _C.muted,
                                        fontSize: 13,
                                      ),
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                    onChanged: (v) =>
                                        setState(() => _search = v),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 14),

                          // ── Volunteering CTA ──────────────────────────
                          _GlassCard(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.eco_rounded,
                                  color: _C.neonGreen,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    '🌱 Volunteering opportunities are prioritised for community engagement.',
                                    style: TextStyle(
                                      color: _C.muted,
                                      fontSize: 11,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () => Navigator.pushNamed(
                                    context,
                                    '/student/volunteering',
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: _C.primary.withValues(
                                          alpha: 0.5,
                                        ),
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

                          // ── Stats strip ───────────────────────────────
                          _StatsRow(items: allItems),

                          const SizedBox(height: 14),

                          // ── Type filter chips ─────────────────────────
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
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(width: 6),
                                    itemBuilder: (ctx, i) {
                                      final t = _types[i];
                                      final isActive = _selectedType == t;
                                      return GestureDetector(
                                        onTap: () =>
                                            setState(() => _selectedType = t),
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 200,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isActive
                                                ? _C.primary.withValues(
                                                    alpha: 0.15,
                                                  )
                                                : _C.secondary,
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            border: Border.all(
                                              color: isActive
                                                  ? _C.primary.withValues(
                                                      alpha: 0.5,
                                                    )
                                                  : _C.border,
                                            ),
                                          ),
                                          child: Text(
                                            t,
                                            style: TextStyle(
                                              color: isActive
                                                  ? _C.primary
                                                  : _C.muted,
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

                          // ── Cards ─────────────────────────────────────
                          if (filtered.isEmpty)
                            _EmptyState(
                              msg: 'No activities found',
                              sub: _search.isNotEmpty || _selectedType != 'All'
                                  ? 'Try adjusting your search or filter'
                                  : 'Check back later for new activities',
                            )
                          else
                            ...filtered.map(
                              (a) => _ActivityCard(
                                activity: a,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        ActivityDetailScreen(activity: a),
                                  ),
                                ),
                              ),
                            ),
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
