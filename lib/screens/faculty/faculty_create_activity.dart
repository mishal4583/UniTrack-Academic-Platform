// ═══════════════════════════════════════════════════════════════════════════════
// faculty_create_activity.dart   Route: /faculty/create
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
  static const text = Color(0xFFEFF3F8);
  static const muted = Color(0xFF7E8A9A);
  static const border = Color(0xFF1F2937);
  static const secondary = Color(0xFF1A2235);
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
// SHARED FORM WIDGETS
// ─────────────────────────────────────────────────────────────────────────────
class _FieldLabel extends StatelessWidget {
  final String text;
  final bool required;
  const _FieldLabel(this.text, {this.required = false});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              color: _C.text,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (required) ...[
          const SizedBox(width: 3),
          const Text(
            '*',
            style: TextStyle(
              color: _C.amber,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ],
    ),
  );
}

class _TF extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final TextInputType? keyboardType;

  const _TF({
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    maxLines: maxLines,
    keyboardType: keyboardType,
    style: const TextStyle(color: _C.text, fontSize: 13),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: _C.muted, fontSize: 12),
      filled: true,
      fillColor: _C.secondary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _C.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _C.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _C.primary, width: 1.4),
      ),
    ),
  );
}

class _Dropdown extends StatelessWidget {
  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  const _Dropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(
      color: _C.secondary,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _C.border),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        dropdownColor: _C.card,
        style: const TextStyle(color: _C.text, fontSize: 13),
        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _C.muted),
        items: items
            .map(
              (i) => DropdownMenuItem(
                value: i,
                child: Text(
                  i,
                  style: const TextStyle(color: _C.text, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    ),
  );
}

class _Toggle extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _Toggle({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _C.secondary,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _C.border),
    ),
    child: Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
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
                subtitle,
                style: const TextStyle(color: _C.muted, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () => onChanged(!value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 46,
            height: 26,
            decoration: BoxDecoration(
              color: value ? _C.primary : _C.border,
              borderRadius: BorderRadius.circular(13),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 200),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
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
  );
}

class _SectionCard extends StatelessWidget {
  final Widget child;
  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _C.card.withValues(alpha: 0.75),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _C.border),
    ),
    child: child,
  );
}

Widget _sectionHeader(String title, IconData icon, Color color) => Padding(
  padding: const EdgeInsets.only(bottom: 14),
  child: Row(
    children: [
      Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 16),
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
  ),
);

// ─────────────────────────────────────────────────────────────────────────────
// TOP BAR
// ─────────────────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  const _TopBar({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
  });

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
            onTap: () => Navigator.pop(context),
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
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
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
                    fontSize: 16,
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
}

// ─────────────────────────────────────────────────────────────────────────────
// PUBLISH BUTTON
// ─────────────────────────────────────────────────────────────────────────────
class _PublishButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onTap;
  const _PublishButton({
    required this.label,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: loading ? null : onTap,
    child: Opacity(
      opacity: loading ? 0.7 : 1.0,
      child: Container(
        height: 46,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_C.primary, _C.neonBlue]),
          borderRadius: BorderRadius.circular(12),
        ),
        child: loading
            ? const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.rocket_launch_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
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

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class FacultyCreateActivityScreen extends StatefulWidget {
  const FacultyCreateActivityScreen({super.key});

  @override
  State<FacultyCreateActivityScreen> createState() =>
      _FacultyCreateActivityScreenState();
}

class _FacultyCreateActivityScreenState
    extends State<FacultyCreateActivityScreen> {
  // Controllers
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _deptCtrl = TextEditingController();
  final _creditsCtrl = TextEditingController();
  final _capacityCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();

  // State
  String _type = 'Workshop';
  bool _blockchainCert = true;
  bool _loading = false;
  DateTime? _startDate;
  DateTime? _endDate;

  static const _types = [
    'Workshop',
    'Seminar',
    'Bootcamp',
    'Competition',
    'Research',
    'Conference',
    'Hackathon',
  ];

  @override
  void dispose() {
    for (final c in [
      _titleCtrl,
      _descCtrl,
      _deptCtrl,
      _creditsCtrl,
      _capacityCtrl,
      _locationCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _fmtDate(DateTime? d) => d == null
      ? 'Not set'
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? _startDate : _endDate) ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _C.primary,
            onPrimary: Colors.white,
            surface: _C.card,
            onSurface: _C.text,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) _endDate = null;
      } else {
        _endDate = picked;
      }
    });
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

  Future<void> _publish() async {
    final title = _titleCtrl.text.trim();
    final desc = _descCtrl.text.trim();
    final dept = _deptCtrl.text.trim();

    if (title.isEmpty) {
      _snack('Activity title is required', _C.amber);
      return;
    }
    if (desc.isEmpty) {
      _snack('Description is required', _C.amber);
      return;
    }
    if (_creditsCtrl.text.isEmpty) {
      _snack('Credit points are required', _C.amber);
      return;
    }
    if (_capacityCtrl.text.isEmpty) {
      _snack('Max capacity is required', _C.amber);
      return;
    }
    if (_startDate == null) {
      _snack('Please select a start date', _C.amber);
      return;
    }

    final credits = int.tryParse(_creditsCtrl.text.trim()) ?? 0;
    final capacity = int.tryParse(_capacityCtrl.text.trim()) ?? 0;

    if (credits <= 0) {
      _snack('Credits must be greater than 0', _C.amber);
      return;
    }
    if (capacity <= 0) {
      _snack('Capacity must be greater than 0', _C.amber);
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _snack('Not signed in', Colors.redAccent);
      return;
    }

    setState(() => _loading = true);

    try {
      // Fetch faculty display name
      String facultyName = user.email ?? user.uid;
      try {
        final uDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final data = uDoc.data();
        final name = (data?['name'] as String?) ?? '';
        if (name.isNotEmpty) facultyName = name;
      } catch (_) {}

      // Duration string
      String duration = '';
      if (_endDate != null && _startDate != null) {
        final diff = _endDate!.difference(_startDate!).inDays + 1;
        duration = '$diff Day${diff == 1 ? '' : 's'}';
      }

      await FirebaseFirestore.instance.collection('activities').add({
        'title': title,
        'description': desc,
        'type': _type,
        'department': dept.isEmpty ? 'General' : dept,
        'faculty': facultyName,
        'createdBy': user.uid,
        'credits': credits,
        'capacity': capacity,
        'enrolled': 0,
        'status': 'open',
        'date': _fmtDate(_startDate),
        'startDate': _startDate!.toIso8601String(),
        'endDate': _endDate?.toIso8601String() ?? '',
        'duration': duration,
        'location': _locationCtrl.text.trim(),
        'blockchainVerified': _blockchainCert,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Activity published successfully! 🚀', _C.neonGreen);
      if (!mounted) return;

      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil('/faculty', (route) => false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Error: $e', Colors.redAccent);
    }
  }

  Widget _dateButton({
    required String label,
    required DateTime? date,
    required bool isStart,
  }) => GestureDetector(
    onTap: () => _pickDate(isStart: isStart),
    child: Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: _C.secondary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: date != null ? _C.primary.withValues(alpha: 0.5) : _C.border,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.calendar_today_rounded,
            size: 16,
            color: date != null ? _C.primary : _C.muted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              date != null ? _fmtDate(date) : label,
              style: TextStyle(
                color: date != null ? _C.text : _C.muted,
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    ),
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
              _TopBar(
                title: 'Create Academic Activity',
                subtitle: 'Define a new activity for students to enroll in',
                icon: Icons.menu_book_rounded,
                iconColor: _C.primary,
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, botPad + 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── BASIC INFO ─────────────────────────────────────
                      _SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _sectionHeader(
                              'Basic Information',
                              Icons.info_outline_rounded,
                              _C.primary,
                            ),
                            const _FieldLabel('Activity Title', required: true),
                            _TF(
                              controller: _titleCtrl,
                              hint: 'e.g. AI Workshop 2025',
                            ),
                            const SizedBox(height: 14),
                            const _FieldLabel('Activity Type', required: true),
                            _Dropdown(
                              value: _type,
                              items: _types,
                              onChanged: (v) => setState(() => _type = v!),
                            ),
                            const SizedBox(height: 14),
                            const _FieldLabel('Description', required: true),
                            _TF(
                              controller: _descCtrl,
                              hint:
                                  'Describe the activity, learning outcomes and requirements...',
                              maxLines: 4,
                            ),
                            const SizedBox(height: 14),
                            const _FieldLabel('Department'),
                            _TF(
                              controller: _deptCtrl,
                              hint: 'e.g. Computer Science',
                            ),
                          ],
                        ),
                      ),

                      // ── CAPACITY & SCHEDULE ────────────────────────────
                      _SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _sectionHeader(
                              'Schedule & Capacity',
                              Icons.event_rounded,
                              _C.neonCyan,
                            ),
                            LayoutBuilder(
                              builder: (ctx, c) {
                                const gap = 12.0;
                                final w = (c.maxWidth - gap) / 2;
                                return Wrap(
                                  spacing: gap,
                                  runSpacing: 12,
                                  children: [
                                    SizedBox(
                                      width: w,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const _FieldLabel(
                                            'Credit Points',
                                            required: true,
                                          ),
                                          _TF(
                                            controller: _creditsCtrl,
                                            hint: 'e.g. 3',
                                            keyboardType: TextInputType.number,
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                      width: w,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const _FieldLabel(
                                            'Max Capacity',
                                            required: true,
                                          ),
                                          _TF(
                                            controller: _capacityCtrl,
                                            hint: 'e.g. 50',
                                            keyboardType: TextInputType.number,
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                      width: w,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const _FieldLabel(
                                            'Start Date',
                                            required: true,
                                          ),
                                          _dateButton(
                                            label: 'Pick start date',
                                            date: _startDate,
                                            isStart: true,
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                      width: w,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const _FieldLabel('End Date'),
                                          _dateButton(
                                            label: 'Pick end date',
                                            date: _endDate,
                                            isStart: false,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 14),
                            const _FieldLabel('Venue / Location'),
                            _TF(
                              controller: _locationCtrl,
                              hint: 'e.g. Auditorium Block A, Room 301',
                            ),
                          ],
                        ),
                      ),

                      // ── BLOCKCHAIN ─────────────────────────────────────
                      _SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _sectionHeader(
                              'Verification',
                              Icons.verified_rounded,
                              _C.neonGreen,
                            ),
                            _Toggle(
                              label: 'Blockchain Certificate',
                              subtitle:
                                  'Issue verifiable NFT credential on completion',
                              icon: Icons.shield_rounded,
                              iconColor: _C.neonCyan,
                              value: _blockchainCert,
                              onChanged: (v) =>
                                  setState(() => _blockchainCert = v),
                            ),
                          ],
                        ),
                      ),

                      // ── PUBLISH ────────────────────────────────────────
                      _PublishButton(
                        label: 'Publish Activity',
                        loading: _loading,
                        onTap: _publish,
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
