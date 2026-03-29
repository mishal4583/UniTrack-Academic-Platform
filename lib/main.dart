import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:unitrack_flutter/screens/faculty/faculty_analytics_screen.dart';
import 'package:unitrack_flutter/screens/faculty/faculty_verify_screen.dart';
import 'firebase_options.dart';

// AUTH
import 'package:unitrack_flutter/screens/auth/auth_gate.dart';
import 'package:unitrack_flutter/screens/auth/register_screen.dart';

// STUDENT
import 'package:unitrack_flutter/screens/student/student_home.dart';
import 'package:unitrack_flutter/screens/student/student_volunteering_screen.dart';
import 'package:unitrack_flutter/screens/student/student_activities_screen.dart';

// FACULTY
import 'package:unitrack_flutter/screens/faculty/faculty_home.dart';
import 'package:unitrack_flutter/screens/faculty/faculty_create_activity.dart';
import 'package:unitrack_flutter/screens/faculty/faculty_create_volunteering.dart';

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

      navigatorKey: GlobalKey<NavigatorState>(),

      // ENTRY
      home: const AuthGate(),

      routes: {
        // AUTH
        "/register": (context) => const RegisterScreen(),

        // STUDENT
        "/student": (context) => const StudentHome(),
        "/student/volunteering": (context) => const VolunteeringFeedScreen(),
        "/student/volunteering/accepted": (context) =>
            const AcceptedVolunteeringScreen(),
        "/student/activities": (context) => const StudentActivitiesScreen(),
        "/student/profile": (context) =>
            const PlaceholderScreen(title: "Profile"),
        "/student/certificates": (context) =>
            const PlaceholderScreen(title: "Certificates"),

        // FACULTY
        // FACULTY
        "/faculty": (context) => const FacultyHome(),

        "/faculty/create": (context) => const FacultyCreateActivityScreen(),

        "/faculty/volunteering/create": (context) =>
            const FacultyCreateVolunteeringScreen(),

        "/faculty/verify": (context) => const FacultyVerifyScreen(),

        "/faculty/analytics": (context) => const FacultyAnalyticsScreen(),

        "/faculty/profile": (context) =>
            const PlaceholderScreen(title: "Faculty Profile"),
      },

      // SAFETY NET (VERY IMPORTANT)
      onUnknownRoute: (settings) {
        return MaterialPageRoute(
          builder: (_) =>
              const Scaffold(body: Center(child: Text("Page not found"))),
        );
      },
    );
  }
}

/// PLACEHOLDER
class PlaceholderScreen extends StatelessWidget {
  final String title;

  const PlaceholderScreen({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text(
          "$title Page Coming Soon",
          style: const TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
