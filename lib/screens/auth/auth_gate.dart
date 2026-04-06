import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// SCREENS
import 'package:unitrack_flutter/screens/auth/login_screen.dart';
import 'package:unitrack_flutter/screens/student/student_home.dart';
import 'package:unitrack_flutter/screens/faculty/faculty_home.dart';
import 'package:unitrack_flutter/screens/admin/admin_dashboard_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // 🔄 Loading auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }

        // ❌ Not logged in
        if (!snapshot.hasData || snapshot.data == null) {
          return const LoginScreen();
        }

        final user = snapshot.data!;

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots(),
          builder: (context, roleSnap) {
            // 🔄 Loading user role
            if (roleSnap.connectionState == ConnectionState.waiting) {
              return const _LoadingScreen();
            }

            // ❌ Firestore error
            if (roleSnap.hasError) {
              debugPrint("AuthGate Firestore error: ${roleSnap.error}");
              return const _ErrorScreen(message: "Failed to load user data");
            }

            // ❌ No user document
            if (!roleSnap.hasData || !roleSnap.data!.exists) {
              debugPrint("User document missing for uid: ${user.uid}");
              return const _ErrorScreen(message: "User data not found");
            }

            final data = roleSnap.data!.data() as Map<String, dynamic>? ?? {};

            final role = (data['role'] ?? '').toString().toLowerCase();

            debugPrint("User role: $role");

            // 🎯 ROLE-BASED ROUTING
            switch (role) {
              case 'student':
                return const StudentHome();
              case 'faculty':
                return const FacultyHome();
              case 'admin':
                return const AdminDashboardScreen();
              default:
                debugPrint("Unknown role, defaulting to student");
                return const StudentHome();
            }
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 🔹 COMMON UI COMPONENTS
// ─────────────────────────────────────────────────────────────

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _ErrorScreen extends StatelessWidget {
  final String message;
  const _ErrorScreen({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(message, style: const TextStyle(color: Colors.red)),
      ),
    );
  }
}
