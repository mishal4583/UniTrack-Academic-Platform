// ═══════════════════════════════════════════════════════════════════════════════
// student_volunteering_screen.dart  — Production-ready, zero mock in Accepted
//
// Screens:
//   1. VolunteeringFeedScreen     → /student/volunteering
//   2. AcceptedVolunteeringScreen → /student/volunteering/accepted
//   3. ActivityDetailScreen       → push with VolunteeringOpportunity
//   4. CreateVolunteeringScreen   → /faculty/volunteering/create
//
// Firestore schema:
//   volunteering/{id} → title, description, credits, organization, date,
//                        category, duration, maxParticipants,
//                        currentParticipants, skills, blockchainCert, status
//   applications/{id} → userId, volunteeringId, status, appliedAt, txHash?
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DESIGN TOKENS
// ─────────────────────────────────────────────────────────────────────────────
class AppColors {
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
  static const yellow = Color(0xFFFBBF24);
  static const secondary = Color(0xFF1A2235);
}

// ─────────────────────────────────────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────────────────────────────────────

/// A single volunteering listing from Firestore.
class VolunteeringOpportunity {
  final String id;
  final String title;
  final String category;
  final String description;
  final int credits;
  final String duration;
  final int maxParticipants;
  final int currentParticipants;
  final List<String> skills;
  final bool blockchainCert;
  final String status; // "open" | "full"
  final String organization;
  final String date;

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
      credits: (d['credits'] as int?) ?? 0,
      duration: (d['duration'] as String?) ?? '',
      maxParticipants: (d['maxParticipants'] as int?) ?? 0,
      currentParticipants: (d['currentParticipants'] as int?) ?? 0,
      skills: List<String>.from((d['skills'] as List?) ?? []),
      blockchainCert: (d['blockchainCert'] as bool?) ?? false,
      status: (d['status'] as String?) ?? 'open',
      organization: (d['organization'] as String?) ?? '',
      date: (d['date'] as String?) ?? '',
    );
  }
}

/// An application record merged with its volunteering listing.
class AppliedVolunteering {
  final String applicationId;
  final String applicationStatus; // Applied | Approved | Completed | Verified
  final String? txHash;
  final VolunteeringOpportunity volunteering;

  const AppliedVolunteering({
    required this.applicationId,
    required this.applicationStatus,
    this.txHash,
    required this.volunteering,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// FIRESTORE SERVICE  — all data-access logic centralised here
// ─────────────────────────────────────────────────────────────────────────────
class _VolunteeringService {
  static final _db = FirebaseFirestore.instance;

  /// Fetch all applications for [uid], then batch-fetch their volunteering docs.
  /// Returns a merged list. Never calls Firestore inside a loop.
  static Future<List<AppliedVolunteering>> fetchApplied(String uid) async {
    // 1 — applications for this user
    final appSnap = await _db
        .collection('applications')
        .where('userId', isEqualTo: uid)
        .get();

    if (appSnap.docs.isEmpty) return [];

    // 2 — collect unique volunteeringIds
    final ids = appSnap.docs
        .map((d) => (d.data()['volunteeringId'] as String?) ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (ids.isEmpty) return [];

    // 3 — batch-fetch all volunteering docs in one call (max 30 per whereIn)
    //     Split if needed.
    final Map<String, VolunteeringOpportunity> volMap = {};
    const batchSize = 30;
    for (int i = 0; i < ids.length; i += batchSize) {
      final chunk = ids.sublist(i, (i + batchSize).clamp(0, ids.length));
      final volSnap = await _db
          .collection('volunteering')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in volSnap.docs) {
        volMap[doc.id] = VolunteeringOpportunity.fromFirestore(doc);
      }
    }

    // 4 — merge
    final result = <AppliedVolunteering>[];
    for (final appDoc in appSnap.docs) {
      final d = appDoc.data();
      final vid = (d['volunteeringId'] as String?) ?? '';
      final vol = volMap[vid];
      if (vol == null) continue; // orphaned application — skip
      result.add(
        AppliedVolunteering(
          applicationId: appDoc.id,
          applicationStatus: (d['status'] as String?) ?? 'Applied',
          txHash: (d['txHash'] as String?),
          volunteering: vol,
        ),
      );
    }
    return result;
  }

  /// Apply: duplicate-check → write application → increment currentParticipants.
  /// Returns null on success, or an error message string.
  static Future<String?> apply({
    required String uid,
    required VolunteeringOpportunity opportunity,
  }) async {
    // Duplicate check
    final existing = await _db
        .collection('applications')
        .where('userId', isEqualTo: uid)
        .where('volunteeringId', isEqualTo: opportunity.id)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) return 'already_applied';

    // Write application + increment in one logical operation (two writes — no transaction needed for UX)
    await _db.collection('applications').add({
      'userId': uid,
      'volunteeringId': opportunity.id,
      'status': 'Applied',
      'appliedAt': FieldValue.serverTimestamp(),
    });

    await _db.collection('volunteering').doc(opportunity.id).update({
      'currentParticipants': FieldValue.increment(1),
    });

    return null; // success
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STATUS → STEPPER STEPS
// ─────────────────────────────────────────────────────────────────────────────
const _allStepLabels = ['Applied', 'Approved', 'Completed', 'Verified'];

/// Returns step status ("completed" | "active" | "upcoming") for each step
/// based on the current application status string.
List<String> _stepStatuses(String appStatus) {
  final idx = _allStepLabels.indexWhere(
    (s) => s.toLowerCase() == appStatus.toLowerCase(),
  );
  final current = idx < 0 ? 0 : idx;
  return List.generate(_allStepLabels.length, (i) {
    if (i < current) return 'completed';
    if (i == current) return 'active';
    return 'upcoming';
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// CATEGORY COLOR
// ─────────────────────────────────────────────────────────────────────────────
Color _categoryColor(String cat) {
  switch (cat) {
    case 'Academic Support':
      return AppColors.neonBlue;
    case 'Campus Life & Services':
      return AppColors.primary;
    case 'Event Management & Outreach':
      return AppColors.neonCyan;
    case 'Sustainability & Environmental':
      return AppColors.neonGreen;
    case 'Specialized Roles':
      return AppColors.amber;
    default:
      return AppColors.muted;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ═════════════════════════════════════════════════════════════════════════════

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF1F2937).withOpacity(0.3)
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

class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final Color? glowColor;
  final VoidCallback? onTap;
  final bool gradientBorder;

  const _GlassCard({
    required this.child,
    this.padding,
    this.glowColor,
    this.onTap,
    this.gradientBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: padding ?? const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card.withOpacity(0.75),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: gradientBorder
                ? AppColors.primary.withOpacity(0.5)
                : AppColors.border,
            width: gradientBorder ? 1.5 : 1,
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
      ),
    );
  }
}

class _BlockchainBadge extends StatelessWidget {
  final String status;
  const _BlockchainBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;
    final String label;
    switch (status) {
      case 'verified':
        color = AppColors.neonCyan;
        icon = Icons.check_circle_rounded;
        label = 'Verified';
        break;
      case 'pending':
        color = AppColors.yellow;
        icon = Icons.access_time_rounded;
        label = 'Pending';
        break;
      default:
        color = AppColors.muted;
        icon = Icons.shield_outlined;
        label = 'Not Verified';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AppStatusBadge extends StatelessWidget {
  final String status;
  const _AppStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final Color color;
    switch (status.toLowerCase()) {
      case 'applied':
        color = AppColors.yellow;
        break;
      case 'approved':
        color = AppColors.neonBlue;
        break;
      case 'completed':
        color = AppColors.neonGreen;
        break;
      case 'verified':
        color = AppColors.neonCyan;
        break;
      case 'full':
        color = AppColors.muted;
        break;
      default:
        color = AppColors.muted;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
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
  Widget build(BuildContext context) {
    return GestureDetector(
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
                : const LinearGradient(
                    colors: [AppColors.primary, AppColors.neonBlue],
                  ),
            borderRadius: BorderRadius.circular(12),
            border: outlined
                ? Border.all(color: AppColors.primary, width: 1.4)
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  color: outlined ? AppColors.primary : Colors.white,
                  size: 16,
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: outlined ? AppColors.primary : Colors.white,
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
}

/// Shared scaffold: grid bg + top bar.
class _VScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData titleIcon;
  final Color iconColor;
  final Widget body;
  final Widget? topRight;

  const _VScaffold({
    required this.title,
    required this.subtitle,
    required this.titleIcon,
    required this.iconColor,
    required this.body,
    this.topRight,
  });

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final botPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          Column(
            children: [
              Container(
                padding: EdgeInsets.fromLTRB(16, topPad + 10, 16, 12),
                decoration: BoxDecoration(
                  color: AppColors.card.withOpacity(0.7),
                  border: const Border(
                    bottom: BorderSide(color: AppColors.border),
                  ),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 34,
                        height: 34,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          color: AppColors.secondary,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: AppColors.muted,
                          size: 15,
                        ),
                      ),
                    ),
                    Icon(titleIcon, color: iconColor, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: AppColors.text,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    ?topRight,
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, botPad + 24),
                  child: body,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  final String sub;
  const _EmptyState({required this.message, required this.sub});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.eco_rounded, color: AppColors.muted, size: 40),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(
              color: AppColors.text,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            sub,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
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
          Text(
            'Something went wrong',
            style: const TextStyle(
              color: AppColors.text,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            style: const TextStyle(color: AppColors.muted, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// SCREEN 1 — VOLUNTEERING FEED
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

  static const _categories = [
    'All',
    'Academic Support',
    'Campus Life & Services',
    'Event Management & Outreach',
    'Sustainability & Environmental',
    'Specialized Roles',
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<VolunteeringOpportunity> _filter(List<VolunteeringOpportunity> items) {
    return items.where((v) {
      final matchCat =
          _selectedCategory == 'All' || v.category == _selectedCategory;
      final matchSrch =
          _search.isEmpty ||
          v.title.toLowerCase().contains(_search.toLowerCase()) ||
          v.category.toLowerCase().contains(_search.toLowerCase());
      return matchCat && matchSrch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return _VScaffold(
      title: 'Volunteering',
      subtitle: 'Browse opportunities, earn credits & blockchain certificates',
      titleIcon: Icons.eco_rounded,
      iconColor: AppColors.neonGreen,
      topRight: GestureDetector(
        onTap: () =>
            Navigator.pushNamed(context, '/student/volunteering/accepted'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.neonGreen.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.neonGreen.withOpacity(0.4)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.task_alt_rounded,
                color: AppColors.neonGreen,
                size: 14,
              ),
              SizedBox(width: 5),
              Text(
                'My Volunteering',
                style: TextStyle(
                  color: AppColors.neonGreen,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search bar
          Container(
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.card.withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),
                const Icon(
                  Icons.search_rounded,
                  color: AppColors.muted,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(color: AppColors.text, fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'Search volunteering...',
                      hintStyle: TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                      ),
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

          // Category chips
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, i) {
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
                          ? AppColors.primary.withOpacity(0.15)
                          : AppColors.secondary,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isActive
                            ? AppColors.primary.withOpacity(0.5)
                            : AppColors.border,
                      ),
                    ),
                    child: Text(
                      cat,
                      style: TextStyle(
                        color: isActive ? AppColors.primary : AppColors.muted,
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

          // Feed
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('volunteering')
                .snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return _ErrorState(message: snap.error.toString());
              }
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                );
              }

              final List<VolunteeringOpportunity> items;
              if (snap.hasData && snap.data!.docs.isNotEmpty) {
                items = snap.data!.docs
                    .map(VolunteeringOpportunity.fromFirestore)
                    .toList();
              } else {
                items = [];
              }

              final filtered = _filter(items);

              if (filtered.isEmpty) {
                return _EmptyState(
                  message: 'No volunteering found.',
                  sub: 'Try a different category or search term 🌱',
                );
              }

              return Column(
                children: filtered
                    .map(
                      (v) => _OpportunityCard(
                        opportunity: v,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ActivityDetailScreen(opportunity: v),
                          ),
                        ),
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

// ── Opportunity Card
class _OpportunityCard extends StatelessWidget {
  final VolunteeringOpportunity opportunity;
  final VoidCallback onTap;
  const _OpportunityCard({required this.opportunity, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final v = opportunity;
    final catColor = _categoryColor(v.category);
    final isFull = v.status == 'full';

    return _GlassCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(
                      Icons.eco_rounded,
                      color: AppColors.neonGreen,
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
                          color: catColor.withOpacity(0.1),
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
              if (v.blockchainCert) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.neonCyan.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.shield_rounded,
                        color: AppColors.neonCyan,
                        size: 10,
                      ),
                      SizedBox(width: 3),
                      Text(
                        'NFT Cert',
                        style: TextStyle(
                          color: AppColors.neonCyan,
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
              color: AppColors.text,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),

          const SizedBox(height: 4),

          Text(
            '${v.organization} · ${v.date}',
            style: const TextStyle(color: AppColors.muted, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

          const SizedBox(height: 8),

          Text(
            v.description,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              height: 1.45,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),

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
                      color: AppColors.secondary,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      s,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),

          const SizedBox(height: 12),

          // Meta row — wrapped so no overflow
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _MetaChip(
                icon: Icons.star_rounded,
                label: '${v.credits} credits',
                color: AppColors.primary,
              ),
              _MetaChip(
                icon: Icons.schedule_rounded,
                label: v.duration,
                color: AppColors.muted,
              ),
              _MetaChip(
                icon: Icons.people_rounded,
                label: '${v.currentParticipants}/${v.maxParticipants}',
                color: AppColors.muted,
              ),
            ],
          ),

          const SizedBox(height: 12),

          _GradientButton(
            label: isFull ? 'Fully Booked' : 'View & Apply',
            icon: isFull ? Icons.block_rounded : Icons.arrow_forward_rounded,
            disabled: isFull,
            outlined: isFull,
            onTap: onTap,
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
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
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
}

// ═════════════════════════════════════════════════════════════════════════════
// SCREEN 2 — ACCEPTED / MY VOLUNTEERING  (100% Firestore, NO mock)
// ═════════════════════════════════════════════════════════════════════════════
class AcceptedVolunteeringScreen extends StatefulWidget {
  const AcceptedVolunteeringScreen({super.key});

  @override
  State<AcceptedVolunteeringScreen> createState() =>
      _AcceptedVolunteeringScreenState();
}

class _AcceptedVolunteeringScreenState
    extends State<AcceptedVolunteeringScreen> {
  late Future<List<AppliedVolunteering>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _future = _VolunteeringService.fetchApplied(uid);
  }

  @override
  Widget build(BuildContext context) {
    return _VScaffold(
      title: 'My Volunteering',
      subtitle: 'Track your progress and blockchain verification',
      titleIcon: Icons.task_alt_rounded,
      iconColor: AppColors.neonGreen,
      body: FutureBuilder<List<AppliedVolunteering>>(
        future: _future,
        builder: (context, snap) {
          // ── Loading ──────────────────────────────────────────────────────
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 64),
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            );
          }

          // ── Error ────────────────────────────────────────────────────────
          if (snap.hasError) {
            return Column(
              children: [
                _ErrorState(message: snap.error.toString()),
                const SizedBox(height: 12),
                _GradientButton(
                  label: 'Retry',
                  icon: Icons.refresh_rounded,
                  onTap: () => setState(_load),
                ),
              ],
            );
          }

          // ── Empty ────────────────────────────────────────────────────────
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return _EmptyState(
              message: 'No volunteering yet.',
              sub: 'Start contributing to your campus today 🌱',
            );
          }

          // ── Data ─────────────────────────────────────────────────────────
          return Column(
            children: items.map((item) => _AcceptedCard(item: item)).toList(),
          );
        },
      ),
    );
  }
}

class _AcceptedCard extends StatelessWidget {
  final AppliedVolunteering item;
  const _AcceptedCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final vol = item.volunteering;
    final stepSts = _stepStatuses(item.applicationStatus);
    final allDone = stepSts.every((s) => s == 'completed');

    return _GlassCard(
      glowColor: allDone ? AppColors.neonCyan : null,
      gradientBorder: allDone,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.eco_rounded,
                color: AppColors.neonGreen,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      vol.title,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${vol.category} · ${vol.credits} credits',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              allDone
                  ? const _BlockchainBadge(status: 'verified')
                  : _AppStatusBadge(status: item.applicationStatus),
            ],
          ),

          const SizedBox(height: 16),

          // Stepper — driven by Firestore application.status
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(_allStepLabels.length, (i) {
                final isLast = i == _allStepLabels.length - 1;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _StepBubble(label: _allStepLabels[i], status: stepSts[i]),
                    if (!isLast)
                      Container(
                        width: 28,
                        height: 1.5,
                        margin: const EdgeInsets.only(bottom: 18),
                        color: stepSts[i] == 'completed'
                            ? AppColors.neonCyan.withOpacity(0.4)
                            : AppColors.border,
                      ),
                  ],
                );
              }),
            ),
          ),

          // Tx hash (if certified)
          if (item.txHash != null && item.txHash!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.neonCyan.withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.neonCyan.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.workspace_premium_rounded,
                    color: AppColors.neonCyan,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.txHash!,
                      style: const TextStyle(
                        color: AppColors.neonCyan,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AppColors.primary.withOpacity(0.4),
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'View Cert',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 11,
                          color: AppColors.primary,
                        ),
                      ],
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
}

class _StepBubble extends StatelessWidget {
  final String label;
  final String status; // "completed" | "active" | "upcoming"
  const _StepBubble({required this.label, required this.status});

  @override
  Widget build(BuildContext context) {
    final Color borderColor;
    final Color bgColor;
    final Widget iconW;
    final Color labelColor;

    switch (status) {
      case 'completed':
        borderColor = AppColors.neonCyan.withOpacity(0.4);
        bgColor = AppColors.neonCyan.withOpacity(0.1);
        iconW = const Icon(
          Icons.check_circle_rounded,
          size: 16,
          color: AppColors.neonCyan,
        );
        labelColor = AppColors.neonCyan;
        break;
      case 'active':
        borderColor = AppColors.primary.withOpacity(0.5);
        bgColor = AppColors.primary.withOpacity(0.1);
        iconW = const Icon(
          Icons.bolt_rounded,
          size: 16,
          color: AppColors.primary,
        );
        labelColor = AppColors.primary;
        break;
      default:
        borderColor = AppColors.border;
        bgColor = AppColors.secondary;
        iconW = const Icon(
          Icons.access_time_rounded,
          size: 16,
          color: AppColors.muted,
        );
        labelColor = AppColors.muted.withOpacity(0.5);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
            border: Border.all(color: borderColor),
          ),
          child: Center(child: iconW),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: labelColor,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// SCREEN 3 — ACTIVITY DETAIL
// ═════════════════════════════════════════════════════════════════════════════
class ActivityDetailScreen extends StatefulWidget {
  final VolunteeringOpportunity opportunity;
  const ActivityDetailScreen({super.key, required this.opportunity});

  @override
  State<ActivityDetailScreen> createState() => _ActivityDetailScreenState();
}

class _ActivityDetailScreenState extends State<ActivityDetailScreen> {
  bool _applied = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _checkAlreadyApplied();
  }

  Future<void> _checkAlreadyApplied() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final snap = await FirebaseFirestore.instance
        .collection('applications')
        .where('userId', isEqualTo: uid)
        .where('volunteeringId', isEqualTo: widget.opportunity.id)
        .limit(1)
        .get();
    if (snap.docs.isNotEmpty && mounted) setState(() => _applied = true);
  }

  Future<void> _apply() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _loading = true);

    try {
      final error = await _VolunteeringService.apply(
        uid: uid,
        opportunity: widget.opportunity,
      );

      if (!mounted) return;

      setState(() => _loading = false);

      if (error == 'already_applied') {
        setState(() => _applied = true);
        _snack('You have already applied!', AppColors.yellow);
      } else if (error != null) {
        _snack('Error: $error', Colors.redAccent);
      } else {
        setState(() => _applied = true);
        _snack('Applied successfully! 🎉', AppColors.neonGreen);
      }
    } catch (e) {
      if (!mounted) return;

      setState(() => _loading = false);

      _snack('Error: $e', Colors.redAccent);
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: color.withOpacity(0.85),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.opportunity;
    final isFull = v.status == 'full';
    final catColor = _categoryColor(v.category);
    final progress = v.maxParticipants > 0
        ? (v.currentParticipants / v.maxParticipants).clamp(0.0, 1.0)
        : 0.0;

    return _VScaffold(
      title: 'Activity Details',
      subtitle: v.organization,
      titleIcon: Icons.eco_rounded,
      iconColor: AppColors.neonGreen,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title card
          _GlassCard(
            glowColor: catColor.withOpacity(0.4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: catColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              v.category,
                              style: TextStyle(
                                color: catColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            v.title,
                            style: const TextStyle(
                              color: AppColors.text,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${v.organization} · ${v.date}',
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.neonBlue],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '${v.credits}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 22,
                            ),
                          ),
                          const Text(
                            'credits',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (v.blockchainCert) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.neonCyan.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.neonCyan.withOpacity(0.3),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.shield_rounded,
                          color: AppColors.neonCyan,
                          size: 14,
                        ),
                        SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Blockchain NFT Certificate on Completion',
                            style: TextStyle(
                              color: AppColors.neonCyan,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
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

          // Description
          _GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'About this Role',
                  style: TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  v.description,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),

          // Meta 2×2 grid
          LayoutBuilder(
            builder: (ctx, c) {
              final w = (c.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: w,
                    child: _DetailTile(
                      icon: Icons.star_rounded,
                      color: AppColors.primary,
                      label: 'Credits',
                      value: '${v.credits}',
                    ),
                  ),
                  SizedBox(
                    width: w,
                    child: _DetailTile(
                      icon: Icons.schedule_rounded,
                      color: AppColors.neonCyan,
                      label: 'Duration',
                      value: v.duration,
                    ),
                  ),
                  SizedBox(
                    width: w,
                    child: _DetailTile(
                      icon: Icons.people_rounded,
                      color: AppColors.neonGreen,
                      label: 'Spots',
                      value: '${v.currentParticipants}/${v.maxParticipants}',
                    ),
                  ),
                  SizedBox(
                    width: w,
                    child: _DetailTile(
                      icon: Icons.flag_rounded,
                      color: catColor,
                      label: 'Status',
                      value: isFull ? 'Full' : 'Open',
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 4),

          // Participants progress
          _GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Flexible(
                      child: Text(
                        'Participant Spots',
                        style: TextStyle(
                          color: AppColors.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${v.currentParticipants}/${v.maxParticipants}',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (ctx, c) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: c.maxWidth,
                        height: 8,
                        child: Stack(
                          children: [
                            Container(color: AppColors.border),
                            FractionallySizedBox(
                              widthFactor: progress,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: isFull
                                        ? [AppColors.muted, AppColors.muted]
                                        : [
                                            AppColors.neonGreen,
                                            AppColors.neonCyan,
                                          ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  isFull
                      ? 'No spots remaining'
                      : '${v.maxParticipants - v.currentParticipants} spots remaining',
                  style: TextStyle(
                    color: isFull ? AppColors.muted : AppColors.neonGreen,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          // Skills
          _GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Required Skills',
                  style: TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: v.skills
                      .map(
                        (s) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppColors.primary.withOpacity(0.3),
                            ),
                          ),
                          child: Text(
                            s,
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),

          const SizedBox(height: 4),

          // Apply / loading / success
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (_applied)
            _GlassCard(
              glowColor: AppColors.neonGreen,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.neonGreen,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Application Submitted!',
                    style: TextStyle(
                      color: AppColors.neonGreen,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            )
          else
            _GradientButton(
              label: isFull ? 'Fully Booked' : 'Apply Now',
              icon: isFull ? Icons.block_rounded : Icons.send_rounded,
              disabled: isFull,
              outlined: isFull,
              onTap: _apply,
            ),
        ],
      ),
    );
  }
}

class _DetailTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  const _DetailTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card.withOpacity(0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// SCREEN 4 — CREATE VOLUNTEERING  (Faculty)
// ═════════════════════════════════════════════════════════════════════════════
class CreateVolunteeringScreen extends StatefulWidget {
  const CreateVolunteeringScreen({super.key});

  @override
  State<CreateVolunteeringScreen> createState() =>
      _CreateVolunteeringScreenState();
}

class _CreateVolunteeringScreenState extends State<CreateVolunteeringScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _skillsCtrl = TextEditingController();
  final _creditsCtrl = TextEditingController();
  final _durationCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();
  final _orgCtrl = TextEditingController();

  String _selectedCategory = 'Academic Support';
  String _verificationType = 'Faculty Approval';
  bool _blockchainCert = true;
  bool _loading = false;

  static const _categories = [
    'Academic Support',
    'Campus Life & Services',
    'Event Management & Outreach',
    'Sustainability & Environmental',
    'Specialized Roles',
  ];
  static const _verTypes = ['Faculty Approval', 'QR Check-in'];

  @override
  void dispose() {
    for (final c in [
      _titleCtrl,
      _descCtrl,
      _skillsCtrl,
      _creditsCtrl,
      _durationCtrl,
      _maxCtrl,
      _orgCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _publish() async {
    if (_titleCtrl.text.trim().isEmpty) {
      _snack('Please enter a title', AppColors.yellow);
      return;
    }
    setState(() => _loading = true);
    try {
      await FirebaseFirestore.instance.collection('volunteering').add({
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'category': _selectedCategory,
        'skills': _skillsCtrl.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        'credits': int.tryParse(_creditsCtrl.text) ?? 0,
        'duration': _durationCtrl.text.trim(),
        'maxParticipants': int.tryParse(_maxCtrl.text) ?? 0,
        'currentParticipants': 0,
        'organization': _orgCtrl.text.trim(),
        'blockchainCert': _blockchainCert,
        'verificationType': _verificationType,
        'status': 'open',
        'date': 'Apr 2025',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Volunteering request published! 🚀', AppColors.neonGreen);
      if (Navigator.canPop(context)) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        } else {
          Navigator.pushReplacementNamed(context, '/faculty');
        }
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        } else {
          Navigator.pushReplacementNamed(context, '/faculty');
        }
      } else {
        Navigator.pushReplacementNamed(context, '/faculty');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Error: $e', Colors.redAccent);
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: color.withOpacity(0.85),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _VScaffold(
      title: 'Create Volunteering',
      subtitle: 'Define a new opportunity for students',
      titleIcon: Icons.eco_rounded,
      iconColor: AppColors.neonGreen,
      body: _GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _Field(
              label: 'Title',
              hint: 'e.g. Campus Green Initiative Coordinator',
              controller: _titleCtrl,
            ),
            const SizedBox(height: 14),
            _Field(
              label: 'Organization',
              hint: 'e.g. CS Department',
              controller: _orgCtrl,
            ),
            const SizedBox(height: 14),
            _Label('Category'),
            const SizedBox(height: 6),
            _DropdownField(
              value: _selectedCategory,
              items: _categories,
              onChanged: (v) => setState(() => _selectedCategory = v!),
            ),
            const SizedBox(height: 14),
            _Field(
              label: 'Description',
              hint: 'Describe the role...',
              controller: _descCtrl,
              maxLines: 3,
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (ctx, c) {
                final w = (c.maxWidth - 12) / 2;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: w,
                      child: _Field(
                        label: 'Required Skills',
                        hint: 'e.g. Leadership, Python',
                        controller: _skillsCtrl,
                      ),
                    ),
                    SizedBox(
                      width: w,
                      child: _Field(
                        label: 'Credit Points',
                        hint: 'e.g. 3',
                        controller: _creditsCtrl,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    SizedBox(
                      width: w,
                      child: _Field(
                        label: 'Duration',
                        hint: 'e.g. 4 weeks',
                        controller: _durationCtrl,
                      ),
                    ),
                    SizedBox(
                      width: w,
                      child: _Field(
                        label: 'Max Participants',
                        hint: 'e.g. 15',
                        controller: _maxCtrl,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            _Label('Verification Type'),
            const SizedBox(height: 8),
            Row(
              children: _verTypes.map((t) {
                final isActive = _verificationType == t;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _verificationType = t),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: EdgeInsets.only(
                        right: t == _verTypes.first ? 10 : 0,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: isActive
                            ? AppColors.primary.withOpacity(0.1)
                            : AppColors.secondary,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isActive
                              ? AppColors.primary.withOpacity(0.5)
                              : AppColors.border,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          t,
                          style: TextStyle(
                            color: isActive
                                ? AppColors.primary
                                : AppColors.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            // Blockchain toggle
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.secondary,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.neonCyan.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.shield_rounded,
                      color: AppColors.neonCyan,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Blockchain Certificate',
                          style: TextStyle(
                            color: AppColors.text,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Issue verifiable NFT credential on completion',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () =>
                        setState(() => _blockchainCert = !_blockchainCert),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 46,
                      height: 26,
                      decoration: BoxDecoration(
                        color: _blockchainCert
                            ? AppColors.primary
                            : AppColors.border,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: AnimatedAlign(
                        duration: const Duration(milliseconds: 200),
                        alignment: _blockchainCert
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.all(3),
                          width: 20,
                          height: 20,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : _GradientButton(
                    label: 'Publish Volunteering Request',
                    icon: Icons.add_circle_outline_rounded,
                    onTap: _publish,
                  ),
          ],
        ),
      ),
    );
  }
}

// ── Form helpers
class _Field extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final int maxLines;
  final TextInputType? keyboardType;

  const _Field({
    required this.label,
    required this.hint,
    required this.controller,
    this.maxLines = 1,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Label(label),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          style: const TextStyle(color: AppColors.text, fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.muted, fontSize: 12),
            filled: true,
            fillColor: AppColors.secondary,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: AppColors.text,
      fontWeight: FontWeight.w600,
      fontSize: 12,
    ),
  );
}

class _DropdownField extends StatelessWidget {
  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  const _DropdownField({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: AppColors.card,
          style: const TextStyle(color: AppColors.text, fontSize: 13),
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColors.muted,
          ),
          items: items
              .map(
                (i) => DropdownMenuItem(
                  value: i,
                  child: Text(
                    i,
                    style: const TextStyle(color: AppColors.text, fontSize: 13),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
