// ═══════════════════════════════════════════════════════════════════════════════
// student_my_progress_screen.dart   Route: /student/my-progress
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
  static const text = Color(0xFFEFF3F8);
  static const muted = Color(0xFF7E8A9A);
  static const border = Color(0xFF1F2937);
  static const yellow = Color(0xFFFBBF24);
  static const secondary = Color(0xFF1A2235);
}

// ─────────────────────────────────────────────────────────────────────────────
// UNIFIED MODEL
// ─────────────────────────────────────────────────────────────────────────────
class ProgressItem {
  final String id;
  final String title;
  final String type; // 'Activity' | 'Volunteering'
  final int credits;
  final String status; // Applied | Approved | Completed | Verified
  final String date;
  final String? txHash;

  const ProgressItem({
    required this.id,
    required this.title,
    required this.type,
    required this.credits,
    required this.status,
    required this.date,
    this.txHash,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// SERVICE  — two parallel batch-joins, zero N+1
// ─────────────────────────────────────────────────────────────────────────────
class _ProgressService {
  static final _db = FirebaseFirestore.instance;

  static Future<Map<String, Map<String, dynamic>>> _batchFetch(
    String collection,
    List<String> ids,
  ) async {
    final result = <String, Map<String, dynamic>>{};
    if (ids.isEmpty) return result;
    const chunk = 30;
    for (int i = 0; i < ids.length; i += chunk) {
      final slice = ids.sublist(i, (i + chunk).clamp(0, ids.length));
      final snap = await _db
          .collection(collection)
          .where(FieldPath.documentId, whereIn: slice)
          .get();
      for (final doc in snap.docs) {
        result[doc.id] = doc.data();
      }
    }
    return result;
  }

  static Future<List<ProgressItem>> load(String uid) async {
    if (uid.isEmpty) return [];

    final results = await Future.wait([
      _db.collection('enrollments').where('userId', isEqualTo: uid).get(),
      _db.collection('applications').where('userId', isEqualTo: uid).get(),
    ]);
    final enrSnap = results[0];
    final appSnap = results[1];

    final actIds = enrSnap.docs
        .map((d) => (d.data()['activityId'] as String?) ?? '')
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();

    final volIds = appSnap.docs
        .map((d) => (d.data()['volunteeringId'] as String?) ?? '')
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();

    final joins = await Future.wait([
      _batchFetch('activities', actIds),
      _batchFetch('volunteering', volIds),
    ]);
    final actMap = joins[0];
    final volMap = joins[1];

    final items = <ProgressItem>[];

    for (final doc in enrSnap.docs) {
      final d = doc.data();
      final aid = (d['activityId'] as String?) ?? '';
      final act = actMap[aid];
      if (act == null) continue;
      items.add(
        ProgressItem(
          id: doc.id,
          title: (act['title'] as String?) ?? aid,
          type: 'Activity',
          credits: (act['credits'] as num? ?? 0).toInt(),
          status: (d['status'] as String?) ?? 'Applied',
          date: _fmtTs(d['appliedAt']),
        ),
      );
    }

    for (final doc in appSnap.docs) {
      final d = doc.data();
      final vid = (d['volunteeringId'] as String?) ?? '';
      final vol = volMap[vid];
      if (vol == null) continue;
      items.add(
        ProgressItem(
          id: doc.id,
          title: (vol['title'] as String?) ?? vid,
          type: 'Volunteering',
          credits: (vol['credits'] as num? ?? 0).toInt(),
          status: (d['status'] as String?) ?? 'Applied',
          date: _fmtTs(d['appliedAt']),
          txHash: d['txHash'] as String?,
        ),
      );
    }

    items.sort((a, b) => b.date.compareTo(a.date));
    return items;
  }

  static String _fmtTs(dynamic ts) {
    if (ts is Timestamp) {
      final dt = ts.toDate();
      return '${dt.year.toString().padLeft(4, '0')}'
          '-${dt.month.toString().padLeft(2, '0')}'
          '-${dt.day.toString().padLeft(2, '0')}';
    }
    return '';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEPPER HELPERS
// ─────────────────────────────────────────────────────────────────────────────
const _steps = ['Applied', 'Approved', 'Completed', 'Verified'];

List<String> _stepStatuses(String status) {
  final idx = _steps.indexWhere((s) => s.toLowerCase() == status.toLowerCase());
  final cur = idx < 0 ? 0 : idx;
  return List.generate(_steps.length, (i) {
    if (i < cur) return 'completed';
    if (i == cur) return 'active';
    return 'upcoming';
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class StudentMyProgressScreen extends StatefulWidget {
  const StudentMyProgressScreen({super.key});

  @override
  State<StudentMyProgressScreen> createState() =>
      _StudentMyProgressScreenState();
}

class _StudentMyProgressScreenState extends State<StudentMyProgressScreen> {
  late Future<List<ProgressItem>> _future;
  String _userName = '';
  String _uid = '';
  String _typeFilter = 'All';

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _future = Future.value([]);
      return;
    }
    _uid = user.uid;

    FirebaseFirestore.instance.collection('users').doc(_uid).get().then((doc) {
      if (!mounted) return;
      final name = ((doc.data() ?? {})['name'] as String?) ?? '';
      if (name.isNotEmpty) setState(() => _userName = name);
    });

    _future = _ProgressService.load(_uid);
  }

  void _reload() => setState(_init);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    return StudentDashboardLayout(
      currentRoute: '/student/my-progress',
      userName: _userName,
      child: Padding(
        // ── Fix 8: safe horizontal padding ──────────────────────────────────
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ───────────────────────────────────────────────────────
            Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pushReplacementNamed(
                    context,
                    '/student/volunteering',
                  ),
                  child: Container(
                    width: 34,
                    height: 34,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: _C.secondary,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _C.border),
                    ),
                    child: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: _C.muted,
                      size: 15,
                    ),
                  ),
                ),
                // ── Fix 4: Expanded text, ellipsis ──────────────────────────
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'My Progress',
                        style: TextStyle(
                          color: _C.text,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Activities & volunteering tracker',
                        style: TextStyle(color: _C.muted, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ── Fix 3: Filter chips in Wrap ──────────────────────────────────
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['All', 'Activity', 'Volunteering'].map((f) {
                final isActive = _typeFilter == f;
                return GestureDetector(
                  onTap: () => setState(() => _typeFilter = f),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
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
                      f,
                      style: TextStyle(
                        color: isActive ? _C.primary : _C.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // ── Content ───────────────────────────────────────────────────────
            FutureBuilder<List<ProgressItem>>(
              future: _future,
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 64),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: _C.primary,
                        strokeWidth: 2,
                      ),
                    ),
                  );
                }

                if (snap.hasError) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ErrorCard(message: snap.error.toString()),
                      const SizedBox(height: 12),
                      _GradientButton(
                        label: 'Retry',
                        icon: Icons.refresh_rounded,
                        onTap: _reload,
                      ),
                    ],
                  );
                }

                final all = snap.data ?? [];
                final filtered = _typeFilter == 'All'
                    ? all
                    : all.where((i) => i.type == _typeFilter).toList();

                if (filtered.isEmpty) {
                  return _EmptyState(
                    message: all.isEmpty
                        ? 'No progress yet'
                        : 'No ${_typeFilter.toLowerCase()}s found',
                    sub: all.isEmpty
                        ? 'Start applying to activities or volunteering 🚀'
                        : 'Switch filters to see other records',
                  );
                }

                final verifiedCount = filtered
                    .where((i) => i.status == 'Verified')
                    .length;
                final totalCredits = filtered
                    .where((i) => i.status == 'Verified')
                    .fold(0, (s, i) => s + i.credits);

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Fix 5: Stats — responsive width ──────────────────────
                    _StatsRow(
                      width: width,
                      total: filtered.length,
                      verified: verifiedCount,
                      credits: totalCredits,
                    ),
                    const SizedBox(height: 16),
                    // Progress cards
                    ...filtered.map(
                      (item) => _ProgressCard(item: item, screenWidth: width),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fix 5: STATS ROW — LayoutBuilder-based, no fixed Expanded overflow
// ─────────────────────────────────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  final double width;
  final int total;
  final int verified;
  final int credits;
  const _StatsRow({
    required this.width,
    required this.total,
    required this.verified,
    required this.credits,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final itemWidth = (constraints.maxWidth - 20) / 3;
        return Row(
          children: [
            SizedBox(
              width: itemWidth,
              child: _MiniStat(
                label: 'Total',
                value: '$total',
                color: _C.primary,
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: itemWidth,
              child: _MiniStat(
                label: 'Verified',
                value: '$verified',
                color: _C.neonCyan,
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: itemWidth,
              child: _MiniStat(
                label: 'Credits Earned',
                value: '$credits',
                color: _C.amber,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PROGRESS CARD
// ─────────────────────────────────────────────────────────────────────────────
class _ProgressCard extends StatelessWidget {
  final ProgressItem item;
  final double screenWidth;
  const _ProgressCard({required this.item, required this.screenWidth});

  @override
  Widget build(BuildContext context) {
    final stepSts = _stepStatuses(item.status);
    final isVerified = item.status.toLowerCase() == 'verified';
    final isActivity = item.type == 'Activity';
    final isSmall = screenWidth < 360;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _C.card.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isVerified ? _C.neonCyan.withValues(alpha: 0.45) : _C.border,
          width: isVerified ? 1.5 : 1,
        ),
        boxShadow: isVerified
            ? [
                BoxShadow(
                  color: _C.neonCyan.withValues(alpha: 0.12),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ]
            : [],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Fix 7: Title row — icon + Expanded text + Flexible badge ────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: (isActivity ? _C.primary : _C.neonGreen).withValues(
                    alpha: 0.1,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isActivity ? Icons.menu_book_rounded : Icons.eco_rounded,
                  color: isActivity ? _C.primary : _C.neonGreen,
                  size: 17,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        color: _C.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    // ── Fix 2: meta row in Wrap, never overflows ─────────────
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _TypeBadge(type: item.type),
                        Text(
                          '${item.credits} cr',
                          style: const TextStyle(color: _C.muted, fontSize: 11),
                        ),
                        if (item.date.isNotEmpty)
                          Text(
                            _displayDate(item.date),
                            style: const TextStyle(
                              color: _C.muted,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              // ── Flexible badge so it never forces overflow ────────────────
              Flexible(child: _StatusBadge(status: item.status)),
            ],
          ),

          const SizedBox(height: 14),

          // ── Fix 6: Stepper — horizontal scroll + IntrinsicWidth ─────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: IntrinsicWidth(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(_steps.length, (i) {
                  final isLast = i == _steps.length - 1;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _StepBubble(
                        label: _steps[i],
                        status: stepSts[i],
                        compact: isSmall,
                      ),
                      if (!isLast)
                        Container(
                          width: isSmall ? 20 : 28,
                          height: 1.5,
                          margin: const EdgeInsets.only(bottom: 18),
                          color: stepSts[i] == 'completed'
                              ? _C.neonCyan.withValues(alpha: 0.4)
                              : _C.border,
                        ),
                    ],
                  );
                }),
              ),
            ),
          ),

          // ── Tx hash ──────────────────────────────────────────────────────────
          if (item.txHash != null && item.txHash!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _C.neonCyan.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _C.neonCyan.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.workspace_premium_rounded,
                    color: _C.neonCyan,
                    size: 15,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.txHash!,
                      style: const TextStyle(
                        color: _C.neonCyan,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _displayDate(String iso) {
    if (iso.length < 10) return iso;
    final parts = iso.split('-');
    if (parts.length < 3) return iso;
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final m = int.tryParse(parts[1]) ?? 0;
    return '${parts[2]} ${m < months.length ? months[m] : parts[1]}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP BUBBLE — compact mode for very small screens
// ─────────────────────────────────────────────────────────────────────────────
class _StepBubble extends StatelessWidget {
  final String label;
  final String status;
  final bool compact;
  const _StepBubble({
    required this.label,
    required this.status,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color borderC;
    final Color bgC;
    final Widget iconW;
    final Color labelC;
    final double sz = compact ? 28 : 34;
    final double icSz = compact ? 13 : 16;

    switch (status) {
      case 'completed':
        borderC = _C.neonCyan.withValues(alpha: 0.4);
        bgC = _C.neonCyan.withValues(alpha: 0.1);
        iconW = Icon(
          Icons.check_circle_rounded,
          size: icSz,
          color: _C.neonCyan,
        );
        labelC = _C.neonCyan;
        break;
      case 'active':
        borderC = _C.primary.withValues(alpha: 0.5);
        bgC = _C.primary.withValues(alpha: 0.1);
        iconW = Icon(Icons.bolt_rounded, size: icSz, color: _C.primary);
        labelC = _C.primary;
        break;
      default:
        borderC = _C.border;
        bgC = _C.secondary;
        iconW = Icon(Icons.access_time_rounded, size: icSz, color: _C.muted);
        labelC = _C.muted;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: sz,
          height: sz,
          decoration: BoxDecoration(
            color: bgC,
            shape: BoxShape.circle,
            border: Border.all(color: borderC),
          ),
          child: Center(child: iconW),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: labelC,
            fontSize: compact ? 8 : 9,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TYPE BADGE
// ─────────────────────────────────────────────────────────────────────────────
class _TypeBadge extends StatelessWidget {
  final String type;
  const _TypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final isActivity = type == 'Activity';
    final color = isActivity ? _C.primary : _C.neonGreen;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isActivity ? Icons.menu_book_rounded : Icons.eco_rounded,
            size: 10,
            color: color,
          ),
          const SizedBox(width: 3),
          Text(
            type,
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

// ─────────────────────────────────────────────────────────────────────────────
// STATUS BADGE
// ─────────────────────────────────────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final Color color;
    switch (status.toLowerCase()) {
      case 'applied':
        color = _C.yellow;
        break;
      case 'approved':
        color = _C.neonBlue;
        break;
      case 'completed':
        color = _C.neonGreen;
        break;
      case 'verified':
        color = _C.neonCyan;
        break;
      default:
        color = _C.muted;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MINI STAT CARD
// ─────────────────────────────────────────────────────────────────────────────
class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(
      color: _C.card.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _C.border),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            label,
            style: const TextStyle(color: _C.muted, fontSize: 10),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED HELPERS
// ─────────────────────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final String message;
  final String sub;
  const _EmptyState({required this.message, required this.sub});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
    decoration: BoxDecoration(
      color: _C.card.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _C.border),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.inbox_rounded, color: _C.muted, size: 44),
        const SizedBox(height: 12),
        Text(
          message,
          style: const TextStyle(
            color: _C.text,
            fontWeight: FontWeight.w600,
            fontSize: 15,
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

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.redAccent.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.error_outline_rounded,
          color: Colors.redAccent,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Error: $message',
            style: const TextStyle(color: Colors.redAccent, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

class _GradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  const _GradientButton({required this.label, this.icon, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 44,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_C.primary, _C.neonBlue]),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    ),
  );
}
