// ═══════════════════════════════════════════════════════════════════════════════
// faculty_analytics_screen.dart   Route: /faculty/analytics
//
// FIX 1 — White screen when pressing back from Analytics:
//   _TopBar previously called Navigator.pop(context) unconditionally.
//   Analytics is a PEER route reached via pushReplacementNamed, so there is
//   nothing below it to pop → navigator stack empties → blank screen.
//   SOLUTION: Check Navigator.canPop() first; fall back to pushReplacementNamed.
//
// FIX 2 — "setState() callback returned a Future":
//   _load() was called directly from initState() as an async void, which made
//   initState() implicitly return a Future — Flutter detects this and throws.
//   SOLUTION: Assign _future synchronously in initState; use Future.microtask
//   for anything that needs setState after an await.
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:unitrack_flutter/screens/faculty/faculty_dashboard_layout.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DESIGN TOKENS
// ─────────────────────────────────────────────────────────────────────────────
class _C {
  static const bg = Color(0xFF080D19); // used for chart dot stroke colour
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
class _AnalyticsData {
  final int totalActivities, totalVolunteering, totalParticipants;
  final int totalCreditsIssued, verifiedCount, pendingCount;
  final List<_MonthPoint> monthlyActivity, creditTrend;
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
  final double activities, participants, credits;
  const _MonthPoint({
    required this.label,
    this.activities = 0,
    this.participants = 0,
    this.credits = 0,
  });
}

class _StudentStat {
  final String userId, name;
  final int credits, activities;
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
      (doc.data() ?? {}) as Map<String, dynamic>;

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
    int verified = 0, pending = 0;
    for (final doc in enrSnap.docs) {
      final d = _safe(doc);
      if (!actIds.contains((d['activityId'] as String?) ?? '')) continue;
      final u = (d['userId'] as String?) ?? '';
      if (u.isNotEmpty) studentSet.add(u);
      final s = (d['status'] as String?) ?? '';
      if (s == 'Verified' || s == 'Completed')
        verified++;
      else if (s == 'Enrolled')
        pending++;
    }
    for (final doc in appSnap.docs) {
      final d = _safe(doc);
      if (!volIds.contains((d['volunteeringId'] as String?) ?? '')) continue;
      final u = (d['userId'] as String?) ?? '';
      if (u.isNotEmpty) studentSet.add(u);
      final s = (d['status'] as String?) ?? '';
      if (s == 'Verified' || s == 'Completed')
        verified++;
      else if (s == 'Applied')
        pending++;
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

    final actPM = <String, double>{};
    final partPM = <String, double>{};
    final credPM = <String, double>{};
    for (final m in months) {
      final key = '${m.year}-${m.month}';
      actPM[key] = 0;
      partPM[key] = 0;
      credPM[key] = 0;
    }
    for (final doc in actSnap.docs) {
      final d = _safe(doc);
      final ts = d['createdAt'];
      if (ts is! Timestamp) continue;
      final dt = ts.toDate();
      final key = '${dt.year}-${dt.month}';
      if (!actPM.containsKey(key)) continue;
      actPM[key] = (actPM[key] ?? 0) + 1;
      partPM[key] = (partPM[key] ?? 0) + ((d['enrolled'] as int?) ?? 0);
      credPM[key] =
          (credPM[key] ?? 0) +
          ((d['credits'] as int?) ?? 0) * ((d['enrolled'] as int?) ?? 0);
    }

    final monthlyActivity = months.map((m) {
      final key = '${m.year}-${m.month}';
      return _MonthPoint(
        label: monthLabels[m.month - 1],
        activities: actPM[key] ?? 0,
        participants: partPM[key] ?? 0,
        credits: credPM[key] ?? 0,
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
      final u2 = (d['userId'] as String?) ?? '';
      if (u2.isEmpty) continue;
      final aid = (d['activityId'] as String?) ?? '';
      final aDoc = actSnap.docs.where((a) => a.id == aid).firstOrNull;
      final c = aDoc != null ? ((_safe(aDoc)['credits'] as int?) ?? 0) : 0;
      creditMap[u2] = (creditMap[u2] ?? 0) + c;
      actCountMap[u2] = (actCountMap[u2] ?? 0) + 1;
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
// ─────────────────────────────────────────────────────────────────────────────
// SHARED WIDGETS
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
// CHARTS
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
                      getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
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

class _TypeDistributionChart extends StatefulWidget {
  final Map<String, int> data;
  const _TypeDistributionChart({required this.data});
  @override
  State<_TypeDistributionChart> createState() => _TypeDistributionChartState();
}

class _TypeDistributionChartState extends State<_TypeDistributionChart> {
  int _touchedIndex = -1;
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
                          () => _touchedIndex =
                              res?.touchedSection?.touchedSectionIndex ?? -1,
                        ),
                      ),
                      sectionsSpace: 3,
                      centerSpaceRadius: 46,
                      sections: List.generate(entries.length, (i) {
                        final e = entries[i];
                        final color = _colors[i % _colors.length];
                        final pct = total > 0 ? (e.value / total * 100) : 0.0;
                        final touched = i == _touchedIndex;
                        return PieChartSectionData(
                          value: e.value.toDouble(),
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
                    final e = entries[i];
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
                              e.key,
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
                            '${e.value}',
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
  String _uid = '';

  @override
  void initState() {
    super.initState();
    // ── Assign _future synchronously — required by `late`, no setState needed.
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _uid = user.uid;
      _future = _AnalyticsService.load(_uid);
    } else {
      _future = Future.error('Not signed in');
    }
    // Fetch display name after mount — deferred safely.
    Future.microtask(_fetchDisplayName);
  }

  Future<void> _fetchDisplayName() async {
    if (_uid.isEmpty || !mounted) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .get();
      if (!mounted) return;
      final name = ((doc.data()?['name']) as String?) ?? '';
      if (name.isNotEmpty) setState(() => _displayName = name);
    } catch (_) {}
  }

  // Refresh: create Future synchronously, assign in sync setState — no Future returned.
  void _refresh() {
    if (!mounted || _uid.isEmpty) return;
    final f = _AnalyticsService.load(_uid);
    setState(() => _future = f);
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
  Widget build(BuildContext context) => FacultyDashboardLayout(
    currentRoute: '/faculty/analytics',
    userName: _displayName,
    child: FutureBuilder<_AnalyticsData>(
      future: _future,
      builder: (context, snap) {
        // ── Loading ──────────────────────────────────────────────────────────
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 80),
            child: Center(child: CircularProgressIndicator(color: _C.primary)),
          );
        }

        // ── Error ─────────────────────────────────────────────────────────────
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
                    style: const TextStyle(color: _C.muted, fontSize: 12),
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

        // ── Data ──────────────────────────────────────────────────────────────
        final data = snap.data ?? _empty();
        final total = data.verifiedCount + data.pendingCount;
        final verRate = total > 0
            ? '${(data.verifiedCount / total * 100).round()}%'
            : '—';

        // FacultyDashboardLayout owns Scaffold + SingleChildScrollView.
        // child must be Column(mainAxisSize: MainAxisSize.min) — NO Expanded,
        // NO Scaffold, NO Stack with Positioned.fill here.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Heading
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
        );
      },
    ),
  );
}
