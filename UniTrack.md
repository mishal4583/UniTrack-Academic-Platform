# UniTrack — Complete Project Documentation

> Academic Activity & Credit Management System powered by Firebase, Blockchain, and AI

---

## What is UniTrack?

UniTrack is a full-stack mobile + web app built in **Flutter** that lets universities track student participation in activities and volunteering, issue blockchain-verified certificates, manage credits, and provide AI-powered activity recommendations.

Three types of users exist — **Students**, **Faculty**, and **Admins** — each with their own portal, dashboard, and feature set.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter (Dart) — cross-platform (Android, iOS, Web, Windows) |
| Backend / Database | Firebase Firestore (NoSQL, real-time) |
| Authentication | Firebase Auth (email/password) |
| Charts | fl_chart |
| Blockchain | MetaMask wallet integration (certificate verification) |
| AI Engine | Content-based filtering algorithm (on-device, no external API) |
| State Management | Flutter `setState` + `FutureBuilder` / `StreamBuilder` |

---

## App Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                          APP LAUNCH                                  │
│                        main.dart + Firebase.init()                   │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         AUTH GATE                                    │
│              StreamBuilder on FirebaseAuth.authStateChanges()        │
│                                                                      │
│   Not logged in ──────────────────────► Login Screen                │
│                                              │                       │
│   Logged in ──► Firestore users/{uid}        │                       │
│                 read role field              ▼                       │
│                    │               Register Screen                   │
│          ┌─────────┼─────────┐         (new account)                │
│          ▼         ▼         ▼                                       │
│       student   faculty    admin                                     │
└──────────┬──────────┬──────────┬───────────────────────────────────┘
           │          │          │
           ▼          ▼          ▼
    Student Portal  Faculty    Admin
    (8 screens)     Portal     Portal
                   (8 screens) (5 screens)
```

---

## Authentication Flow

```
Login Screen
├── Role selector: [Student] [Faculty] [Admin]
├── Email + Password fields
├── Sign In → Firebase Auth signInWithEmailAndPassword()
│               └── On success: reads users/{uid}.role → navigate to /{role}
├── Connect Wallet (MetaMask) button  ← blockchain wallet link
└── Register link → Register Screen
        ├── Role selector
        ├── Full Name + Email + Password
        ├── Role-specific fields:
        │     Student: Student ID, Department, Year
        │     Faculty: Faculty ID, Department, Designation
        └── Firebase Auth createUserWithEmailAndPassword()
              └── Creates users/{uid} document with role + profile data
```

**Role-based routing** — `AuthGate` reads `users/{uid}.role` from Firestore in real time. If the role changes while the app is open, the user is automatically redirected to the correct portal.

---

## Student Portal

### Navigation (Sidebar / Bottom Nav)

| Item | Route | Screen |
|---|---|---|
| Dashboard | `/student` | Student Home |
| Volunteering | `/student/volunteering` | Volunteering Feed |
| Activities | `/student/activities` | Activities Feed |
| My Progress | `/student/my-progress` | Progress Tracker |
| Certificates | `/student/certificates` | Certificate Wallet |
| Profile | `/student/profile` | Student Profile |
| For You | `/student/recommendations` | AI Recommendations |

---

### Screen 1 — Student Home (Dashboard)

The main dashboard a student sees after logging in.

**What it shows:**
- Greeting with the student's name
- Two quick action buttons: **Apply Volunteering** and **Enroll Activity**
- **4-tile stat grid**: Total Credits, Activities enrolled, Volunteering applied, Certificates earned
- **Rank card**: Position among all students by credit count
- **Credit Progress bar**: Shows progress toward 60-credit graduation requirement
- **Recent Activities feed**: Last 5 enrollments + volunteering applications with status badges
- **Digital Certificates section**: Last 3 earned certificates
- **Blockchain Records summary**: On-chain count + certified count
- **DID card**: Student's Decentralized Identity — `did:ethr:0x...`

**Data sources:**
```
users/{uid}           → name, credits
enrollments           → filtered by userId, joined with activities
applications          → filtered by userId, joined with volunteering
certificates          → filtered by userId
users (all)           → for rank calculation
```

---

### Screen 2 — Activities Feed

Browse and enroll in academic activities.

**Features:**
- Real-time stream from `activities` collection
- Search bar (filters by title)
- Type filter chips: All / Workshop / Bootcamp / Research / Event / Certification / Seminar
- **Stats strip**: Open activities count, total credits available, verified count
- Volunteering CTA card (links to volunteering screen)
- Each activity card shows:
  - Type pill + Blockchain badge
  - Title, department, faculty name
  - Date, duration, credits
  - Capacity fill bar (enrolled / total)
  - **Enroll button** — changes to Enrolled / Completed / Verified based on status

**Enrollment flow:**
```
Student taps Enroll
└── Firestore Transaction (prevents double-booking):
    1. Read activity doc (check not full, not already enrolled)
    2. Create enrollments/{docId} with status = "Enrolled"
    3. Increment activities/{activityId}.enrolled
    4. If enrolled == capacity: set status = "full"
```

---

### Screen 3 — Activity Detail

Reached by tapping an activity card.

**Features:**
- Real-time `StreamBuilder` on the activity document
- Title, type, blockchain badge, department, faculty
- 2×2 meta grid: Date, Duration, Credits, Enrolled count
- Full description
- Capacity progress bar
- Blockchain info card (tx hash if verified)
- Enrollment progress stepper: Applied → Approved → Completed → Verified
- Enroll / Already Enrolled button

---

### Screen 4 — Volunteering Feed

Browse and apply for volunteering opportunities.

**Features:**
- Real-time stream from `volunteering` collection
- Search + Category filter chips (6 categories)
- Each card shows category, title, organization, skills required, credits, participants, apply button
- Application status tracked per student
- Duplicate-safe apply (checks existing applications first)

---

### Screen 5 — My Progress

Unified view of all activities and volunteering with status tracking.

**Features:**
- Filter: All / Activity / Volunteering
- Stats row: Total items, Verified items, Total credits earned
- Each progress card shows:
  - Title, type, credits, date
  - Status badge
  - **4-step progress stepper**: Applied → Approved → Completed → Verified
  - Blockchain tx hash (if on-chain verified)

---

### Screen 6 — Certificate Wallet

All earned blockchain certificates in one place.

**Features:**
- Summary strip: Total certificates, Total credits, Verified count
- Filter by type (Activity / Volunteering) and status (Issued / Verified)
- Each certificate card shows:
  - Gradient accent bar
  - Title, type, status badges, credits pill
  - Issue date + Blockchain hash
  - "Verified on-chain" banner (if hash exists)

**MetaMask integration**: Certificates with a `blockchainHash` field are marked as on-chain verified. The hash is the transaction ID on the Ethereum network. The **Connect Wallet (MetaMask)** button on the login/register screen is the entry point for linking a student's wallet address to their profile.

---

### Screen 7 — Student Profile

Complete profile overview.

**Features:**
- Avatar (gradient with initials), name, email, department, credits
- **DID badge** — `did:ethr:0x{uid_shortened}` — student's on-chain identity
- 2×2 stat grid: Total Credits, Activities, Volunteering, Certificates
- Recent Activity list (last 5)
- Certificates preview (last 3) + View All button

---

### Screen 8 — AI Recommendations (For You)

Personalised activity and volunteering suggestions using a content-based filtering engine.

**Scoring formula:**
```
matchScore = (0.45 × skillScore) + (0.35 × interestScore) + (0.20 × deptScore)
```

**Features:**
- **My Preferences panel** (collapsible):
  - 32 skills to toggle (Flutter, Python, ML, Blockchain, etc.)
  - 26 interests to toggle (Technology, Research, Entrepreneurship, etc.)
  - **Save & Re-score** button — writes to Firestore and instantly re-ranks results
- **Profile card** showing name, dept, credits, skill count, interest count
- **Scoring formula card** (shows when prefs are set): 45% Skills · 35% Interests · 20% Department
- **Top 5 Activities** — each with:
  - Match % badge (color-coded: green ≥80%, blue ≥60%, amber ≥40%)
  - Match fill bar
  - Required skills tags
  - Enrollment fill bar + Enroll button
- **Top 5 Volunteering** — same layout
- Browse All footer → Activities screen

**Score color guide:**

| Score | Color | Meaning |
|---|---|---|
| ≥ 80% | Green | Excellent match |
| ≥ 60% | Blue | Good match |
| ≥ 40% | Amber | Partial match |
| < 40% | Grey | Weak match |

> Items scoring 0 are hidden when preferences are set. Without preferences, dept-matched items are shown without badges.

---

## Faculty Portal

### Navigation

| Item | Route |
|---|---|
| Dashboard | `/faculty` |
| Analytics | `/faculty/analytics` |
| Verify Students | `/faculty/verify` |
| Create Activity | `/faculty/create` |
| Create Volunteering | `/faculty/volunteering/create` |
| Manage | `/faculty/manage` |
| Profile | `/faculty/profile` |

---

### Screen 1 — Faculty Dashboard

**What it shows:**
- Welcome greeting
- **4-tile stat grid**: Activities created, Volunteering created, Unique students, Pending verifications
- **Quick Actions** (3-tile grid): Create Activity, Create Volunteer, Verify Students
- **Your Activities table**: Title, students enrolled, credits, status
- **Smart Contract card**: Trigger credit distribution button (executes blockchain credit issuance)
- **Volunteering Requests**: Active/Full status per opportunity
- **Pending Verifications**: Student + activity name with Verify / Reject action buttons

**Verify/Reject flow:**
```
Faculty taps Verify
└── enrollments/{id}.status = "Completed"  (for activity enrollments)
    applications/{id}.status = "Approved"  (for volunteering applications)

Faculty taps Reject
└── status = "Rejected"
```

---

### Screen 2 — Faculty Verify Panel

Full tracking panel for all student submissions.

**3 tabs with live counts:**
- **Pending** — Applied (volunteering) / Enrolled (activities) — has Approve + Reject buttons
- **Completed** — marked as completed, awaiting final verification
- **Verified** — fully verified on-chain

**Features:**
- Search bar (filter by student name or activity title)
- Each card shows: student avatar + name, activity title, time ago, type badge, credits, current status
- Batch-optimised Firestore queries (max 30 docs per query, no N+1)

---

### Screen 3 — Faculty Analytics

Data visualisation dashboard for a faculty member's own activities.

**Charts:**
- **Monthly Activities & Participation** — grouped bar chart (last 6 months)
- **Monthly Credit Issuance Trend** — line chart with area fill
- **Activity Type Distribution** — interactive pie/donut chart
- **Top Performing Students** — ranked leaderboard (by credits from this faculty's activities)
- **Verification Overview** — verified vs pending count + rate bar

**Stats:**
- Total Activities, Total Participants, Credits Issued, Verification Rate

---

### Screen 4 — Create Activity

Form to publish a new academic activity.

**Fields:** Title, Type, Department, Description, Date, Duration, Credits, Capacity, Blockchain verification toggle

---

### Screen 5 — Create Volunteering

Form to publish a new volunteering opportunity.

**Fields:** Title, Category, Organization, Description, Date, Duration, Credits, Max Participants, Skills required

---

## Admin Portal

### Navigation

| Route | Screen |
|---|---|
| `/admin` | Admin Dashboard |
| `/admin/users` | User Management |
| `/admin/activities` | Content Management |
| `/admin/blockchain` | Blockchain Logs |
| `/admin/settings` | Settings (placeholder) |

---

### Admin Dashboard

Platform-wide overview:
- Total users, Total activities, Total enrollments, Total credits distributed
- System health indicators
- Recent platform activity

### Admin Users Screen

- List all users with role, department, status
- Search and filter
- View/Edit user details, toggle active/inactive

### Admin Content Screen

- All activities and volunteering across all faculty
- Create, edit, delete content
- Status management (open / full / closed)

### Admin Blockchain Logs

- Audit trail of all on-chain transactions
- Certificate issuance records
- Smart contract execution history

---

## Blockchain & MetaMask

### How it works

```
Student completes activity
         │
         ▼
Faculty verifies → status = "Completed"
         │
         ▼
Admin / Smart Contract triggers credit issuance
         │
         ▼
Certificate issued in Firestore:
  certificates/{docId}:
    userId, itemId, type, credits,
    status = "issued",
    blockchainHash = "0x..."   ← Ethereum tx hash
         │
         ▼
Certificate shows as "Verified on-chain" in student wallet
```

### MetaMask Connection
- **Login screen**: "Connect Wallet (MetaMask)" button links a student's Ethereum wallet to their UniTrack profile
- **Register screen**: Same button available during sign-up
- **Certificate wallet**: Certificates with a `blockchainHash` show a verified banner and the tx hash
- **DID (Decentralized Identity)**: Each student gets a DID derived from their Firebase UID in the format `did:ethr:0x{uid}`
- **Smart Contract card** on Faculty Dashboard: "Execute" button triggers on-chain credit distribution for verified activities

---

## Firestore Database Schema

```
users/
  {uid}/
    name, email, role, department, credits,
    studentId (students), year (students),
    facultyId (faculty), designation (faculty),
    skills[], interests[],        ← AI recommendations
    createdAt, isActive

activities/
  {docId}/
    title, description, type, department, faculty,
    date, duration, status (open|full),
    credits, capacity, enrolled,
    blockchainVerified (bool),
    createdBy (facultyUid),
    createdAt,
    required_skills[],            ← AI recommendations
    category_tags[],              ← AI recommendations
    target_departments[]          ← AI recommendations

volunteering/
  {docId}/
    title, category, description, organization,
    date, duration, status (open|full),
    credits, maxParticipants, currentParticipants,
    skills[], blockchainCert,
    createdBy (facultyUid),
    category_tags[],              ← AI recommendations
    target_departments[]          ← AI recommendations

enrollments/
  {docId}/
    userId, activityId,
    status (Enrolled|Approved|Completed|Verified|Rejected),
    appliedAt

applications/
  {docId}/
    userId, volunteeringId,
    status (Applied|Approved|Completed|Verified|Rejected),
    appliedAt, txHash (optional)

certificates/
  {docId}/
    userId, itemId,
    type (activity|volunteering),
    status (issued|verified),
    credits, title,
    blockchainHash (optional),
    createdAt
```

---

## Credit System

```
Single source of truth: users/{uid}.credits

Flow:
  Student enrolls in activity / applies for volunteering
      ↓
  Faculty verifies completion
      ↓
  Admin / Smart Contract awards credits
      ↓
  users/{uid}.credits  ←  incremented
      ↓
  Rank recalculated on next dashboard load
  Credit progress bar updates (target: 60 credits for graduation)
```

---

## Status Lifecycle

### Activity Enrollment
```
Enrolled  →  Approved  →  Completed  →  Verified
    ↓
 Rejected (at any stage)
```

### Volunteering Application
```
Applied  →  Approved  →  Completed  →  Verified
    ↓
 Rejected (at any stage)
```

### Certificate
```
issued  →  verified (once blockchainHash is written)
```

---

## AI Recommendation System — Quick Reference

| | |
|---|---|
| **Algorithm** | Content-based filtering (no external AI, runs on-device) |
| **Formula** | `(0.45 × skills) + (0.35 × interests) + (0.20 × department)` |
| **Output** | Integer 0–100 match score |
| **Top N shown** | 5 activities + 5 volunteering |
| **Preferences stored** | `users/{uid}.skills[]` and `users/{uid}.interests[]` |
| **Activity tags** | `required_skills[]`, `category_tags[]`, `target_departments[]` |
| **Fallback (no prefs)** | Dept-matched items shown, no score badges |
| **Full doc** | `AI Recommendation System.md` |

---

## Project File Structure

```
lib/
├── main.dart                          ← App entry, routes, theme
├── firebase_options.dart              ← Firebase config
│
├── screens/
│   ├── auth/
│   │   ├── auth_gate.dart             ← Role-based routing
│   │   ├── login_screen.dart          ← Login + MetaMask button
│   │   └── register_screen.dart       ← Registration
│   │
│   ├── student/
│   │   ├── Student_dashboard_layout.dart  ← Shared layout (sidebar/nav)
│   │   ├── student_home.dart              ← Dashboard
│   │   ├── student_activities_screen.dart ← Activity feed
│   │   ├── activity_detail_screen.dart    ← Activity detail + enroll
│   │   ├── student_volunteering_screen.dart ← Volunteering feed
│   │   ├── student_my_progress_screen.dart  ← Progress tracker
│   │   ├── Student_profile_screen.dart      ← Profile
│   │   ├── Student_certificates_screen.dart ← Certificate wallet
│   │   └── Studentrecommendationscreen.dart ← AI Recommendations
│   │
│   ├── faculty/
│   │   ├── faculty_dashboard_layout.dart  ← Shared layout
│   │   ├── faculty_home.dart              ← Faculty dashboard
│   │   ├── faculty_verify_screen.dart     ← Verification panel
│   │   ├── faculty_analytics_screen.dart  ← Charts & analytics
│   │   ├── faculty_create_activity.dart   ← Create activity form
│   │   ├── faculty_create_volunteering.dart ← Create volunteering form
│   │   ├── faculty_manage_screen.dart     ← Manage listings
│   │   ├── faculty_manage_detail_screen.dart
│   │   └── faculty_profile_screen.dart
│   │
│   └── admin/
│       ├── admin_dashboard_screen.dart    ← Platform overview
│       ├── admin_users_screen.dart        ← User management
│       ├── admin_content_screen.dart      ← Content management
│       └── admin_logs_screen.dart         ← Blockchain logs
│
└── widgets/
    ├── neon_button.dart               ← Gradient sign-in button
    └── glass_card.dart                ← Reusable glass card
```

---

## Running the App

### Prerequisites
- Flutter SDK installed
- Android device (USB debugging on) or emulator
- Firebase project configured

### Commands
```bash
# Install dependencies
flutter pub get

# Run on connected Android device
flutter run

# Run on web
flutter run -d chrome

# Build release APK
flutter build apk --release
```

### Firebase Setup
The app uses `firebase_options.dart` (generated by FlutterFire CLI). This file contains project-specific API keys and is already configured.

---

## Design System

| Token | Colour | Hex |
|---|---|---|
| Background | Deep navy | `#080D19` |
| Card | Dark slate | `#111827` |
| Primary | Purple | `#8B5CF6` |
| Neon Blue | Blue | `#3B82F6` |
| Neon Cyan | Cyan | `#06B6D4` |
| Neon Green | Green | `#10B981` |
| Amber | Amber | `#F59E0B` |
| Rose | Red | `#F43F5E` |
| Text | Off-white | `#EFF3F8` |
| Muted | Grey | `#7E8A9A` |
| Border | Dark border | `#1F2937` |

**Style**: Dark glassmorphism — `backdrop-filter: blur`, semi-transparent cards, neon glow `boxShadow` effects, gradient buttons and badges throughout.

**Layout pattern**: Every screen uses a shared `DashboardLayout` widget (separate for Student and Faculty) that provides the scaffold, sidebar (desktop), bottom nav (mobile), and scroll container. Screen content is passed as a `Column(mainAxisSize: MainAxisSize.min)` child.

---

## Key Architectural Patterns

### 1. Batch Firestore Queries
All secondary lookups use chunks of 30 documents to stay within Firestore's `whereIn` limit:
```dart
for (int i = 0; i < ids.length; i += 30) {
  final chunk = ids.sublist(i, (i + 30).clamp(0, ids.length));
  // query chunk
}
```

### 2. Transaction-safe Enrollment
```dart
db.runTransaction((tx) async {
  // Check capacity, check no duplicate, then write
});
```

### 3. Parallel Fetches
```dart
final results = await Future.wait([
  fetch1(), fetch2(), fetch3()
]);
```

### 4. Real-time vs One-time
- `StreamBuilder` — activities feed, volunteering feed (live slot updates)
- `FutureBuilder` — dashboards, profile, certificates (one-time load with manual refresh)
