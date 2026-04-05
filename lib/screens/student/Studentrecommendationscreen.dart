// ═══════════════════════════════════════════════════════════════════════════════
// student_recommendation_screen.dart   Route: /student/recommendations
//
// Recommendation logic (no external AI):
//   Activities   → same department as user, status=='open', not full, limit 5
//   Volunteering → status=='open', not full, limit 5
//   If <5 department matches, back-fill with other open activities
//
// Data: users/{uid}, activities (stream), volunteering (stream)
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
// MODELS
// ─────────────────────────────────────────────────────────────────────────────
class _UserProfile {
  final String name, department;
  final int credits;
  const _UserProfile({
    required this.name,
    required this.department,
    required this.credits,
  });
}

class _RecActivity {
  final String id, title, description, type, department;
  final int credits, enrolled, capacity;
  const _RecActivity({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.department,
    required this.credits,
    required this.enrolled,
    required this.capacity,
  });
  bool get isFull => capacity > 0 && enrolled >= capacity;
}

class _RecVolunteering {
  final String id, title, description, category, organization;
  final int credits, current, max;
  const _RecVolunteering({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.organization,
    required this.credits,
    required this.current,
    required this.max,
  });
  bool get isFull => max > 0 && current >= max;
}

class _RecData {
  final _UserProfile profile;
  final List<_RecActivity> activities;
  final List<_RecVolunteering> volunteering;
  const _RecData({
    required this.profile,
    required this.activities,
    required this.volunteering,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────────────────────────────────────
class _RecService {
  static final _db = FirebaseFirestore.instance;
  static Map<String, dynamic> _safe(DocumentSnapshot doc) =>
      (doc.data() as Map<String, dynamic>?) ?? {};

  static Future<_RecData> load(String uid) async {
    // Parallel fetch — user profile, all activities, all volunteering
    final results = await Future.wait([
      _db.collection('users').doc(uid).get(),
      _db.collection('activities').where('status', isEqualTo: 'open').get(),
      _db.collection('volunteering').where('status', isEqualTo: 'open').get(),
    ]);

    final userDoc = results[0] as DocumentSnapshot;
    final actSnap = results[1] as QuerySnapshot;
    final volSnap = results[2] as QuerySnapshot;

    final ud = _safe(userDoc);
    final department = (ud['department'] as String?) ?? '';
    final profile = _UserProfile(
      name: (ud['name'] as String?) ?? '',
      department: department,
      credits: (ud['credits'] as int?) ?? 0,
    );

    // Parse activities
    final allActs = actSnap.docs
        .map((doc) {
          final d = _safe(doc);
          final enrolled = (d['enrolled'] as int?) ?? 0;
          final capacity = (d['capacity'] as int?) ?? 0;
          return _RecActivity(
            id: doc.id,
            title: (d['title'] as String?) ?? '',
            description: (d['description'] as String?) ?? '',
            type: (d['type'] as String?) ?? '',
            department: (d['department'] as String?) ?? '',
            credits: (d['credits'] as int?) ?? 0,
            enrolled: enrolled,
            capacity: capacity,
          );
        })
        .where((a) => !a.isFull)
        .toList();

    // Priority: same dept first, then others
    final sameDept = allActs
        .where((a) => a.department.toLowerCase() == department.toLowerCase())
        .toList();
    final others = allActs
        .where((a) => a.department.toLowerCase() != department.toLowerCase())
        .toList();
    final recActs = [...sameDept, ...others].take(5).toList();

    // Parse volunteering
    final recVol = volSnap.docs
        .map((doc) {
          final d = _safe(doc);
          final current = (d['currentParticipants'] as int?) ?? 0;
          final max = (d['maxParticipants'] as int?) ?? 0;
          return _RecVolunteering(
            id: doc.id,
            title: (d['title'] as String?) ?? '',
            description: (d['description'] as String?) ?? '',
            category: (d['category'] as String?) ?? '',
            organization: (d['organization'] as String?) ?? '',
            credits: (d['credits'] as int?) ?? 0,
            current: current,
            max: max,
          );
        })
        .where((v) => !v.isFull)
        .take(5)
        .toList();

    return _RecData(
      profile: profile,
      activities: recActs,
      volunteering: recVol,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED WIDGETS
// ─────────────────────────────────────────────────────────────────────────────
class _GlassCard extends StatelessWidget {
  final Widget child;
  final Color? glowColor;
  const _GlassCard({required this.child, this.glowColor});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
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

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, subtitle;
  const _SectionHeader({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 10),
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
                  fontSize: 15,
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

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool outlined;
  final VoidCallback onTap;
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
      height: 38,
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
        children: [
          Icon(icon, color: outlined ? _C.primary : Colors.white, size: 15),
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

// ─────────────────────────────────────────────────────────────────────────────
// ACTIVITY RECOMMENDATION CARD
// ─────────────────────────────────────────────────────────────────────────────
class _ActivityCard extends StatelessWidget {
  final _RecActivity activity;
  const _ActivityCard({required this.activity});

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final fillPct = a.capacity > 0
        ? (a.enrolled / a.capacity).clamp(0.0, 1.0)
        : 0.0;

    return _GlassCard(
      glowColor: _C.primary.withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Type + dept row
          Row(
            children: [
              if (a.type.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _C.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _C.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    a.type,
                    style: const TextStyle(
                      color: _C.primary,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              Flexible(
                child: Text(
                  a.department,
                  style: const TextStyle(color: _C.muted, fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: _C.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _C.amber.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded, size: 10, color: _C.amber),
                    const SizedBox(width: 3),
                    Text(
                      '+${a.credits}',
                      style: const TextStyle(
                        color: _C.amber,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

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
          const SizedBox(height: 4),

          // Description
          if (a.description.isNotEmpty)
            Text(
              a.description,
              style: const TextStyle(
                color: _C.muted,
                fontSize: 12,
                height: 1.45,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 10),

          // Participants bar
          Row(
            children: [
              const Icon(Icons.people_rounded, size: 11, color: _C.muted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${a.enrolled}/${a.capacity} enrolled',
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
          const SizedBox(height: 12),

          _ActionBtn(
            label: 'Enroll Now',
            icon: Icons.how_to_reg_rounded,
            onTap: () => Navigator.pushNamed(context, '/student/activities'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VOLUNTEERING RECOMMENDATION CARD
// ─────────────────────────────────────────────────────────────────────────────
class _VolCard extends StatelessWidget {
  final _RecVolunteering vol;
  const _VolCard({required this.vol});

  @override
  Widget build(BuildContext context) {
    final v = vol;
    final fillPct = v.max > 0 ? (v.current / v.max).clamp(0.0, 1.0) : 0.0;

    return _GlassCard(
      glowColor: _C.neonGreen.withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Category + credits
          Row(
            children: [
              if (v.category.isNotEmpty)
                Flexible(
                  child: Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _C.neonGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _C.neonGreen.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      v.category,
                      style: const TextStyle(
                        color: _C.neonGreen,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: _C.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _C.amber.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded, size: 10, color: _C.amber),
                    const SizedBox(width: 3),
                    Text(
                      '+${v.credits}',
                      style: const TextStyle(
                        color: _C.amber,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Title
          Text(
            v.title,
            style: const TextStyle(
              color: _C.text,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),

          // Organization
          if (v.organization.isNotEmpty)
            Text(
              v.organization,
              style: const TextStyle(color: _C.muted, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),

          // Description
          if (v.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              v.description,
              style: const TextStyle(
                color: _C.muted,
                fontSize: 12,
                height: 1.45,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 10),

          // Participants bar
          Row(
            children: [
              const Icon(Icons.people_rounded, size: 11, color: _C.muted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${v.current}/${v.max} participants',
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
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [_C.neonGreen, _C.neonCyan],
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

          _ActionBtn(
            label: 'Apply Now',
            icon: Icons.eco_rounded,
            outlined: true,
            onTap: () => Navigator.pushNamed(context, '/student/volunteering'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class StudentRecommendationScreen extends StatefulWidget {
  const StudentRecommendationScreen({super.key});
  @override
  State<StudentRecommendationScreen> createState() =>
      _StudentRecommendationScreenState();
}

class _StudentRecommendationScreenState
    extends State<StudentRecommendationScreen> {
  Future<_RecData> _future = Future.value(
    const _RecData(
      profile: _UserProfile(name: '', department: '', credits: 0),
      activities: [],
      volunteering: [],
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
    final f = _RecService.load(_uid);
    _future = f;
    f.then((d) {
      if (mounted) setState(() => _userName = d.profile.name);
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => StudentDashboardLayout(
    currentRoute: '/student/recommendations',
    userName: _userName,
    child: FutureBuilder<_RecData>(
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

        final data = snap.data!;
        final p = data.profile;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── A. Header ─────────────────────────────────────────────────────
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_C.primary, _C.neonCyan],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text(
                      'AI',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'AI Recommendations',
                        style: TextStyle(
                          color: _C.text,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Personalised based on your profile',
                        style: TextStyle(color: _C.muted, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _init,
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

            // ── B. Profile tags ───────────────────────────────────────────────
            _GlassCard(
              glowColor: _C.primary.withValues(alpha: 0.2),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_C.primary, _C.neonBlue],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        p.name.isNotEmpty ? p.name[0].toUpperCase() : 'S',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
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
                          p.name.isNotEmpty ? p.name : 'Student',
                          style: const TextStyle(
                            color: _C.text,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 5,
                          children: [
                            if (p.department.isNotEmpty)
                              _TagChip(
                                label: '📚 ${p.department}',
                                color: _C.primary,
                              ),
                            _TagChip(
                              label: '⭐ ${p.credits} credits',
                              color: _C.amber,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── C. Recommended activities ─────────────────────────────────────
            _SectionHeader(
              icon: Icons.auto_awesome_rounded,
              color: _C.primary,
              title: 'Recommended Activities',
              subtitle: p.department.isNotEmpty
                  ? 'Matched to ${p.department}'
                  : 'Open activities for you',
            ),

            data.activities.isEmpty
                ? _GlassCard(
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Row(
                        children: [
                          Icon(Icons.inbox_rounded, color: _C.muted, size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'No open activities available right now.',
                              style: TextStyle(color: _C.muted, fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: data.activities
                        .map((a) => _ActivityCard(activity: a))
                        .toList(),
                  ),

            // ── D. Recommended volunteering ───────────────────────────────────
            _SectionHeader(
              icon: Icons.eco_rounded,
              color: _C.neonGreen,
              title: 'Recommended Volunteering',
              subtitle: 'Open opportunities for community impact',
            ),

            data.volunteering.isEmpty
                ? _GlassCard(
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Row(
                        children: [
                          Icon(Icons.inbox_rounded, color: _C.muted, size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'No open volunteering available right now.',
                              style: TextStyle(color: _C.muted, fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: data.volunteering
                        .map((v) => _VolCard(vol: v))
                        .toList(),
                  ),

            // ── Footer CTA ────────────────────────────────────────────────────
            const SizedBox(height: 4),
            _GlassCard(
              glowColor: _C.neonCyan.withValues(alpha: 0.2),
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
                      Icons.explore_rounded,
                      color: _C.neonCyan,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Explore All',
                          style: TextStyle(
                            color: _C.text,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Browse the full catalogue of activities & volunteering',
                          style: TextStyle(color: _C.muted, fontSize: 10),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => Navigator.pushReplacementNamed(
                      context,
                      '/student/activities',
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_C.neonCyan, _C.neonBlue],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Browse',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// TAG CHIP
// ─────────────────────────────────────────────────────────────────────────────
class _TagChip extends StatelessWidget {
  final String label;
  final Color color;
  const _TagChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  );
}
