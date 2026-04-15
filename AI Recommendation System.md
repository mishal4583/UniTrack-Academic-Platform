# AI Recommendation System — UniTrack

## Overview

The AI Recommendation System is a **content-based filtering engine** built directly into the UniTrack Flutter app. It scores every open activity and volunteering opportunity against a student's profile in real time and surfaces the top 5 matches in each category.

No external AI service, no ML model inference, no network round-trips beyond Firestore — the scoring algorithm runs entirely on-device after a single parallel Firestore fetch.

---

## Scoring Formula

```
matchScore = (0.45 × skillScore) + (0.35 × interestScore) + (0.20 × deptScore)
```

| Signal | Weight | How it is calculated |
|---|---|---|
| **Skill overlap** | 45% | `matched skills ÷ activity's required_skills count` |
| **Interest / category overlap** | 35% | `matched interests ÷ activity's category_tags count` |
| **Department match** | 20% | `1.0` if student's dept is in `target_departments`, else `0`. If `target_departments` is empty the item is treated as open to all → full `1.0` credit. |

The raw float `0.0–1.0` is multiplied by 100 and rounded to produce an integer **0–100** displayed as a `%` match badge.

Items scoring `0` are filtered out entirely when the student has set at least one skill or interest. If no preferences are set, all open (non-full) items are shown sorted by department first.

---

## Architecture

### File

```
lib/screens/student/Studentrecommendationscreen.dart
```

The entire feature — algorithm, data models, Firestore service, preference panel, and card widgets — lives in this single file, following the same pattern used by every other student screen in the project.

### Route

```
/student/recommendations   →   StudentRecommendationScreen
```

Registered in `lib/main.dart`. Reachable from the sidebar nav item **"For You"** in `StudentDashboardLayout`.

---

## Data Flow

```
1. initState() → Future.microtask(_init)
        ↓
2. _RecService.load(uid)
   ├─ Parallel Firestore fetches:
   │    users/{uid}             → name, department, credits, skills[], interests[]
   │    activities (status=open) → all open activities
   │    volunteering (status=open)→ all open volunteering
        ↓
3. Algorithm runs on every non-full item
   ├─ _computeScore() for each activity
   └─ _computeScore() for each volunteering entry
        ↓
4. Filter (score > 0 if prefs set) → sort descending → take top 5
        ↓
5. FutureBuilder renders scored cards with match badges + bars
```

When the student saves preferences → `_RecService.savePreferences()` writes to Firestore → `_init()` re-runs the full load → FutureBuilder rebuilds with updated scores.

---

## Firestore Fields

### `users/{uid}` (student document)

| Field | Type | Notes |
|---|---|---|
| `department` | `String` | Existing field — used for dept scoring |
| `credits` | `int` | Existing field — displayed in profile card |
| `name` | `String` | Existing field |
| `skills` | `List<String>` | **New** — written by the preferences panel |
| `interests` | `List<String>` | **New** — written by the preferences panel |

### `activities/{docId}`

| Field | Type | Notes |
|---|---|---|
| `status` | `String` | Must be `"open"` to appear |
| `enrolled` | `int` | Combined with `capacity` to filter full items |
| `capacity` | `int` | |
| `required_skills` | `List<String>` | **New optional** — matched against student skills (45%). Defaults to `[]` if absent → skill score = 0. |
| `category_tags` | `List<String>` | **New optional** — matched against student interests (35%). Defaults to `[]` if absent. |
| `target_departments` | `List<String>` | **New optional** — e.g. `["CS", "ECE"]`. Empty = open to all (full dept credit). |

### `volunteering/{docId}`

| Field | Type | Notes |
|---|---|---|
| `status` | `String` | Must be `"open"` |
| `currentParticipants` | `int` | |
| `maxParticipants` | `int` | |
| `skills` | `List<String>` | **New optional** — acts as `required_skills` in scoring |
| `category_tags` | `List<String>` | **New optional** — matched against student interests. Falls back to the existing `category` string if absent. |
| `target_departments` | `List<String>` | **New optional** — same as activities |

> **Backwards compatibility:** All new Firestore fields are optional. If they are absent, the algorithm scores based only on the department signal (max score = 20). Existing documents require no migration.

---

## Algorithm Implementation

```dart
int _computeScore({
  required String userDept,
  required List<String> userSkills,
  required List<String> userInterests,
  required List<String> requiredSkills,   // from Firestore: required_skills / skills
  required List<String> categoryTags,     // from Firestore: category_tags
  required List<String> targetDepts,      // from Firestore: target_departments
}) {
  // Skill overlap (45%)
  double skillScore = 0;
  if (requiredSkills.isNotEmpty && userSkills.isNotEmpty) {
    final lowerReq = requiredSkills.map((s) => s.toLowerCase()).toSet();
    final matched = userSkills.where((s) => lowerReq.contains(s.toLowerCase())).length;
    skillScore = matched / requiredSkills.length;
  }

  // Interest overlap (35%)
  double interestScore = 0;
  if (categoryTags.isNotEmpty && userInterests.isNotEmpty) {
    final lowerTags = categoryTags.map((t) => t.toLowerCase()).toSet();
    final matched = userInterests.where((i) => lowerTags.contains(i.toLowerCase())).length;
    interestScore = matched / categoryTags.length;
  }

  // Department match (20%)
  double deptScore;
  if (targetDepts.isEmpty) {
    deptScore = 1.0;            // no restriction → open to all
  } else {
    final lowerDepts = targetDepts.map((d) => d.toLowerCase()).toSet();
    deptScore = lowerDepts.contains(userDept.toLowerCase()) ? 1.0 : 0.0;
  }

  final raw = (0.45 * skillScore) + (0.35 * interestScore) + (0.20 * deptScore);
  return (raw * 100).round();
}
```

Comparisons are case-insensitive throughout. The algorithm is pure Dart — no dependencies.

---

## Preferences Panel

The collapsible **My Preferences** card lets students select skills and interests without leaving the recommendations screen.

**Skills catalogue (32 options):**
Flutter, Python, Machine Learning, Data Science, Web Development, Java, C++, JavaScript, React, Node.js, Blockchain, UI/UX Design, Figma, Content Writing, Public Speaking, Research, Data Analysis, Cybersecurity, Cloud Computing, DevOps, Android Development, IoT, Embedded Systems, Database Management, Marketing, Finance, Business Strategy, Molecular Biology, Bioinformatics, Lab Research, Graphic Design, Video Editing

**Interests catalogue (26 options):**
Technology, Research & Innovation, Entrepreneurship, Community Service, Environmental Sustainability, Finance & Economics, Healthcare & Wellness, Creative Arts, Data & Analytics, Artificial Intelligence, Open Source, Social Impact, Education, Business & Strategy, Cybersecurity, Blockchain & Web3, Design & Creativity, Science & Engineering, Public Speaking & Debate, Mental Health & Wellbeing, Sports & Fitness, Cultural Activities, Networking, Leadership, Writing & Journalism, Film & Media

**Behaviour:**
- Loaded from Firestore on screen open
- Amber dot appears on the header when there are unsaved changes
- **Save & Re-score** button (active when dirty) writes to `users/{uid}` and triggers a full re-score
- Button label changes to **Preferences Saved** (greyed) when no unsaved changes

---

## Match Score Display

| Score band | Colour | Hex |
|---|---|---|
| ≥ 80% | Neon Green | `#10B981` |
| ≥ 60% | Neon Blue | `#3B82F6` |
| ≥ 40% | Amber | `#F59E0B` |
| < 40% | Muted grey | `#7E8A9A` |

Each recommendation card shows:
- **Match badge** — `★ 85% match` pill (colour-coded)
- **Match bar** — gradient fill bar proportional to score, shown directly below the badge row
- **Required skills tags** — up to 4 tags (blue for activities, cyan for volunteering)
- **Enrollment / participants fill bar** — separate from the match bar

When no preferences are set, badges and bars are hidden and the section subtitle changes to "Matched to your department".

---

## Screen Structure

```
StudentDashboardLayout (currentRoute: '/student/recommendations')
└── FutureBuilder<_RecData>
    ├── Loading → CircularProgressIndicator
    ├── Error  → error card + Retry button
    └── Data   →
        ├── Header (AI badge + title + refresh)
        ├── Profile card (avatar, dept, credits, skill/interest count pills)
        ├── Preferences panel (collapsible skills + interests picker)
        ├── Scoring formula card (shown when prefs are set)
        ├── "Boost" prompt card (shown when no prefs set)
        ├── Section: Recommended Activities (top 5)
        │   └── _ActivityCard × N  (match badge + bar + skills + enroll btn)
        ├── Section: Recommended Volunteering (top 5)
        │   └── _VolCard × N  (match badge + bar + skills + apply btn)
        └── Footer CTA → Browse full catalogue
```

---

## Graceful Degradation

| Scenario | Behaviour |
|---|---|
| Student has no skills/interests | All open non-full items shown sorted by dept; no score badges |
| Activity has no `required_skills` | Skill score = 0; item can still score up to 55% from interests + dept |
| Activity has no `category_tags` | Interest score = 0; item can still score up to 65% from skills + dept |
| Activity has no `target_departments` | Dept score = 1.0 (open to all); item gets full 20% dept credit |
| Item scores 0 with prefs set | Filtered out entirely |
| All items score 0 | Empty state card: "No matching activities right now." |

---

## Integration with Existing Screens

- **No changes** to any other screen or route
- Enroll / Apply buttons navigate to `/student/activities` and `/student/volunteering` respectively — students complete the action in the dedicated screens (which handle enrollment transactions, duplicate guards, etc.)
- The `users/{uid}.skills` and `users/{uid}.interests` fields written here are read-only from all other screens; no other screen reads or writes them

---

## Future Enhancements

1. **Collaborative filtering** — once enrollment history is sufficient, factor in what students with overlapping skills enrolled in (user-based CF on top of the content score)
2. **Weights tuning** — expose the 0.45/0.35/0.20 weights as Firestore remote-config values so they can be adjusted without a release
3. **Negative signals** — down-rank items the student has already enrolled in or explicitly dismissed
4. **Admin tagging UI** — add `required_skills` / `category_tags` / `target_departments` fields to the admin content management screen so that admins can tag activities from within the app
5. **Real-time stream** — switch from `FutureBuilder` to `StreamBuilder` on the activities/volunteering collections for live slot updates without manual refresh
