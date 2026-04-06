// ═══════════════════════════════════════════════════════════════════════════════
// faculty_create_volunteering.dart   Route: /faculty/volunteering/create
//
// FIX: Was using Scaffold + Stack + Column(Expanded(SingleChildScrollView))
//      → caused white screen (same "unbounded height" crash as create_activity).
//      Now uses FacultyDashboardLayout(child: Column(mainAxisSize: min)).
//      No Scaffold, no Stack, no Expanded, no scroll view in this file.
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
// FORM WIDGETS
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
          gradient: const LinearGradient(colors: [_C.neonGreen, _C.neonBlue]),
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
                  const Icon(Icons.eco_rounded, color: Colors.white, size: 18),
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

class _VerifyTypeSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  static const _types = ['Faculty Approval', 'QR Check-in'];
  const _VerifyTypeSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) => Row(
    children: _types.asMap().entries.map((entry) {
      final t = entry.value;
      final isActive = selected == t;
      final isFirst = entry.key == 0;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(t),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: isFirst
                ? const EdgeInsets.only(right: 10)
                : EdgeInsets.zero,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: isActive
                  ? _C.primary.withValues(alpha: 0.1)
                  : _C.secondary,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive ? _C.primary.withValues(alpha: 0.5) : _C.border,
              ),
            ),
            child: Center(
              child: Text(
                t,
                style: TextStyle(
                  color: isActive ? _C.primary : _C.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      );
    }).toList(),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class FacultyCreateVolunteeringScreen extends StatefulWidget {
  const FacultyCreateVolunteeringScreen({super.key});
  @override
  State<FacultyCreateVolunteeringScreen> createState() =>
      _FacultyCreateVolunteeringScreenState();
}

class _FacultyCreateVolunteeringScreenState
    extends State<FacultyCreateVolunteeringScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _skillsCtrl = TextEditingController();
  final _orgCtrl = TextEditingController();
  final _creditCtrl = TextEditingController();
  final _durCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();

  String _category = 'Academic Support';
  String _verifyType = 'Faculty Approval';
  bool _blockchainCert = true;
  bool _loading = false;

  static const _categories = [
    'Academic Support',
    'Campus Life & Services',
    'Event Management & Outreach',
    'Sustainability & Environmental',
    'Specialized Roles',
  ];

  @override
  void dispose() {
    for (final c in [
      _titleCtrl,
      _descCtrl,
      _skillsCtrl,
      _orgCtrl,
      _creditCtrl,
      _durCtrl,
      _maxCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
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

  String _monthName(int m) => [
    '',
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
  ][m];

  Future<void> _publish() async {
    final title = _titleCtrl.text.trim();
    final desc = _descCtrl.text.trim();
    if (title.isEmpty) {
      _snack('Title is required', _C.amber);
      return;
    }
    if (desc.isEmpty) {
      _snack('Description is required', _C.amber);
      return;
    }
    if (_creditCtrl.text.isEmpty) {
      _snack('Credit points are required', _C.amber);
      return;
    }
    if (_maxCtrl.text.isEmpty) {
      _snack('Max participants is required', _C.amber);
      return;
    }

    final credits = int.tryParse(_creditCtrl.text.trim()) ?? 0;
    final maxP = int.tryParse(_maxCtrl.text.trim()) ?? 0;
    if (credits <= 0) {
      _snack('Credits must be > 0', _C.amber);
      return;
    }
    if (maxP <= 0) {
      _snack('Max participants must be > 0', _C.amber);
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _snack('Not signed in', Colors.redAccent);
      return;
    }

    setState(() => _loading = true);

    try {
      final skillsList = _skillsCtrl.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final now = DateTime.now();
      final dateStr = '${_monthName(now.month)} ${now.year}';

      await FirebaseFirestore.instance.collection('volunteering').add({
        'title': title,
        'description': desc,
        'category': _category,
        'organization': _orgCtrl.text.trim().isEmpty
            ? 'General'
            : _orgCtrl.text.trim(),
        'skills': skillsList,
        'credits': credits,
        'duration': _durCtrl.text.trim(),
        'maxParticipants': maxP,
        'currentParticipants': 0,
        'status': 'open',
        'blockchainCert': _blockchainCert,
        'verificationType': _verifyType,
        'createdBy': user.uid,
        'date': dateStr,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Volunteering published! 🌱', _C.neonGreen);
      if (!mounted) return;
      // Use pushReplacementNamed — never pop() from a peer page
      Navigator.pushReplacementNamed(context, '/faculty');
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Error: $e', Colors.redAccent);
    }
  }

  // ── build ────────────────────────────────────────────────────────────────────
  // Returns FacultyDashboardLayout(child: Column(mainAxisSize.min)).
  // NO Scaffold, NO Stack, NO Expanded, NO SingleChildScrollView here.
  // The layout owns all of those.
  @override
  Widget build(BuildContext context) => FacultyDashboardLayout(
    currentRoute: '/faculty/volunteering/create',
    userName: '',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min, // ← critical: no unbounded height
      children: [
        // Page heading
        const Text(
          'Create Volunteering',
          style: TextStyle(
            color: _C.text,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Define a new volunteering opportunity for students',
          style: TextStyle(color: _C.muted, fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 20),

        // ── Basic info ────────────────────────────────────────────────────────
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _sectionHeader(
                'Basic Information',
                Icons.eco_rounded,
                _C.neonGreen,
              ),
              const _FieldLabel('Title', required: true),
              _TF(
                controller: _titleCtrl,
                hint: 'e.g. Campus Green Initiative Coordinator',
              ),
              const SizedBox(height: 14),
              const _FieldLabel('Organization / Dept.'),
              _TF(controller: _orgCtrl, hint: 'e.g. Eco Club'),
              const SizedBox(height: 14),
              const _FieldLabel('Category', required: true),
              _Dropdown(
                value: _category,
                items: _categories,
                onChanged: (v) => setState(() => _category = v!),
              ),
              const SizedBox(height: 14),
              const _FieldLabel('Description', required: true),
              _TF(
                controller: _descCtrl,
                hint: 'Describe the volunteering role and responsibilities...',
                maxLines: 3,
              ),
            ],
          ),
        ),

        // ── Details & capacity ────────────────────────────────────────────────
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _sectionHeader(
                'Details & Capacity',
                Icons.tune_rounded,
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
                              controller: _creditCtrl,
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
                            const _FieldLabel(
                              'Max Participants',
                              required: true,
                            ),
                            _TF(
                              controller: _maxCtrl,
                              hint: 'e.g. 15',
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
                            const _FieldLabel('Duration'),
                            _TF(controller: _durCtrl, hint: 'e.g. 4 weeks'),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: w,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _FieldLabel('Required Skills'),
                            _TF(
                              controller: _skillsCtrl,
                              hint: 'e.g. Leadership, Python',
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),

        // ── Verification settings ─────────────────────────────────────────────
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _sectionHeader(
                'Verification Settings',
                Icons.verified_rounded,
                _C.primary,
              ),
              const _FieldLabel('Verification Type'),
              const SizedBox(height: 6),
              _VerifyTypeSelector(
                selected: _verifyType,
                onChanged: (v) => setState(() => _verifyType = v),
              ),
              const SizedBox(height: 14),
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
          label: 'Publish Volunteering Request',
          loading: _loading,
          onTap: _publish,
        ),
        const SizedBox(height: 8),
      ],
    ),
  );
}
