// ═══════════════════════════════════════════════════════════════════════════════
// faculty_analytics_screen.dart   Route: /faculty/analytics
//
// KEY FIX vs previous version:
//   _TopBar back button — changed from Navigator.pop(context) to:
//
//     if (Navigator.canPop(context)) {
//       Navigator.pop(context);
//     } else {
//       Navigator.pushReplacementNamed(context, '/faculty');
//     }
//
//   WHY: Analytics is reached via pushReplacementNamed from the bottom nav.
//   That means there is no previous route on the stack to pop back to.
//   Calling Navigator.pop() on an empty stack produces a blank white screen
//   on Flutter Web. The canPop() guard means:
//     • If user somehow reached Analytics via pushNamed (e.g. deep-link) → pop works.
//     • If user reached it via pushReplacementNamed → fall back to /faculty safely.
//
// Everything else is identical to the last working version.
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:collection/collection.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DESIGN TOKENS
// ─────────────────────────────────────────────────────────────────────────────
class _C {
  static const bg = Color(0xFF080D19);
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
class _AnalyticsData {
  final int totalActivities;
  final int totalVolunteering;
  final int totalParticipants;
  final int totalCreditsIssued;
  final int verifiedCount;
  final int pendingCount;
  final List<_MonthPoint> monthlyActivity;
  final List<_MonthPoint> creditTrend;
  final Map<String, int> typeDistribution;
  final List<_StudentStat> topStudents;

  const _AnalyticsData({
    required this.totalActivities,
    required this.totalVolunteering,
    required this.totalParticipants,
    required this.totalCreditsIssued,
    required this.verifiedCount,
    required this.pendingCount,
    required this.monthlyActivity,
    required this.creditTrend,
    required this.typeDistribution,
    required this.topStudents,
  });
}

class _MonthPoint {
  final String label;
  final double activities;
  final double participants;
  final double credits;
  const _MonthPoint({
    required this.label,
    this.activities = 0,
    this.participants = 0,
    this.credits = 0,
  });
}

class _StudentStat {
  final String userId;
  final String name;
  final int credits;
  final int activities;
  const _StudentStat({
    required this.userId,
    required this.name,
    required this.credits,
    required this.activities,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// FIRESTORE SERVICE
// ─────────────────────────────────────────────────────────────────────────────
class _AnalyticsService {
  static final _db = FirebaseFirestore.instance;

  static Map<String, dynamic> _safe(DocumentSnapshot doc) =>
      (doc.data() as Map<String, dynamic>?) ?? {};

  static Future<_AnalyticsData> load(String uid) async {
    final results = await Future.wait([
      _db.collection('activities').where('createdBy', isEqualTo: uid).get(),
      _db.collection('volunteering').where('createdBy', isEqualTo: uid).get(),
      _db.collection('enrollments').get(),
      _db.collection('applications').get(),
      _db.collection('users').get(),
    ]);

    final actSnap = results[0] as QuerySnapshot;
    final volSnap = results[1] as QuerySnapshot;
    final enrSnap = results[2] as QuerySnapshot;
    final appSnap = results[3] as QuerySnapshot;
    final usersSnap = results[4] as QuerySnapshot;

    final actIds = actSnap.docs.map((d) => d.id).toSet();
    final volIds = volSnap.docs.map((d) => d.id).toSet();

    final studentSet = <String>{};
    int verified = 0;
    int pending = 0;

    for (final doc in enrSnap.docs) {
      final d = _safe(doc);
      if (!actIds.contains((d['activityId'] as String?) ?? '')) continue;
      final u = (d['userId'] as String?) ?? '';
      if (u.isNotEmpty) studentSet.add(u);
      final s = (d['status'] as String?) ?? '';
      if (s == 'Verified' || s == 'Completed') {
        verified++;
      } else if (s == 'Enrolled') {
        pending++;
      }
    }
    for (final doc in appSnap.docs) {
      final d = _safe(doc);
      if (!volIds.contains((d['volunteeringId'] as String?) ?? '')) continue;
      final u = (d['userId'] as String?) ?? '';
      if (u.isNotEmpty) studentSet.add(u);
      final s = (d['status'] as String?) ?? '';
      if (s == 'Verified' || s == 'Completed') {
        verified++;
      } else if (s == 'Applied') {
        pending++;
      }
    }

    int totalCredits = 0;
    for (final doc in actSnap.docs) {
      final d = _safe(doc);
      totalCredits +=
          ((d['credits'] as int?) ?? 0) * ((d['enrolled'] as int?) ?? 0);
    }
    for (final doc in volSnap.docs) {
      final d = _safe(doc);
      totalCredits +=
          ((d['credits'] as int?) ?? 0) *
          ((d['currentParticipants'] as int?) ?? 0);
    }

    final now = DateTime.now();
    final months = List.generate(
      6,
      (i) => DateTime(now.year, now.month - 5 + i),
    );
    const monthLabels = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    final actPerMonth = <String, double>{};
    final partPerMonth = <String, double>{};
    final credPerMonth = <String, double>{};
    for (final m in months) {
      final k = '${m.year}-${m.month}';
      actPerMonth[k] = partPerMonth[k] = credPerMonth[k] = 0;
    }
    for (final doc in actSnap.docs) {
      final d = _safe(doc);
      final ts = d['createdAt'];
      if (ts is! Timestamp) continue;
      final k = '${ts.toDate().year}-${ts.toDate().month}';
      if (!actPerMonth.containsKey(k)) continue;
      actPerMonth[k] = (actPerMonth[k] ?? 0) + 1;
      partPerMonth[k] = (partPerMonth[k] ?? 0) + ((d['enrolled'] as int?) ?? 0);
      credPerMonth[k] =
          (credPerMonth[k] ?? 0) +
          ((d['credits'] as int?) ?? 0) * ((d['enrolled'] as int?) ?? 0);
    }
    final monthlyActivity = months.map((m) {
      final k = '${m.year}-${m.month}';
      return _MonthPoint(
        label: monthLabels[m.month - 1],
        activities: actPerMonth[k] ?? 0,
        participants: partPerMonth[k] ?? 0,
        credits: credPerMonth[k] ?? 0,
      );
    }).toList();
    final creditTrend = monthlyActivity
        .map((p) => _MonthPoint(label: p.label, credits: p.credits))
        .toList();

    final typeDist = <String, int>{};
    for (final doc in actSnap.docs) {
      final t = (_safe(doc)['type'] as String?) ?? 'Other';
      typeDist[t] = (typeDist[t] ?? 0) + 1;
    }

    final creditMap = <String, int>{};
    final actCountMap = <String, int>{};
    for (final doc in enrSnap.docs) {
      final d = _safe(doc);
      if (!actIds.contains((d['activityId'] as String?) ?? '')) continue;
      final s = (d['status'] as String?) ?? '';
      if (s != 'Completed' && s != 'Verified') continue;
      final u = (d['userId'] as String?) ?? '';
      if (u.isEmpty) continue;
      final activityId = (d['activityId'] as String?) ?? '';
      final actDoc = actSnap.docs.firstWhereOrNull((a) => a.id == activityId);
      final c = actDoc != null ? ((_safe(actDoc)['credits'] as int?) ?? 0) : 0;
      creditMap[u] = (creditMap[u] ?? 0) + c;
      actCountMap[u] = (actCountMap[u] ?? 0) + 1;
    }
    final userNameMap = <String, String>{};
    for (final doc in usersSnap.docs) {
      final d = _safe(doc);
      userNameMap[doc.id] =
          (d['name'] as String?) ?? (d['email'] as String?) ?? doc.id;
    }
    final sorted = creditMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topStudents = sorted
        .take(5)
        .map(
          (e) => _StudentStat(
            userId: e.key,
            name:
                userNameMap[e.key] ??
                e.key.substring(0, math.min(8, e.key.length)),
            credits: e.value,
            activities: actCountMap[e.key] ?? 0,
          ),
        )
        .toList();

    return _AnalyticsData(
      totalActivities: actSnap.docs.length,
      totalVolunteering: volSnap.docs.length,
      totalParticipants: studentSet.length,
      totalCreditsIssued: totalCredits,
      verifiedCount: verified,
      pendingCount: pending,
      monthlyActivity: monthlyActivity,
      creditTrend: creditTrend,
      typeDistribution: typeDist,
      topStudents: topStudents,
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
      ..color = const Color(0xFF1F2937).withValues(alpha: 0.3)
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
    _anim = Tween(begin: 0.3, end: 1.0).animate(_ctrl);
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
        color: _C.neonCyan,
        shape: BoxShape.circle,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// TOP BAR — FIXED back-navigation
// ─────────────────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  const _TopBar();

  // ── THE KEY FIX ─────────────────────────────────────────────────────────────
  // BEFORE: onTap: () => Navigator.pop(context)
  //   → crashes with blank white screen when Analytics was reached via
  //     pushReplacementNamed (nothing to pop to on Flutter Web).
  //
  // AFTER: canPop() guard → pop if possible, otherwise pushReplacementNamed.
  //   → always lands on a valid route no matter how the page was opened.
  // ────────────────────────────────────────────────────────────────────────────
  void _goBack(BuildContext context) {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacementNamed(context, '/faculty');
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(16, topPad + 10, 16, 12),
      decoration: BoxDecoration(
        color: _C.card.withValues(alpha: 0.7),
        border: const Border(bottom: BorderSide(color: _C.border)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _goBack(context),
            child: Container(
              width: 34,
              height: 34,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: _C.secondary,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _C.border),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: _C.muted,
                size: 15,
              ),
            ),
          ),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _C.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.bar_chart_rounded,
              color: _C.primary,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Analytics & Reports',
                  style: TextStyle(
                    color: _C.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Track performance, participation & credit distribution',
                  style: TextStyle(color: _C.muted, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _C.neonCyan.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _C.neonCyan.withValues(alpha: 0.3)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PulsingDot(),
                SizedBox(width: 5),
                Text(
                  'Live',
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

// ─────────────────────────────────────────────────────────────────────────────
// GLASS CARD
// ─────────────────────────────────────────────────────────────────────────────
class _Card extends StatelessWidget {
  final Widget child;
  final Color? glowColor;
  const _Card({required this.child, this.glowColor});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _C.card.withValues(alpha: 0.75),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _C.border),
      boxShadow: glowColor != null
          ? [
              BoxShadow(
                color: glowColor!.withValues(alpha: 0.18),
                blurRadius: 18,
                spreadRadius: 1,
              ),
            ]
          : [],
    ),
    child: child,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// STAT CARD
// ─────────────────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color iconColor;
  final String? trend;
  final bool trendUp;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
    this.trend,
    this.trendUp = true,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _C.card.withValues(alpha: 0.75),
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
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 15),
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
        if (trend != null) ...[
          const SizedBox(height: 4),
          Text(
            '${trendUp ? '↑' : '↓'} $trend',
            style: TextStyle(
              color: trendUp ? _C.neonCyan : _C.rose,
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

// ─────────────────────────────────────────────────────────────────────────────
// BAR CHART
// ─────────────────────────────────────────────────────────────────────────────
class _MonthlyBarChart extends StatelessWidget {
  final List<_MonthPoint> data;
  const _MonthlyBarChart({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox(height: 200);
    final maxAct = data.map((e) => e.activities).fold(0.0, math.max);
    final maxPart = data.map((e) => e.participants).fold(0.0, math.max);
    final maxY = math.max(maxAct, maxPart / 10).ceilToDouble();

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _CardHeader(
            title: 'Monthly Activities & Participation',
            icon: Icons.bar_chart_rounded,
            iconColor: _C.primary,
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              _LegendDot(color: _C.primary, label: 'Activities'),
              SizedBox(width: 16),
              _LegendDot(color: _C.neonCyan, label: 'Participants ÷10'),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                maxY: maxY == 0 ? 10 : maxY + 2,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: _C.border.withValues(alpha: 0.5),
                    strokeWidth: 0.8,
                    dashArray: [4, 4],
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= data.length) return const SizedBox();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            data[i].label,
                            style: const TextStyle(
                              color: _C.muted,
                              fontSize: 10,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (v, _) => Text(
                        v.toInt().toString(),
                        style: const TextStyle(color: _C.muted, fontSize: 9),
                      ),
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                barGroups: List.generate(
                  data.length,
                  (i) => BarChartGroupData(
                    x: i,
                    barsSpace: 4,
                    barRods: [
                      BarChartRodData(
                        toY: data[i].activities,
                        color: _C.primary,
                        width: 10,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                      BarChartRodData(
                        toY: data[i].participants / 10,
                        color: _C.neonCyan,
                        width: 10,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => _C.card,
                    tooltipRoundedRadius: 8,
                    getTooltipItem: (group, _, rod, rodIndex) {
                      final d = data[group.x.toInt()];
                      return rodIndex == 0
                          ? BarTooltipItem(
                              '${d.label}\n${d.activities.toInt()} activities',
                              const TextStyle(
                                color: _C.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          : BarTooltipItem(
                              '${d.participants.toInt()} participants',
                              const TextStyle(
                                color: _C.neonCyan,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            );
                    },
                  ),
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
// LINE CHART
// ─────────────────────────────────────────────────────────────────────────────
class _CreditTrendChart extends StatelessWidget {
  final List<_MonthPoint> data;
  const _CreditTrendChart({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox();
    final maxY = data.map((e) => e.credits).fold(0.0, math.max);

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _CardHeader(
            title: 'Monthly Credit Issuance Trend',
            icon: Icons.show_chart_rounded,
            iconColor: _C.neonGreen,
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                maxY: maxY == 0 ? 100 : maxY * 1.2,
                minY: 0,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: _C.border.withValues(alpha: 0.5),
                    strokeWidth: 0.8,
                    dashArray: [4, 4],
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= data.length) return const SizedBox();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            data[i].label,
                            style: const TextStyle(
                              color: _C.muted,
                              fontSize: 10,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      getTitlesWidget: (v, _) => Text(
                        v.toInt().toString(),
                        style: const TextStyle(color: _C.muted, fontSize: 9),
                      ),
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: List.generate(
                      data.length,
                      (i) => FlSpot(i.toDouble(), data[i].credits),
                    ),
                    isCurved: true,
                    color: _C.neonGreen,
                    barWidth: 2.5,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                        radius: 4,
                        color: _C.neonGreen,
                        strokeColor: _C.bg,
                        strokeWidth: 1.5,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: _C.neonGreen.withValues(alpha: 0.08),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => _C.card,
                    tooltipRoundedRadius: 8,
                    getTooltipItems: (spots) => spots
                        .map(
                          (s) => LineTooltipItem(
                            '${data[s.x.toInt()].label}\n${s.y.toInt()} credits',
                            const TextStyle(
                              color: _C.neonGreen,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                        .toList(),
                  ),
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
// DONUT CHART
// ─────────────────────────────────────────────────────────────────────────────
class _TypeDistributionChart extends StatefulWidget {
  final Map<String, int> data;
  const _TypeDistributionChart({required this.data});
  @override
  State<_TypeDistributionChart> createState() => _TypeDistributionChartState();
}

class _TypeDistributionChartState extends State<_TypeDistributionChart> {
  int _touched = -1;
  static const _colors = [
    _C.primary,
    _C.neonBlue,
    _C.neonCyan,
    _C.neonGreen,
    _C.amber,
    _C.rose,
  ];

  @override
  Widget build(BuildContext context) {
    if (widget.data.isEmpty) {
      return _Card(
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'No activity data yet.',
              style: TextStyle(color: _C.muted, fontSize: 13),
            ),
          ),
        ),
      );
    }
    final entries = widget.data.entries.toList();
    final total = entries.fold(0, (s, e) => s + e.value);

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _CardHeader(
            title: 'Activity Type Distribution',
            icon: Icons.donut_large_rounded,
            iconColor: _C.neonBlue,
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 5,
                child: SizedBox(
                  height: 180,
                  child: PieChart(
                    PieChartData(
                      pieTouchData: PieTouchData(
                        touchCallback: (_, res) => setState(
                          () => _touched =
                              res?.touchedSection?.touchedSectionIndex ?? -1,
                        ),
                      ),
                      sectionsSpace: 3,
                      centerSpaceRadius: 46,
                      sections: List.generate(entries.length, (i) {
                        final color = _colors[i % _colors.length];
                        final pct = total > 0
                            ? (entries[i].value / total * 100)
                            : 0.0;
                        final touched = i == _touched;
                        return PieChartSectionData(
                          value: entries[i].value.toDouble(),
                          color: color,
                          radius: touched ? 54 : 46,
                          title: '${pct.round()}%',
                          titleStyle: TextStyle(
                            color: Colors.white,
                            fontSize: touched ? 13 : 11,
                            fontWeight: FontWeight.bold,
                          ),
                          titlePositionPercentageOffset: 0.55,
                        );
                      }),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 4,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List.generate(entries.length, (i) {
                    final color = _colors[i % _colors.length];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              entries[i].key,
                              style: const TextStyle(
                                color: _C.muted,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${entries[i].value}',
                            style: const TextStyle(
                              color: _C.text,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
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
// TOP STUDENTS
// ─────────────────────────────────────────────────────────────────────────────
class _TopStudentsCard extends StatelessWidget {
  final List<_StudentStat> students;
  const _TopStudentsCard({required this.students});

  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _CardHeader(
          title: 'Top Performing Students',
          icon: Icons.emoji_events_rounded,
          iconColor: _C.amber,
        ),
        const SizedBox(height: 12),
        if (students.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                'No verified completions yet.',
                style: TextStyle(color: _C.muted, fontSize: 12),
              ),
            ),
          )
        else
          ...students.asMap().entries.map((entry) {
            final i = entry.key;
            final s = entry.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _C.secondary.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: i == 0
                      ? _C.amber.withValues(alpha: 0.3)
                      : _C.border.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: i == 0
                            ? [_C.amber, _C.amber.withValues(alpha: 0.6)]
                            : [_C.primary, _C.neonBlue],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          s.name,
                          style: const TextStyle(
                            color: _C.text,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${s.activities} activit${s.activities == 1 ? 'y' : 'ies'}',
                          style: const TextStyle(color: _C.muted, fontSize: 11),
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
                        '${s.credits}',
                        style: const TextStyle(
                          color: _C.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
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
            );
          }),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// VERIFICATION STATUS
// ─────────────────────────────────────────────────────────────────────────────
class _VerificationStatusCard extends StatelessWidget {
  final int verified, pending;
  const _VerificationStatusCard({
    required this.verified,
    required this.pending,
  });

  @override
  Widget build(BuildContext context) {
    final total = verified + pending;
    final rate = total > 0 ? (verified / total * 100).round() : 0;
    final filPct = total > 0 ? (verified / total).clamp(0.0, 1.0) : 0.0;

    return _Card(
      glowColor: _C.neonCyan.withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _CardHeader(
            title: 'Verification Overview',
            icon: Icons.verified_rounded,
            iconColor: _C.neonCyan,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _VerifyStat(
                  label: 'Verified',
                  value: verified,
                  color: _C.neonGreen,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _VerifyStat(
                  label: 'Pending',
                  value: pending,
                  color: _C.amber,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _VerifyStat(
                  label: 'Rate',
                  value: rate,
                  suffix: '%',
                  color: _C.neonCyan,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (ctx, c) => ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: c.maxWidth,
                height: 8,
                child: Stack(
                  children: [
                    Container(color: _C.secondary),
                    FractionallySizedBox(
                      widthFactor: filPct,
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
          const SizedBox(height: 6),
          Text(
            '$verified of $total submissions verified',
            style: const TextStyle(color: _C.muted, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _VerifyStat extends StatelessWidget {
  final String label, suffix;
  final int value;
  final Color color;
  const _VerifyStat({
    required this.label,
    required this.value,
    required this.color,
    this.suffix = '',
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '$value$suffix',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
        ),
        const SizedBox(height: 4),
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
// SHARED HELPERS
// ─────────────────────────────────────────────────────────────────────────────
class _CardHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  const _CardHeader({
    required this.title,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: iconColor, size: 15),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            color: _C.text,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(color: _C.muted, fontSize: 10)),
    ],
  );
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _SummaryRow({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, color: color, size: 13),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(color: _C.muted, fontSize: 12, height: 1.5),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class FacultyAnalyticsScreen extends StatefulWidget {
  const FacultyAnalyticsScreen({super.key});
  @override
  State<FacultyAnalyticsScreen> createState() => _FacultyAnalyticsScreenState();
}

class _FacultyAnalyticsScreenState extends State<FacultyAnalyticsScreen> {
  late Future<_AnalyticsData> _future;
  String _displayName = '';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  // Uses the same mounted-safe pattern as faculty_home.dart:
  // 1. Kick off the data fetch synchronously (no async setState).
  // 2. Fetch display name separately; check mounted before setState.
  void _loadAll() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _future = Future.value(_empty());
      return;
    }

    // Store future synchronously — no setState needed here because
    // this is called from initState (before first build) or from
    // a plain setState wrapper below.
    _future = _AnalyticsService.load(user.uid);

    // Fetch display name in background — mounted check before setState
    FirebaseFirestore.instance.collection('users').doc(user.uid).get().then((
      doc,
    ) {
      if (!mounted) return;
      final data = doc.data();
      final name = (data?['name'] as String?) ?? '';
      if (name.isNotEmpty) setState(() => _displayName = name);
    });
  }

  void _refresh() {
    if (!mounted) return;
    setState(_loadAll);
  }

  _AnalyticsData _empty() => const _AnalyticsData(
    totalActivities: 0,
    totalVolunteering: 0,
    totalParticipants: 0,
    totalCreditsIssued: 0,
    verifiedCount: 0,
    pendingCount: 0,
    monthlyActivity: [],
    creditTrend: [],
    typeDistribution: {},
    topStudents: [],
  );

  @override
  Widget build(BuildContext context) {
    final botPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: _C.bg,
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          Column(
            children: [
              const _TopBar(),
              Expanded(
                child: FutureBuilder<_AnalyticsData>(
                  future: _future,
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: _C.primary),
                      );
                    }
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
                                'Failed to load analytics',
                                style: TextStyle(
                                  color: _C.text,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                snap.error.toString(),
                                style: const TextStyle(
                                  color: _C.muted,
                                  fontSize: 12,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),
                              GestureDetector(
                                onTap: _refresh,
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

                    final data = snap.data ?? _empty();
                    final verRate = (data.verifiedCount + data.pendingCount) > 0
                        ? '${(data.verifiedCount / (data.verifiedCount + data.pendingCount) * 100).round()}%'
                        : '—';

                    return SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, botPad + 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _displayName.isNotEmpty
                                ? 'Dr. $_displayName\'s Analytics'
                                : 'Analytics & Reports',
                            style: const TextStyle(
                              color: _C.text,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Track performance, participation & credit distribution',
                            style: TextStyle(color: _C.muted, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 20),

                          // Stat grid
                          LayoutBuilder(
                            builder: (ctx, c) {
                              const gap = 10.0;
                              final w = (c.maxWidth - gap) / 2;
                              final stats = [
                                (
                                  label: 'Total Activities',
                                  value: '${data.totalActivities}',
                                  icon: Icons.menu_book_rounded,
                                  color: _C.primary,
                                  trend: 'created by you',
                                  up: true,
                                ),
                                (
                                  label: 'Total Participants',
                                  value: '${data.totalParticipants}',
                                  icon: Icons.people_rounded,
                                  color: _C.neonBlue,
                                  trend: 'unique students',
                                  up: true,
                                ),
                                (
                                  label: 'Credits Issued',
                                  value: '${data.totalCreditsIssued}',
                                  icon: Icons.star_rounded,
                                  color: _C.neonCyan,
                                  trend: 'total distributed',
                                  up: true,
                                ),
                                (
                                  label: 'Verification Rate',
                                  value: verRate,
                                  icon: Icons.verified_rounded,
                                  color: _C.neonGreen,
                                  trend: 'approvals',
                                  up: true,
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
                                          iconColor: s.color,
                                          trend: s.trend,
                                          trendUp: s.up,
                                        ),
                                      ),
                                    )
                                    .toList(),
                              );
                            },
                          ),
                          const SizedBox(height: 6),

                          _VerificationStatusCard(
                            verified: data.verifiedCount,
                            pending: data.pendingCount,
                          ),
                          _MonthlyBarChart(data: data.monthlyActivity),
                          _TypeDistributionChart(data: data.typeDistribution),
                          _TopStudentsCard(students: data.topStudents),
                          _CreditTrendChart(data: data.creditTrend),

                          // Summary
                          _Card(
                            glowColor: _C.primary.withValues(alpha: 0.2),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const _CardHeader(
                                  title: 'Summary',
                                  icon: Icons.summarize_rounded,
                                  iconColor: _C.amber,
                                ),
                                const SizedBox(height: 12),
                                _SummaryRow(
                                  icon: Icons.menu_book_rounded,
                                  color: _C.primary,
                                  text:
                                      '${data.totalActivities} activities and ${data.totalVolunteering} volunteering opportunities created',
                                ),
                                const SizedBox(height: 8),
                                _SummaryRow(
                                  icon: Icons.people_rounded,
                                  color: _C.neonBlue,
                                  text:
                                      '${data.totalParticipants} unique students have participated across all your programmes',
                                ),
                                const SizedBox(height: 8),
                                _SummaryRow(
                                  icon: Icons.star_rounded,
                                  color: _C.neonCyan,
                                  text:
                                      '${data.totalCreditsIssued} total credits distributed to participating students',
                                ),
                                const SizedBox(height: 8),
                                _SummaryRow(
                                  icon: Icons.pending_actions_rounded,
                                  color: _C.amber,
                                  text:
                                      '${data.pendingCount} verifications pending — visit Verify panel to take action',
                                ),
                              ],
                            ),
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
