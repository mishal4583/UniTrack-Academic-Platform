import 'package:flutter/material.dart';

class NeonButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;

  const NeonButton({super.key, required this.text, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            colors: [Color(0xFF8B5CF6), Color(0xFF3B82F6)],
          ),
          boxShadow: [
            BoxShadow(color: Colors.purple.withOpacity(0.4), blurRadius: 20),
          ],
        ),
        alignment: Alignment.center,
        child: const Text(
          "Sign In →",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
