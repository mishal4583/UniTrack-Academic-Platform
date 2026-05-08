import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:unitrack_flutter/screens/faculty/faculty_manage_detail_screen.dart';
import 'package:unitrack_flutter/screens/faculty/faculty_manage_screen.dart';
import 'package:unitrack_flutter/screens/student/student_certificates_screen.dart';
import 'package:unitrack_flutter/screens/student/student_profile_screen.dart';
import 'package:unitrack_flutter/screens/student/studentrecommendationscreen.dart';
import 'package:unitrack_flutter/screens/student/student_my_progress_screen.dart';
import 'firebase_options.dart';

// AUTH
import 'package:unitrack_flutter/screens/auth/auth_gate.dart';
import 'package:unitrack_flutter/screens/auth/register_screen.dart';

// STUDENT
import 'package:unitrack_flutter/screens/student/student_home.dart';
import 'package:unitrack_flutter/screens/student/student_volunteering_screen.dart';
import 'package:unitrack_flutter/screens/student/student_activities_screen.dart';
import 'package:unitrack_flutter/screens/student/activity_detail_screen.dart';

// FACULTY
import 'package:unitrack_flutter/screens/faculty/faculty_home.dart';
import 'package:unitrack_flutter/screens/faculty/faculty_create_activity.dart';
import 'package:unitrack_flutter/screens/faculty/faculty_create_volunteering.dart';
import 'package:unitrack_flutter/screens/faculty/faculty_verify_screen.dart';
import 'package:unitrack_flutter/screens/faculty/faculty_analytics_screen.dart';
import 'package:unitrack_flutter/screens/faculty/faculty_profile_screen.dart';

// ADMIN
import 'package:unitrack_flutter/screens/admin/admin_dashboard_screen.dart';
import 'package:unitrack_flutter/screens/admin/admin_users_screen.dart';
import 'package:unitrack_flutter/screens/admin/admin_content_screen.dart';
import 'package:unitrack_flutter/screens/admin/admin_logs_screen.dart';
import 'package:unitrack_flutter/screens/admin/admin_settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UniTrack',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFF0A0A0F),
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF8B5CF6),
          surface: const Color(0xFF12121F),
        ),
        fontFamily: 'Inter',
      ),
      initialRoute: '/',
      routes: {
        // ── ROOT
        '/': (ctx) => const AuthGate(),
        '/register': (ctx) => const RegisterScreen(),

        // ── STUDENT
        // ── STUDENT
        '/student': (ctx) => const StudentHome(),
        '/student/volunteering': (ctx) => const VolunteeringFeedScreen(),
        '/student/activities': (ctx) => const StudentActivitiesScreen(),
        '/student/activity-detail': (ctx) => const ActivityDetailScreen(),
        '/student/my-progress': (ctx) => const StudentMyProgressScreen(),
        '/student/profile': (ctx) => const StudentProfileScreen(),
        '/student/certificates': (ctx) => const StudentCertificatesScreen(),
        '/student/recommendations': (ctx) =>
            const StudentRecommendationScreen(),

        '/student/settings': (ctx) => const _Placeholder(title: 'Settings'),

        // ── FACULTY
        '/faculty': (ctx) => const FacultyHome(),
        '/faculty/create': (ctx) => const FacultyCreateActivityScreen(),
        '/faculty/volunteering/create': (ctx) =>
            const FacultyCreateVolunteeringScreen(),
        '/faculty/verify': (ctx) => const FacultyVerifyScreen(),
        '/faculty/analytics': (ctx) => const FacultyAnalyticsScreen(),
        '/faculty/profile': (ctx) => const FacultyProfileScreen(),
        '/faculty/manage': (ctx) => const FacultyManageScreen(),
        '/faculty/manage/detail': (ctx) => const FacultyManageDetailScreen(),

        // ── ADMIN
        // Matches _Sidebar routes in admin_dashboard_screen.dart exactly:
        // /admin, /admin/users, /admin/activities, /admin/blockchain, /admin/settings
        '/admin': (ctx) => const AdminDashboardScreen(),
        '/admin/users': (ctx) => const AdminUsersScreen(),
        '/admin/activities': (ctx) => const AdminContentScreen(),
        // mapped to AdminContentScreen
        '/admin/blockchain': (ctx) =>
            const AdminLogsScreen(), // mapped to AdminLogsScreen
        '/admin/settings': (ctx) => const AdminSettingsScreen(),

        // Legacy routes kept for backward compatibility
        '/admin/content': (ctx) =>
            const AdminContentScreen(), // legacy alias        '/admin/logs': (ctx) => const AdminLogsScreen(),
      },
      onUnknownRoute: (settings) => MaterialPageRoute(
        builder: (_) => const Scaffold(
          body: Center(
            child: Text(
              'Page not found',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  final String title;
  const _Placeholder({required this.title});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0A0A0F),
    appBar: AppBar(
      backgroundColor: const Color(0xFF0F0F1A),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      iconTheme: const IconThemeData(color: Colors.white),
    ),
    body: Center(
      child: Text(
        '$title — Coming Soon',
        style: const TextStyle(fontSize: 18, color: Color(0xFF6B7280)),
      ),
    ),
  );
}
