// ═══════════════════════════════════════════════════════════════════════════════
// student_profile_screen.dart   Route: /student/profile
//
// Data flow:
//   Future.wait → users/{uid}, applications, enrollments, certificates
//   Batch-join   → activities (from enrollments) + volunteering (from applications)
//                + item titles for certificates
//   Stats        → totalCredits = users/{uid}.credits  (SINGLE SOURCE OF TRUTH)
//                  activitiesCount = enrollments.length
//                  volunteeringCount = applications.length
//                  certificatesCount = certificates.length
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'student_dashboard_layout.dart';

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
// DATA MODELS
// ─────────────────────────────────────────────────────────────────────────────
class _ProfileData {
  final String name, email, department, did;
  final int totalCredits, activitiesCount, volunteeringCount, certificatesCount;
  final List<_ActivityRow> recentActivity;
  final List<_CertPreviewRow> recentCerts;

  const _ProfileData({
    required this.name,
    required this.email,
    required this.department,
    required this.did,
    required this.totalCredits,
    required this.activitiesCount,
    required this.volunteeringCount,
    required this.certificatesCount,
    required this.recentActivity,
    required this.recentCerts,
  });
}

class _ActivityRow {
  final String title, type, status, date;
  const _ActivityRow({
    required this.title,
    required this.type,
    required this.status,
    required this.date,
  });
}

class _CertPreviewRow {
  final String title, type, date;
  final int credits;
  final bool hasHash;
  const _CertPreviewRow({
    required this.title,
    required this.type,
    required this.date,
    required this.credits,
    required this.hasHash,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// FIRESTORE SERVICE
// ─────────────────────────────────────────────────────────────────────────────
class _ProfileService {
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
      for (final doc in snap.docs) result[doc.id] = _safe(doc);
    }
    return result;
  }

  static Future<_ProfileData> load(String uid) async {
    // Step 1: parallel primary fetches
    final results = await Future.wait([
      _db.collection('users').doc(uid).get(),
      _db.collection('applications').where('userId', isEqualTo: uid).get(),
      _db.collection('enrollments').where('userId', isEqualTo: uid).get(),
      _db.collection('certificates').where('userId', isEqualTo: uid).get(),
    ]);
    final userDoc = results[0] as DocumentSnapshot;
    final appSnap = results[1] as QuerySnapshot;
    final enrSnap = results[2] as QuerySnapshot;
    final certSnap = results[3] as QuerySnapshot;

    final ud = _safe(userDoc);
    final name = (ud['name'] as String?) ?? '';
    final email = (ud['email'] as String?) ?? '';
    final department = (ud['department'] as String?) ?? '';
    final did = uid.length >= 12
        ? 'did:ethr:0x${uid.substring(0, 8)}...${uid.substring(uid.length - 4)}'
        : 'did:ethr:0x---';

    // Step 2: collect IDs
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

    // Step 3: batch-join in parallel
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

    // Step 4: credits — single source of truth: users/{uid}.credits
    // Certificates are used for display only, NOT for credit calculation.
    final totalCredits = (ud['credits'] as int?) ?? 0;

    // Step 5: recent activity
    String fmtTs(dynamic ts) {
      if (ts is! Timestamp) return '';
      final dt = ts.toDate();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    }

    final combined = <(DateTime, _ActivityRow)>[];
    for (final doc in enrSnap.docs) {
      final d = _safe(doc);
      final aid = (d['activityId'] as String?) ?? '';
      final act = actMap[aid] ?? {};
      final ts = d['appliedAt'];
      final dt = ts is Timestamp ? ts.toDate() : DateTime(2000);
      combined.add((
        dt,
        _ActivityRow(
          title: (act['title'] as String?) ?? aid,
          type: (act['type'] as String?) ?? 'Activity',
          status: (d['status'] as String?) ?? '',
          date: fmtTs(ts),
        ),
      ));
    }
    for (final doc in appSnap.docs) {
      final d = _safe(doc);
      final vid = (d['volunteeringId'] as String?) ?? '';
      final vol = volMap[vid] ?? {};
      final ts = d['appliedAt'];
      final dt = ts is Timestamp ? ts.toDate() : DateTime(2000);
      combined.add((
        dt,
        _ActivityRow(
          title: (vol['title'] as String?) ?? vid,
          type: (vol['category'] as String?) ?? 'Volunteering',
          status: (d['status'] as String?) ?? '',
          date: fmtTs(ts),
        ),
      ));
    }
    combined.sort((a, b) => b.$1.compareTo(a.$1));
    final recentActivity = combined.take(5).map((e) => e.$2).toList();

    // Step 6: latest 3 certificates
    final sortedCerts = [...certSnap.docs]
      ..sort((a, b) {
        final ta = _safe(a)['createdAt'];
        final tb = _safe(b)['createdAt'];
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return (tb as Timestamp).compareTo(ta as Timestamp);
      });

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
      return _CertPreviewRow(
        title: (item['title'] as String?) ?? itemId,
        type: type,
        date: date,
        credits: (d['credits'] as int?) ?? 0,
        hasHash: (d['blockchainHash'] as String?) != null,
      );
    }).toList();

    return _ProfileData(
      name: name,
      email: email,
      department: department,
      did: did,
      totalCredits: totalCredits,
      activitiesCount: enrSnap.docs.length,
      volunteeringCount: appSnap.docs.length,
      certificatesCount: certSnap.docs.length,
      recentActivity: recentActivity,
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
  final EdgeInsets? padding;
  const _GlassCard({required this.child, this.glowColor, this.padding});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: padding ?? const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _C.card.withValues(alpha: 0.75),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: glowColor?.withValues(alpha: 0.4) ?? _C.border),
      boxShadow: glowColor != null
          ? [
              BoxShadow(
                color: glowColor!.withValues(alpha: 0.15),
                blurRadius: 14,
              ),
            ]
          : [],
    ),
    child: child,
  );
}

Color _statusColor(String s) {
  switch (s.toLowerCase()) {
    case 'enrolled':
      return _C.primary;
    case 'applied':
      return _C.neonBlue;
    case 'approved':
      return _C.neonBlue;
    case 'completed':
      return _C.amber;
    case 'verified':
      return _C.neonGreen;
    case 'rejected':
      return _C.rose;
    default:
      return _C.muted;
  }
}

Widget _statusBadge(String status) {
  final color = _statusColor(status);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Text(
      status.isNotEmpty ? status : 'Pending',
      style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  const _SectionHeader({
    required this.icon,
    required this.color,
    required this.title,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: _C.text,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
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
// ─────────────────────────────────────────────────────────────────────────────
class StudentProfileScreen extends StatefulWidget {
  const StudentProfileScreen({super.key});
  @override
  State<StudentProfileScreen> createState() => _StudentProfileScreenState();
}

class _StudentProfileScreenState extends State<StudentProfileScreen> {
  Future<_ProfileData> _future = Future.value(
    const _ProfileData(
      name: '',
      email: '',
      department: '',
      did: '',
      totalCredits: 0,
      activitiesCount: 0,
      volunteeringCount: 0,
      certificatesCount: 0,
      recentActivity: [],
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
    final f = _ProfileService.load(_uid);
    _future = f;
    f.then((data) {
      if (mounted) setState(() => _userName = data.name);
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => StudentDashboardLayout(
    currentRoute: '/student/profile',
    userName: _userName,
    child: FutureBuilder<_ProfileData>(
      future: _future,
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
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: Colors.redAccent,
                    size: 36,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    snap.error.toString(),
                    style: const TextStyle(color: _C.muted, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: _init,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_C.primary, _C.neonBlue],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.refresh_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                          SizedBox(width: 6),
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

        final d = snap.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── A. Profile header ────────────────────────────────────────────
            _GlassCard(
              glowColor: _C.primary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_C.primary, _C.neonBlue],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Center(
                          child: Text(
                            d.name.isNotEmpty ? d.name[0].toUpperCase() : 'S',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 26,
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
                            Text(
                              d.name.isNotEmpty ? d.name : 'Student',
                              style: const TextStyle(
                                color: _C.text,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              d.email,
                              style: const TextStyle(
                                color: _C.muted,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (d.department.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                d.department,
                                style: const TextStyle(
                                  color: _C.muted,
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${d.totalCredits}',
                            style: const TextStyle(
                              color: _C.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 28,
                            ),
                          ),
                          const Text(
                            'credits',
                            style: TextStyle(color: _C.muted, fontSize: 9),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Divider(color: _C.border, height: 1),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.shield_rounded,
                        size: 13,
                        color: _C.neonCyan,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          d.did,
                          style: const TextStyle(
                            color: _C.neonCyan,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _C.neonGreen.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _C.neonGreen.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.verified_rounded,
                              size: 9,
                              color: _C.neonGreen,
                            ),
                            SizedBox(width: 3),
                            Text(
                              'Verified',
                              style: TextStyle(
                                color: _C.neonGreen,
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
            ),

            // ── B. Stats grid ────────────────────────────────────────────────
            _SectionHeader(
              icon: Icons.bar_chart_rounded,
              color: _C.primary,
              title: 'Overview',
            ),
            LayoutBuilder(
              builder: (_, c) {
                const gap = 10.0;
                final w = (c.maxWidth - gap) / 2;
                final stats = [
                  (
                    label: 'Total Credits',
                    value: '${d.totalCredits}',
                    icon: Icons.star_rounded,
                    color: _C.primary,
                  ),
                  (
                    label: 'Activities',
                    value: '${d.activitiesCount}',
                    icon: Icons.menu_book_rounded,
                    color: _C.neonBlue,
                  ),
                  (
                    label: 'Volunteering',
                    value: '${d.volunteeringCount}',
                    icon: Icons.eco_rounded,
                    color: _C.neonGreen,
                  ),
                  (
                    label: 'Certificates',
                    value: '${d.certificatesCount}',
                    icon: Icons.workspace_premium_rounded,
                    color: _C.amber,
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
                            color: s.color,
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 6),

            // ── C. Recent activity ───────────────────────────────────────────
            _SectionHeader(
              icon: Icons.timeline_rounded,
              color: _C.neonCyan,
              title: 'Recent Activity',
            ),
            d.recentActivity.isEmpty
                ? _GlassCard(
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Row(
                        children: [
                          Icon(Icons.inbox_rounded, color: _C.muted, size: 18),
                          SizedBox(width: 10),
                          Text(
                            'No activity yet',
                            style: TextStyle(color: _C.muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: d.recentActivity
                        .map((r) => _ActivityTile(row: r))
                        .toList(),
                  ),

            // ── D. Certificate preview ───────────────────────────────────────
            _SectionHeader(
              icon: Icons.workspace_premium_rounded,
              color: _C.amber,
              title: 'Certificates',
            ),
            d.recentCerts.isEmpty
                ? _GlassCard(
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Row(
                        children: [
                          Icon(Icons.inbox_rounded, color: _C.muted, size: 18),
                          SizedBox(width: 10),
                          Text(
                            'No certificates yet',
                            style: TextStyle(color: _C.muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: d.recentCerts
                        .map((c) => _CertPreviewTile(row: c))
                        .toList(),
                  ),

            if (d.certificatesCount > 3) ...[
              GestureDetector(
                onTap: () => Navigator.pushReplacementNamed(
                  context,
                  '/student/certificates',
                ),
                child: Container(
                  width: double.infinity,
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: _C.primary, width: 1.4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.workspace_premium_rounded,
                        color: _C.primary,
                        size: 16,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'View All Certificates',
                        style: TextStyle(
                          color: _C.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      },
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// STAT CARD
// ─────────────────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _C.card.withValues(alpha: 0.75),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
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
        Text(
          label,
          style: const TextStyle(color: _C.muted, fontSize: 10),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// ACTIVITY TILE
// ─────────────────────────────────────────────────────────────────────────────
class _ActivityTile extends StatelessWidget {
  final _ActivityRow row;
  const _ActivityTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final isVol = row.type.toLowerCase().contains('vol');
    final ic = isVol ? _C.neonGreen : _C.primary;
    return _GlassCard(
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: ic.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isVol ? Icons.eco_rounded : Icons.menu_book_rounded,
              size: 18,
              color: ic,
            ),
          ),
          const SizedBox(width: 10),
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
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '${row.type} · ${row.date}',
                  style: const TextStyle(color: _C.muted, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _statusBadge(row.status),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CERT PREVIEW TILE
// ─────────────────────────────────────────────────────────────────────────────
class _CertPreviewTile extends StatelessWidget {
  final _CertPreviewRow row;
  const _CertPreviewTile({required this.row});

  @override
  Widget build(BuildContext context) => _GlassCard(
    glowColor: _C.neonCyan.withValues(alpha: 0.3),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _C.neonCyan.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
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
                row.title,
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
                '${row.type} · ${row.date}',
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
              '+${row.credits}',
              style: const TextStyle(
                color: _C.amber,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            row.hasHash
                ? Container(
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
                        Icon(Icons.link_rounded, size: 9, color: _C.neonCyan),
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
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _C.amber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _C.amber.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Text(
                      'Issued',
                      style: TextStyle(
                        color: _C.amber,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
          ],
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// MIGRATION HELPER
// Run once for users created before the credits-on-markCompleted rule was live.
// Call from a dev/admin screen or a one-time initState guard:
//   if ((userData['credits'] ?? 0) == 0) fixUserCredits(uid);
// ─────────────────────────────────────────────────────────────────────────────
Future<void> fixUserCredits(String uid) async {
  final db = FirebaseFirestore.instance;
  final certs = await db
      .collection('certificates')
      .where('userId', isEqualTo: uid)
      .get();
  int total = 0;
  for (final doc in certs.docs) {
    total += ((doc.data() as Map)['credits'] as int?) ?? 0;
  }
  await db.collection('users').doc(uid).update({'credits': total});
}
