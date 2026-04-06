// ═══════════════════════════════════════════════════════════════════════════════
// student_home.dart   Route: /student
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
}

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────────────────────────────────────────
class _DashData {
  final int totalCredits;
  final int enrollmentsCount;
  final int applicationsCount;
  final int certificatesCount;
  final int rank;
  final List<_EnrolledRow> recentEnrollments;
  final List<_CertRow> recentCerts;

  const _DashData({
    required this.totalCredits,
    required this.enrollmentsCount,
    required this.applicationsCount,
    required this.certificatesCount,
    required this.rank,
    required this.recentEnrollments,
    required this.recentCerts,
  });
}

class _EnrolledRow {
  final String title, date, status, type;
  final int credits;
  const _EnrolledRow({
    required this.title,
    required this.date,
    required this.status,
    required this.type,
    required this.credits,
  });
}

class _CertRow {
  final String title, date, type;
  final int credits;
  const _CertRow({
    required this.title,
    required this.date,
    required this.type,
    required this.credits,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// FIRESTORE SERVICE
// Correct joins:
//   credits       → users/{uid}.credits
//   activity feed → enrollments(userId) → activities(activityId)
//   vol feed      → applications(userId) → volunteering(volunteeringId)
//   cert feed     → certificates(userId) → activities|volunteering(itemId)
// ─────────────────────────────────────────────────────────────────────────────
class _HomeService {
  static final _db = FirebaseFirestore.instance;
  static Map<String, dynamic> _safe(DocumentSnapshot doc) =>
      (doc.data() as Map<String, dynamic>?) ?? {};

  static Future<Map<String, Map<String, dynamic>>> _batchIds(
    String col,
    List<String> ids,
  ) async {
    final result = <String, Map<String, dynamic>>{};
    for (int i = 0; i < ids.length; i += 30) {
      final chunk = ids.sublist(i, (i + 30).clamp(0, ids.length));
      final snap = await _db
          .collection(col)
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snap.docs) {
        result[doc.id] = _safe(doc);
      }
    }
    return result;
  }

  static Future<_DashData> load(String uid) async {
    // ── Step 1: primary parallel fetches ─────────────────────────────────────
    final results = await Future.wait([
      _db
          .collection('enrollments')
          .where('userId', isEqualTo: uid)
          .get(), // [0]
      _db
          .collection('applications')
          .where('userId', isEqualTo: uid)
          .get(), // [1]
      _db
          .collection('certificates')
          .where('userId', isEqualTo: uid)
          .get(), // [2]
      _db.collection('users').doc(uid).get(), // [3]
      _db.collection('users').get(), // [4] rank
    ]);
    final enrSnap = results[0] as QuerySnapshot;
    final appSnap = results[1] as QuerySnapshot;
    final certSnap = results[2] as QuerySnapshot;
    final userDoc = results[3] as DocumentSnapshot;
    final usersSnap = results[4] as QuerySnapshot;

    // Credits come directly from the user doc — no manual calculation
    final userCredits = (_safe(userDoc)['credits'] as int?) ?? 0;

    // ── Step 2: collect IDs ───────────────────────────────────────────────────
    final actIds = enrSnap.docs
        .map((d) => (_safe(d)['activityId'] as String?) ?? '')
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    final volIds = appSnap.docs
        .map((d) => (_safe(d)['volunteeringId'] as String?) ?? '')
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    final certItemIds = certSnap.docs
        .map((d) => (_safe(d)['itemId'] as String?) ?? '')
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();

    // ── Step 3: batch-join in parallel ────────────────────────────────────────
    final joins = await Future.wait([
      actIds.isNotEmpty
          ? _batchIds('activities', actIds)
          : Future.value(<String, Map<String, dynamic>>{}),
      volIds.isNotEmpty
          ? _batchIds('volunteering', volIds)
          : Future.value(<String, Map<String, dynamic>>{}),
      certItemIds.isNotEmpty
          ? _batchIds('activities', certItemIds)
          : Future.value(<String, Map<String, dynamic>>{}),
      certItemIds.isNotEmpty
          ? _batchIds('volunteering', certItemIds)
          : Future.value(<String, Map<String, dynamic>>{}),
    ]);
    final actMap = joins[0];
    final volMap = joins[1];
    final certActMap = joins[2];
    final certVolMap = joins[3];

    // ── Step 4: rank ──────────────────────────────────────────────────────────
    int rank = 1;
    for (final doc in usersSnap.docs) {
      if (doc.id == uid) continue;
      if (((_safe(doc)['credits'] as int?) ?? 0) > userCredits) rank++;
    }

    // ── Step 5: enrollment feed (activities) — latest 5 ──────────────────────
    int cmpTs(Timestamp? a, Timestamp? b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return b.compareTo(a);
    }

    final sortedEnr = [...enrSnap.docs]
      ..sort(
        (a, b) => cmpTs(
          _safe(a)['appliedAt'] as Timestamp?,
          _safe(b)['appliedAt'] as Timestamp?,
        ),
      );
    final enrRows = sortedEnr.take(5).map((doc) {
      final d = _safe(doc);
      final aid = (d['activityId'] as String?) ?? '';
      final act = actMap[aid] ?? {};
      return _EnrolledRow(
        title: (act['title'] as String?) ?? aid,
        date: (act['date'] as String?) ?? '',
        status: (d['status'] as String?) ?? '',
        type: (act['type'] as String?) ?? 'Activity',
        credits: (act['credits'] as int?) ?? 0,
      );
    }).toList();

    // Volunteering applications — latest 3
    final sortedApp = [...appSnap.docs]
      ..sort(
        (a, b) => cmpTs(
          _safe(a)['appliedAt'] as Timestamp?,
          _safe(b)['appliedAt'] as Timestamp?,
        ),
      );
    final appRows = sortedApp.take(3).map((doc) {
      final d = _safe(doc);
      final vid = (d['volunteeringId'] as String?) ?? '';
      final vol = volMap[vid] ?? {};
      return _EnrolledRow(
        title: (vol['title'] as String?) ?? vid,
        date: (vol['date'] as String?) ?? '',
        status: (d['status'] as String?) ?? '',
        type: (vol['category'] as String?) ?? 'Volunteering',
        credits: (vol['credits'] as int?) ?? 0,
      );
    }).toList();

    final recentEnrollments = [...enrRows, ...appRows];

    // ── Step 6: cert feed — latest 3 ─────────────────────────────────────────
    final sortedCerts = [...certSnap.docs]
      ..sort(
        (a, b) => cmpTs(
          _safe(a)['createdAt'] as Timestamp?,
          _safe(b)['createdAt'] as Timestamp?,
        ),
      );

    final recentCerts = sortedCerts.take(3).map((doc) {
      final d = _safe(doc);
      final itemId = (d['itemId'] as String?) ?? '';
      final type = (d['type'] as String?) ?? 'activity';
      final item = type == 'activity'
          ? (certActMap[itemId] ?? {})
          : (certVolMap[itemId] ?? {});
      final ts = d['createdAt'];
      String date = '';
      if (ts is Timestamp) {
        final dt = ts.toDate();
        date =
            '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
      }
      return _CertRow(
        title: (item['title'] as String?) ?? itemId,
        date: date,
        type: type,
        credits: (d['credits'] as int?) ?? 0,
      );
    }).toList();

    return _DashData(
      totalCredits: userCredits,
      enrollmentsCount: enrSnap.docs.length,
      applicationsCount: appSnap.docs.length,
      certificatesCount: certSnap.docs.length,
      rank: rank,
      recentEnrollments: recentEnrollments,
      recentCerts: recentCerts,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED WIDGETS
// ─────────────────────────────────────────────────────────────────────────────
class _GlassCard extends StatelessWidget {
  final Widget child;
  final Color? glowColor;
  final VoidCallback? onTap;

  const _GlassCard({
    required this.child,
    this.glowColor,
    this.onTap, // ✅ FIXED
  });

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _C.card.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.border),
        boxShadow: glowColor != null
            ? [
                BoxShadow(
                  color: glowColor!.withValues(alpha: 0.18),
                  blurRadius: 18,
                ),
              ]
            : [],
      ),
      child: child,
    );

    return onTap == null ? box : GestureDetector(onTap: onTap, child: box);
  }
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final String? sub;
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.sub,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _C.card.withValues(alpha: 0.7),
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
                color: _C.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: _C.primary, size: 15),
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
        if (sub != null) ...[
          const SizedBox(height: 4),
          Text(
            sub!,
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

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  Color _color() {
    switch (status.toLowerCase()) {
      case 'verified':
        return _C.neonCyan;
      case 'completed':
        return _C.neonGreen;
      case 'approved':
        return _C.amber;
      default:
        return _C.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _color();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Text(
        status.isNotEmpty ? status : 'Pending',
        style: TextStyle(color: c, fontSize: 9, fontWeight: FontWeight.w700),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool outlined;
  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.onTap,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 44,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        gradient: outlined
            ? null
            : const LinearGradient(colors: [_C.primary, _C.neonBlue]),
        borderRadius: BorderRadius.circular(12),
        border: outlined ? Border.all(color: _C.primary, width: 1.4) : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: outlined ? _C.primary : Colors.white, size: 16),
          const SizedBox(width: 6),
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
  );
}

class _ProgressBar extends StatelessWidget {
  final int earned, total;
  const _ProgressBar({required this.earned, required this.total});

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? (earned / total).clamp(0.0, 1.0) : 0.0;
    return _GlassCard(
      glowColor: _C.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Credit Progress',
                style: TextStyle(
                  color: _C.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              Text(
                '$earned / $total',
                style: const TextStyle(color: _C.muted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (_, c) => ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 10,
                width: c.maxWidth,
                child: Stack(
                  children: [
                    Container(color: _C.border),
                    FractionallySizedBox(
                      widthFactor: pct,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [_C.primary, _C.neonBlue],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            earned >= total
                ? 'Graduation requirement met! 🎉'
                : '${total - earned} more credits needed',
            style: const TextStyle(color: _C.muted, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _EnrollmentTile extends StatelessWidget {
  final _EnrolledRow item;
  const _EnrollmentTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final isVol = item.type.toLowerCase().contains('vol');
    final ic = isVol ? _C.neonGreen : _C.primary;
    return _GlassCard(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: ic.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isVol ? Icons.eco_rounded : Icons.menu_book_rounded,
              color: ic,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
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
                const SizedBox(height: 3),
                Text(
                  '${item.type} · ${item.date}',
                  style: const TextStyle(color: _C.muted, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '+${item.credits}',
                style: const TextStyle(
                  color: _C.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 6),
              _StatusBadge(status: item.status),
            ],
          ),
        ],
      ),
    );
  }
}

class _CertTile extends StatelessWidget {
  final _CertRow item;
  const _CertTile({required this.item});

  @override
  Widget build(BuildContext context) => _GlassCard(
    glowColor: _C.neonCyan,
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _C.neonCyan.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.workspace_premium_rounded,
            color: _C.neonCyan,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
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
              const SizedBox(height: 3),
              Text(
                '${item.type} · ${item.date}',
                style: const TextStyle(color: _C.muted, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '+${item.credits}',
              style: const TextStyle(
                color: _C.amber,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _C.neonCyan.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _C.neonCyan.withValues(alpha: 0.3)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_rounded, size: 9, color: _C.neonCyan),
                  SizedBox(width: 3),
                  Text(
                    'Issued',
                    style: TextStyle(
                      color: _C.neonCyan,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _DIDCard extends StatelessWidget {
  final String uid;
  const _DIDCard({required this.uid});

  @override
  Widget build(BuildContext context) {
    final short = uid.length >= 12
        ? '${uid.substring(0, 8)}...${uid.substring(uid.length - 4)}'
        : uid;
    final did = uid.isNotEmpty ? 'did:ethr:0x$short' : 'did:ethr:0x---';
    return _GlassCard(
      glowColor: _C.primary,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_C.primary, _C.neonCyan],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: Text(
                'DID',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Decentralized Identity',
                  style: TextStyle(
                    color: _C.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  did,
                  style: const TextStyle(
                    color: _C.muted,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: _C.neonCyan.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _C.neonCyan.withValues(alpha: 0.4)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_rounded, size: 11, color: _C.neonCyan),
                SizedBox(width: 4),
                Text(
                  'Verified',
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

class _EmptySection extends StatelessWidget {
  final String message;
  const _EmptySection({required this.message});

  @override
  Widget build(BuildContext context) => _GlassCard(
    child: Row(
      children: [
        const Icon(Icons.inbox_rounded, color: _C.muted, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: _C.muted, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN
// No Scaffold — StudentDashboardLayout owns Scaffold + scroll
// ─────────────────────────────────────────────────────────────────────────────
class StudentHome extends StatefulWidget {
  const StudentHome({super.key});
  @override
  State<StudentHome> createState() => _StudentHomeState();
}

class _StudentHomeState extends State<StudentHome> {
  Future<_DashData> _future = Future.value(
    const _DashData(
      totalCredits: 0,
      enrollmentsCount: 0,
      applicationsCount: 0,
      certificatesCount: 0,
      rank: 0,
      recentEnrollments: [],
      recentCerts: [],
    ),
  );
  String _userName = '';
  String _uid = '';

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
      final name = ((doc.data() ?? {})['name'] as String?) ?? '';
      if (name.isNotEmpty) setState(() => _userName = name);
    });

    final f = _HomeService.load(_uid);
    _future = f;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => StudentDashboardLayout(
    currentRoute: '/student',
    userName: _userName,
    child: FutureBuilder<_DashData>(
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
                    style: const TextStyle(color: _C.muted, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: _init,
                    child: Container(
                      height: 44,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_C.primary, _C.neonBlue],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
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
          );
        }

        final data = snap.data!;
        const required = 60;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Greeting
            Text(
              'Welcome back, ${_userName.isNotEmpty ? _userName : 'Student'} 👋',
              style: const TextStyle(
                color: _C.text,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Track your activities and blockchain-verified credentials',
              style: TextStyle(color: _C.muted, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),

            // Quick actions
            Row(
              children: [
                Expanded(
                  child: _ActionBtn(
                    label: 'Apply Volunteering',
                    icon: Icons.eco_rounded,
                    onTap: () => Navigator.pushReplacementNamed(
                      context,
                      '/student/volunteering',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionBtn(
                    label: 'Enroll Activity',
                    icon: Icons.flash_on_rounded,
                    outlined: true,
                    onTap: () => Navigator.pushReplacementNamed(
                      context,
                      '/student/activities',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Stat grid (2-column)
            LayoutBuilder(
              builder: (_, c) {
                const gap = 10.0;
                final w = (c.maxWidth - gap) / 2;
                final stats = [
                  (
                    label: 'Total Credits',
                    value: '${data.totalCredits}',
                    icon: Icons.star_rounded,
                    sub: '↑ from profile',
                  ),
                  (
                    label: 'Activities',
                    value: '${data.enrollmentsCount}',
                    icon: Icons.menu_book_rounded,
                    sub: 'enrolled',
                  ),
                  (
                    label: 'Volunteering',
                    value: '${data.applicationsCount}',
                    icon: Icons.eco_rounded,
                    sub: 'applied',
                  ),
                  (
                    label: 'Certificates',
                    value: '${data.certificatesCount}',
                    icon: Icons.workspace_premium_rounded,
                    sub: 'earned',
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
                            sub: s.sub,
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 10),

            // Rank full-width
            _StatCard(
              label: 'Rank',
              value: '#${data.rank}',
              icon: Icons.trending_up_rounded,
              sub: 'among all students',
            ),
            const SizedBox(height: 20),

            // Credit progress
            _ProgressBar(earned: data.totalCredits, total: required),
            const SizedBox(height: 20),

            // Recent activity feed
            const Text(
              'Recent Activities',
              style: TextStyle(
                color: _C.text,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 10),
            data.recentEnrollments.isEmpty
                ? const _EmptySection(
                    message: 'No activities yet. Enroll to earn credits!',
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: data.recentEnrollments
                        .map((e) => _EnrollmentTile(item: e))
                        .toList(),
                  ),
            const SizedBox(height: 20),

            // Digital certificates
            const Text(
              'Digital Certificates',
              style: TextStyle(
                color: _C.text,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 10),
            data.recentCerts.isEmpty
                ? const _EmptySection(
                    message:
                        'No certificates yet. Complete activities to earn them!',
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: data.recentCerts
                        .map((c) => _CertTile(item: c))
                        .toList(),
                  ),

            if (data.recentCerts.isNotEmpty) ...[
              const SizedBox(height: 4),
              _ActionBtn(
                label: 'View All Certificates',
                icon: Icons.arrow_forward_rounded,
                outlined: true,
                onTap: () => Navigator.pushReplacementNamed(
                  context,
                  '/student/certificates',
                ),
              ),
            ],
            const SizedBox(height: 20),

            // Blockchain summary
            _GlassCard(
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _C.neonCyan.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.shield_rounded,
                      color: _C.neonCyan,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '🔗 Blockchain Records',
                          style: TextStyle(
                            color: _C.text,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Your on-chain academic footprint',
                          style: TextStyle(color: _C.muted, fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${data.enrollmentsCount + data.applicationsCount}',
                        style: const TextStyle(
                          color: _C.text,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                      const Text(
                        'On-Chain',
                        style: TextStyle(color: _C.muted, fontSize: 9),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${data.certificatesCount}',
                        style: const TextStyle(
                          color: _C.neonCyan,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                      const Text(
                        'Certified',
                        style: TextStyle(color: _C.muted, fontSize: 9),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // DID badge
            _DIDCard(uid: _uid),
          ],
        );
      },
    ),
  );
}
