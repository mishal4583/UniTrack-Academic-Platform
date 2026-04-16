// ═══════════════════════════════════════════════════════════════════════════════
// faculty_create_activity.dart   Route: /faculty/create
//
// FIX: Removed the inner Scaffold + Stack + Column(Expanded(SingleChildScrollView))
//      that was causing the black screen. The page now returns
//      FacultyDashboardLayout(child: Column(mainAxisSize.min, [...])) directly.
//      FacultyDashboardLayout owns the Scaffold and the scroll view.
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'faculty_dashboard_layout.dart';

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
  static const secondary = Color(0xFF1A2235);
}

// ─────────────────────────────────────────────────────────────────────────────
// AI MATCHING CATALOGUES  (must match Studentrecommendationscreen catalogues)
// ─────────────────────────────────────────────────────────────────────────────
const List<String> _kSkills = [
  'Flutter', 'Python', 'Machine Learning', 'Data Science',
  'Web Development', 'Java', 'C++', 'JavaScript', 'React',
  'Node.js', 'Blockchain', 'UI/UX Design', 'Figma',
  'Content Writing', 'Public Speaking', 'Research',
  'Data Analysis', 'Cybersecurity', 'Cloud Computing',
  'DevOps', 'Android Development', 'IoT', 'Embedded Systems',
  'Database Management', 'Marketing', 'Finance',
  'Business Strategy', 'Molecular Biology', 'Bioinformatics',
  'Lab Research', 'Graphic Design', 'Video Editing',
];

const List<String> _kInterests = [
  'Technology', 'Research & Innovation', 'Entrepreneurship',
  'Community Service', 'Environmental Sustainability',
  'Finance & Economics', 'Healthcare & Wellness',
  'Creative Arts', 'Data & Analytics', 'Artificial Intelligence',
  'Open Source', 'Social Impact', 'Education',
  'Business & Strategy', 'Cybersecurity', 'Blockchain & Web3',
  'Design & Creativity', 'Science & Engineering',
  'Public Speaking & Debate', 'Mental Health & Wellbeing',
  'Sports & Fitness', 'Cultural Activities', 'Networking',
  'Leadership', 'Writing & Journalism', 'Film & Media',
];

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
  final String label, subtitle;
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
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _deptCtrl = TextEditingController();
  final _creditsCtrl = TextEditingController();
  final _capacityCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();

  String _type = 'Workshop';
  bool _blockchainCert = true;
  bool _loading = false;
  DateTime? _startDate;
  DateTime? _endDate;

  List<String> _selectedSkills = [];
  List<String> _selectedCategoryTags = [];

  void _toggleSkill(String s) => setState(() {
    _selectedSkills.contains(s) ? _selectedSkills.remove(s) : _selectedSkills.add(s);
  });
  void _toggleTag(String t) => setState(() {
    _selectedCategoryTags.contains(t) ? _selectedCategoryTags.remove(t) : _selectedCategoryTags.add(t);
  });

  Widget _chip(String label, bool selected, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: selected ? _C.primary.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: selected ? _C.primary : _C.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? _C.primary : _C.muted,
          fontSize: 11,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    ),
  );

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
      _snack('Credits must be > 0', _C.amber);
      return;
    }
    if (capacity <= 0) {
      _snack('Capacity must be > 0', _C.amber);
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _snack('Not signed in', Colors.redAccent);
      return;
    }

    setState(() => _loading = true);
    try {
      String facultyName = user.email ?? user.uid;
      try {
        final uDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final name = (uDoc.data()?['name'] as String?) ?? '';
        if (name.isNotEmpty) facultyName = name;
      } catch (_) {}

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
        'required_skills': _selectedSkills,
        'category_tags': _selectedCategoryTags,
        'target_departments': <String>[],
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Activity published! 🚀', _C.neonGreen);
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/faculty', (r) => false);
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

  // ── build ────────────────────────────────────────────────────────────────
  // The child passed to FacultyDashboardLayout is a plain Column(min).
  // No Scaffold, no Stack, no Expanded, no scroll view here.
  @override
  Widget build(BuildContext context) => FacultyDashboardLayout(
    currentRoute: '/faculty/create',
    userName: '',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min, // ← critical
      children: [
        // Page heading (layout header already shows title, but a sub-heading is fine)
        const Text(
          'Create Academic Activity',
          style: TextStyle(
            color: _C.text,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Define a new activity for students to enroll in',
          style: TextStyle(color: _C.muted, fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 20),

        // ── Basic info ──────────────────────────────────────────────────────
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
              _TF(controller: _titleCtrl, hint: 'e.g. AI Workshop 2025'),
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
              _TF(controller: _deptCtrl, hint: 'e.g. Computer Science'),
            ],
          ),
        ),

        // ── Schedule & capacity ──────────────────────────────────────────────
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _FieldLabel('Credit Points', required: true),
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _FieldLabel('Max Capacity', required: true),
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _FieldLabel('Start Date', required: true),
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
                          crossAxisAlignment: CrossAxisAlignment.start,
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

        // ── AI Matching Tags ──────────────────────────────────────────────────
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _sectionHeader(
                'AI Matching Tags',
                Icons.auto_awesome_rounded,
                _C.amber,
              ),
              const Text(
                'Tag this activity so the recommendation engine surfaces it to the right students.',
                style: TextStyle(color: _C.muted, fontSize: 11),
              ),
              const SizedBox(height: 14),
              const _FieldLabel('Required Skills'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _kSkills
                    .map((s) => _chip(s, _selectedSkills.contains(s), () => _toggleSkill(s)))
                    .toList(),
              ),
              const SizedBox(height: 14),
              const _FieldLabel('Interest Categories'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _kInterests
                    .map((t) => _chip(t, _selectedCategoryTags.contains(t), () => _toggleTag(t)))
                    .toList(),
              ),
            ],
          ),
        ),

        // ── Verification ─────────────────────────────────────────────────────
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
                subtitle: 'Issue verifiable NFT credential on completion',
                icon: Icons.shield_rounded,
                iconColor: _C.neonCyan,
                value: _blockchainCert,
                onChanged: (v) => setState(() => _blockchainCert = v),
              ),
            ],
          ),
        ),

        // ── Publish ───────────────────────────────────────────────────────────
        _PublishButton(
          label: 'Publish Activity',
          loading: _loading,
          onTap: _publish,
        ),
        const SizedBox(height: 8),
      ],
    ),
  );
}
