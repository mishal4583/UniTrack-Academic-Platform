import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// SCREENS
import 'package:unitrack_flutter/screens/auth/login_screen.dart';
import 'package:unitrack_flutter/screens/student/student_home.dart';
import 'package:unitrack_flutter/screens/faculty/faculty_home.dart';
import 'package:unitrack_flutter/screens/admin_home.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // 🔄 Loading
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // ❌ Not logged in
        if (!snapshot.hasData) {
          return const LoginScreen();
        }

        final user = snapshot.data!;

        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get(),
          builder: (context, roleSnap) {
            // 🔄 Loading
            if (roleSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            // ❌ Error
            if (roleSnap.hasError) {
              return Scaffold(
                body: Center(
                  child: Text(
                    "Error: ${roleSnap.error}",
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              );
            }

            // ❌ No user doc
            if (!roleSnap.hasData || !roleSnap.data!.exists) {
              return const Scaffold(
                body: Center(child: Text("User data not found")),
              );
            }

            // ✅ SAFE DATA
            final data = roleSnap.data!.data() as Map<String, dynamic>? ?? {};

            final role = (data['role'] ?? 'student').toString();

            // 🎯 ROUTING
            switch (role) {
              case "student":
                return const StudentHome();
              case "faculty":
                return const FacultyHome();
              case "admin":
                return const AdminHome();
              default:
                return const StudentHome();
            }
          },
        );
      },
    );
  }
}
