// ═══════════════════════════════════════════════════════════════════════════════
// Studentrecommendationscreen.dart   Route: /student/recommendations
//
// AI Recommendation Engine — content-based filtering
//   matchScore = (0.45 × skillScore) + (0.35 × interestScore) + (0.20 × deptScore)
//   Displayed as integer 0–100 (match %)
//   Items scoring 0 are hidden when preferences are set; otherwise dept-sorted.
//
// Preferences (skills + interests) are persisted to users/{uid} in Firestore.
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'student_dashboard_layout.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DESIGN TOKENS
// ─────────────────────────────────────────────────────────────────────────────
class _C {
  static const card      = Color(0xFF111827);
  static const primary   = Color(0xFF8B5CF6);
  static const neonBlue  = Color(0xFF3B82F6);
  static const neonCyan  = Color(0xFF06B6D4);
  static const neonGreen = Color(0xFF10B981);
  static const amber     = Color(0xFFF59E0B);
  static const text      = Color(0xFFEFF3F8);
  static const muted     = Color(0xFF7E8A9A);
  static const border    = Color(0xFF1F2937);
  static const secondary = Color(0xFF1A2235);
}

// ─────────────────────────────────────────────────────────────────────────────
// STATIC CATALOGUES  (skills & interests the student can pick from)
// ─────────────────────────────────────────────────────────────────────────────
const List<String> _kAllSkills = [
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

const List<String> _kAllInterests = [
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
// ALGORITHM
// Content-based filtering — returns 0–100 integer match score.
// ─────────────────────────────────────────────────────────────────────────────
int _computeScore({
  required String userDept,
  required List<String> userSkills,
  required List<String> userInterests,
  required List<String> requiredSkills,
  required List<String> categoryTags,
  required List<String> targetDepts,
}) {
  // Skill overlap (45%)
  double skillScore = 0;
  if (requiredSkills.isNotEmpty && userSkills.isNotEmpty) {
    final lowerReq = requiredSkills.map((s) => s.toLowerCase()).toSet();
    final matched =
        userSkills.where((s) => lowerReq.contains(s.toLowerCase())).length;
    skillScore = matched / requiredSkills.length;
  }

  // Interest overlap (35%)
  double interestScore = 0;
  if (categoryTags.isNotEmpty && userInterests.isNotEmpty) {
    final lowerTags = categoryTags.map((t) => t.toLowerCase()).toSet();
    final matched = userInterests
        .where((i) => lowerTags.contains(i.toLowerCase()))
        .length;
    interestScore = matched / categoryTags.length;
  }

  // Department match (20%)
  // Empty targetDepts → open to all → full credit
  double deptScore;
  if (targetDepts.isEmpty) {
    deptScore = 1.0;
  } else {
    final lowerDepts = targetDepts.map((d) => d.toLowerCase()).toSet();
    deptScore = lowerDepts.contains(userDept.toLowerCase()) ? 1.0 : 0.0;
  }

  final raw =
      (0.45 * skillScore) + (0.35 * interestScore) + (0.20 * deptScore);
  return (raw * 100).round();
}

// ─────────────────────────────────────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────────────────────────────────────
class _UserProfile {
  final String name, department;
  final int credits;
  final List<String> skills, interests;
  const _UserProfile({
    required this.name,
    required this.department,
    required this.credits,
    required this.skills,
    required this.interests,
  });
  bool get hasPreferences => skills.isNotEmpty || interests.isNotEmpty;
}

class _ScoredActivity {
  final String id, title, description, type, department;
  final int credits, enrolled, capacity, score;
  final List<String> requiredSkills;
  const _ScoredActivity({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.department,
    required this.credits,
    required this.enrolled,
    required this.capacity,
    required this.score,
    required this.requiredSkills,
  });
  bool get isFull => capacity > 0 && enrolled >= capacity;
  double get fillPct =>
      capacity > 0 ? (enrolled / capacity).clamp(0.0, 1.0) : 0.0;
}

class _ScoredVol {
  final String id, title, description, category, organization;
  final int credits, current, max, score;
  final List<String> skills;
  const _ScoredVol({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.organization,
    required this.credits,
    required this.current,
    required this.max,
    required this.score,
    required this.skills,
  });
  bool get isFull => max > 0 && current >= max;
  double get fillPct => max > 0 ? (current / max).clamp(0.0, 1.0) : 0.0;
}

class _RecData {
  final _UserProfile profile;
  final List<_ScoredActivity> activities;
  final List<_ScoredVol> volunteering;
  const _RecData({
    required this.profile,
    required this.activities,
    required this.volunteering,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────────────────────────────────────
class _RecService {
  static final _db = FirebaseFirestore.instance;

  static Map<String, dynamic> _safe(DocumentSnapshot doc) =>
      (doc.data() as Map<String, dynamic>?) ?? {};

  static List<String> _strList(dynamic v) {
    if (v is List) return v.whereType<String>().toList();
    return [];
  }

  static Future<_RecData> load(String uid) async {
    final results = await Future.wait([
      _db.collection('users').doc(uid).get(),
      _db.collection('activities').where('status', isEqualTo: 'open').get(),
      _db.collection('volunteering').where('status', isEqualTo: 'open').get(),
    ]);

    final userDoc = results[0] as DocumentSnapshot;
    final actSnap = results[1] as QuerySnapshot;
    final volSnap = results[2] as QuerySnapshot;

    final ud = _safe(userDoc);
    final userDept      = (ud['department'] as String?) ?? '';
    final userSkills    = _strList(ud['skills']);
    final userInterests = _strList(ud['interests']);

    final profile = _UserProfile(
      name:        (ud['name']    as String?) ?? '',
      department:  userDept,
      credits:     (ud['credits'] as int?)    ?? 0,
      skills:      userSkills,
      interests:   userInterests,
    );

    final hasPrefs = userSkills.isNotEmpty || userInterests.isNotEmpty;

    // ── Score activities ─────────────────────────────────────────────────────
    final scoredActs = actSnap.docs
        .map((doc) {
          final d        = _safe(doc);
          final enrolled = (d['enrolled'] as int?) ?? 0;
          final capacity = (d['capacity'] as int?) ?? 0;
          if (capacity > 0 && enrolled >= capacity) return null;

          final reqSkills   = _strList(d['required_skills']);
          final catTags     = _strList(d['category_tags']);
          final targetDepts = _strList(d['target_departments']);

          final score = _computeScore(
            userDept:       userDept,
            userSkills:     userSkills,
            userInterests:  userInterests,
            requiredSkills: reqSkills,
            categoryTags:   catTags,
            targetDepts:    targetDepts,
          );

          return _ScoredActivity(
            id:             doc.id,
            title:          (d['title']       as String?) ?? '',
            description:    (d['description'] as String?) ?? '',
            type:           (d['type']        as String?) ?? '',
            department:     (d['department']  as String?) ?? '',
            credits:        (d['credits']     as int?)    ?? 0,
            enrolled:       enrolled,
            capacity:       capacity,
            score:          score,
            requiredSkills: reqSkills,
          );
        })
        .whereType<_ScoredActivity>()
        .toList();

    final filteredActs = hasPrefs
        ? scoredActs.where((a) => a.score > 0).toList()
        : scoredActs;
    filteredActs.sort((a, b) => b.score.compareTo(a.score));
    final topActs = filteredActs.take(5).toList();

    // ── Score volunteering ───────────────────────────────────────────────────
    final scoredVols = volSnap.docs
        .map((doc) {
          final d       = _safe(doc);
          final current = (d['currentParticipants'] as int?) ?? 0;
          final max     = (d['maxParticipants']     as int?) ?? 0;
          if (max > 0 && current >= max) return null;

          final skills      = _strList(d['skills']);
          final catTags     = _strList(d['category_tags']);
          final targetDepts = _strList(d['target_departments']);
          final category    = (d['category'] as String?) ?? '';

          // Fall back to category string if no explicit category_tags
          final List<String> effectiveTags =
              catTags.isNotEmpty ? catTags
              : (category.isNotEmpty ? [category] : <String>[]);

          final score = _computeScore(
            userDept:       userDept,
            userSkills:     userSkills,
            userInterests:  userInterests,
            requiredSkills: skills,
            categoryTags:   effectiveTags,
            targetDepts:    targetDepts,
          );

          return _ScoredVol(
            id:           doc.id,
            title:        (d['title']        as String?) ?? '',
            description:  (d['description']  as String?) ?? '',
            category:     category,
            organization: (d['organization'] as String?) ?? '',
            credits:      (d['credits']      as int?)    ?? 0,
            current:      current,
            max:          max,
            score:        score,
            skills:       skills,
          );
        })
        .whereType<_ScoredVol>()
        .toList();

    final filteredVols = hasPrefs
        ? scoredVols.where((v) => v.score > 0).toList()
        : scoredVols;
    filteredVols.sort((a, b) => b.score.compareTo(a.score));
    final topVols = filteredVols.take(5).toList();

    return _RecData(
      profile:      profile,
      activities:   topActs,
      volunteering: topVols,
    );
  }

  static Future<void> savePreferences(
    String uid,
    List<String> skills,
    List<String> interests,
  ) =>
      _db.collection('users').doc(uid).update({
        'skills':    skills,
        'interests': interests,
      });
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED WIDGETS
// ─────────────────────────────────────────────────────────────────────────────
class _GlassCard extends StatelessWidget {
  final Widget child;
  final Color? glowColor;
  const _GlassCard({required this.child, this.glowColor});

  @override
  Widget build(BuildContext context) => Container(
    width:   double.infinity,
    margin:  const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color:        _C.card.withValues(alpha: 0.75),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: glowColor?.withValues(alpha: 0.4) ?? _C.border,
      ),
      boxShadow: glowColor != null
          ? [BoxShadow(color: glowColor!.withValues(alpha: 0.15), blurRadius: 14)]
          : [],
    ),
    child: child,
  );
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, subtitle;
  const _SectionHeader({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color:        color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: _C.text,
                      fontWeight: FontWeight.bold,
                      fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text(subtitle,
                  style: const TextStyle(color: _C.muted, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool outlined;
  final VoidCallback onTap;
  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.onTap,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height:  38,
      width:   double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        gradient: outlined
            ? null
            : const LinearGradient(colors: [_C.primary, _C.neonBlue]),
        borderRadius: BorderRadius.circular(10),
        border: outlined ? Border.all(color: _C.primary, width: 1.3) : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon,
              color: outlined ? _C.primary : Colors.white, size: 15),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label,
                style: TextStyle(
                    color: outlined ? _C.primary : Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
                maxLines: 1),
          ),
        ],
      ),
    ),
  );
}

class _TagChip extends StatelessWidget {
  final String label;
  final Color color;
  const _TagChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color:        color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
      border:       Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Text(label,
        style: TextStyle(
            color: color, fontSize: 10, fontWeight: FontWeight.w600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis),
  );
}

// Match score badge (color-coded by score band)
class _MatchBadge extends StatelessWidget {
  final int score;
  const _MatchBadge({required this.score});

  Color get _color {
    if (score >= 80) return _C.neonGreen;
    if (score >= 60) return _C.neonBlue;
    if (score >= 40) return _C.amber;
    return _C.muted;
  }

  @override
  Widget build(BuildContext context) {
    final c = _color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color:        c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border:       Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.auto_awesome_rounded, size: 9, color: c),
        const SizedBox(width: 3),
        Text('$score% match',
            style: TextStyle(
                color: c, fontSize: 9, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

// Gradient fill bar proportional to match score
class _MatchBar extends StatelessWidget {
  final int score;
  const _MatchBar({required this.score});

  Color get _color {
    if (score >= 80) return _C.neonGreen;
    if (score >= 60) return _C.neonBlue;
    if (score >= 40) return _C.amber;
    return _C.muted;
  }

  @override
  Widget build(BuildContext context) {
    final pct = (score / 100).clamp(0.0, 1.0);
    final c   = _color;
    return LayoutBuilder(
      builder: (_, constraints) => ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          height: 4,
          width:  constraints.maxWidth,
          child: Stack(children: [
            Container(color: _C.secondary),
            FractionallySizedBox(
              widthFactor: pct,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: [c, c.withValues(alpha: 0.6)]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// Toggleable chip used inside the preferences panel
class _ToggleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;
  const _ToggleChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: selected ? color.withValues(alpha: 0.18) : _C.secondary,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color:  selected ? color.withValues(alpha: 0.6) : _C.border,
          width:  selected ? 1.2 : 1,
        ),
      ),
      child: Text(label,
          style: TextStyle(
              color:      selected ? color : _C.muted,
              fontSize:   11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// PREFERENCES PANEL  (collapsible skills + interests picker)
// ─────────────────────────────────────────────────────────────────────────────
class _PreferencesPanel extends StatefulWidget {
  final List<String> initialSkills, initialInterests;
  final Future<void> Function(List<String>, List<String>) onSave;
  const _PreferencesPanel({
    required this.initialSkills,
    required this.initialInterests,
    required this.onSave,
  });

  @override
  State<_PreferencesPanel> createState() => _PreferencesPanelState();
}

class _PreferencesPanelState extends State<_PreferencesPanel> {
  late Set<String> _skills;
  late Set<String> _interests;
  bool _expanded = false;
  bool _saving   = false;
  bool _dirty    = false;

  @override
  void initState() {
    super.initState();
    _skills    = Set.from(widget.initialSkills);
    _interests = Set.from(widget.initialInterests);
  }

  void _toggle(Set<String> set, String val) => setState(() {
    set.contains(val) ? set.remove(val) : set.add(val);
    _dirty = true;
  });

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.onSave(_skills.toList(), _interests.toList());
    if (mounted) setState(() { _saving = false; _dirty = false; });
  }

  @override
  Widget build(BuildContext context) {
    final sc = _skills.length;
    final ic = _interests.length;

    return _GlassCard(
      glowColor: _C.primary.withValues(alpha: 0.18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header row — always visible
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(children: [
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color:        _C.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.tune_rounded,
                    color: _C.primary, size: 17),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('My Preferences',
                        style: TextStyle(
                            color:      _C.text,
                            fontWeight: FontWeight.bold,
                            fontSize:   14)),
                    Text(
                      sc > 0 || ic > 0
                          ? '$sc skill${sc == 1 ? '' : 's'} · '
                            '$ic interest${ic == 1 ? '' : 's'} selected'
                          : 'Tap to add skills & interests',
                      style: const TextStyle(color: _C.muted, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (_dirty)
                Container(
                  width: 7, height: 7,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: const BoxDecoration(
                      color: _C.amber, shape: BoxShape.circle),
                ),
              Icon(
                _expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: _C.muted,
                size:  20,
              ),
            ]),
          ),

          // Expanded body
          if (_expanded) ...[
            const SizedBox(height: 14),
            const Divider(color: _C.border, height: 1),
            const SizedBox(height: 14),

            // Skills
            const Text('Skills',
                style: TextStyle(
                    color:      _C.text,
                    fontSize:   12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6, runSpacing: 6,
              children: _kAllSkills
                  .map((s) => _ToggleChip(
                        label:    s,
                        selected: _skills.contains(s),
                        color:    _C.primary,
                        onTap:    () => _toggle(_skills, s),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 14),

            // Interests
            const Text('Interests',
                style: TextStyle(
                    color:      _C.text,
                    fontSize:   12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6, runSpacing: 6,
              children: _kAllInterests
                  .map((i) => _ToggleChip(
                        label:    i,
                        selected: _interests.contains(i),
                        color:    _C.neonCyan,
                        onTap:    () => _toggle(_interests, i),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 14),

            // Save button
            GestureDetector(
              onTap: (_saving || !_dirty) ? null : _save,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 40,
                decoration: BoxDecoration(
                  gradient: _dirty
                      ? const LinearGradient(
                          colors: [_C.primary, _C.neonBlue])
                      : null,
                  color:        _dirty ? null : _C.secondary,
                  borderRadius: BorderRadius.circular(10),
                  border: _dirty ? null : Border.all(color: _C.border),
                ),
                child: Center(
                  child: _saving
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(
                            _dirty
                                ? Icons.save_rounded
                                : Icons.check_circle_rounded,
                            color: _dirty ? Colors.white : _C.muted,
                            size:  15,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _dirty
                                ? 'Save & Re-score'
                                : 'Preferences Saved',
                            style: TextStyle(
                              color:      _dirty ? Colors.white : _C.muted,
                              fontSize:   13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ]),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ACTIVITY RECOMMENDATION CARD
// ─────────────────────────────────────────────────────────────────────────────
class _ActivityCard extends StatelessWidget {
  final _ScoredActivity a;
  final bool showScore;
  const _ActivityCard({required this.a, required this.showScore});

  @override
  Widget build(BuildContext context) => _GlassCard(
    glowColor: _C.primary.withValues(alpha: 0.25),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Type pill + match badge + credits
        Row(children: [
          if (a.type.isNotEmpty)
            Container(
              margin:  const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color:        _C.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border:       Border.all(color: _C.primary.withValues(alpha: 0.3)),
              ),
              child: Text(a.type,
                  style: const TextStyle(
                      color:      _C.primary,
                      fontSize:   9,
                      fontWeight: FontWeight.w700)),
            ),
          if (showScore && a.score > 0) _MatchBadge(score: a.score),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color:        _C.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border:       Border.all(color: _C.amber.withValues(alpha: 0.3)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.star_rounded, size: 10, color: _C.amber),
              const SizedBox(width: 3),
              Text('+${a.credits}',
                  style: const TextStyle(
                      color:      _C.amber,
                      fontSize:   10,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
        const SizedBox(height: 8),

        // Match bar
        if (showScore && a.score > 0) ...[
          _MatchBar(score: a.score),
          const SizedBox(height: 8),
        ],

        Text(a.title,
            style: const TextStyle(
                color:      _C.text,
                fontWeight: FontWeight.w700,
                fontSize:   14),
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),

        if (a.department.isNotEmpty)
          Text(a.department,
              style: const TextStyle(color: _C.muted, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),

        if (a.description.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(a.description,
              style: const TextStyle(
                  color: _C.muted, fontSize: 12, height: 1.45),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ],

        // Required skills tags
        if (a.requiredSkills.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 4, runSpacing: 4,
            children: a.requiredSkills
                .take(4)
                .map((s) => _TagChip(label: s, color: _C.neonBlue))
                .toList(),
          ),
        ],
        const SizedBox(height: 10),

        // Enrollment fill bar
        Row(children: [
          const Icon(Icons.people_rounded, size: 11, color: _C.muted),
          const SizedBox(width: 4),
          Expanded(
            child: Text('${a.enrolled}/${a.capacity} enrolled',
                style: const TextStyle(color: _C.muted, fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          Text('${(a.fillPct * 100).round()}%',
              style: const TextStyle(color: _C.muted, fontSize: 10)),
        ]),
        const SizedBox(height: 5),
        LayoutBuilder(
          builder: (_, c) => ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 5, width: c.maxWidth,
              child: Stack(children: [
                Container(color: _C.secondary),
                FractionallySizedBox(
                  widthFactor: a.fillPct,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                          colors: [_C.primary, _C.neonBlue]),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 12),

        _ActionBtn(
          label: 'Enroll Now',
          icon:  Icons.how_to_reg_rounded,
          onTap: () =>
              Navigator.pushNamed(context, '/student/activities'),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// VOLUNTEERING RECOMMENDATION CARD
// ─────────────────────────────────────────────────────────────────────────────
class _VolCard extends StatelessWidget {
  final _ScoredVol v;
  final bool showScore;
  const _VolCard({required this.v, required this.showScore});

  @override
  Widget build(BuildContext context) => _GlassCard(
    glowColor: _C.neonGreen.withValues(alpha: 0.25),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Category + match badge + credits
        Row(children: [
          if (v.category.isNotEmpty)
            Flexible(
              child: Container(
                margin:  const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color:        _C.neonGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border:       Border.all(color: _C.neonGreen.withValues(alpha: 0.3)),
                ),
                child: Text(v.category,
                    style: const TextStyle(
                        color:      _C.neonGreen,
                        fontSize:   9,
                        fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ),
          if (showScore && v.score > 0) _MatchBadge(score: v.score),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color:        _C.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border:       Border.all(color: _C.amber.withValues(alpha: 0.3)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.star_rounded, size: 10, color: _C.amber),
              const SizedBox(width: 3),
              Text('+${v.credits}',
                  style: const TextStyle(
                      color:      _C.amber,
                      fontSize:   10,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
        const SizedBox(height: 8),

        // Match bar
        if (showScore && v.score > 0) ...[
          _MatchBar(score: v.score),
          const SizedBox(height: 8),
        ],

        Text(v.title,
            style: const TextStyle(
                color:      _C.text,
                fontWeight: FontWeight.w700,
                fontSize:   14),
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),

        if (v.organization.isNotEmpty)
          Text(v.organization,
              style: const TextStyle(color: _C.muted, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),

        if (v.description.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(v.description,
              style: const TextStyle(
                  color: _C.muted, fontSize: 12, height: 1.45),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ],

        // Skills tags
        if (v.skills.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 4, runSpacing: 4,
            children: v.skills
                .take(4)
                .map((s) => _TagChip(label: s, color: _C.neonCyan))
                .toList(),
          ),
        ],
        const SizedBox(height: 10),

        // Participants fill bar
        Row(children: [
          const Icon(Icons.people_rounded, size: 11, color: _C.muted),
          const SizedBox(width: 4),
          Expanded(
            child: Text('${v.current}/${v.max} participants',
                style: const TextStyle(color: _C.muted, fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          Text('${(v.fillPct * 100).round()}%',
              style: const TextStyle(color: _C.muted, fontSize: 10)),
        ]),
        const SizedBox(height: 5),
        LayoutBuilder(
          builder: (_, c) => ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 5, width: c.maxWidth,
              child: Stack(children: [
                Container(color: _C.secondary),
                FractionallySizedBox(
                  widthFactor: v.fillPct,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                          colors: [_C.neonGreen, _C.neonCyan]),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 12),

        _ActionBtn(
          label:    'Apply Now',
          icon:     Icons.eco_rounded,
          outlined: true,
          onTap:    () =>
              Navigator.pushNamed(context, '/student/volunteering'),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class StudentRecommendationScreen extends StatefulWidget {
  const StudentRecommendationScreen({super.key});
  @override
  State<StudentRecommendationScreen> createState() =>
      _StudentRecommendationScreenState();
}

class _StudentRecommendationScreenState
    extends State<StudentRecommendationScreen> {
  Future<_RecData> _future = Future.value(const _RecData(
    profile: _UserProfile(
        name: '', department: '', credits: 0, skills: [], interests: []),
    activities:   [],
    volunteering: [],
  ));
  String _userName = '';
  String _uid      = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(_init);
  }

  void _init() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) return;
    _uid = user.uid;
    final f = _RecService.load(_uid);
    _future = f;
    f.then((d) { if (mounted) setState(() => _userName = d.profile.name); });
    setState(() {});
  }

  Future<void> _savePrefs(List<String> skills, List<String> interests) async {
    await _RecService.savePreferences(_uid, skills, interests);
    _init();
  }

  @override
  Widget build(BuildContext context) => StudentDashboardLayout(
    currentRoute: '/student/recommendations',
    userName:     _userName,
    child: FutureBuilder<_RecData>(
      future: _future,
      builder: (context, snap) {
        // Loading
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 80),
            child: Center(
                child: CircularProgressIndicator(color: _C.primary)),
          );
        }

        // Error
        if (snap.hasError) {
          return _GlassCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: Colors.redAccent, size: 36),
                  const SizedBox(height: 12),
                  Text(snap.error.toString(),
                      style: const TextStyle(
                          color: _C.muted, fontSize: 12),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: _init,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [_C.primary, _C.neonBlue]),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.refresh_rounded,
                                color: Colors.white, size: 14),
                            SizedBox(width: 6),
                            Text('Retry',
                                style: TextStyle(
                                    color:      Colors.white,
                                    fontWeight: FontWeight.bold)),
                          ]),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final data     = snap.data!;
        final p        = data.profile;
        final hasPrefs = p.hasPreferences;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── A. Header ─────────────────────────────────────────────────────
            Row(children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [_C.primary, _C.neonCyan],
                      begin: Alignment.topLeft,
                      end:   Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text('AI',
                      style: TextStyle(
                          color:      Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize:   14)),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('AI Recommendations',
                        style: TextStyle(
                            color:      _C.text,
                            fontWeight: FontWeight.bold,
                            fontSize:   20),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    SizedBox(height: 2),
                    Text('Content-based personalised matching',
                        style:
                            TextStyle(color: _C.muted, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              GestureDetector(
                onTap: _init,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color:        _C.secondary,
                    borderRadius: BorderRadius.circular(10),
                    border:       Border.all(color: _C.border),
                  ),
                  child: const Icon(Icons.refresh_rounded,
                      color: _C.muted, size: 16),
                ),
              ),
            ]),
            const SizedBox(height: 16),

            // ── B. Profile card ───────────────────────────────────────────────
            _GlassCard(
              glowColor: _C.primary.withValues(alpha: 0.15),
              child: Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        colors: [_C.primary, _C.neonBlue]),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      p.name.isNotEmpty
                          ? p.name[0].toUpperCase()
                          : 'S',
                      style: const TextStyle(
                          color:      Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize:   16),
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
                        p.name.isNotEmpty ? p.name : 'Student',
                        style: const TextStyle(
                            color:      _C.text,
                            fontWeight: FontWeight.w600,
                            fontSize:   14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Wrap(spacing: 6, runSpacing: 5, children: [
                        if (p.department.isNotEmpty)
                          _TagChip(
                              label: '📚 ${p.department}',
                              color: _C.primary),
                        _TagChip(
                            label: '⭐ ${p.credits} credits',
                            color: _C.amber),
                        if (p.skills.isNotEmpty)
                          _TagChip(
                              label: '🔧 ${p.skills.length} skills',
                              color: _C.neonBlue),
                        if (p.interests.isNotEmpty)
                          _TagChip(
                              label:
                                  '💡 ${p.interests.length} interests',
                              color: _C.neonCyan),
                      ]),
                    ],
                  ),
                ),
              ]),
            ),

            // ── C. Preferences panel ──────────────────────────────────────────
            _PreferencesPanel(
              initialSkills:    p.skills,
              initialInterests: p.interests,
              onSave:           _savePrefs,
            ),

            // ── D. Algorithm info (only when prefs are set) ───────────────────
            if (hasPrefs)
              _GlassCard(
                child: Row(children: [
                  Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                      color:        _C.neonCyan.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.calculate_rounded,
                        color: _C.neonCyan, size: 17),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Scoring Formula',
                            style: TextStyle(
                                color:      _C.text,
                                fontSize:   13,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Wrap(spacing: 6, runSpacing: 4, children: const [
                          _TagChip(label: '45% Skills',     color: _C.primary),
                          _TagChip(label: '35% Interests',  color: _C.neonCyan),
                          _TagChip(label: '20% Department', color: _C.neonGreen),
                        ]),
                      ],
                    ),
                  ),
                ]),
              ),

            // ── E. Prompt to set prefs (shown when no prefs yet) ──────────────
            if (!hasPrefs)
              _GlassCard(
                glowColor: _C.amber.withValues(alpha: 0.2),
                child: Row(children: [
                  Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                      color:        _C.amber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.lightbulb_rounded,
                        color: _C.amber, size: 17),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Boost Your Recommendations',
                            style: TextStyle(
                                color:      _C.text,
                                fontSize:   13,
                                fontWeight: FontWeight.bold)),
                        SizedBox(height: 3),
                        Text(
                          'Add skills & interests above to unlock '
                          'personalised match scores (0–100%)',
                          style: TextStyle(color: _C.muted, fontSize: 11),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ]),
              ),

            // ── F. Recommended activities ─────────────────────────────────────
            _SectionHeader(
              icon:     Icons.auto_awesome_rounded,
              color:    _C.primary,
              title:    'Recommended Activities',
              subtitle: hasPrefs
                  ? 'Scored by skills, interests & department'
                  : 'Matched to your department',
            ),

            data.activities.isEmpty
                ? _GlassCard(
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Row(children: [
                        Icon(Icons.inbox_rounded,
                            color: _C.muted, size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'No matching activities right now.',
                            style: TextStyle(
                                color: _C.muted, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ]),
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: data.activities
                        .map((a) => _ActivityCard(
                            a: a, showScore: hasPrefs))
                        .toList(),
                  ),

            // ── G. Recommended volunteering ───────────────────────────────────
            _SectionHeader(
              icon:     Icons.eco_rounded,
              color:    _C.neonGreen,
              title:    'Recommended Volunteering',
              subtitle: hasPrefs
                  ? 'Scored by skills, interests & category'
                  : 'Open opportunities for you',
            ),

            data.volunteering.isEmpty
                ? _GlassCard(
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Row(children: [
                        Icon(Icons.inbox_rounded,
                            color: _C.muted, size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'No matching volunteering right now.',
                            style: TextStyle(
                                color: _C.muted, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ]),
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: data.volunteering
                        .map((v) =>
                            _VolCard(v: v, showScore: hasPrefs))
                        .toList(),
                  ),

            // ── H. Footer CTA ─────────────────────────────────────────────────
            const SizedBox(height: 4),
            _GlassCard(
              glowColor: _C.neonCyan.withValues(alpha: 0.2),
              child: Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color:        _C.neonCyan.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.explore_rounded,
                      color: _C.neonCyan, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Explore All',
                          style: TextStyle(
                              color:      _C.text,
                              fontWeight: FontWeight.w700,
                              fontSize:   13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(
                        'Browse the full catalogue of activities & volunteering',
                        style: TextStyle(color: _C.muted, fontSize: 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => Navigator.pushReplacementNamed(
                      context, '/student/activities'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [_C.neonCyan, _C.neonBlue]),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Browse',
                        style: TextStyle(
                            color:      Colors.white,
                            fontSize:   11,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              ]),
            ),
          ],
        );
      },
    ),
  );
}
