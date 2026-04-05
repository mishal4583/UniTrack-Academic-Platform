// ═══════════════════════════════════════════════════════════════════════════════
// faculty_profile_screen.dart   Route: /faculty/profile
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'faculty_dashboard_layout.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DESIGN TOKENS (self-contained for easy copy-paste)
// ─────────────────────────────────────────────────────────────────────────────
class _C {
  static const bg = Color(0xFF080D19);
  static const card = Color(0xFF111827);
  static const primary = Color(0xFF8B5CF6);
  static const neonBlue = Color(0xFF3B82F6);
  static const neonCyan = Color(0xFF06B6D4);
  static const neonGreen = Color(0xFF10B981);
  static const amber = Color(0xFFF59E0B);
  static const yellow = Color(0xFFFBBF24);
  static const text = Color(0xFFEFF3F8);
  static const muted = Color(0xFF7E8A9A);
  static const border = Color(0xFF1F2937);
  static const secondary = Color(0xFF1A2235);
}

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────────────────────────────────────────
class _ProfileData {
  final String name;
  final String email;
  final String department;
  final String role;
  final int activitiesCreated;
  final int creditsIssued;
  final int studentsImpacted;
  final List<_ActivityRow> recentActivities;

  const _ProfileData({
    required this.name,
    required this.email,
    required this.department,
    required this.role,
    required this.activitiesCreated,
    required this.creditsIssued,
    required this.studentsImpacted,
    required this.recentActivities,
  });
}

class _ActivityRow {
  final String id, title, type, date, status;
  final int participants;
  const _ActivityRow({
    required this.id,
    required this.title,
    required this.type,
    required this.date,
    required this.status,
    required this.participants,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// FIRESTORE SERVICE
// ─────────────────────────────────────────────────────────────────────────────
class _ProfileService {
  static final _db = FirebaseFirestore.instance;

  static Map<String, dynamic> _safe(DocumentSnapshot doc) =>
      (doc.data() as Map<String, dynamic>?) ?? {};

  static Future<_ProfileData> load(String uid) async {
    final results = await Future.wait([
      _db.collection('users').doc(uid).get(),
      _db.collection('activities').where('createdBy', isEqualTo: uid).get(),
      _db.collection('enrollments').get(),
    ]);

    final userDoc = results[0] as DocumentSnapshot;
    final actSnap = results[1] as QuerySnapshot;
    final enrSnap = results[2] as QuerySnapshot;

    final userData = _safe(userDoc);
    final name = (userData['name'] as String?) ?? '';
    final email = (userData['email'] as String?) ?? '';
    final department = (userData['department'] as String?) ?? '';
    final role = (userData['role'] as String?) ?? 'faculty';

    final actIds = actSnap.docs.map((d) => d.id).toSet();

    // Credits issued = sum(credits × enrolled) for this faculty's activities
    int creditsIssued = 0;
    for (final doc in actSnap.docs) {
      final d = _safe(doc);
      creditsIssued +=
          ((d['credits'] as int?) ?? 0) * ((d['enrolled'] as int?) ?? 0);
    }

    // Unique students across this faculty's activities
    final studentSet = <String>{};
    for (final doc in enrSnap.docs) {
      final d = _safe(doc);
      if (actIds.contains((d['activityId'] as String?) ?? '')) {
        final u = (d['userId'] as String?) ?? '';
        if (u.isNotEmpty) studentSet.add(u);
      }
    }

    // Recent 5 activities, newest first
    final sorted = [...actSnap.docs]
      ..sort((a, b) {
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
        type: (d['type'] as String?) ?? '',
        date: (d['date'] as String?) ?? '',
        status: (d['status'] as String?) ?? 'open',
        participants: (d['enrolled'] as int?) ?? 0,
      );
    }).toList();

    return _ProfileData(
      name: name.isNotEmpty ? name : 'Faculty',
      email: email,
      department: department,
      role: role,
      activitiesCreated: actSnap.docs.length,
      creditsIssued: creditsIssued,
      studentsImpacted: studentSet.length,
      recentActivities: recentActivities,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SMALL SHARED WIDGETS
// ─────────────────────────────────────────────────────────────────────────────
class _GlassCard extends StatelessWidget {
  final Widget child;
  final Color? glowColor;

  const _GlassCard({required this.child, this.glowColor});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _C.card.withOpacity(0.75),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: glowColor != null ? glowColor!.withOpacity(0.4) : _C.border,
      ),
      boxShadow: glowColor != null
          ? [
              BoxShadow(
                color: glowColor!.withOpacity(0.18),
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
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STAT CARD (3-column strip)
// ─────────────────────────────────────────────────────────────────────────────
class _StatStrip extends StatelessWidget {
  final _ProfileData data;
  const _StatStrip({required this.data});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (ctx, c) {
      const gap = 12.0;
      final stats = [
        (
          icon: Icons.menu_book_rounded,
          color: _C.primary,
          value: data.activitiesCreated,
          label: 'Activities\nCreated',
        ),
        (
          icon: Icons.star_rounded,
          color: _C.neonCyan,
          value: data.creditsIssued,
          label: 'Credits\nIssued',
        ),
        (
          icon: Icons.school_rounded,
          color: _C.neonGreen,
          value: data.studentsImpacted,
          label: 'Students\nImpacted',
        ),
      ];
      return Row(
        children: stats.asMap().entries.map((entry) {
          final i = entry.key;
          final s = entry.value;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(left: i == 0 ? 0 : gap),
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              decoration: BoxDecoration(
                color: _C.card.withOpacity(0.75),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _C.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(s.icon, color: s.color, size: 22),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${s.value}',
                      style: const TextStyle(
                        color: _C.text,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.label,
                    style: const TextStyle(
                      color: _C.muted,
                      fontSize: 9,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
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
// PROFILE IDENTITY CARD
// ─────────────────────────────────────────────────────────────────────────────
class _IdentityCard extends StatelessWidget {
  final _ProfileData data;
  const _IdentityCard({required this.data});

  String get _initials {
    final parts = data.name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return data.name.isNotEmpty ? data.name[0].toUpperCase() : 'F';
  }

  @override
  Widget build(BuildContext context) => _GlassCard(
    glowColor: _C.primary,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Avatar
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_C.primary, _C.neonBlue],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              _initials,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ),
        ),

        const SizedBox(width: 16),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                data.name,
                style: const TextStyle(
                  color: _C.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              const SizedBox(height: 2),

              Text(
                data.department.isNotEmpty ? data.department : 'Faculty',
                style: const TextStyle(color: _C.muted, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              const SizedBox(height: 8),

              // Email row
              if (data.email.isNotEmpty)
                Row(
                  children: [
                    const Icon(Icons.email_rounded, size: 12, color: _C.muted),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        data.email,
                        style: const TextStyle(color: _C.muted, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 6),

              // Blockchain DID badge + DID string
              Row(
                children: [
                  const _BlockchainBadge(status: 'verified'),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'did:ethr:0x3c91...8f2a',
                      style: const TextStyle(
                        color: _C.muted,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// RECENT ACTIVITIES SECTION
// ─────────────────────────────────────────────────────────────────────────────
class _RecentActivities extends StatelessWidget {
  final List<_ActivityRow> items;
  const _RecentActivities({required this.items});

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
        return const Color(0xFFF43F5E);
      default:
        return _C.muted;
    }
  }

  @override
  Widget build(BuildContext context) => _GlassCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Row(
          children: [
            Icon(Icons.menu_book_rounded, size: 16, color: _C.primary),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Recent Activities Created',
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
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                'No activities created yet.',
                style: TextStyle(color: _C.muted, fontSize: 12),
              ),
            ),
          )
        else
          ...items.map(
            (a) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _C.secondary.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _C.border.withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: _typeColor(a.type).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.menu_book_rounded,
                      size: 16,
                      color: _typeColor(a.type),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          a.title,
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
                                '${a.type}${a.date.isNotEmpty ? ' · ${a.date}' : ''} · ${a.participants} participants',
                                style: const TextStyle(
                                  color: _C.muted,
                                  fontSize: 10,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _BlockchainBadge(status: a.status),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// BLOCKCHAIN IDENTITY CARD
// ─────────────────────────────────────────────────────────────────────────────
class _BlockchainIdentityCard extends StatelessWidget {
  final String name;
  const _BlockchainIdentityCard({required this.name});

  @override
  Widget build(BuildContext context) => _GlassCard(
    glowColor: _C.neonCyan,
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
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.shield_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Faculty Decentralized Identity',
                style: TextStyle(
                  color: _C.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              const Text(
                'DID: did:ethr:0x3c91...8f2a',
                style: TextStyle(
                  color: _C.muted,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const Text(
                'Wallet: 0x3c91fe...8f2a  ·  Ethereum',
                style: TextStyle(
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
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class FacultyProfileScreen extends StatefulWidget {
  const FacultyProfileScreen({super.key});

  @override
  State<FacultyProfileScreen> createState() => _FacultyProfileScreenState();
}

class _FacultyProfileScreenState extends State<FacultyProfileScreen> {
  late Future<_ProfileData> _future;
  String _userName = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _future = Future.error('Not signed in');
      return;
    }
    _future = _ProfileService.load(user.uid);
    _future.then((data) {
      if (!mounted) return;
      setState(() => _userName = data.name);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FacultyDashboardLayout(
      currentRoute: '/faculty/profile',
      userName: _userName,
      child: FutureBuilder<_ProfileData>(
        future: _future,
        builder: (context, snap) {
          // ── Loading ──────────────────────────────────────────────────────
          if (snap.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 80),
              child: Center(
                child: CircularProgressIndicator(color: _C.primary),
              ),
            );
          }

          // ── Error ────────────────────────────────────────────────────────
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
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
                      'Failed to load profile',
                      style: TextStyle(
                        color: _C.text,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
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
                      onTap: () => setState(_load),
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

          // ── Data ─────────────────────────────────────────────────────────
          final data = snap.data!;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Page heading
              const Text(
                'Faculty Profile',
                style: TextStyle(
                  color: _C.text,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),

              // Identity card
              _IdentityCard(data: data),

              // Stats strip
              _StatStrip(data: data),
              const SizedBox(height: 4),

              // Recent activities
              _RecentActivities(items: data.recentActivities),

              // Blockchain identity
              _BlockchainIdentityCard(name: data.name),
            ],
          );
        },
      ),
    );
  }
}
