import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String selectedRole = "student";
  bool showPassword = false;

  final emailController = TextEditingController();
  final passwordController = TextEditingController();

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

  final roles = [
    {"value": "student", "label": "Student", "icon": Icons.school},
    {"value": "faculty", "label": "Faculty", "icon": Icons.menu_book},
    {"value": "admin", "label": "Admin", "icon": Icons.settings},
  ];

  // 🔥 LOGIN
  Future<void> login() async {
    try {
      final userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(
            email: emailController.text.trim(),
            password: passwordController.text.trim(),
          );

      final uid = userCredential.user!.uid;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      final role = userDoc['role'];

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, "/$role");
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Login failed")));
    }
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
                  child: ClipRRect(
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
                            // 🔷 LOGO
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: const LinearGradient(
                                  colors: [primary, neonBlue],
                                ),
                              ),
                              child: const Icon(
                                Icons.shield,
                                color: Colors.white,
                              ),
                            ),

                            const SizedBox(height: 12),

                            // TITLE
                            ShaderMask(
                              shaderCallback: (bounds) => const LinearGradient(
                                colors: [primary, neonBlue],
                              ).createShader(bounds),
                              child: const Text(
                                "UniTrack",
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),

                            const SizedBox(height: 4),

                            const Text(
                              "Academic Activity & Credit Management",
                              style: TextStyle(fontSize: 12, color: muted),
                            ),

                            const SizedBox(height: 20),

                            // 🔥 ROLE SELECT
                            Row(
                              children: roles.map((r) {
                                final selected = selectedRole == r["value"];
                                return Expanded(
                                  child: GestureDetector(
                                    onTap: () => setState(
                                      () => selectedRole = r["value"] as String,
                                    ),
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: selected ? primary : border,
                                        ),
                                        color: selected
                                            ? primary.withOpacity(0.1)
                                            : const Color(0xFF151E2C),
                                      ),
                                      child: Column(
                                        children: [
                                          Icon(
                                            r["icon"] as IconData,
                                            size: 20,
                                            color: selected ? primary : muted,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            r["label"] as String,
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
                            ),

                            const SizedBox(height: 20),

                            _input("EMAIL", emailController),
                            const SizedBox(height: 14),
                            _passwordInput(),

                            const SizedBox(height: 18),

                            // 🔥 LOGIN BUTTON
                            Container(
                              width: double.infinity,
                              height: 42,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                gradient: const LinearGradient(
                                  colors: [primary, neonBlue],
                                ),
                              ),
                              child: TextButton(
                                onPressed: login,
                                child: const Text(
                                  "Sign In →",
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ),

                            const SizedBox(height: 20),

                            // DIVIDER
                            Row(
                              children: [
                                Expanded(child: Divider(color: border)),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8),
                                  child: Text(
                                    "or",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: muted,
                                    ),
                                  ),
                                ),
                                Expanded(child: Divider(color: border)),
                              ],
                            ),

                            const SizedBox(height: 16),

                            // WALLET BUTTON
                            Container(
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
                                  Icon(
                                    Icons.account_balance_wallet,
                                    size: 18,
                                    color: neonCyan,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    "Connect Wallet (MetaMask)",
                                    style: TextStyle(color: text),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 14),

                            // ✅ FIXED REGISTER NAVIGATION
                            Text.rich(
                              TextSpan(
                                text: "Don't have an account? ",
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: muted,
                                ),
                                children: [
                                  TextSpan(
                                    text: "Register",
                                    style: const TextStyle(
                                      color: primary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = () {
                                        Navigator.pushNamed(
                                          context,
                                          "/register",
                                        );
                                      },
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 8),

                            const Text(
                              "🔐 Secure academic record system powered by blockchain.",
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 11, color: muted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _input(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: muted)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: const TextStyle(color: text),
          decoration: InputDecoration(
            hintText: "your.email@university.edu",
            hintStyle: const TextStyle(color: muted),
            filled: true,
            fillColor: input,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  Widget _passwordInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("PASSWORD", style: TextStyle(fontSize: 10, color: muted)),
        const SizedBox(height: 6),
        TextField(
          controller: passwordController,
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
              onPressed: () {
                setState(() => showPassword = !showPassword);
              },
            ),
          ),
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

    const step = 40.0;

    for (double i = 0; i < size.width; i += step) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }

    for (double j = 0; j < size.height; j += step) {
      canvas.drawLine(Offset(0, j), Offset(size.width, j), paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
