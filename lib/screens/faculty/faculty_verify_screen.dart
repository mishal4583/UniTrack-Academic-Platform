// ═══════════════════════════════════════════════════════════════════════════════
// faculty_verify_screen.dart   Route: /faculty/verify
//
// Real-time verification panel: reads applications + enrollments from Firestore,
// joins them with their activity/volunteering titles, lets faculty approve/reject.
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
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
  static const rose = Color(0xFFF43F5E);
  static const text = Color(0xFFEFF3F8);
  static const muted = Color(0xFF7E8A9A);
  static const border = Color(0xFF1F2937);
  static const secondary = Color(0xFF1A2235);
}

// ─────────────────────────────────────────────────────────────────────────────
// MODEL — a pending verification item (application or enrollment)
// ─────────────────────────────────────────────────────────────────────────────
class _PendingItem {
  final String docId;
  final String collection; // "applications" | "enrollments"
  final String userId;
  final String userName; // resolved from users collection
  final String itemTitle; // resolved volunteering/activity title
  final String itemType; // "Volunteering" | "Activity"
  final String activityType; // Workshop, Bootcamp, etc.
  final int credits;
  final String status;
  final DateTime? submittedAt;

  const _PendingItem({
    required this.docId,
    required this.collection,
    required this.userId,
    required this.userName,
    required this.itemTitle,
    required this.itemType,
    required this.activityType,
    required this.credits,
    required this.status,
    this.submittedAt,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// DATA SERVICE — joins in memory, no nested async in builder
// ─────────────────────────────────────────────────────────────────────────────
class _VerifyService {
  static final _db = FirebaseFirestore.instance;

  static Map<String, dynamic> _safe(DocumentSnapshot doc) =>
      (doc.data() as Map<String, dynamic>?) ?? {};

  /// Fetches ALL pending applications (status == "Applied") and
  /// pending enrollments (status == "Enrolled"), then joins with
  /// volunteering / activities and users in batch.
  static Future<List<_PendingItem>> fetchPending() async {
    // ── 1. Parallel top-level reads ──────────────────────────────────────────
    final results = await Future.wait([
      _db
          .collection('applications')
          .where('status', isEqualTo: 'Applied')
          .get(),
      _db
          .collection('enrollments')
          .where('status', isEqualTo: 'Enrolled')
          .get(),
    ]);

    final appSnap = results[0] as QuerySnapshot;
    final enrSnap = results[1] as QuerySnapshot;

    if (appSnap.docs.isEmpty && enrSnap.docs.isEmpty) return [];

    // ── 2. Collect unique IDs for batch lookups ──────────────────────────────
    final volIds = <String>{};
    final actIds = <String>{};
    final userIds = <String>{};

    for (final doc in appSnap.docs) {
      final d = _safe(doc);
      final vid = (d['volunteeringId'] as String?) ?? '';
      if (vid.isNotEmpty) volIds.add(vid);
      final uid = (d['userId'] as String?) ?? '';
      if (uid.isNotEmpty) userIds.add(uid);
    }
    for (final doc in enrSnap.docs) {
      final d = _safe(doc);
      final aid = (d['activityId'] as String?) ?? '';
      if (aid.isNotEmpty) actIds.add(aid);
      final uid = (d['userId'] as String?) ?? '';
      if (uid.isNotEmpty) userIds.add(uid);
    }

    // ── 3. Batch fetch reference collections ────────────────────────────────
    const batchSize = 30;

    Future<Map<String, Map<String, dynamic>>> batchFetch(
      String col,
      Set<String> ids,
    ) async {
      final map = <String, Map<String, dynamic>>{};
      final list = ids.toList();
      for (int i = 0; i < list.length; i += batchSize) {
        final chunk = list.sublist(i, (i + batchSize).clamp(0, list.length));
        final snap = await _db
            .collection(col)
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          map[doc.id] = _safe(doc);
        }
      }
      return map;
    }

    final batchResults = await Future.wait([
      volIds.isNotEmpty
          ? batchFetch('volunteering', volIds)
          : Future.value(<String, Map<String, dynamic>>{}),
      actIds.isNotEmpty
          ? batchFetch('activities', actIds)
          : Future.value(<String, Map<String, dynamic>>{}),
      userIds.isNotEmpty
          ? batchFetch('users', userIds)
          : Future.value(<String, Map<String, dynamic>>{}),
    ]);

    final volMap = batchResults[0];
    final actMap = batchResults[1];
    final userMap = batchResults[2];

    String resolveUser(String uid) {
      final d = userMap[uid] ?? {};
      return (d['name'] as String?) ??
          (d['email'] as String?) ??
          uid.substring(0, uid.length.clamp(0, 8));
    }

    // ── 4. Build merged list ─────────────────────────────────────────────────
    final items = <_PendingItem>[];

    for (final doc in appSnap.docs) {
      final d = _safe(doc);
      final vid = (d['volunteeringId'] as String?) ?? '';
      final vol = volMap[vid] ?? {};
      final ts = d['appliedAt'];
      items.add(
        _PendingItem(
          docId: doc.id,
          collection: 'applications',
          userId: (d['userId'] as String?) ?? '',
          userName: resolveUser((d['userId'] as String?) ?? ''),
          itemTitle: (vol['title'] as String?) ?? vid,
          itemType: 'Volunteering',
          activityType: (vol['category'] as String?) ?? 'Volunteering',
          credits: (vol['credits'] as int?) ?? 0,
          status: (d['status'] as String?) ?? 'Applied',
          submittedAt: ts is Timestamp ? ts.toDate() : null,
        ),
      );
    }

    for (final doc in enrSnap.docs) {
      final d = _safe(doc);
      final aid = (d['activityId'] as String?) ?? '';
      final act = actMap[aid] ?? {};
      final ts = d['appliedAt'];
      items.add(
        _PendingItem(
          docId: doc.id,
          collection: 'enrollments',
          userId: (d['userId'] as String?) ?? '',
          userName: resolveUser((d['userId'] as String?) ?? ''),
          itemTitle: (act['title'] as String?) ?? aid,
          itemType: 'Activity',
          activityType: (act['type'] as String?) ?? 'Activity',
          credits: (act['credits'] as int?) ?? 0,
          status: (d['status'] as String?) ?? 'Enrolled',
          submittedAt: ts is Timestamp ? ts.toDate() : null,
        ),
      );
    }

    // Newest first
    items.sort((a, b) {
      if (a.submittedAt == null && b.submittedAt == null) return 0;
      if (a.submittedAt == null) return 1;
      if (b.submittedAt == null) return -1;
      return b.submittedAt!.compareTo(a.submittedAt!);
    });

    return items;
  }

  static Future<void> approve(_PendingItem item) async {
    final newStatus = item.collection == 'applications'
        ? 'Approved'
        : 'Completed';
    await _db.collection(item.collection).doc(item.docId).update({
      'status': newStatus,
    });
  }

  static Future<void> reject(_PendingItem item) async {
    await _db.collection(item.collection).doc(item.docId).update({
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
class _TopBar extends StatelessWidget {
  final int pendingCount;
  const _TopBar({required this.pendingCount});

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
          GestureDetector(
            onTap: () {
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              } else {
                Navigator.pushReplacementNamed(context, '/faculty');
              }
            },
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
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _C.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.fact_check_rounded,
              color: _C.primary,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Verification Panel',
                  style: TextStyle(
                    color: _C.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  pendingCount > 0
                      ? '$pendingCount pending verification${pendingCount == 1 ? '' : 's'} require your attention'
                      : 'All caught up!',
                  style: const TextStyle(color: _C.muted, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
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
                SizedBox(width: 5),
                Text(
                  'Live',
                  style: TextStyle(
                    color: _C.neonCyan,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
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
// FILTER CHIPS
// ─────────────────────────────────────────────────────────────────────────────
class _FilterChips extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  final int pendingCount;
  final int activityCount;
  final int volunteeringCount;

  const _FilterChips({
    required this.selected,
    required this.onChanged,
    required this.pendingCount,
    required this.activityCount,
    required this.volunteeringCount,
  });

  @override
  Widget build(BuildContext context) {
    final filters = [
      ('All', 'All', pendingCount),
      ('Activity', 'Activity', activityCount),
      ('Volunteering', 'Volunteering', volunteeringCount),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((f) {
          final isActive = selected == f.$1;
          return GestureDetector(
            onTap: () => onChanged(f.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    f.$2,
                    style: TextStyle(
                      color: isActive ? _C.primary : _C.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (f.$3 > 0) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: isActive ? _C.primary : _C.border,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${f.$3}',
                        style: TextStyle(
                          color: isActive ? Colors.white : _C.muted,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VERIFICATION CARD
// ─────────────────────────────────────────────────────────────────────────────
class _VerifyCard extends StatefulWidget {
  final _PendingItem item;
  final VoidCallback onAction;
  const _VerifyCard({required this.item, required this.onAction});

  @override
  State<_VerifyCard> createState() => _VerifyCardState();
}

class _VerifyCardState extends State<_VerifyCard> {
  bool _processing = false;
  Future<void> _act(bool approve) async {
    if (mounted) {
      setState(() => _processing = true);
    }

    try {
      if (approve) {
        await _VerifyService.approve(widget.item);
      } else {
        await _VerifyService.reject(widget.item);
      }

      // ✅ SAFE CALL (VERY IMPORTANT)
      if (mounted) {
        widget.onAction();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error: $e',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: _C.rose.withValues(alpha: 0.9),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      // ✅ ALSO SAFE
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  String _timeAgo() {
    if (widget.item.submittedAt == null) return '';
    final diff = DateTime.now().difference(widget.item.submittedAt!);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _initial() {
    final name = widget.item.userName;
    if (name.isEmpty) return '?';
    return name[0].toUpperCase();
  }

  Color _typeColor() =>
      widget.item.itemType == 'Volunteering' ? _C.neonGreen : _C.primary;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final tColor = _typeColor();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _C.card.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header row ──────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_C.primary, _C.neonBlue],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    _initial(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.userName,
                      style: const TextStyle(
                        color: _C.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.itemTitle,
                            style: const TextStyle(
                              color: _C.muted,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_timeAgo().isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(
                            '· ${_timeAgo()}',
                            style: const TextStyle(
                              color: _C.muted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Type badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: tColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: tColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  item.itemType,
                  style: TextStyle(
                    color: tColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ── Detail chips ─────────────────────────────────────────────────
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              _DetailChip(
                icon: Icons.category_rounded,
                label: item.activityType,
                color: _C.muted,
              ),
              if (item.credits > 0)
                _DetailChip(
                  icon: Icons.star_rounded,
                  label: '${item.credits} credits',
                  color: _C.primary,
                ),
              _DetailChip(
                icon: item.itemType == 'Volunteering'
                    ? Icons.eco_rounded
                    : Icons.menu_book_rounded,
                label: item.itemType,
                color: tColor,
              ),
            ],
          ),

          const SizedBox(height: 14),
          const Divider(color: _C.border, height: 1),
          const SizedBox(height: 14),

          // ── Actions ──────────────────────────────────────────────────────
          _processing
              ? const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: _C.primary,
                    ),
                  ),
                )
              : Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _act(true),
                        child: Container(
                          height: 38,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [_C.neonGreen, _C.neonCyan],
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.check_circle_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Approve',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _act(false),
                        child: Container(
                          height: 38,
                          decoration: BoxDecoration(
                            color: _C.rose.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _C.rose.withValues(alpha: 0.5),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.cancel_rounded,
                                color: _C.rose,
                                size: 16,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Reject',
                                style: TextStyle(
                                  color: _C.rose,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ],
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _DetailChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 4),
      Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// STATS STRIP
// ─────────────────────────────────────────────────────────────────────────────
class _StatsStrip extends StatelessWidget {
  final int total;
  final int activities;
  final int volunteering;

  const _StatsStrip({
    required this.total,
    required this.activities,
    required this.volunteering,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (ctx, c) {
      final stats = [
        (
          label: 'Pending',
          value: '$total',
          icon: Icons.pending_actions_rounded,
          color: _C.amber,
        ),
        (
          label: 'Activities',
          value: '$activities',
          icon: Icons.menu_book_rounded,
          color: _C.primary,
        ),
        (
          label: 'Volunteering',
          value: '$volunteering',
          icon: Icons.eco_rounded,
          color: _C.neonGreen,
        ),
      ];
      return Row(
        children: stats.asMap().entries.map((e) {
          final s = e.value;
          return Expanded(
            child: Container(
              margin: e.key < stats.length - 1
                  ? const EdgeInsets.only(right: 10)
                  : EdgeInsets.zero,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: _C.card.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _C.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(s.icon, size: 16, color: s.color),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      s.value,
                      style: const TextStyle(
                        color: _C.text,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    s.label,
                    style: const TextStyle(
                      color: _C.muted,
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      );
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class FacultyVerifyScreen extends StatefulWidget {
  const FacultyVerifyScreen({super.key});

  @override
  State<FacultyVerifyScreen> createState() => _FacultyVerifyScreenState();
}

class _FacultyVerifyScreenState extends State<FacultyVerifyScreen> {
  late Future<List<_PendingItem>> _future;
  String _filter = 'All';
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final future = _VerifyService.fetchPending();

    if (mounted) {
      setState(() {
        _future = future;
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<_PendingItem> _applyFilter(List<_PendingItem> items) {
    return items.where((item) {
      final matchFilter = _filter == 'All' || item.itemType == _filter;
      final matchSearch =
          _search.isEmpty ||
          item.userName.toLowerCase().contains(_search.toLowerCase()) ||
          item.itemTitle.toLowerCase().contains(_search.toLowerCase());
      return matchFilter && matchSearch;
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
          FutureBuilder<List<_PendingItem>>(
            future: _future,
            builder: (context, snap) {
              final allItems = snap.data ?? [];
              final actCount = allItems
                  .where((i) => i.itemType == 'Activity')
                  .length;
              final volCount = allItems
                  .where((i) => i.itemType == 'Volunteering')
                  .length;
              final filtered = _applyFilter(allItems);

              return Column(
                children: [
                  _TopBar(pendingCount: allItems.length),

                  Expanded(
                    child: Builder(
                      builder: (ctx) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(color: _C.primary),
                          );
                        }
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
                                    'Failed to load verifications',
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
                                  GestureDetector(
                                    onTap: _load,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [_C.primary, _C.neonBlue],
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.refresh_rounded,
                                            color: Colors.white,
                                            size: 16,
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            'Retry',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        return SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(16, 16, 16, botPad + 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ── STATS STRIP ──────────────────────────────
                              _StatsStrip(
                                total: allItems.length,
                                activities: actCount,
                                volunteering: volCount,
                              ),

                              const SizedBox(height: 16),

                              // ── SEARCH BAR ───────────────────────────────
                              Container(
                                height: 44,
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
                                          hintText:
                                              'Search student or activity...',
                                          hintStyle: TextStyle(
                                            color: _C.muted,
                                            fontSize: 13,
                                          ),
                                          border: InputBorder.none,
                                          isDense: true,
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                        onChanged: (v) {
                                          _search = v;
                                          setState(() {});
                                        },
                                      ),
                                    ),
                                    if (_search.isNotEmpty)
                                      GestureDetector(
                                        onTap: () {
                                          _searchCtrl.clear();
                                          setState(() => _search = '');
                                        },
                                        child: const Padding(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 10,
                                          ),
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

                              const SizedBox(height: 12),

                              // ── FILTER CHIPS ─────────────────────────────
                              _FilterChips(
                                selected: _filter,
                                onChanged: (f) => setState(() => _filter = f),
                                pendingCount: allItems.length,
                                activityCount: actCount,
                                volunteeringCount: volCount,
                              ),

                              const SizedBox(height: 16),

                              // ── SECTION HEADER ────────────────────────────
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Pending Verifications',
                                      style: TextStyle(
                                        color: _C.text,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: _load,
                                    child: Container(
                                      padding: const EdgeInsets.all(7),
                                      decoration: BoxDecoration(
                                        color: _C.secondary,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: _C.border),
                                      ),
                                      child: const Icon(
                                        Icons.refresh_rounded,
                                        color: _C.muted,
                                        size: 15,
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 12),

                              // ── CARDS / EMPTY STATE ───────────────────────
                              if (allItems.isEmpty)
                                Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 48,
                                    horizontal: 24,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _C.card.withValues(alpha: 0.75),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: _C.border),
                                  ),
                                  child: const Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.check_circle_outline_rounded,
                                        color: _C.neonGreen,
                                        size: 48,
                                      ),
                                      SizedBox(height: 16),
                                      Text(
                                        'All caught up!',
                                        style: TextStyle(
                                          color: _C.text,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      SizedBox(height: 6),
                                      Text(
                                        'No pending verifications at this time.',
                                        style: TextStyle(
                                          color: _C.muted,
                                          fontSize: 13,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                )
                              else if (filtered.isEmpty)
                                Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 32,
                                    horizontal: 24,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _C.card.withValues(alpha: 0.75),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: _C.border),
                                  ),
                                  child: const Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.search_off_rounded,
                                        color: _C.muted,
                                        size: 36,
                                      ),
                                      SizedBox(height: 10),
                                      Text(
                                        'No results found',
                                        style: TextStyle(
                                          color: _C.text,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Try adjusting your search or filter.',
                                        style: TextStyle(
                                          color: _C.muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                ...filtered.map(
                                  (item) =>
                                      _VerifyCard(item: item, onAction: _load),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
