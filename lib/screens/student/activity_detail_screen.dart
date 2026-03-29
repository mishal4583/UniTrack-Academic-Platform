// ═══════════════════════════════════════════════════════════════════════════════
// activity_detail_screen.dart
//
// Pushed from StudentActivitiesScreen with an ActivityModel argument.
// Handles: enroll, duplicate-check, increment enrolled count,
//          status stepper (Enrolled → Completed → Verified).
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'student_activities_screen.dart' show ActivityModel;

// ─────────────────────────────────────────────────────────────────────────────
// ENROLLMENT MODEL
// ─────────────────────────────────────────────────────────────────────────────
class _Enrollment {
  final String id;
  final String status; // Enrolled | Completed | Verified
  const _Enrollment({required this.id, required this.status});
}

// ─────────────────────────────────────────────────────────────────────────────
// STATUS → STEP PROGRESSION
// ─────────────────────────────────────────────────────────────────────────────
const _stepLabels = ['Enrolled', 'Completed', 'Verified'];

List<String> _stepStatuses(String enrollmentStatus) {
  final idx = _stepLabels.indexWhere(
    (s) => s.toLowerCase() == enrollmentStatus.toLowerCase(),
  );
  final cur = idx < 0 ? 0 : idx;
  return List.generate(_stepLabels.length, (i) {
    if (i < cur) return 'completed';
    if (i == cur) return 'active';
    return 'upcoming';
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// DETAIL SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class ActivityDetailScreen extends StatefulWidget {
  final ActivityModel activity;
  const ActivityDetailScreen({super.key, required this.activity});

  @override
  State<ActivityDetailScreen> createState() => _ActivityDetailScreenState();
}

class _ActivityDetailScreenState extends State<ActivityDetailScreen> {
  _Enrollment? _enrollment;
  bool _loading = true;
  bool _enrolling = false;

  @override
  void initState() {
    super.initState();
    _checkEnrollment();
  }

  Future<void> _checkEnrollment() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }

    final snap = await FirebaseFirestore.instance
        .collection('enrollments')
        .where('userId', isEqualTo: uid)
        .where('activityId', isEqualTo: widget.activity.id)
        .limit(1)
        .get();

    if (!mounted) return;
    setState(() {
      _loading = snap.docs.isNotEmpty ? false : false;
      if (snap.docs.isNotEmpty) {
        final d = (snap.docs.first.data() as Map<String, dynamic>?) ?? {};
        _enrollment = _Enrollment(
          id: snap.docs.first.id,
          status: (d['status'] as String?) ?? 'Enrolled',
        );
      }
      _loading = false;
    });
  }

  Future<void> _enroll() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _enrolling = true);

    try {
      // Duplicate check
      final existing = await FirebaseFirestore.instance
          .collection('enrollments')
          .where('userId', isEqualTo: uid)
          .where('activityId', isEqualTo: widget.activity.id)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        final d = (existing.docs.first.data() as Map<String, dynamic>?) ?? {};
        setState(() {
          _enrollment = _Enrollment(
            id: existing.docs.first.id,
            status: (d['status'] as String?) ?? 'Enrolled',
          );
          _enrolling = false;
        });
        _snack('You are already enrolled!', _C.neonCyan);
        return;
      }

      // Write enrollment
      final docRef = await FirebaseFirestore.instance
          .collection('enrollments')
          .add({
            'userId': uid,
            'activityId': widget.activity.id,
            'status': 'Enrolled',
            'appliedAt': FieldValue.serverTimestamp(),
          });

      // Increment enrolled count
      await FirebaseFirestore.instance
          .collection('activities')
          .doc(widget.activity.id)
          .update({'enrolled': FieldValue.increment(1)});

      if (!mounted) return;
      setState(() {
        _enrollment = _Enrollment(id: docRef.id, status: 'Enrolled');
        _enrolling = false;
      });
      _snack('Enrolled successfully! 🎉', _C.neonGreen);
    } catch (e) {
      if (!mounted) return;
      setState(() => _enrolling = false);
      _snack('Error enrolling: $e', Colors.redAccent);
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
        backgroundColor: color.withValues(alpha: 0.9),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.activity;
    final isFull = a.status == 'full';
    final fillPct = a.capacity > 0
        ? (a.enrolled / a.capacity).clamp(0.0, 1.0)
        : 0.0;
    final botPad = MediaQuery.of(context).padding.bottom;

    // Initials from faculty name
    final parts = a.faculty.split(' ');
    final initials = parts.length >= 2
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : a.faculty.isNotEmpty
        ? a.faculty[0].toUpperCase()
        : '?';

    return Scaffold(
      backgroundColor: _C.bg,
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          Column(
            children: [
              _TopBar(
                title: 'Activity Details',
                subtitle: a.department,
                icon: Icons.menu_book_rounded,
                iconColor: _C.primary,
                showBack: true,
              ),

              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: _C.primary),
                      )
                    : SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(16, 16, 16, botPad + 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── TITLE CARD ───────────────────────────────
                            _Card(
                              glowColor: _C.primary.withOpacity(0.3),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      _TypePill(type: a.type),
                                      const SizedBox(width: 8),
                                      if (a.blockchainVerified)
                                        const _BlockchainBadge(
                                          status: 'verified',
                                        ),
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
                                    style: const TextStyle(
                                      color: _C.muted,
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 14),
                                  // Meta 2×2
                                  LayoutBuilder(
                                    builder: (ctx, c) {
                                      final w = (c.maxWidth - 10) / 2;
                                      return Wrap(
                                        spacing: 10,
                                        runSpacing: 10,
                                        children: [
                                          SizedBox(
                                            width: w,
                                            child: _MetaTile(
                                              icon:
                                                  Icons.calendar_today_rounded,
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
                                              value:
                                                  '${a.enrolled}/${a.capacity}',
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),

                            // ── DESCRIPTION ──────────────────────────────
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

                            // ── FACULTY CARD ─────────────────────────────
                            _Card(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(
                                        Icons.person_rounded,
                                        color: _C.primary,
                                        size: 16,
                                      ),
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
                                          borderRadius: BorderRadius.circular(
                                            22,
                                          ),
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
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
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

                            // ── VENUE ────────────────────────────────────
                            _Card(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(
                                        Icons.location_on_rounded,
                                        color: _C.primary,
                                        size: 16,
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        'Venue & Schedule',
                                        style: TextStyle(
                                          color: _C.text,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  const _VenueRow(
                                    emoji: '📍',
                                    text:
                                        'Seminar Hall B, Block 3 — Main Campus',
                                  ),
                                  const SizedBox(height: 6),
                                  const _VenueRow(
                                    emoji: '🕐',
                                    text: '9:00 AM – 4:00 PM',
                                  ),
                                  const SizedBox(height: 6),
                                  const _VenueRow(
                                    emoji: '📋',
                                    text: 'Refer activity prerequisites',
                                  ),
                                ],
                              ),
                            ),

                            // ── CAPACITY PROGRESS ────────────────────────
                            _Card(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
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
                                        style: const TextStyle(
                                          color: _C.muted,
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
                                              Container(color: _C.secondary),
                                              FractionallySizedBox(
                                                widthFactor: fillPct,
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                      colors: isFull
                                                          ? [_C.muted, _C.muted]
                                                          : [
                                                              _C.primary,
                                                              _C.neonBlue,
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
                                        : '${a.capacity - a.enrolled} spots remaining',
                                    style: TextStyle(
                                      color: isFull ? _C.muted : _C.neonGreen,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // ── BLOCKCHAIN CARD ──────────────────────────
                            if (a.blockchainVerified)
                              _Card(
                                glowColor: _C.neonCyan.withOpacity(0.2),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Row(
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
                                    const SizedBox(height: 10),
                                    _InfoRow(
                                      label: 'Network',
                                      value: 'Ethereum ✔',
                                      valueColor: _C.neonCyan,
                                    ),
                                    const SizedBox(height: 6),
                                    _InfoRow(
                                      label: 'Contract',
                                      value: '0x7a2...f3b',
                                      mono: true,
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'Status',
                                          style: TextStyle(
                                            color: _C.muted,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const _BlockchainBadge(
                                          status: 'verified',
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    GestureDetector(
                                      onTap: () {},
                                      child: Container(
                                        height: 36,
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: _C.primary.withOpacity(0.5),
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: const Center(
                                          child: Text(
                                            'View on Explorer',
                                            style: TextStyle(
                                              color: _C.primary,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            // ── ENROLLMENT STATUS STEPPER ────────────────
                            if (_enrollment != null) ...[
                              _Card(
                                glowColor: _C.neonCyan.withOpacity(0.15),
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
                                      child: Row(
                                        children: List.generate(
                                          _stepLabels.length,
                                          (i) {
                                            final statuses = _stepStatuses(
                                              _enrollment!.status,
                                            );
                                            final isLast =
                                                i == _stepLabels.length - 1;
                                            return Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                _StepBubble(
                                                  label: _stepLabels[i],
                                                  status: statuses[i],
                                                ),
                                                if (!isLast)
                                                  Container(
                                                    width: 28,
                                                    height: 1.5,
                                                    margin:
                                                        const EdgeInsets.only(
                                                          bottom: 18,
                                                        ),
                                                    color:
                                                        statuses[i] ==
                                                            'completed'
                                                        ? _C.neonCyan
                                                              .withOpacity(0.4)
                                                        : _C.border,
                                                  ),
                                              ],
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            // ── ENROLL BUTTON ────────────────────────────
                            const SizedBox(height: 4),

                            if (_enrolling)
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 20),
                                  child: CircularProgressIndicator(
                                    color: _C.primary,
                                  ),
                                ),
                              )
                            else if (_enrollment != null)
                              _Card(
                                glowColor: _C.neonGreen.withOpacity(0.3),
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
                                        'Enrolled · ${_enrollment!.status}',
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
                              _GradientButton(
                                label: isFull ? 'Fully Booked' : 'Enroll Now',
                                icon: isFull
                                    ? Icons.block_rounded
                                    : Icons.how_to_reg_rounded,
                                disabled: isFull,
                                outlined: isFull,
                                onTap: _enroll,
                              ),
                          ],
                        ),
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
// COLORS & CONSTANTS (from student_activities_screen)
// ─────────────────────────────────────────────────────────────────────────────
class _C {
  static const Color bg = Color(0xFF0a0e27);
  static const Color card = Color(0xFF1a1f3a);
  static const Color secondary = Color(0xFF16213e);
  static const Color text = Color(0xFFe0e0e0);
  static const Color muted = Color(0xFF999999);
  static const Color border = Color(0xFF2d3561);
  static const Color primary = Color(0xFF00d4ff);
  static const Color neonCyan = Color(0xFF00d4ff);
  static const Color neonBlue = Color(0xFF0099ff);
  static const Color neonGreen = Color(0xFF00ff88);
  static const Color amber = Color(0xFFffaa00);
  static const Color rose = Color(0xFFff0055);
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.02)
      ..strokeWidth = 1;
    const spacing = 40.0;
    for (double i = 0; i < size.width; i += spacing) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += spacing) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => false;
}

class _BlockchainBadge extends StatelessWidget {
  final String status;
  const _BlockchainBadge({required this.status});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: _C.neonCyan.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _C.neonCyan.withValues(alpha: 0.4)),
    ),
    child: Text(
      status.toUpperCase(),
      style: const TextStyle(
        color: _C.neonCyan,
        fontSize: 9,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _TopBar extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final bool showBack;
  const _TopBar({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    this.showBack = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(
      children: [
        if (showBack)
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: _C.text,
              size: 24,
            ),
          ),
        if (showBack) const SizedBox(width: 12),
        Icon(icon, color: iconColor, size: 24),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: _C.text,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(color: _C.muted, fontSize: 12),
            ),
          ],
        ),
      ],
    ),
  );
}

class _GradientButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool disabled;
  final bool outlined;
  final VoidCallback onTap;
  const _GradientButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.disabled = false,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: disabled ? null : onTap,
    child: Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: disabled || outlined
            ? null
            : const LinearGradient(
                colors: [_C.primary, _C.neonBlue],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        color: outlined ? _C.secondary : null,
        borderRadius: BorderRadius.circular(14),
        border: outlined || disabled
            ? Border.all(
                color: disabled ? _C.muted : _C.primary.withValues(alpha: 0.5),
              )
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: disabled
                ? _C.muted
                : outlined
                ? _C.primary
                : Colors.white,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: disabled
                  ? _C.muted
                  : outlined
                  ? _C.primary
                  : Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// LOCAL WIDGETS (private to this file)
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
      color: _C.card.withOpacity(0.75),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _C.border),
      boxShadow: glowColor != null
          ? [BoxShadow(color: glowColor!, blurRadius: 16, spreadRadius: 1)]
          : [],
    ),
    child: child,
  );
}

class _TypePill extends StatelessWidget {
  final String type;
  const _TypePill({required this.type});

  Color _color() {
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
        return _C.rose;
      default:
        return _C.muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _color();
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
}

class _MetaTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
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

class _VenueRow extends StatelessWidget {
  final String emoji;
  final String text;
  const _VenueRow({required this.emoji, required this.text});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(emoji, style: const TextStyle(fontSize: 13)),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(color: _C.muted, fontSize: 12),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool mono;
  const _InfoRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.mono = false,
  });

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
            fontFamily: mono ? 'monospace' : null,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
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
        borderColor = _C.neonCyan.withOpacity(0.4);
        bgColor = _C.neonCyan.withOpacity(0.1);
        iconW = const Icon(
          Icons.check_circle_rounded,
          size: 16,
          color: _C.neonCyan,
        );
        labelColor = _C.neonCyan;
        break;
      case 'active':
        borderColor = _C.primary.withOpacity(0.5);
        bgColor = _C.primary.withOpacity(0.1);
        iconW = const Icon(Icons.bolt_rounded, size: 16, color: _C.primary);
        labelColor = _C.primary;
        break;
      default:
        borderColor = _C.border;
        bgColor = _C.secondary;
        iconW = const Icon(
          Icons.access_time_rounded,
          size: 16,
          color: _C.muted,
        );
        labelColor = _C.muted.withOpacity(0.5);
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
