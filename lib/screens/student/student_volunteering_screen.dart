// ═══════════════════════════════════════════════════════════════════════════════
// student_volunteering_screen.dart   Route: /student/volunteering
//
// AcceptedVolunteeringScreen REMOVED — superseded by StudentMyProgressScreen
// Route: /student/my-progress
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
// MODELS
// ─────────────────────────────────────────────────────────────────────────────
class VolunteeringOpportunity {
  final String id,
      title,
      category,
      description,
      duration,
      status,
      organization,
      date;
  final int credits, maxParticipants, currentParticipants;
  final List<String> skills;
  final bool blockchainCert;

  const VolunteeringOpportunity({
    required this.id,
    required this.title,
    required this.category,
    required this.description,
    required this.credits,
    required this.duration,
    required this.maxParticipants,
    required this.currentParticipants,
    required this.skills,
    required this.blockchainCert,
    required this.status,
    required this.organization,
    required this.date,
  });

  factory VolunteeringOpportunity.fromFirestore(DocumentSnapshot doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? {};
    return VolunteeringOpportunity(
      id: doc.id,
      title: (d['title'] as String?) ?? '',
      category: (d['category'] as String?) ?? '',
      description: (d['description'] as String?) ?? '',
      credits: (d['credits'] as num? ?? 0).toInt(),
      duration: (d['duration'] as String?) ?? '',
      maxParticipants: (d['maxParticipants'] as num? ?? 0).toInt(),
      currentParticipants: (d['currentParticipants'] as num? ?? 0).toInt(),
      skills: List<String>.from((d['skills'] as List?) ?? []),
      blockchainCert: (d['blockchainCert'] as bool?) ?? false,
      status: (d['status'] as String?) ?? 'open',
      organization: (d['organization'] as String?) ?? '',
      date: (d['date'] as String?) ?? '',
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FIRESTORE SERVICE
// ─────────────────────────────────────────────────────────────────────────────
class _VolunteeringService {
  static final _db = FirebaseFirestore.instance;

  /// Returns `Map<volunteeringId, applicationStatus>` — single query, no loops.
  static Future<Map<String, String>> fetchApplicationMap(String uid) async {
    if (uid.isEmpty) return {};
    final snap = await _db
        .collection('applications')
        .where('userId', isEqualTo: uid)
        .get();
    final result = <String, String>{};
    for (final doc in snap.docs) {
      final d = doc.data();
      final vid = (d['volunteeringId'] as String?) ?? '';
      final st = (d['status'] as String?) ?? 'Applied';
      if (vid.isNotEmpty) result[vid] = st;
    }
    return result;
  }

  /// Apply — duplicate-safe. Returns null on success, error string on failure.
  static Future<String?> apply({
    required String uid,
    required String volunteeringId,
  }) async {
    final existing = await _db
        .collection('applications')
        .where('userId', isEqualTo: uid)
        .where('volunteeringId', isEqualTo: volunteeringId)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) return 'already_applied';

    await _db.collection('applications').add({
      'userId': uid,
      'volunteeringId': volunteeringId,
      'status': 'Applied',
      'appliedAt': FieldValue.serverTimestamp(),
    });
    await _db.collection('volunteering').doc(volunteeringId).update({
      'currentParticipants': FieldValue.increment(1),
    });
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CATEGORY COLOR
// ─────────────────────────────────────────────────────────────────────────────
Color _categoryColor(String cat) {
  switch (cat) {
    case 'Academic Support':
      return _C.neonBlue;
    case 'Campus Life & Services':
      return _C.primary;
    case 'Event Management & Outreach':
      return _C.neonCyan;
    case 'Sustainability & Environmental':
      return _C.neonGreen;
    case 'Specialized Roles':
      return _C.amber;
    default:
      return _C.muted;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED WIDGETS
// ─────────────────────────────────────────────────────────────────────────────
class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;

  const _GlassCard({required this.child, this.padding});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: padding ?? const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _C.card.withValues(alpha: 0.75),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _C.border),
    ),
    child: child,
  );
}

class _AppStatusBadge extends StatelessWidget {
  final String status;
  const _AppStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final Color c;
    switch (status.toLowerCase()) {
      case 'applied':
        c = _C.yellow;
        break;
      case 'approved':
        c = _C.neonBlue;
        break;
      case 'completed':
        c = _C.neonGreen;
        break;
      case 'verified':
        c = _C.neonCyan;
        break;
      default:
        c = _C.muted;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Text(
        status,
        style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w600),
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
        height: 42,
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
            if (icon != null) ...[
              Icon(icon, color: outlined ? _C.primary : Colors.white, size: 16),
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
  final String message, sub;
  const _EmptyState({required this.message, required this.sub});

  @override
  Widget build(BuildContext context) => _GlassCard(
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.eco_rounded, color: _C.muted, size: 40),
        const SizedBox(height: 12),
        Text(
          message,
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
  final String message;
  const _ErrorState({required this.message});

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
          message,
          style: const TextStyle(color: _C.muted, fontSize: 11),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
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
// OPPORTUNITY CARD
// ─────────────────────────────────────────────────────────────────────────────
class _OpportunityCard extends StatefulWidget {
  final VolunteeringOpportunity opportunity;
  final String? applicationStatus;
  final String uid;

  const _OpportunityCard({
    required this.opportunity,
    required this.applicationStatus,
    required this.uid,
  });

  @override
  State<_OpportunityCard> createState() => _OpportunityCardState();
}

class _OpportunityCardState extends State<_OpportunityCard> {
  bool _applying = false;
  String? _localStatus;

  @override
  void initState() {
    super.initState();
    _localStatus = widget.applicationStatus;
  }

  Future<void> _apply() async {
    if (widget.uid.isEmpty) return;
    setState(() => _applying = true);

    final err = await _VolunteeringService.apply(
      uid: widget.uid,
      volunteeringId: widget.opportunity.id,
    );

    if (!mounted) return;
    setState(() {
      _applying = false;
      if (err == null || err == 'already_applied') _localStatus = 'Applied';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          (err != null && err != 'already_applied')
              ? 'Error: $err'
              : 'Applied successfully! 🎉',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: (err != null && err != 'already_applied')
            ? Colors.redAccent.withValues(alpha: 0.85)
            : _C.neonGreen.withValues(alpha: 0.85),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.opportunity;
    final catColor = _categoryColor(v.category);
    final isFull = v.status == 'full';
    final appSt = _localStatus;

    final Widget button;
    if (_applying) {
      button = const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: CircularProgressIndicator(color: _C.primary, strokeWidth: 2),
        ),
      );
    } else if (appSt != null) {
      button = _GradientButton(
        label: appSt,
        icon: appSt == 'Verified'
            ? Icons.verified_rounded
            : appSt == 'Completed'
            ? Icons.check_circle_rounded
            : Icons.hourglass_top_rounded,
        disabled: true,
        outlined: true,
      );
    } else if (isFull) {
      button = const _GradientButton(
        label: 'Fully Booked',
        icon: Icons.block_rounded,
        disabled: true,
        outlined: true,
      );
    } else {
      button = _GradientButton(
        label: 'View & Apply',
        icon: Icons.arrow_forward_rounded,
        onTap: _apply,
      );
    }

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(
                      Icons.eco_rounded,
                      color: _C.neonGreen,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: catColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          v.category,
                          style: TextStyle(
                            color: catColor,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (appSt != null) ...[
                const SizedBox(width: 8),
                _AppStatusBadge(status: appSt),
              ] else if (v.blockchainCert) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _C.neonCyan.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shield_rounded, color: _C.neonCyan, size: 10),
                      SizedBox(width: 3),
                      Text(
                        'NFT Cert',
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
            ],
          ),

          const SizedBox(height: 10),
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
          Text(
            '${v.organization} · ${v.date}',
            style: const TextStyle(color: _C.muted, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Text(
            v.description,
            style: const TextStyle(color: _C.muted, fontSize: 12, height: 1.45),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),

          if (v.skills.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: v.skills
                  .map(
                    (s) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _C.secondary,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _C.border),
                      ),
                      child: Text(
                        s,
                        style: const TextStyle(
                          color: _C.muted,
                          fontSize: 9,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],

          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _MetaChip(
                icon: Icons.star_rounded,
                label: '${v.credits} credits',
                color: _C.primary,
              ),
              if (v.duration.isNotEmpty)
                _MetaChip(
                  icon: Icons.schedule_rounded,
                  label: v.duration,
                  color: _C.muted,
                ),
              _MetaChip(
                icon: Icons.people_rounded,
                label: '${v.currentParticipants}/${v.maxParticipants}',
                color: _C.muted,
              ),
            ],
          ),
          const SizedBox(height: 12),
          button,
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// SCREEN — VOLUNTEERING FEED
// ═════════════════════════════════════════════════════════════════════════════
class VolunteeringFeedScreen extends StatefulWidget {
  const VolunteeringFeedScreen({super.key});

  @override
  State<VolunteeringFeedScreen> createState() => _VolunteeringFeedScreenState();
}

class _VolunteeringFeedScreenState extends State<VolunteeringFeedScreen> {
  String _selectedCategory = 'All';
  String _search = '';
  final _searchCtrl = TextEditingController();
  Map<String, String> _appMap = {};
  bool _appMapLoaded = false;
  String _uid = '';
  String _userName = '';

  static const _categories = [
    'All',
    'Academic Support',
    'Campus Life & Services',
    'Event Management & Outreach',
    'Sustainability & Environmental',
    'Specialized Roles',
  ];

  @override
  void initState() {
    super.initState();
    _initUser();
  }

  Future<void> _initUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _uid = user.uid;
    FirebaseFirestore.instance.collection('users').doc(_uid).get().then((doc) {
      if (!mounted) return;
      final name = ((doc.data() ?? {})['name'] as String?) ?? '';
      if (name.isNotEmpty) setState(() => _userName = name);
    });
    final map = await _VolunteeringService.fetchApplicationMap(_uid);
    if (!mounted) return;
    setState(() {
      _appMap = map;
      _appMapLoaded = true;
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<VolunteeringOpportunity> _filter(List<VolunteeringOpportunity> items) =>
      items.where((v) {
        final matchCat =
            _selectedCategory == 'All' || v.category == _selectedCategory;
        final matchSrch =
            _search.isEmpty ||
            v.title.toLowerCase().contains(_search.toLowerCase()) ||
            v.category.toLowerCase().contains(_search.toLowerCase());
        return matchCat && matchSrch;
      }).toList();

  @override
  Widget build(BuildContext context) {
    return StudentDashboardLayout(
      currentRoute: '/student/volunteering',
      userName: _userName,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Row(
            children: [
              const Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Volunteering',
                      style: TextStyle(
                        color: _C.text,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Browse opportunities & earn credits',
                      style: TextStyle(color: _C.muted, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // ── "My Progress" button — replaces old "My Volunteering" ───────
              GestureDetector(
                onTap: () => Navigator.pushReplacementNamed(
                  context,
                  '/student/my-progress',
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _C.neonGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _C.neonGreen.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.timeline_rounded,
                        color: _C.neonGreen,
                        size: 14,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'My Progress',
                        style: TextStyle(
                          color: _C.neonGreen,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Search bar ────────────────────────────────────────────────────
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
                const Icon(Icons.search_rounded, color: _C.muted, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(color: _C.text, fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'Search volunteering...',
                      hintStyle: TextStyle(color: _C.muted, fontSize: 13),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ── Category chips ────────────────────────────────────────────────
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (ctx, i) {
                final cat = _categories[i];
                final isActive = _selectedCategory == cat;
                return GestureDetector(
                  onTap: () => setState(() => _selectedCategory = cat),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
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
                      cat,
                      style: TextStyle(
                        color: isActive ? _C.primary : _C.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 16),

          // ── Feed ──────────────────────────────────────────────────────────
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('volunteering')
                .snapshots(),
            builder: (ctx, snap) {
              if (snap.hasError) {
                return _ErrorState(message: snap.error.toString());
              }
              if (snap.connectionState == ConnectionState.waiting ||
                  !_appMapLoaded) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: CircularProgressIndicator(color: _C.primary),
                  ),
                );
              }
              final items = snap.hasData && snap.data!.docs.isNotEmpty
                  ? snap.data!.docs
                        .map(VolunteeringOpportunity.fromFirestore)
                        .toList()
                  : <VolunteeringOpportunity>[];

              final filtered = _filter(items);

              if (filtered.isEmpty) {
                return _EmptyState(
                  message: 'No volunteering found.',
                  sub: 'Try a different category or search term 🌱',
                );
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: filtered
                    .map(
                      (v) => _OpportunityCard(
                        opportunity: v,
                        applicationStatus: _appMap[v.id],
                        uid: _uid,
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
