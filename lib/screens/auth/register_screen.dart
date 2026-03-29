import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:unitrack_flutter/screens/auth/login_screen.dart';

class RoleModel {
  final String value;
  final String label;
  final IconData icon;

  const RoleModel({
    required this.value,
    required this.label,
    required this.icon,
  });
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  String selectedRole = "student";
  bool showPassword = false;

  final fullName = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final confirmPassword = TextEditingController();

  final studentId = TextEditingController();
  final studentDept = TextEditingController();
  final year = TextEditingController();

  final facultyId = TextEditingController();
  final facultyDept = TextEditingController();
  final designation = TextEditingController();

  // 🎨 COLORS
  static const bg = Color(0xFF080D19);
  static const card = Color(0xFF111827);
  static const primary = Color(0xFF8B5CF6);
  static const neonBlue = Color(0xFF3B82F6);
  static const neonCyan = Color(0xFF06B6D4);
  static const text = Color(0xFFEFF3F8);
  static const muted = Color(0xFF7E8A9A);
  static const border = Color(0xFF1F2937);
  static const input = Color(0xFF1A2332);
  static const glassBorder = Color(0xFF2A3548);

  final List<RoleModel> roles = const [
    RoleModel(value: "student", label: "Student", icon: Icons.school),
    RoleModel(value: "faculty", label: "Faculty", icon: Icons.menu_book),
    RoleModel(value: "admin", label: "Admin", icon: Icons.settings),
  ];

  // ✅ FIXED REGISTER FUNCTION
  Future<void> register() async {
    if (password.text != confirmPassword.text) {
      _snack("Passwords do not match");
      return;
    }

    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email.text.trim(),
        password: password.text.trim(),
      );

      final uid = cred.user!.uid;

      // ✅ CLEAN DATA (NO NULL ISSUES)
      Map<String, dynamic> userData = {
        "name": fullName.text,
        "email": email.text,
        "role": selectedRole,
        "createdAt": Timestamp.now(),
      };

      if (selectedRole == "student") {
        userData["studentId"] = studentId.text;
        userData["department"] = studentDept.text;
        userData["year"] = year.text;
      }

      if (selectedRole == "faculty") {
        userData["facultyId"] = facultyId.text;
        userData["department"] = facultyDept.text;
        userData["designation"] = designation.text;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set(userData);

      if (!mounted) return;

      Navigator.pushReplacementNamed(context, "/$selectedRole");
    } catch (e) {
      print("🔥 REGISTER ERROR: $e"); // DEBUG
      _snack("Error: $e");
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: GridPainter())),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: _glassCard(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glassCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: card.withOpacity(0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: glassBorder),
          ),
          child: Column(
            children: [
              _logo(),
              const SizedBox(height: 20),
              _roleSelector(),
              const SizedBox(height: 20),

              _input("FULL NAME", fullName, "John Doe"),
              _input("EMAIL", email, "your.email@university.edu"),

              if (selectedRole == "student") ...[
                _input("STUDENT ID", studentId, "STU-001"),
                Row(
                  children: [
                    Expanded(child: _input("DEPT", studentDept, "")),
                    const SizedBox(width: 8),
                    Expanded(child: _input("YEAR", year, "")),
                  ],
                ),
              ],

              if (selectedRole == "faculty") ...[
                _input("FACULTY ID", facultyId, "FAC-001"),
                Row(
                  children: [
                    Expanded(child: _input("DEPT", facultyDept, "")),
                    const SizedBox(width: 8),
                    Expanded(child: _input("DESIGNATION", designation, "")),
                  ],
                ),
              ],

              _passwordField(),
              _input("CONFIRM PASSWORD", confirmPassword, "••••••••"),

              const SizedBox(height: 16),
              _button(),

              const SizedBox(height: 16),
              _divider(),

              const SizedBox(height: 12),
              _walletButton(),

              const SizedBox(height: 12),
              _footer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roleSelector() {
    return Row(
      children: roles.map((r) {
        final selected = selectedRole == r.value;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => selectedRole = r.value),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: selected ? primary : border),
                color: selected
                    ? primary.withOpacity(0.1)
                    : const Color(0xFF151E2C),
              ),
              child: Column(
                children: [
                  Icon(r.icon, size: 20, color: selected ? primary : muted),
                  const SizedBox(height: 4),
                  Text(
                    r.label,
                    style: TextStyle(
                      fontSize: 12,
                      color: selected ? text : muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _input(String label, TextEditingController c, String hint) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: muted)),
          const SizedBox(height: 6),
          TextField(
            controller: c,
            style: const TextStyle(color: text),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: muted),
              filled: true,
              fillColor: input,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _passwordField() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("PASSWORD", style: TextStyle(fontSize: 10, color: muted)),
        const SizedBox(height: 6),
        TextField(
          controller: password,
          obscureText: !showPassword,
          style: const TextStyle(color: text),
          decoration: InputDecoration(
            hintText: "••••••••",
            filled: true,
            fillColor: input,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            suffixIcon: IconButton(
              icon: Icon(
                showPassword ? Icons.visibility_off : Icons.visibility,
                color: muted,
              ),
              onPressed: () => setState(() => showPassword = !showPassword),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _button() {
    return Container(
      width: double.infinity,
      height: 42,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [primary, neonBlue]),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextButton(
        onPressed: register,
        child: const Text(
          "Create Account →",
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  Widget _divider() {
    return Row(
      children: const [
        Expanded(child: Divider(color: border)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text("or", style: TextStyle(color: muted)),
        ),
        Expanded(child: Divider(color: border)),
      ],
    );
  }

  Widget _walletButton() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: glassBorder),
        color: card.withOpacity(0.6),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.account_balance_wallet, color: neonCyan),
          SizedBox(width: 8),
          Text("Connect Wallet (MetaMask)", style: TextStyle(color: text)),
        ],
      ),
    );
  }

  Widget _footer() {
    return GestureDetector(
      onTap: () {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      },
      child: const Text(
        "Already have an account? Sign In",
        style: TextStyle(fontSize: 12, color: muted),
      ),
    );
  }

  Widget _logo() {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(colors: [primary, neonBlue]),
          ),
          child: const Icon(Icons.shield, color: Colors.white),
        ),
        const SizedBox(height: 10),
        ShaderMask(
          shaderCallback: (b) =>
              const LinearGradient(colors: [primary, neonBlue]).createShader(b),
          child: const Text(
            "UniTrack",
            style: TextStyle(fontSize: 26, color: Colors.white),
          ),
        ),
        const Text(
          "Create your account",
          style: TextStyle(fontSize: 12, color: muted),
        ),
      ],
    );
  }
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1F2937).withOpacity(0.3)
      ..strokeWidth = 1;

    for (double i = 0; i < size.width; i += 40) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double j = 0; j < size.height; j += 40) {
      canvas.drawLine(Offset(0, j), Offset(size.width, j), paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
