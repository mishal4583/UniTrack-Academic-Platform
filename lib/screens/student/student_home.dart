// ═══════════════════════════════════════════════════════════════════════════════
// student_home.dart — Production-ready, 100% real Firestore data
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
  static const text = Color(0xFFEFF3F8);
  static const muted = Color(0xFF7E8A9A);
  static const border = Color(0xFF1F2937);
  static const yellow = Color(0xFFFBBF24);
  static const secondary = Color(0xFF1A2235);
}

// ─────────────────────────────────────────────────────────────────────────────
// DASHBOARD DATA MODEL
// ─────────────────────────────────────────────────────────────────────────────
class _DashboardData {
  final int totalCredits;
  final int volunteeringCount;
  final int volunteeringCredits;
  final int certificatesCount;
  final int activitiesCount;
  final int rank;
  final List<_ActivityRow> recentActivities;
  final List<_CertRow> recentCerts;

  const _DashboardData({
    required this.totalCredits,
    required this.volunteeringCount,
    required this.volunteeringCredits,
    required this.certificatesCount,
    required this.activitiesCount,
    required this.rank,
    required this.recentActivities,
    required this.recentCerts,
  });
}

class _ActivityRow {
  final String title;
  final int credits;
  final String date;
  final String status;
  final String type;
  const _ActivityRow({
    required this.title,
    required this.credits,
    required this.date,
    required this.status,
    required this.type,
  });
}

class _CertRow {
  final String title;
  final String issuer;
  final String date;
  final String txHash;
  const _CertRow({
    required this.title,
    required this.issuer,
    required this.date,
    required this.txHash,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// FIRESTORE SERVICE — all reads in one place, no nested futures in UI
// ─────────────────────────────────────────────────────────────────────────────
class _HomeService {
  static final _db = FirebaseFirestore.instance;

  /// Safe map accessor from a DocumentSnapshot.
  static Map<String, dynamic> _data(DocumentSnapshot doc) =>
      (doc.data() as Map<String, dynamic>?) ?? {};

  static Future<_DashboardData> load(String uid) async {
    // ── 1. Parallel fetches that don't depend on each other ─────────────────
    final results = await Future.wait([
      // [0] applications for this user
      _db.collection('applications').where('userId', isEqualTo: uid).get(),
      // [1] certificates count
      _db.collection('certificates').where('userId', isEqualTo: uid).get(),
      // [2] activities (for feed + count)
      _db
          .collection('activities')
          .where('userId', isEqualTo: uid)
          .orderBy('date', descending: true)
          .limit(5)
          .get(),
      // [3] total activities count
      _db.collection('activities').where('userId', isEqualTo: uid).get(),
      // [4] certificates feed (limit 3)
      _db
          .collection('certificates')
          .where('userId', isEqualTo: uid)
          .orderBy('date', descending: true)
          .limit(3)
          .get(),
      // [5] all users for rank (lightweight — just ids & credits)
      _db.collection('users').get(),
    ]);

    final appSnap = results[0] as QuerySnapshot;
    final certSnap = results[1] as QuerySnapshot;
    final actFeedSnap = results[2] as QuerySnapshot;
    final actAllSnap = results[3] as QuerySnapshot;
    final certFeedSnap = results[4] as QuerySnapshot;
    final usersSnap = results[5] as QuerySnapshot;

    // ── 2. Volunteering join — batch fetch volunteering docs ─────────────────
    final volIds = appSnap.docs
        .map((d) => (_data(d)['volunteeringId'] as String?) ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final Map<String, Map<String, dynamic>> volMap = {};
    const batchSize = 30;
    for (int i = 0; i < volIds.length; i += batchSize) {
      final chunk = volIds.sublist(i, (i + batchSize).clamp(0, volIds.length));
      final snap = await _db
          .collection('volunteering')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snap.docs) {
        volMap[doc.id] = _data(doc);
      }
    }

    // ── 3. Compute volunteering credits (status == "Completed") ─────────────
    int volunteeringCredits = 0;
    for (final appDoc in appSnap.docs) {
      final ad = _data(appDoc);
      final vid = (ad['volunteeringId'] as String?) ?? '';
      final vol = volMap[vid];
      if (vol == null) continue;
      if ((ad['status'] as String?)?.toLowerCase() == 'completed') {
        volunteeringCredits += (vol['credits'] as int?) ?? 0;
      }
    }

    // ── 4. Compute activity credits (status == "verified") ───────────────────
    int activityCredits = 0;
    for (final doc in actAllSnap.docs) {
      final d = _data(doc);
      if ((d['status'] as String?)?.toLowerCase() == 'verified') {
        activityCredits += (d['credits'] as int?) ?? 0;
      }
    }

    final totalCredits = volunteeringCredits + activityCredits;

    // ── 5. Rank — count users with more credits than current user ────────────
    int rank = 1;
    for (final doc in usersSnap.docs) {
      if (doc.id == uid) continue;
      final d = _data(doc);
      if (((d['totalCredits'] as int?) ?? 0) > totalCredits) rank++;
    }

    // ── 6. Activity feed rows ────────────────────────────────────────────────
    final recentActivities = actFeedSnap.docs.map((doc) {
      final d = _data(doc);
      return _ActivityRow(
        title: (d['title'] as String?) ?? '',
        credits: (d['credits'] as int?) ?? 0,
        date: (d['date'] as String?) ?? '',
        status: (d['status'] as String?) ?? 'pending',
        type: (d['type'] as String?) ?? '',
      );
    }).toList();

    // ── 7. Certificate feed rows ─────────────────────────────────────────────
    final recentCerts = certFeedSnap.docs.map((doc) {
      final d = _data(doc);
      return _CertRow(
        title: (d['title'] as String?) ?? '',
        issuer: (d['issuer'] as String?) ?? '',
        date: (d['date'] as String?) ?? '',
        txHash: (d['txHash'] as String?) ?? '0x---',
      );
    }).toList();

    return _DashboardData(
      totalCredits: totalCredits,
      volunteeringCount: appSnap.docs.length,
      volunteeringCredits: volunteeringCredits,
      certificatesCount: certSnap.docs.length,
      activitiesCount: actAllSnap.docs.length,
      rank: rank,
      recentActivities: recentActivities,
      recentCerts: recentCerts,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GRID PAINTER
// ─────────────────────────────────────────────────────────────────────────────
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

// ─────────────────────────────────────────────────────────────────────────────
// GLASS CARD
// ─────────────────────────────────────────────────────────────────────────────
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final Color? glowColor;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.glowColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: padding ?? const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card.withOpacity(0.7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 1),
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

// ─────────────────────────────────────────────────────────────────────────────
// STAT CARD
// ─────────────────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final String? trend;
  final bool trendUp;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.trend,
    this.trendUp = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card.withOpacity(0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
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
                    color: AppColors.muted,
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
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: AppColors.primary, size: 15),
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
                color: AppColors.text,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (trend != null) ...[
            const SizedBox(height: 4),
            Text(
              '${trendUp ? '↑' : '↓'} $trend',
              style: TextStyle(
                color: trendUp ? AppColors.neonCyan : Colors.redAccent,
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
}

// ─────────────────────────────────────────────────────────────────────────────
// STAT GRID — 2-column responsive, data-driven
// ─────────────────────────────────────────────────────────────────────────────
class _StatGrid extends StatelessWidget {
  final _DashboardData data;
  const _StatGrid({required this.data});

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        label: 'Total Credits',
        value: '${data.totalCredits}',
        icon: Icons.star_rounded,
        trend: 'from activities',
        trendUp: true,
      ),
      (
        label: 'Volunteering',
        value: '${data.volunteeringCount}',
        icon: Icons.eco_rounded,
        trend: '${data.volunteeringCredits} credits',
        trendUp: true,
      ),
      (
        label: 'Certificates',
        value: '${data.certificatesCount}',
        icon: Icons.workspace_premium_rounded,
        trend: 'earned',
        trendUp: true,
      ),
      (
        label: 'Activities',
        value: '${data.activitiesCount}',
        icon: Icons.menu_book_rounded,
        trend: 'total',
        trendUp: true,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final cardWidth = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: items
              .map(
                (e) => SizedBox(
                  width: cardWidth,
                  child: _StatCard(
                    label: e.label,
                    value: e.value,
                    icon: e.icon,
                    trend: e.trend,
                    trendUp: e.trendUp,
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BLOCKCHAIN BADGE
// ─────────────────────────────────────────────────────────────────────────────
class BlockchainBadge extends StatelessWidget {
  final String status;
  const BlockchainBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final isVerified = status == 'verified';
    final isPending = status == 'pending';

    final Color badgeColor;
    final Color borderColor;
    final IconData badgeIcon;
    final String badgeLabel;

    if (isVerified) {
      badgeColor = AppColors.neonCyan;
      borderColor = AppColors.neonCyan.withOpacity(0.4);
      badgeIcon = Icons.check_circle_rounded;
      badgeLabel = 'Verified';
    } else if (isPending) {
      badgeColor = AppColors.yellow;
      borderColor = AppColors.yellow.withOpacity(0.4);
      badgeIcon = Icons.access_time_rounded;
      badgeLabel = 'Pending';
    } else {
      badgeColor = AppColors.muted;
      borderColor = AppColors.border;
      badgeIcon = Icons.shield_outlined;
      badgeLabel = 'Not Verified';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badgeIcon, size: 11, color: badgeColor),
          const SizedBox(width: 4),
          Text(
            badgeLabel,
            style: TextStyle(
              color: badgeColor,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GRADIENT BUTTON
// ─────────────────────────────────────────────────────────────────────────────
class GradientButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final List<Color> colors;
  final bool outlined;

  const GradientButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.colors = const [AppColors.primary, AppColors.neonBlue],
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          gradient: outlined ? null : LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(12),
          border: outlined
              ? Border.all(color: AppColors.primary, width: 1.4)
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: outlined ? AppColors.primary : Colors.white,
              size: 16,
            ),
            const SizedBox(width: 6),
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CREDIT PROGRESS BAR
// ─────────────────────────────────────────────────────────────────────────────
class _CreditProgressBar extends StatelessWidget {
  final int earned;
  final int total;
  const _CreditProgressBar({required this.earned, required this.total});

  @override
  Widget build(BuildContext context) {
    final progress = total > 0 ? (earned / total).clamp(0.0, 1.0) : 0.0;
    return GlassCard(
      glowColor: AppColors.primary,
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
                  color: AppColors.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              Text(
                '$earned / $total credits',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (ctx, c) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: c.maxWidth,
                  height: 10,
                  child: Stack(
                    children: [
                      Container(color: AppColors.border),
                      FractionallySizedBox(
                        widthFactor: progress,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [AppColors.primary, AppColors.neonBlue],
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
          const SizedBox(height: 8),
          Text(
            earned >= total
                ? 'Graduation requirement met! 🎉'
                : '${total - earned} more credits needed for graduation',
            style: const TextStyle(color: AppColors.muted, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ACTIVITY TILE
// ─────────────────────────────────────────────────────────────────────────────
class _ActivityTile extends StatelessWidget {
  final _ActivityRow item;
  const _ActivityTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final isVerified = item.status == 'verified';
    return GlassCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isVerified
                  ? Icons.check_circle_rounded
                  : Icons.access_time_rounded,
              color: isVerified ? AppColors.neonCyan : AppColors.yellow,
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
                    color: AppColors.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '${item.type} · ${item.date}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
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
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 6),
              BlockchainBadge(status: item.status),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CERTIFICATE TILE
// ─────────────────────────────────────────────────────────────────────────────
class _CertTile extends StatelessWidget {
  final _CertRow item;
  const _CertTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      glowColor: AppColors.neonCyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.workspace_premium_rounded,
                color: AppColors.neonCyan,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.title,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${item.issuer} · ${item.date}',
            style: const TextStyle(color: AppColors.muted, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  item.txHash,
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.primary.withOpacity(0.4)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Verify',
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
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VOLUNTEERING SUMMARY CARD — dynamic data
// ─────────────────────────────────────────────────────────────────────────────
class _VolunteeringCard extends StatelessWidget {
  final int credits;
  final int count;
  final VoidCallback onTap;
  const _VolunteeringCard({
    required this.credits,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      glowColor: AppColors.neonGreen,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.neonGreen.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.eco_rounded,
              color: AppColors.neonGreen,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '🌱 Volunteering Credits Earned',
                  style: TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  count > 0
                      ? '$credits credits from $count volunteering activit${count == 1 ? 'y' : 'ies'}'
                      : 'No volunteering activities yet',
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$credits',
                style: const TextStyle(
                  color: AppColors.neonGreen,
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                ),
              ),
              const Text(
                'credits',
                style: TextStyle(color: AppColors.muted, fontSize: 9),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BLOCKCHAIN RECORDS CARD
// ─────────────────────────────────────────────────────────────────────────────
class _BlockchainRecordsCard extends StatelessWidget {
  final int onChain;
  final int verified;
  const _BlockchainRecordsCard({required this.onChain, required this.verified});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.neonCyan.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.shield_rounded,
              color: AppColors.neonCyan,
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
                    color: AppColors.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 3),
                Text(
                  'Your on-chain academic footprint',
                  style: TextStyle(color: AppColors.muted, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          _StatPair(
            value: '$onChain',
            label: 'On-Chain',
            color: AppColors.text,
          ),
          const SizedBox(width: 16),
          _StatPair(
            value: '$verified',
            label: 'Verified',
            color: AppColors.neonCyan,
          ),
        ],
      ),
    );
  }
}

class _StatPair extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _StatPair({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: AppColors.muted, fontSize: 9),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DID CARD
// ─────────────────────────────────────────────────────────────────────────────
class _DIDCard extends StatelessWidget {
  final String did;
  const _DIDCard({required this.did});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      glowColor: AppColors.primary,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.neonCyan],
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
                    color: AppColors.text,
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
                    color: AppColors.muted,
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
          const BlockchainBadge(status: 'verified'),
        ],
      ),
    );
  }
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
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(_ctrl);
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
        color: AppColors.neonCyan,
        shape: BoxShape.circle,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// TOP APP BAR
// ─────────────────────────────────────────────────────────────────────────────
class _StudentTopBar extends StatelessWidget {
  final String userName;
  const _StudentTopBar({required this.userName});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: MediaQuery.of(context).padding.top + 8,
        bottom: 10,
      ),
      decoration: BoxDecoration(
        color: AppColors.card.withOpacity(0.7),
        border: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // Logo
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.neonBlue],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.shield_rounded,
              color: Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 8),
          const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'UniTrack',
                style: TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              Text(
                'Student Portal',
                style: TextStyle(color: AppColors.muted, fontSize: 10),
              ),
            ],
          ),
          const Spacer(),
          // Network badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.neonCyan.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.neonCyan.withOpacity(0.3)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PulsingDot(),
                SizedBox(width: 6),
                Text(
                  'Connected ✔',
                  style: TextStyle(
                    color: AppColors.neonCyan,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Bell
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.border.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.notifications_rounded,
                  color: AppColors.muted,
                  size: 17,
                ),
              ),
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  width: 15,
                  height: 15,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text(
                      '3',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          // Wallet
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.border.withOpacity(0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.account_balance_wallet_rounded,
                  color: AppColors.neonCyan,
                  size: 13,
                ),
                SizedBox(width: 4),
                Text(
                  '0x7f...3a2b',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Avatar
          Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.neonBlue],
              ),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOTTOM NAV — uses pushReplacementNamed
// ─────────────────────────────────────────────────────────────────────────────
class _NavItem {
  final String label;
  final IconData icon;
  final String route;
  final bool highlight;
  const _NavItem({
    required this.label,
    required this.icon,
    required this.route,
    this.highlight = false,
  });
}

const _navItems = [
  _NavItem(label: 'Home', icon: Icons.dashboard_rounded, route: '/student'),
  _NavItem(
    label: 'Volunteer',
    icon: Icons.eco_rounded,
    route: '/student/volunteering',
    highlight: true,
  ),
  _NavItem(
    label: 'Activities',
    icon: Icons.menu_book_rounded,
    route: '/student/activities',
  ),
  _NavItem(
    label: 'Portfolio',
    icon: Icons.person_rounded,
    route: '/student/profile',
  ),
  _NavItem(
    label: 'Wallet',
    icon: Icons.workspace_premium_rounded,
    route: '/student/certificates',
  ),
];

class _StudentBottomNav extends StatelessWidget {
  final String currentRoute;
  const _StudentBottomNav({required this.currentRoute});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: _navItems.map((item) {
              final isActive = currentRoute == item.route;
              final Color iconColor = item.highlight
                  ? (isActive
                        ? AppColors.neonGreen
                        : AppColors.neonGreen.withOpacity(0.5))
                  : (isActive ? AppColors.primary : AppColors.muted);

              return Expanded(
                child: GestureDetector(
                  // Use pushReplacementNamed to avoid stacking nav pages
                  onTap: () =>
                      Navigator.pushReplacementNamed(context, item.route),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(item.icon, size: 21, color: iconColor),
                      const SizedBox(height: 3),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w500,
                          color: iconColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EMPTY SECTION STATE
// ─────────────────────────────────────────────────────────────────────────────
class _EmptySectionState extends StatelessWidget {
  final String message;
  const _EmptySectionState({required this.message});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Row(
        children: [
          const Icon(Icons.inbox_rounded, color: AppColors.muted, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN — STUDENT HOME
// ─────────────────────────────────────────────────────────────────────────────
class StudentHome extends StatefulWidget {
  const StudentHome({super.key});

  @override
  State<StudentHome> createState() => _StudentHomeState();
}

class _StudentHomeState extends State<StudentHome> {
  late Future<_DashboardData> _dashFuture;
  String _userName = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    // Load user name
    FirebaseFirestore.instance.collection('users').doc(user.uid).get().then((
      doc,
    ) {
      final d = doc.data() ?? {};
      final name = (d['name'] as String?) ?? '';
      if (mounted && name.isNotEmpty) setState(() => _userName = name);
    });
    // Load dashboard data
    _dashFuture = _HomeService.load(user.uid);
  }

  void _refresh() => setState(_init);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      extendBody: true,
      bottomNavigationBar: const _StudentBottomNav(currentRoute: '/student'),
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          Column(
            children: [
              _StudentTopBar(userName: _userName),
              Expanded(
                child: FutureBuilder<_DashboardData>(
                  future: _dashFuture,
                  builder: (context, snap) {
                    // ── Loading ──────────────────────────────────────────────
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      );
                    }

                    // ── Error ────────────────────────────────────────────────
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
                                'Failed to load dashboard',
                                style: TextStyle(
                                  color: AppColors.text,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                snap.error.toString(),
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 12,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),
                              GradientButton(
                                label: 'Retry',
                                icon: Icons.refresh_rounded,
                                onTap: _refresh,
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    // ── Data ─────────────────────────────────────────────────
                    final data = snap.data!;
                    const requiredCredits = 60;

                    return SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        16,
                        16,
                        MediaQuery.of(context).padding.bottom + 72,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── HEADER ────────────────────────────────────────
                          Text(
                            'Welcome back, ${_userName.isNotEmpty ? _userName : 'Student'} 👋',
                            style: const TextStyle(
                              color: AppColors.text,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Track your academic activities and blockchain-verified credits',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),

                          const SizedBox(height: 16),

                          // ── ACTION BUTTONS ────────────────────────────────
                          Row(
                            children: [
                              Expanded(
                                child: GradientButton(
                                  label: 'Apply Volunteering',
                                  icon: Icons.eco_rounded,
                                  onTap: () => Navigator.pushNamed(
                                    context,
                                    '/student/volunteering',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: GradientButton(
                                  label: 'Enroll Activity',
                                  icon: Icons.flash_on_rounded,
                                  onTap: () => Navigator.pushNamed(
                                    context,
                                    '/student/activities',
                                  ),
                                  outlined: true,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 20),

                          // ── STAT GRID ─────────────────────────────────────
                          _StatGrid(data: data),

                          const SizedBox(height: 10),

                          // Rank — full width
                          _StatCard(
                            label: 'Rank',
                            value: '#${data.rank}',
                            icon: Icons.trending_up_rounded,
                            trend: 'among all students',
                            trendUp: true,
                          ),

                          const SizedBox(height: 20),

                          // ── CREDIT PROGRESS ───────────────────────────────
                          _CreditProgressBar(
                            earned: data.totalCredits,
                            total: requiredCredits,
                          ),

                          const SizedBox(height: 20),

                          // ── RECENT ACTIVITIES ─────────────────────────────
                          const Text(
                            'Recent Activities',
                            style: TextStyle(
                              color: AppColors.text,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 10),

                          data.recentActivities.isEmpty
                              ? const _EmptySectionState(
                                  message:
                                      'No activities yet. Enroll to earn credits!',
                                )
                              : Column(
                                  children: data.recentActivities
                                      .map((a) => _ActivityTile(item: a))
                                      .toList(),
                                ),

                          const SizedBox(height: 20),

                          // ── CERTIFICATES ──────────────────────────────────
                          const Text(
                            'Digital Certificates',
                            style: TextStyle(
                              color: AppColors.text,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 10),

                          data.recentCerts.isEmpty
                              ? const _EmptySectionState(
                                  message:
                                      'No certificates yet. Complete activities to earn them!',
                                )
                              : Column(
                                  children: data.recentCerts
                                      .map((c) => _CertTile(item: c))
                                      .toList(),
                                ),

                          if (data.recentCerts.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            GradientButton(
                              label: 'View All Certificates',
                              icon: Icons.arrow_forward_rounded,
                              onTap: () => Navigator.pushNamed(
                                context,
                                '/student/certificates',
                              ),
                              outlined: true,
                            ),
                          ],

                          const SizedBox(height: 20),

                          // ── VOLUNTEERING SUMMARY ──────────────────────────
                          _VolunteeringCard(
                            credits: data.volunteeringCredits,
                            count: data.volunteeringCount,
                            onTap: () => Navigator.pushNamed(
                              context,
                              '/student/volunteering',
                            ),
                          ),

                          // ── BLOCKCHAIN RECORDS ────────────────────────────
                          _BlockchainRecordsCard(
                            onChain:
                                data.activitiesCount + data.volunteeringCount,
                            verified: data.certificatesCount,
                          ),

                          // ── DID BADGE ─────────────────────────────────────
                          _DIDCard(
                            did: FirebaseAuth.instance.currentUser?.uid != null
                                ? 'did:ethr:0x${FirebaseAuth.instance.currentUser!.uid.substring(0, 8)}...${FirebaseAuth.instance.currentUser!.uid.substring(FirebaseAuth.instance.currentUser!.uid.length - 4)}'
                                : 'did:ethr:0x---',
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
