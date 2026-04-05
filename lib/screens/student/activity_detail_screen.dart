// ═══════════════════════════════════════════════════════════════════════════════
// activity_detail_screen.dart   Route: /student/activity-detail
//
// CHANGES vs previous version:
//   Task 1 — _enroll() rewritten as a Firestore TRANSACTION:
//             reads activity doc inside txn → checks enrolled < capacity →
//             duplicate guard → writes enrollment + increments enrolled +
//             sets status='full' when enrolled+1 == capacity.
//   Task 2 — Enroll button disabled when activity.status == 'full'.
//   Task 4 — Static ActivityModel replaced by StreamBuilder on
//             activities/{id}, so enrolled/capacity/status update in real time.
//   Task 5 — Activity status: 'open' | 'full'.
//             Enrollment status: 'Enrolled' | 'Approved' | 'Completed' | 'Verified'.
//   Task 7 — Wrap used for meta chips; withOpacity → withValues.
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:unitrack_flutter/screens/student/student_dashboard_layout.dart';
import 'student_activities_screen.dart' show ActivityModel;

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
// ENROLLMENT STATUS STEPPER  Enrolled → Approved → Completed → Verified
// ─────────────────────────────────────────────────────────────────────────────
const _enrollSteps = ['Enrolled', 'Approved', 'Completed', 'Verified'];

int _stepIndex(String status) {
  final idx = _enrollSteps.indexWhere(
    (s) => s.toLowerCase() == status.toLowerCase(),
  );
  return idx < 0 ? 0 : idx;
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class ActivityDetailScreen extends StatefulWidget {
  const ActivityDetailScreen({super.key});
  @override
  State<ActivityDetailScreen> createState() => _ActivityDetailScreenState();
}

class _ActivityDetailScreenState extends State<ActivityDetailScreen> {
  ActivityModel?
  _activity; // initial model from route args (for id + static fields)
  String _userName = '';
  String _uid = '';
  String? _enrollmentId;
  String? _enrollmentStatus; // null = not enrolled
  bool _loadingEnr = true;
  bool _enrolling = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_activity != null) return;
    final arg = ModalRoute.of(context)?.settings.arguments;
    if (arg is ActivityModel) {
      _activity = arg;
      Future.microtask(_init);
    }
  }

  Future<void> _init() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) return;

    _uid = user.uid;

    try {
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('users').doc(_uid).get(),
        FirebaseFirestore.instance
            .collection('enrollments')
            .where('userId', isEqualTo: _uid)
            .where('activityId', isEqualTo: _activity!.id)
            .limit(1)
            .get(),
      ]);

      if (!mounted) return;

      final userDoc = results[0] as DocumentSnapshot;
      final enrSnap = results[1] as QuerySnapshot;

      final userData = userDoc.data() as Map<String, dynamic>? ?? {};

      final name = userData['name'] as String? ?? '';

      String? enrId;
      String? enrSt;

      if (enrSnap.docs.isNotEmpty) {
        final doc = enrSnap.docs.first;
        final data = doc.data() as Map<String, dynamic>? ?? {};

        enrId = doc.id;
        enrSt = data['status'] as String? ?? 'Enrolled';
      }

      setState(() {
        _userName = name;
        _enrollmentId = enrId;
        _enrollmentStatus = enrSt;
        _loadingEnr = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingEnr = false);
      _snack('Failed to load data', Colors.redAccent);
    }
  }

  // ── Task 1: Transaction-safe enroll ─────────────────────────────────────────
  Future<void> _enroll() async {
    if (_activity == null || _uid.isEmpty) return;
    setState(() => _enrolling = true);

    try {
      final db = FirebaseFirestore.instance;
      final actRef = db.collection('activities').doc(_activity!.id);
      final enrColRef = db.collection('enrollments');

      // TRANSACTION — prevents overbooking / race conditions
      String? newEnrId;
      await db.runTransaction((txn) async {
        final actSnap = await txn.get(actRef);

        final data = actSnap.data() as Map<String, dynamic>;

        final enrolled = (data['enrolled'] as int?) ?? 0;
        final capacity = (data['capacity'] as int?) ?? 0;
        final status = (data['status'] as String?) ?? 'open';

        // ✅ ADD HERE
        if (capacity <= 0) {
          throw Exception('Invalid capacity');
        }

        // ✅ ADD HERE
        final existing = await FirebaseFirestore.instance
            .collection('enrollments')
            .where('userId', isEqualTo: _uid)
            .where('activityId', isEqualTo: _activity!.id)
            .limit(1)
            .get();

        if (existing.docs.isNotEmpty) {
          throw Exception('Already enrolled');
        }

        // existing full check (keep it)
        if (status == 'full' || enrolled >= capacity) {
          throw Exception('Activity is fully booked');
        }

        // Create new enrollment document ref (can't use .add() inside txn)
        final newEnrRef = enrColRef.doc();
        newEnrId = newEnrRef.id;

        txn.set(newEnrRef, {
          'userId': _uid,
          'activityId': _activity!.id,
          'status': 'Enrolled', // Task 5: 'Enrolled' not 'enrolled'
          'appliedAt': FieldValue.serverTimestamp(),
        });

        final newEnrolled = enrolled + 1;
        final Map<String, dynamic> actUpdate = {
          'enrolled': FieldValue.increment(1),
        };
        // Task 1: set full when last spot taken
        if (newEnrolled >= capacity) {
          actUpdate['status'] = 'full'; // Task 5: 'full'
        }
        txn.update(actRef, actUpdate);
      });

      if (!mounted) return;
      setState(() {
        _enrollmentId = newEnrId;
        _enrollmentStatus = 'Enrolled';
        _enrolling = false;
      });
      _snack('Enrolled successfully! 🎉', _C.neonGreen);
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() => _enrolling = false);
      _snack('Error: ${e.message}', Colors.redAccent);
    } catch (e) {
      if (!mounted) return;
      setState(() => _enrolling = false);
      _snack(e.toString().replaceAll('Exception: ', ''), Colors.redAccent);
    }
  }

  void _snack(String msg, Color color) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            msg,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: color.withValues(alpha: 0.9),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_activity == null) {
      return StudentDashboardLayout(
        currentRoute: '/student/activities',
        userName: _userName,
        child: const Center(
          child: Text(
            'No activity selected',
            style: TextStyle(color: _C.muted),
          ),
        ),
      );
    }

    // Task 4: StreamBuilder for real-time capacity/enrolled/status
    return StudentDashboardLayout(
      currentRoute: '/student/activities',
      userName: _userName,
      child: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('activities')
            .doc(_activity!.id)
            .snapshots(),
        builder: (context, snap) {
          // Merge live data onto the original model
          ActivityModel a = _activity!;
          if (snap.hasData && snap.data!.exists) {
            final d = (snap.data!.data() as Map<String, dynamic>?) ?? {};
            a = ActivityModel(
              id: _activity!.id,
              title: (d['title'] as String?) ?? _activity!.title,
              description:
                  (d['description'] as String?) ?? _activity!.description,
              type: (d['type'] as String?) ?? _activity!.type,
              department: (d['department'] as String?) ?? _activity!.department,
              faculty: (d['faculty'] as String?) ?? _activity!.faculty,
              date: (d['date'] as String?) ?? _activity!.date,
              duration: (d['duration'] as String?) ?? _activity!.duration,
              status: (d['status'] as String?) ?? _activity!.status,
              credits: (d['credits'] as int?) ?? _activity!.credits,
              capacity: (d['capacity'] as int?) ?? _activity!.capacity,
              enrolled: (d['enrolled'] as int?) ?? _activity!.enrolled,
              blockchainVerified:
                  (d['blockchainVerified'] as bool?) ??
                  _activity!.blockchainVerified,
            );
          }

          // Task 2 & 5: disable button when status == 'full'
          final isFull = a.status == 'full';
          final fillPct = a.capacity > 0
              ? (a.enrolled / a.capacity).clamp(0.0, 1.0)
              : 0.0;
          final parts = a.faculty.split(' ');
          final initials = parts.length >= 2
              ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
              : a.faculty.isNotEmpty
              ? a.faculty[0].toUpperCase()
              : '?';

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Back button
              GestureDetector(
                onTap: () => Navigator.pushReplacementNamed(
                  context,
                  '/student/activities',
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _C.secondary,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _C.border),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: _C.muted,
                        size: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Back to Activities',
                      style: TextStyle(color: _C.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Title card ─────────────────────────────────────────────────
              _Card(
                glowColor: _C.primary.withValues(alpha: 0.2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Task 7: Wrap for pills
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _typePill(a.type),
                        if (a.blockchainVerified) _onChainBadge(),
                        // Task 2: show 'Full' badge in real time
                        if (isFull) _fullBadge(),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      a.title,
                      style: const TextStyle(
                        color: _C.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${a.department} · ${a.faculty}',
                      style: const TextStyle(color: _C.muted, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 14),

                    // Meta 2×2 — Task 7: Wrap
                    LayoutBuilder(
                      builder: (_, c) {
                        final w = (c.maxWidth - 10) / 2;
                        return Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            SizedBox(
                              width: w,
                              child: _MetaTile(
                                icon: Icons.calendar_today_rounded,
                                color: _C.neonCyan,
                                label: 'Date',
                                value: a.date,
                              ),
                            ),
                            SizedBox(
                              width: w,
                              child: _MetaTile(
                                icon: Icons.schedule_rounded,
                                color: _C.neonBlue,
                                label: 'Duration',
                                value: a.duration,
                              ),
                            ),
                            SizedBox(
                              width: w,
                              child: _MetaTile(
                                icon: Icons.star_rounded,
                                color: _C.primary,
                                label: 'Credits',
                                value: '${a.credits}',
                              ),
                            ),
                            SizedBox(
                              width: w,
                              child: _MetaTile(
                                icon: Icons.people_rounded,
                                color: _C.neonGreen,
                                label: 'Enrolled',
                                value: '${a.enrolled}/${a.capacity}',
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),

              // ── Description ────────────────────────────────────────────────
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'About this Activity',
                      style: TextStyle(
                        color: _C.text,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      a.description,
                      style: const TextStyle(
                        color: _C.muted,
                        fontSize: 13,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Faculty card ───────────────────────────────────────────────
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.person_rounded, color: _C.primary, size: 16),
                        SizedBox(width: 6),
                        Text(
                          'Faculty Coordinator',
                          style: TextStyle(
                            color: _C.text,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [_C.primary, _C.neonBlue],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Center(
                            child: Text(
                              initials,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
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
                                a.faculty,
                                style: const TextStyle(
                                  color: _C.text,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Dept. of ${a.department}',
                                style: const TextStyle(
                                  color: _C.muted,
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Capacity progress ──────────────────────────────────────────
              _Card(
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
                              color: _C.text,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${a.enrolled}/${a.capacity}',
                          style: const TextStyle(color: _C.muted, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    LayoutBuilder(
                      builder: (_, c) => ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          height: 8,
                          width: c.maxWidth,
                          child: Stack(
                            children: [
                              Container(color: _C.secondary),
                              FractionallySizedBox(
                                widthFactor: fillPct,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: isFull
                                          ? [_C.muted, _C.muted]
                                          : [_C.primary, _C.neonBlue],
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
                    // Task 7: "Spots remaining" text
                    Text(
                      isFull
                          ? 'No spots remaining'
                          : '${a.capacity - a.enrolled} spot${a.capacity - a.enrolled == 1 ? '' : 's'} remaining',
                      style: TextStyle(
                        color: isFull ? _C.muted : _C.neonGreen,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Blockchain card ────────────────────────────────────────────
              if (a.blockchainVerified)
                _Card(
                  glowColor: _C.neonCyan.withValues(alpha: 0.15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Row(
                        children: [
                          Icon(
                            Icons.shield_rounded,
                            color: _C.neonCyan,
                            size: 16,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Blockchain Verification',
                            style: TextStyle(
                              color: _C.text,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 10),
                      _InfoRow(
                        label: 'Network',
                        value: 'Ethereum ✔',
                        valueColor: _C.neonCyan,
                      ),
                      SizedBox(height: 6),
                      _InfoRow(
                        label: 'Status',
                        value: 'Verified on-chain',
                        valueColor: _C.neonGreen,
                      ),
                    ],
                  ),
                ),

              // ── Enrollment stepper ─────────────────────────────────────────
              if (_enrollmentStatus != null)
                _Card(
                  glowColor: _C.neonCyan.withValues(alpha: 0.1),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Enrollment Progress',
                        style: TextStyle(
                          color: _C.text,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 14),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: IntrinsicWidth(
                          child: Row(
                            children: List.generate(_enrollSteps.length, (i) {
                              final curIdx = _stepIndex(_enrollmentStatus!);
                              final st = i < curIdx
                                  ? 'completed'
                                  : i == curIdx
                                  ? 'active'
                                  : 'upcoming';
                              final isLast = i == _enrollSteps.length - 1;
                              return Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _StepBubble(
                                    label: _enrollSteps[i],
                                    status: st,
                                  ),
                                  if (!isLast)
                                    Container(
                                      width: 28,
                                      height: 1.5,
                                      margin: const EdgeInsets.only(bottom: 18),
                                      color: st == 'completed'
                                          ? _C.neonCyan.withValues(alpha: 0.4)
                                          : _C.border,
                                    ),
                                ],
                              );
                            }),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Enroll button / state ──────────────────────────────────────
              const SizedBox(height: 4),
              if (_loadingEnr || _enrolling)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: CircularProgressIndicator(color: _C.primary),
                  ),
                )
              else if (_enrollmentStatus != null)
                _Card(
                  glowColor: _C.neonGreen.withValues(alpha: 0.2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: _C.neonGreen,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Enrolled · $_enrollmentStatus',
                          style: const TextStyle(
                            color: _C.neonGreen,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )
              else
                // Task 2: disabled when full
                _EnrollBtn(isFull: isFull, onTap: _enroll),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LOCAL WIDGETS
// ─────────────────────────────────────────────────────────────────────────────
class _Card extends StatelessWidget {
  final Widget child;
  final Color? glowColor;
  const _Card({required this.child, this.glowColor});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _C.card.withValues(alpha: 0.75),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _C.border),
      boxShadow: glowColor != null
          ? [BoxShadow(color: glowColor!, blurRadius: 16)]
          : [],
    ),
    child: child,
  );
}

// Task 7: withValues
Widget _typePill(String type) {
  final colors = <String, Color>{
    'Workshop': _C.primary,
    'Bootcamp': _C.neonBlue,
    'Research': _C.amber,
    'Event': _C.neonCyan,
    'Certification': _C.neonGreen,
    'Seminar': _C.rose,
  };
  final c = colors[type] ?? _C.muted;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: c.withValues(alpha: 0.4)),
    ),
    child: Text(
      type,
      style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w700),
    ),
  );
}

Widget _onChainBadge() => Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  decoration: BoxDecoration(
    color: _C.neonCyan.withValues(alpha: 0.1),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: _C.neonCyan.withValues(alpha: 0.4)),
  ),
  child: const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.verified_rounded, size: 10, color: _C.neonCyan),
      SizedBox(width: 4),
      Text(
        'On-Chain',
        style: TextStyle(
          color: _C.neonCyan,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  ),
);

// Task 2 & 5: 'full' badge shown in title row
Widget _fullBadge() => Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  decoration: BoxDecoration(
    color: _C.rose.withValues(alpha: 0.1),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: _C.rose.withValues(alpha: 0.4)),
  ),
  child: const Text(
    'Full',
    style: TextStyle(color: _C.rose, fontSize: 9, fontWeight: FontWeight.w700),
  ),
);

class _MetaTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label, value;
  const _MetaTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: _C.secondary,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _C.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            color: _C.muted,
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
              color: _C.text,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ],
    ),
  );
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  final Color? valueColor;
  const _InfoRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: const TextStyle(color: _C.muted, fontSize: 12)),
      Flexible(
        child: Text(
          value,
          style: TextStyle(
            color: valueColor ?? _C.text,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

class _StepBubble extends StatelessWidget {
  final String label, status;
  const _StepBubble({required this.label, required this.status});

  @override
  Widget build(BuildContext context) {
    final Color borderC, bgC;
    final Widget iconW;
    final Color labelC;

    switch (status) {
      case 'completed':
        borderC = _C.neonCyan.withValues(alpha: 0.4);
        bgC = _C.neonCyan.withValues(alpha: 0.1);
        iconW = const Icon(
          Icons.check_circle_rounded,
          size: 16,
          color: _C.neonCyan,
        );
        labelC = _C.neonCyan;
        break;
      case 'active':
        borderC = _C.primary.withValues(alpha: 0.5);
        bgC = _C.primary.withValues(alpha: 0.1);
        iconW = const Icon(Icons.bolt_rounded, size: 16, color: _C.primary);
        labelC = _C.primary;
        break;
      default:
        borderC = _C.border;
        bgC = _C.secondary;
        iconW = const Icon(
          Icons.access_time_rounded,
          size: 16,
          color: _C.muted,
        );
        labelC = _C.muted.withValues(alpha: 0.5);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: bgC,
            shape: BoxShape.circle,
            border: Border.all(color: borderC),
          ),
          child: Center(child: iconW),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: labelC,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _EnrollBtn extends StatelessWidget {
  final bool isFull;
  final VoidCallback onTap;
  const _EnrollBtn({required this.isFull, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    // Task 2: onTap = null when full → button is unresponsive
    onTap: isFull ? null : onTap,
    child: Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: isFull
            ? null
            : const LinearGradient(
                colors: [_C.primary, _C.neonBlue],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        color: isFull ? _C.secondary : null,
        borderRadius: BorderRadius.circular(14),
        border: isFull
            ? Border.all(color: _C.muted.withValues(alpha: 0.5))
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isFull ? Icons.block_rounded : Icons.how_to_reg_rounded,
            color: isFull ? _C.muted : Colors.white,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            isFull ? 'Fully Booked' : 'Enroll Now',
            style: TextStyle(
              color: isFull ? _C.muted : Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    ),
  );
}
