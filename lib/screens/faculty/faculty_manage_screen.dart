// ═══════════════════════════════════════════════════════════════════════════════
// faculty_manage_screen.dart   Route: /faculty/manage
//
// FIX: Status filter chips now use exact Firestore status values.
//   BEFORE: ['All','active','open','completed','verified','full']
//           → comparison against Firestore values like 'Enrolled', 'Completed' failed
//   AFTER:  ['All','Enrolled','Applied','Completed','Approved','Verified','open','full']
//           matching the real values stored in activities.status and the
//           broader item status field.
//   Also fixed: _applyFilter uses exact string match (not toLowerCase).
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  static const text = Color(0xFFEFF3F8);
  static const muted = Color(0xFF7E8A9A);
  static const border = Color(0xFF1F2937);
  static const secondary = Color(0xFF1A2235);
}

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODEL
// ─────────────────────────────────────────────────────────────────────────────
class _ManageItem {
  final String id, title, type, status, date, department;
  final int credits, participants, capacity;
  final bool blockchainVerified, isActivity;

  const _ManageItem({
    required this.id,
    required this.title,
    required this.type,
    required this.status,
    required this.date,
    required this.department,
    required this.credits,
    required this.participants,
    required this.capacity,
    required this.blockchainVerified,
    required this.isActivity,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// FIRESTORE SERVICE
// ─────────────────────────────────────────────────────────────────────────────
class _ManageService {
  static final _db = FirebaseFirestore.instance;
  static Map<String, dynamic> _safe(DocumentSnapshot doc) =>
      (doc.data() as Map<String, dynamic>?) ?? {};

  static Future<List<_ManageItem>> loadActivities(String uid) async {
    final snap = await _db
        .collection('activities')
        .where('createdBy', isEqualTo: uid)
        .get();
    return snap.docs.map((doc) {
      final d = _safe(doc);
      return _ManageItem(
        id: doc.id,
        title: (d['title'] as String?) ?? '',
        type: (d['type'] as String?) ?? '',
        status: (d['status'] as String?) ?? 'open',
        date: (d['date'] as String?) ?? '',
        department: (d['department'] as String?) ?? '',
        credits: (d['credits'] as int?) ?? 0,
        participants: (d['enrolled'] as int?) ?? 0,
        capacity: (d['capacity'] as int?) ?? 0,
        blockchainVerified: (d['blockchainVerified'] as bool?) ?? false,
        isActivity: true,
      );
    }).toList()..sort((a, b) => b.date.compareTo(a.date));
  }

  static Future<List<_ManageItem>> loadVolunteering(String uid) async {
    final snap = await _db
        .collection('volunteering')
        .where('createdBy', isEqualTo: uid)
        .get();
    return snap.docs.map((doc) {
      final d = _safe(doc);
      return _ManageItem(
        id: doc.id,
        title: (d['title'] as String?) ?? '',
        type: (d['category'] as String?) ?? '',
        status: (d['status'] as String?) ?? 'open',
        date: (d['date'] as String?) ?? '',
        department: (d['organization'] as String?) ?? '',
        credits: (d['credits'] as int?) ?? 0,
        participants: (d['currentParticipants'] as int?) ?? 0,
        capacity: (d['maxParticipants'] as int?) ?? 0,
        blockchainVerified: (d['blockchainCert'] as bool?) ?? false,
        isActivity: false,
      );
    }).toList()..sort((a, b) => b.date.compareTo(a.date));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED WIDGETS
// ─────────────────────────────────────────────────────────────────────────────
class _GlassCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _GlassCard({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _C.card..withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _C.border),
      ),
      child: child,
    );
    return onTap == null ? box : GestureDetector(onTap: onTap, child: box);
  }
}

Color _statusColor(String s) {
  switch (s) {
    case 'active':
    case 'open':
      return _C.neonGreen;
    case 'Verified':
      return _C.neonCyan;
    case 'Completed':
    case 'Approved':
      return _C.amber;
    case 'Enrolled':
    case 'Applied':
      return _C.primary;
    case 'full':
      return _C.muted;
    default:
      return _C.muted;
  }
}

Widget _statusBadge(String status) {
  final color = _statusColor(status);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Text(
      status.toUpperCase(),
      style: TextStyle(
        color: color,
        fontSize: 9,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class FacultyManageScreen extends StatefulWidget {
  const FacultyManageScreen({super.key});
  @override
  State<FacultyManageScreen> createState() => _FacultyManageScreenState();
}

class _FacultyManageScreenState extends State<FacultyManageScreen> {
  bool _isActivity = true;
  String _search = '';
  String _filter = 'All';
  String _uid = '';
  String _displayName = '';

  Future<List<_ManageItem>> _future = Future.value([]);
  final _searchCtrl = TextEditingController();

  // ── FIX: exact Firestore status values, case-sensitive ────────────────────
  // Filters against activities/volunteering .status field only.
  // Enrollment-level statuses (Enrolled, Approved, etc.) belong on the
  // detail screen, not here.
  final _statusFilters = ['All', 'open', 'full'];

  @override
  void initState() {
    super.initState();
    Future.microtask(_init);
  }

  void _init() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) return;
    _uid = user.uid;
    FirebaseFirestore.instance.collection('users').doc(_uid).get().then((doc) {
      if (!mounted) return;
      final name = (doc.data()?['name'] as String?) ?? '';
      if (name.isNotEmpty) setState(() => _displayName = name);
    });
    _load();
  }

  void _load() {
    if (!mounted) return;
    final f = _isActivity
        ? _ManageService.loadActivities(_uid)
        : _ManageService.loadVolunteering(_uid);
    _future = f;
    setState(() {});
  }

  void _switchTab(bool isActivity) {
    if (_isActivity == isActivity) return;
    _isActivity = isActivity;
    _filter = 'All';
    _search = '';
    _searchCtrl.clear();
    _load();
  }

  // ── FIX: exact match — no toLowerCase ────────────────────────────────────
  List<_ManageItem> _applyFilter(List<_ManageItem> items) =>
      items.where((item) {
        final matchSearch =
            _search.isEmpty ||
            item.title.toLowerCase().contains(_search.toLowerCase()) ||
            item.department.toLowerCase().contains(_search.toLowerCase());
        final matchFilter = _filter == 'All' || item.status == _filter;
        return matchSearch && matchFilter;
      }).toList();

  void _goToDetail(_ManageItem item) => Navigator.pushNamed(
    context,
    '/faculty/manage/detail',
    arguments: {'id': item.id, 'isActivity': item.isActivity},
  );

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FacultyDashboardLayout(
    currentRoute: '/faculty/manage',
    userName: _displayName,
    child: FutureBuilder<List<_ManageItem>>(
      future: _future,
      builder: (context, snap) {
        final allItems = snap.data ?? [];
        final filtered = _applyFilter(allItems);
        final isLoading = snap.connectionState == ConnectionState.waiting;

        final totalParticipants = allItems.fold(
          0,
          (s, i) => s + i.participants,
        );
        final activeCount = allItems
            .where((i) => i.status == 'active' || i.status == 'open')
            .length;
        final totalCredits = allItems.fold(0, (s, i) => s + i.credits);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Heading
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Manage',
                        style: TextStyle(
                          color: _C.text,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'View and manage all your ${_isActivity ? 'activities' : 'volunteering'}',
                        style: const TextStyle(color: _C.muted, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pushNamed(
                    context,
                    _isActivity
                        ? '/faculty/create'
                        : '/faculty/volunteering/create',
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_C.primary, _C.neonBlue],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.add_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _isActivity
                              ? 'Create Activity'
                              : 'Create Volunteering',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Tabs
            Container(
              height: 42,
              decoration: BoxDecoration(
                color: _C.secondary,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _C.border),
              ),
              child: Row(
                children: [
                  _TabButton(
                    label: 'Activities',
                    icon: Icons.menu_book_rounded,
                    isActive: _isActivity,
                    onTap: () => _switchTab(true),
                  ),
                  _TabButton(
                    label: 'Volunteering',
                    icon: Icons.eco_rounded,
                    isActive: !_isActivity,
                    onTap: () => _switchTab(false),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Stats
            LayoutBuilder(
              builder: (ctx, c) {
                const gap = 10.0;
                final w = (c.maxWidth - gap * 3) / 4;
                final stats = [
                  (
                    label: 'Total',
                    value: '${allItems.length}',
                    icon: Icons.folder_rounded,
                    color: _C.primary,
                  ),
                  (
                    label: 'Active',
                    value: '$activeCount',
                    icon: Icons.play_circle_rounded,
                    color: _C.neonCyan,
                  ),
                  (
                    label: 'Participants',
                    value: '$totalParticipants',
                    icon: Icons.people_rounded,
                    color: _C.neonBlue,
                  ),
                  (
                    label: 'Credits',
                    value: '$totalCredits',
                    icon: Icons.star_rounded,
                    color: _C.amber,
                  ),
                ];
                return Row(
                  children: stats.asMap().entries.map((e) {
                    final s = e.value;
                    return Container(
                      width: w,
                      margin: e.key < stats.length - 1
                          ? const EdgeInsets.only(right: gap)
                          : EdgeInsets.zero,
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 10,
                      ),
                      decoration: BoxDecoration(
                        color: _C.card.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _C.border),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(s.icon, size: 15, color: s.color),
                          const SizedBox(height: 6),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              s.value,
                              style: const TextStyle(
                                color: _C.text,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Text(
                            s.label,
                            style: const TextStyle(
                              color: _C.muted,
                              fontSize: 9,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 16),

            // Search
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
                            'Search ${_isActivity ? 'activities' : 'volunteering'}...',
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
            const SizedBox(height: 10),

            // Filter chips — exact Firestore values
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _statusFilters.map((f) {
                  final isActive = _filter == f;
                  return GestureDetector(
                    onTap: () => setState(() => _filter = f),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 8),
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
                        f,
                        style: TextStyle(
                          color: isActive ? _C.primary : _C.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),

            // List
            if (isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: CircularProgressIndicator(color: _C.primary),
                ),
              )
            else if (snap.hasError)
              _ErrorBox(onRetry: _load)
            else if (filtered.isEmpty)
              _EmptyBox(isActivity: _isActivity)
            else
              ...filtered.map(
                (item) => _ItemCard(item: item, onTap: () => _goToDetail(item)),
              ),
          ],
        );
      },
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB BUTTON
// ─────────────────────────────────────────────────────────────────────────────
class _TabButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;
  const _TabButton({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: isActive
              ? _C.primary.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: isActive
              ? Border.all(color: _C.primary.withValues(alpha: 0.4))
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: isActive ? _C.primary : _C.muted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isActive ? _C.primary : _C.muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// ITEM CARD
// ─────────────────────────────────────────────────────────────────────────────
class _ItemCard extends StatelessWidget {
  final _ManageItem item;
  final VoidCallback onTap;
  const _ItemCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fillPct = item.capacity > 0
        ? (item.participants / item.capacity).clamp(0.0, 1.0)
        : 0.0;

    return _GlassCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: (item.isActivity ? _C.primary : _C.neonGreen)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  item.isActivity ? Icons.menu_book_rounded : Icons.eco_rounded,
                  size: 18,
                  color: item.isActivity ? _C.primary : _C.neonGreen,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        color: _C.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        _MetaChip(
                          icon: Icons.calendar_today_rounded,
                          label: item.date,
                        ),
                        _MetaChip(
                          icon: Icons.star_rounded,
                          label: '${item.credits} credits',
                          color: _C.primary,
                        ),
                        _MetaChip(
                          icon: Icons.people_rounded,
                          label: '${item.participants}/${item.capacity}',
                        ),
                        if (item.department.isNotEmpty)
                          _MetaChip(
                            icon: Icons.business_rounded,
                            label: item.department,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _statusBadge(item.status),
                  if (item.blockchainVerified) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _C.neonCyan.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _C.neonCyan.withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.verified_rounded,
                            size: 9,
                            color: _C.neonCyan,
                          ),
                          SizedBox(width: 3),
                          Text(
                            'Chain',
                            style: TextStyle(
                              color: _C.neonCyan,
                              fontSize: 8,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 5,
                    child: Stack(
                      children: [
                        Container(color: _C.secondary),
                        FractionallySizedBox(
                          widthFactor: fillPct,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: fillPct >= 1.0
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
              const SizedBox(width: 8),
              Text(
                '${(fillPct * 100).round()}%',
                style: const TextStyle(color: _C.muted, fontSize: 9),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: _C.muted,
              ),
            ],
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
    this.color = _C.muted,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 11, color: color),
      const SizedBox(width: 3),
      Text(label, style: TextStyle(color: color, fontSize: 10)),
    ],
  );
}

class _ErrorBox extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorBox({required this.onRetry});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
    decoration: BoxDecoration(
      color: _C.card.withValues(alpha: 0.75),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _C.border),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.error_outline_rounded,
          color: Colors.redAccent,
          size: 36,
        ),
        const SizedBox(height: 12),
        const Text(
          'Failed to load data',
          style: TextStyle(
            color: _C.text,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: onRetry,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_C.primary, _C.neonBlue]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.refresh_rounded, color: Colors.white, size: 14),
                SizedBox(width: 6),
                Text(
                  'Retry',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
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

class _EmptyBox extends StatelessWidget {
  final bool isActivity;
  const _EmptyBox({required this.isActivity});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
    decoration: BoxDecoration(
      color: _C.card.withValues(alpha: 0.75),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _C.border),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isActivity ? Icons.menu_book_rounded : Icons.eco_rounded,
          size: 40,
          color: _C.muted,
        ),
        const SizedBox(height: 12),
        Text(
          'No ${isActivity ? 'activities' : 'volunteering'} found',
          style: const TextStyle(
            color: _C.text,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Try adjusting your search or filter',
          style: TextStyle(color: _C.muted, fontSize: 12),
        ),
      ],
    ),
  );
}
