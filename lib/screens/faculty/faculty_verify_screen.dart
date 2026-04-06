// ═══════════════════════════════════════════════════════════════════════════════
// faculty_verify_screen.dart   Route: /faculty/verify
//
// UPGRADE: Full tracking panel with 3 tabs — Pending / Completed / Verified
//
// DATA FLOW:
//   fetchAllItems() fetches ALL applications + ALL enrollments in parallel,
//   then batch-joins users + activities/volunteering (no N+1).
//
// TABS:
//   Pending   → applications: Applied  | enrollments: Enrolled
//   Completed → both:         Completed
//   Verified  → both:         Verified
//
// ACTIONS (Pending tab only):
//   Approve → status = "Approved"   (NO credits, NO certificate)
//   Reject  → status = "Rejected"
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'faculty_dashboard_layout.dart';

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
// TAB ENUM
// ─────────────────────────────────────────────────────────────────────────────
enum _Tab { pending, completed, verified }

extension _TabX on _Tab {
  String get label => switch (this) {
    _Tab.pending => 'Pending',
    _Tab.completed => 'Completed',
    _Tab.verified => 'Verified',
  };

  IconData get icon => switch (this) {
    _Tab.pending => Icons.pending_actions_rounded,
    _Tab.completed => Icons.task_alt_rounded,
    _Tab.verified => Icons.verified_rounded,
  };

  Color get color => switch (this) {
    _Tab.pending => _C.amber,
    _Tab.completed => _C.neonBlue,
    _Tab.verified => _C.neonGreen,
  };

  bool matches(String status, String collection) {
    return switch (this) {
      _Tab.pending =>
        (collection == 'applications' && status == 'Applied') ||
            (collection == 'enrollments' && status == 'Enrolled'),
      _Tab.completed => status == 'Completed',
      _Tab.verified => status == 'Verified',
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODEL
// ─────────────────────────────────────────────────────────────────────────────
class _TrackItem {
  final String docId,
      collection,
      userId,
      userName,
      itemTitle,
      itemType,
      activityType;
  final int credits;
  final String status;
  final DateTime? submittedAt;

  const _TrackItem({
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

  bool get isActivity => itemType == 'Activity';
}

// ─────────────────────────────────────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────────────────────────────────────
class _VerifyService {
  static final _db = FirebaseFirestore.instance;
  static Map<String, dynamic> _safe(DocumentSnapshot doc) =>
      (doc.data() as Map<String, dynamic>?) ?? {};

  // Batch-fetch a collection by document IDs (chunks of 30)
  static Future<Map<String, Map<String, dynamic>>> _batchIds(
    String col,
    Set<String> ids,
  ) async {
    final map = <String, Map<String, dynamic>>{};
    final list = ids.toList();
    for (int i = 0; i < list.length; i += 30) {
      final chunk = list.sublist(i, (i + 30).clamp(0, list.length));
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

  // Fetches ALL applications + ALL enrollments, then batch-joins
  static Future<List<_TrackItem>> fetchAllItems() async {
    // ── Step 1: parallel fetch of all apps + enrolments ──────────────────────
    final results = await Future.wait([
      _db.collection('applications').get(),
      _db.collection('enrollments').get(),
    ]);
    final appSnap = results[0] as QuerySnapshot;
    final enrSnap = results[1] as QuerySnapshot;

    if (appSnap.docs.isEmpty && enrSnap.docs.isEmpty) return [];

    // ── Step 2: collect IDs for secondary batch fetches ───────────────────────
    final userIds = <String>{};
    final volIds = <String>{};
    final actIds = <String>{};

    for (final doc in appSnap.docs) {
      final d = _safe(doc);
      _addIfNotEmpty(userIds, d['userId'] as String?);
      _addIfNotEmpty(volIds, d['volunteeringId'] as String?);
    }
    for (final doc in enrSnap.docs) {
      final d = _safe(doc);
      _addIfNotEmpty(userIds, d['userId'] as String?);
      _addIfNotEmpty(actIds, d['activityId'] as String?);
    }

    // ── Step 3: batch-fetch users + activities + volunteering in parallel ─────
    final batches = await Future.wait([
      userIds.isNotEmpty ? _batchIds('users', userIds) : _empty(),
      volIds.isNotEmpty ? _batchIds('volunteering', volIds) : _empty(),
      actIds.isNotEmpty ? _batchIds('activities', actIds) : _empty(),
    ]);
    final userMap = batches[0];
    final volMap = batches[1];
    final actMap = batches[2];

    String resolveUser(String uid) {
      final d = userMap[uid] ?? {};
      return (d['name'] as String?) ??
          (d['email'] as String?) ??
          uid.substring(0, uid.length.clamp(0, 8));
    }

    // ── Step 4: build list ────────────────────────────────────────────────────
    final items = <_TrackItem>[];

    for (final doc in appSnap.docs) {
      final d = _safe(doc);
      final vid = (d['volunteeringId'] as String?) ?? '';
      final vol = volMap[vid] ?? {};
      final ts = d['appliedAt'];
      final uid = (d['userId'] as String?) ?? '';
      items.add(
        _TrackItem(
          docId: doc.id,
          collection: 'applications',
          userId: uid,
          userName: resolveUser(uid),
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
      final uid = (d['userId'] as String?) ?? '';
      items.add(
        _TrackItem(
          docId: doc.id,
          collection: 'enrollments',
          userId: uid,
          userName: resolveUser(uid),
          itemTitle: (act['title'] as String?) ?? aid,
          itemType: 'Activity',
          activityType: (act['type'] as String?) ?? 'Activity',
          credits: (act['credits'] as int?) ?? 0,
          status: (d['status'] as String?) ?? 'Enrolled',
          submittedAt: ts is Timestamp ? ts.toDate() : null,
        ),
      );
    }

    items.sort((a, b) {
      if (a.submittedAt == null && b.submittedAt == null) return 0;
      if (a.submittedAt == null) return 1;
      if (b.submittedAt == null) return -1;
      return b.submittedAt!.compareTo(a.submittedAt!);
    });
    return items;
  }

  static Future<Map<String, Map<String, dynamic>>> _empty() =>
      Future.value(<String, Map<String, dynamic>>{});

  static void _addIfNotEmpty(Set<String> s, String? v) {
    if (v != null && v.isNotEmpty) s.add(v);
  }

  // Approve: status → "Approved" only; no credits, no certificate
  static Future<void> approve(_TrackItem item) => _db
      .collection(item.collection)
      .doc(item.docId)
      .update({'status': 'Approved'});

  // Reject: status → "Rejected"
  static Future<void> reject(_TrackItem item) => _db
      .collection(item.collection)
      .doc(item.docId)
      .update({'status': 'Rejected'});
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class FacultyVerifyScreen extends StatefulWidget {
  const FacultyVerifyScreen({super.key});
  @override
  State<FacultyVerifyScreen> createState() => _FacultyVerifyScreenState();
}

class _FacultyVerifyScreenState extends State<FacultyVerifyScreen> {
  Future<List<_TrackItem>> _future = Future.value([]);
  _Tab _tab = _Tab.pending;
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  void _load() {
    if (!mounted) return;
    final f = _VerifyService.fetchAllItems();
    _future = f;
    setState(() {});
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<_TrackItem> _filter(List<_TrackItem> all) => all.where((item) {
    final matchTab = _tab.matches(item.status, item.collection);
    final matchSearch =
        _search.isEmpty ||
        item.userName.toLowerCase().contains(_search.toLowerCase()) ||
        item.itemTitle.toLowerCase().contains(_search.toLowerCase());
    return matchTab && matchSearch;
  }).toList();

  int _tabCount(List<_TrackItem> all, _Tab t) =>
      all.where((i) => t.matches(i.status, i.collection)).length;

  @override
  Widget build(BuildContext context) => FacultyDashboardLayout(
    currentRoute: '/faculty/verify',
    userName: '',
    child: FutureBuilder<List<_TrackItem>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 80),
            child: Center(child: CircularProgressIndicator(color: _C.primary)),
          );
        }

        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
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
                    style: const TextStyle(color: _C.muted, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  _RetryBtn(onTap: _load),
                ],
              ),
            ),
          );
        }

        final all = snap.data ?? [];
        final filtered = _filter(all);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Heading
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Verification Panel',
                        style: TextStyle(
                          color: _C.text,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Track and manage all student submissions',
                        style: TextStyle(color: _C.muted, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _load,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _C.secondary,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _C.border),
                    ),
                    child: const Icon(
                      Icons.refresh_rounded,
                      color: _C.muted,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Summary strip
            _SummaryStrip(
              pending: _tabCount(all, _Tab.pending),
              completed: _tabCount(all, _Tab.completed),
              verified: _tabCount(all, _Tab.verified),
            ),
            const SizedBox(height: 16),

            // Status tabs
            _TabBar(
              current: _tab,
              counts: {
                _Tab.pending: _tabCount(all, _Tab.pending),
                _Tab.completed: _tabCount(all, _Tab.completed),
                _Tab.verified: _tabCount(all, _Tab.verified),
              },
              onChanged: (t) => setState(() => _tab = t),
            ),
            const SizedBox(height: 14),

            // Search bar
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
                  const Icon(Icons.search_rounded, color: _C.muted, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(color: _C.text, fontSize: 13),
                      decoration: InputDecoration(
                        hintText:
                            'Search student or ${_tab.label.toLowerCase()} item...',
                        hintStyle: const TextStyle(
                          color: _C.muted,
                          fontSize: 13,
                        ),
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
            const SizedBox(height: 16),

            // Section label
            Row(
              children: [
                Text(
                  _tab.label,
                  style: TextStyle(
                    color: _tab.color,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _tab.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _tab.color.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    '${filtered.length}',
                    style: TextStyle(
                      color: _tab.color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Cards
            if (filtered.isEmpty)
              _EmptyTabBox(tab: _tab)
            else
              ...filtered.map(
                (item) => _TrackCard(item: item, tab: _tab, onAction: _load),
              ),
          ],
        );
      },
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SUMMARY STRIP
// ─────────────────────────────────────────────────────────────────────────────
class _SummaryStrip extends StatelessWidget {
  final int pending, completed, verified;
  const _SummaryStrip({
    required this.pending,
    required this.completed,
    required this.verified,
  });

  @override
  Widget build(BuildContext context) {
    final stats = [
      (
        label: 'Pending',
        value: '$pending',
        icon: Icons.pending_actions_rounded,
        color: _C.amber,
      ),
      (
        label: 'Completed',
        value: '$completed',
        icon: Icons.task_alt_rounded,
        color: _C.neonBlue,
      ),
      (
        label: 'Verified',
        value: '$verified',
        icon: Icons.verified_rounded,
        color: _C.neonGreen,
      ),
    ];
    return Row(
      children: stats
          .asMap()
          .entries
          .map(
            (e) => Expanded(
              child: Container(
                margin: e.key < stats.length - 1
                    ? const EdgeInsets.only(right: 10)
                    : EdgeInsets.zero,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _C.card.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _C.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(e.value.icon, size: 16, color: e.value.color),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        e.value.value,
                        style: const TextStyle(
                          color: _C.text,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      e.value.label,
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
            ),
          )
          .toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB BAR
// ─────────────────────────────────────────────────────────────────────────────
class _TabBar extends StatelessWidget {
  final _Tab current;
  final Map<_Tab, int> counts;
  final ValueChanged<_Tab> onChanged;
  const _TabBar({
    required this.current,
    required this.counts,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
    height: 44,
    decoration: BoxDecoration(
      color: _C.secondary,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _C.border),
    ),
    child: Row(
      children: _Tab.values.map((t) {
        final isActive = current == t;
        final count = counts[t] ?? 0;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(t),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: isActive
                    ? t.color.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
                border: isActive
                    ? Border.all(color: t.color.withValues(alpha: 0.4))
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(t.icon, size: 13, color: isActive ? t.color : _C.muted),
                  const SizedBox(width: 5),
                  Text(
                    t.label,
                    style: TextStyle(
                      color: isActive ? t.color : _C.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: isActive
                            ? t.color.withValues(alpha: 0.25)
                            : _C.border,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          color: isActive ? t.color : _C.muted,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }).toList(),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// TRACK CARD  (adapts content based on tab)
// ─────────────────────────────────────────────────────────────────────────────
class _TrackCard extends StatefulWidget {
  final _TrackItem item;
  final _Tab tab;
  final VoidCallback onAction;
  const _TrackCard({
    required this.item,
    required this.tab,
    required this.onAction,
  });
  @override
  State<_TrackCard> createState() => _TrackCardState();
}

class _TrackCardState extends State<_TrackCard> {
  bool _processing = false;

  Future<void> _act(bool approve) async {
    if (!mounted) return;
    setState(() => _processing = true);
    try {
      if (approve) {
        await _VerifyService.approve(widget.item);
      } else {
        await _VerifyService.reject(widget.item);
      }
      if (mounted) widget.onAction();
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
      if (mounted) setState(() => _processing = false);
    }
  }

  String _timeAgo() {
    if (widget.item.submittedAt == null) return '';
    final diff = DateTime.now().difference(widget.item.submittedAt!);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final tColor = item.isActivity ? _C.primary : _C.neonGreen;

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
          // ── Header ──────────────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                    item.userName.isNotEmpty
                        ? item.userName[0].toUpperCase()
                        : '?',
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
                icon: item.isActivity
                    ? Icons.menu_book_rounded
                    : Icons.eco_rounded,
                label: item.itemType,
                color: tColor,
              ),
              // Current status chip
              _DetailChip(
                icon: Icons.info_outline_rounded,
                label: item.status,
                color: widget.tab.color,
              ),
            ],
          ),

          const SizedBox(height: 14),
          const Divider(color: _C.border, height: 1),
          const SizedBox(height: 14),

          // ── Action area — changes by tab ─────────────────────────────────────
          if (widget.tab == _Tab.pending)
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
                  )
          else if (widget.tab == _Tab.completed)
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: _C.neonBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.hourglass_bottom_rounded,
                    size: 14,
                    color: _C.neonBlue,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Marked as completed — awaiting final verification',
                    style: TextStyle(color: _C.muted, fontSize: 11),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            )
          else // verified
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: _C.neonGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.verified_rounded,
                    size: 14,
                    color: _C.neonGreen,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Verified — final status updated',
                    style: TextStyle(
                      color: _C.neonGreen,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SMALL REUSABLE WIDGETS
// ─────────────────────────────────────────────────────────────────────────────
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

class _RetryBtn extends StatelessWidget {
  final VoidCallback onTap;
  const _RetryBtn({required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_C.primary, _C.neonBlue]),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.refresh_rounded, color: Colors.white, size: 16),
          SizedBox(width: 8),
          Text(
            'Retry',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    ),
  );
}

class _EmptyTabBox extends StatelessWidget {
  final _Tab tab;
  const _EmptyTabBox({required this.tab});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
    decoration: BoxDecoration(
      color: _C.card.withValues(alpha: 0.75),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _C.border),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          tab == _Tab.verified
              ? Icons.verified_rounded
              : tab == _Tab.completed
              ? Icons.task_alt_rounded
              : Icons.check_circle_outline_rounded,
          size: 48,
          color: tab.color.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 16),
        Text(
          tab == _Tab.pending
              ? 'All caught up! No pending items.'
              : tab == _Tab.completed
              ? 'No completed items yet.'
              : 'No verified items yet.',
          style: const TextStyle(
            color: _C.text,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}
