// ═══════════════════════════════════════════════════════════════════════════════
// student_certificates_screen.dart   Route: /student/certificates
//
// DATA FLOW:
//   1. Query certificates where userId == currentUser.uid
//   2. Split itemIds into two sets: activityIds, volunteeringIds (by type field)
//   3. Batch-fetch activities + volunteering using whereIn (max 30 per call)
//   4. Map itemId → title for each certificate
//   (No N+1 queries — all secondary fetches are batched in parallel)
//
// LAYOUT:
//   Uses StudentDashboardLayout as root widget.
//   No standalone Scaffold, no custom header, no back button.
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:unitrack_flutter/screens/student/student_dashboard_layout.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DESIGN TOKENS  (matches existing student dark theme)
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
}

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODEL
// ─────────────────────────────────────────────────────────────────────────────
class Certificate {
  final String docId, userId, itemId, type, status;
  final int credits;
  final String title; // resolved from activities / volunteering
  final String? blockchainHash;
  final int rating;
  final String feedback;
  final String? transactionHash;
  final DateTime? createdAt;

  const Certificate({
    required this.docId,
    required this.userId,
    required this.itemId,
    required this.type,
    required this.status,
    required this.credits,
    required this.title,
    required this.rating,
    required this.feedback,
    this.transactionHash,
    this.blockchainHash,
    this.createdAt,
  });

  bool get isActivity => type == 'activity';
  bool get isVerified => status == 'verified';
}

// ─────────────────────────────────────────────────────────────────────────────
// FIRESTORE SERVICE — batch join, zero N+1
// ─────────────────────────────────────────────────────────────────────────────
class _CertService {
  static final _db = FirebaseFirestore.instance;
  static Map<String, dynamic> _safe(DocumentSnapshot doc) =>
      (doc.data() as Map<String, dynamic>?) ?? {};

  // Batch-fetch a collection by a list of document IDs
  static Future<Map<String, Map<String, dynamic>>> _batchByIds(
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

  static Future<List<Certificate>> loadForUser(String uid) async {
    // ── Step 1: fetch all certificates for this user ──────────────────────────
    final certSnap = await _db
        .collection('certificates')
        .where('userId', isEqualTo: uid)
        .get();

    if (certSnap.docs.isEmpty) return [];

    // ── Step 2: split itemIds by type ────────────────────────────────────────
    final activityIds = <String>[];
    final volunteeringIds = <String>[];

    for (final doc in certSnap.docs) {
      final d = _safe(doc);
      final itemId = (d['itemId'] as String?) ?? '';
      final type = (d['type'] as String?) ?? '';
      if (itemId.isEmpty) continue;
      if (type == 'volunteering') {
        volunteeringIds.add(itemId);
      } else {
        activityIds.add(itemId);
      }
    }

    // ── Step 3: batch-fetch activities + volunteering in parallel ─────────────
    final results = await Future.wait([
      activityIds.isNotEmpty
          ? _batchByIds('activities', activityIds.toSet().toList())
          : Future.value(<String, Map<String, dynamic>>{}),
      volunteeringIds.isNotEmpty
          ? _batchByIds('volunteering', volunteeringIds.toSet().toList())
          : Future.value(<String, Map<String, dynamic>>{}),
    ]);
    final actMap = results[0];
    final volMap = results[1];

    // ── Step 4: assemble certificates ─────────────────────────────────────────
    final certs = certSnap.docs.map((doc) {
      final d = _safe(doc);

      final itemId = (d['itemId'] as String?) ?? '';
      final type = (d['type'] as String?) ?? 'activity';
      final item =
          (type == 'volunteering' ? volMap[itemId] : actMap[itemId]) ?? {};

      final title =
          (item['title'] as String?) ??
          (type == 'volunteering' ? 'Volunteering' : 'Activity');

      final ts = d['createdAt'];

      return Certificate(
        docId: doc.id,
        userId: uid,
        itemId: itemId,
        type: type,
        status: (d['status'] as String?) ?? 'issued',
        credits: (d['credits'] as int?) ?? 0,
        blockchainHash: (d['blockchainHash'] as String?),
        rating: (d['rating'] as int?) ?? 0,
        feedback: (d['feedback'] as String?) ?? '',
        transactionHash: (d['transactionHash'] as String?),
        title: title,
        createdAt: ts is Timestamp ? ts.toDate() : null,
      );
    }).toList();

    // ── Sort: most recent first ───────────────────────────────────────────────
    certs.sort((a, b) {
      if (a.createdAt == null && b.createdAt == null) return 0;
      if (a.createdAt == null) return 1;
      if (b.createdAt == null) return -1;
      return b.createdAt!.compareTo(a.createdAt!);
    });

    return certs;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class StudentCertificatesScreen extends StatefulWidget {
  const StudentCertificatesScreen({super.key});

  @override
  State<StudentCertificatesScreen> createState() =>
      _StudentCertificatesScreenState();
}

class _StudentCertificatesScreenState extends State<StudentCertificatesScreen> {
  Future<List<Certificate>> _future = Future.value([]);
  String _filter = 'All'; // All / Activity / Volunteering
  String _status = 'All'; // All / issued / verified
  String _userName = '';

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _userName = user?.displayName ?? user?.email ?? 'Student';
    Future.microtask(_load);
  }

  void _load() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || !mounted) return;
    final f = _CertService.loadForUser(uid);
    setState(() {
      _future = f;
    });
  }

  List<Certificate> _applyFilters(List<Certificate> all) => all.where((c) {
    final matchType = _filter == 'All' || c.type == _filter.toLowerCase();
    final matchStatus = _status == 'All' || c.status == _status;
    return matchType && matchStatus;
  }).toList();

  @override
  Widget build(BuildContext context) {
    return StudentDashboardLayout(
      currentRoute: '/student/certificates',
      userName: _userName,
      child: FutureBuilder<List<Certificate>>(
        future: _future,
        builder: (context, snap) {
          // ── Loading ─────────────────────────────────────────────────────────
          if (snap.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 320,
              child: Center(
                child: CircularProgressIndicator(color: _C.primary),
              ),
            );
          }

          // ── Error ───────────────────────────────────────────────────────────
          if (snap.hasError) {
            return SizedBox(
              height: 320,
              child: Center(
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
                        'Failed to load certificates',
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
              ),
            );
          }

          // ── Data ────────────────────────────────────────────────────────────
          final all = snap.data ?? [];
          final filtered = _applyFilters(all);

          // Summary totals (from all certs, not filtered)
          final totalCredits = all.fold(0, (s, c) => s + c.credits);
          final verifiedCount = all.where((c) => c.isVerified).length;

          // ── Page subtitle strip ─────────────────────────────────────────────
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Page intro + refresh button ─────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Certificate Wallet',
                          style: TextStyle(
                            color: _C.text,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Your blockchain-verified credentials',
                          style: const TextStyle(color: _C.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _load,
                    child: Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: _C.secondary,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _C.border),
                      ),
                      child: const Icon(
                        Icons.refresh_rounded,
                        color: _C.muted,
                        size: 17,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Summary strip ───────────────────────────────────────────────
              _SummaryStrip(
                total: all.length,
                credits: totalCredits,
                verified: verifiedCount,
              ),
              const SizedBox(height: 16),

              // ── Filters ─────────────────────────────────────────────────────
              _FilterRow(
                typeFilter: _filter,
                statusFilter: _status,
                onTypeChanged: (v) => setState(() => _filter = v),
                onStatusChanged: (v) => setState(() => _status = v),
              ),
              const SizedBox(height: 16),

              // ── Certificate list / empty states ─────────────────────────────
              if (all.isEmpty)
                _EmptyState()
              else if (filtered.isEmpty)
                _NoMatch()
              else
                ...filtered.map((c) => CertificateCard(cert: c)),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SUMMARY STRIP
// ─────────────────────────────────────────────────────────────────────────────
class _SummaryStrip extends StatelessWidget {
  final int total, credits, verified;
  const _SummaryStrip({
    required this.total,
    required this.credits,
    required this.verified,
  });

  @override
  Widget build(BuildContext context) {
    final stats = [
      (
        label: 'Total',
        value: '$total',
        icon: Icons.card_membership_rounded,
        color: _C.primary,
      ),
      (
        label: 'Credits',
        value: '$credits',
        icon: Icons.star_rounded,
        color: _C.amber,
      ),
      (
        label: 'Verified',
        value: '$verified',
        icon: Icons.verified_rounded,
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
              border: Border.all(color: s.color.withValues(alpha: 0.25)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
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
                      fontSize: 20,
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
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FILTER ROW
// ─────────────────────────────────────────────────────────────────────────────
class _FilterRow extends StatelessWidget {
  final String typeFilter, statusFilter;
  final ValueChanged<String> onTypeChanged, onStatusChanged;

  const _FilterRow({
    required this.typeFilter,
    required this.statusFilter,
    required this.onTypeChanged,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        // Type filters
        ...[
          ('All', 'All'),
          ('Activity', 'activity'),
          ('Volunteering', 'volunteering'),
        ].map(
          (f) => _Chip(
            label: f.$1,
            isActive: typeFilter == f.$1,
            onTap: () => onTypeChanged(f.$1),
          ),
        ),
        Container(
          width: 1,
          height: 20,
          color: _C.border,
          margin: const EdgeInsets.symmetric(horizontal: 8),
        ),
        // Status filters
        ...[('All', 'All'), ('Issued', 'issued'), ('Verified', 'verified')].map(
          (f) => _Chip(
            label: f.$1,
            isActive: statusFilter == f.$1,
            activeColor: f.$1 == 'Verified'
                ? _C.neonGreen
                : f.$1 == 'Issued'
                ? _C.amber
                : _C.primary,
            onTap: () => onStatusChanged(f.$1),
          ),
        ),
      ],
    ),
  );
}

class _Chip extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color activeColor;
  final VoidCallback onTap;
  const _Chip({
    required this.label,
    required this.isActive,
    required this.onTap,
    this.activeColor = _C.primary,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isActive ? activeColor.withValues(alpha: 0.15) : _C.secondary,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isActive ? activeColor.withValues(alpha: 0.5) : _C.border,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isActive ? activeColor : _C.muted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// CERTIFICATE CARD
// ─────────────────────────────────────────────────────────────────────────────
class CertificateCard extends StatelessWidget {
  final Certificate cert;
  const CertificateCard({super.key, required this.cert});

  static String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year}';
  }

  static String _truncateHash(String hash) {
    if (hash.length <= 14) return hash;
    return '${hash.substring(0, 8)}...${hash.substring(hash.length - 6)}';
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = cert.isActivity ? _C.primary : _C.neonGreen;
    final statusColor = cert.isVerified ? _C.neonGreen : _C.amber;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _C.card.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Gradient accent bar at top
          Container(
            height: 3,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: cert.isActivity
                    ? [_C.primary, _C.neonBlue]
                    : [_C.neonGreen, _C.neonCyan],
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Row 1: icon + title + status ────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        cert.isActivity
                            ? Icons.menu_book_rounded
                            : Icons.eco_rounded,
                        size: 20,
                        color: accentColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            cert.title,
                            style: const TextStyle(
                              color: _C.text,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              // Type badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: accentColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: accentColor.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Text(
                                  cert.isActivity ? 'Activity' : 'Volunteering',
                                  style: TextStyle(
                                    color: accentColor,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              // Status badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: statusColor.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      cert.isVerified
                                          ? Icons.verified_rounded
                                          : Icons.hourglass_bottom_rounded,
                                      size: 9,
                                      color: statusColor,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      cert.isVerified ? 'Verified' : 'Issued',
                                      style: TextStyle(
                                        color: statusColor,
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
                    const SizedBox(width: 8),
                    // Credits pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _C.amber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _C.amber.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '+${cert.credits}',
                            style: const TextStyle(
                              color: _C.amber,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Text(
                            'credits',
                            style: TextStyle(color: _C.amber, fontSize: 8),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                const Divider(color: _C.border, height: 1),
                const SizedBox(height: 10),

                // ── Row 2: date + blockchain info ────────────────────────────
                Row(
                  children: [
                    if (cert.createdAt != null) ...[
                      const Icon(
                        Icons.calendar_today_rounded,
                        size: 11,
                        color: _C.muted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatDate(cert.createdAt),
                        style: const TextStyle(color: _C.muted, fontSize: 11),
                      ),
                      const SizedBox(width: 12),
                    ],
                    const Icon(
                      Icons.shield_rounded,
                      size: 11,
                      color: _C.neonCyan,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        cert.blockchainHash != null
                            ? _truncateHash(cert.blockchainHash!)
                            : 'Pending on-chain',
                        style: TextStyle(
                          color: cert.blockchainHash != null
                              ? _C.neonCyan
                              : _C.muted,
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                // ── Blockchain verified banner ────────────────────────────────
                if (cert.isVerified) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _C.neonCyan.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _C.neonCyan.withValues(alpha: 0.2),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.link_rounded, size: 13, color: _C.neonCyan),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Blockchain-verified credential · Immutable record',
                            style: TextStyle(
                              color: _C.neonCyan,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EMPTY / NO-MATCH STATES
// ─────────────────────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
    decoration: BoxDecoration(
      color: _C.card.withValues(alpha: 0.75),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _C.border),
    ),
    child: const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.card_membership_rounded, size: 52, color: _C.muted),
        SizedBox(height: 16),
        Text(
          'No certificates yet',
          style: TextStyle(
            color: _C.text,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'Complete activities and volunteering to earn blockchain-verified credentials 🎓',
          style: TextStyle(color: _C.muted, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

class _NoMatch extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
    decoration: BoxDecoration(
      color: _C.card.withValues(alpha: 0.75),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _C.border),
    ),
    child: const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.filter_list_off_rounded, size: 36, color: _C.muted),
        SizedBox(height: 10),
        Text(
          'No certificates match the filter',
          style: TextStyle(
            color: _C.text,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Try selecting "All" to see everything.',
          style: TextStyle(color: _C.muted, fontSize: 12),
        ),
      ],
    ),
  );
}
