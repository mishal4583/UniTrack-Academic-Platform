// ═══════════════════════════════════════════════════════════════════════════════
// admin_settings_screen.dart   Route: /admin/settings
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:unitrack_flutter/screens/admin/admin_dashboard_layout.dart';

// ─────────────────────────────────────────────
// THEME CONSTANTS (matches dashboard)
// ─────────────────────────────────────────────
const _cardColor    = Color(0xFF12121F);
const _borderColor  = Color(0xFF1E1E35);
const _neonCyan     = Color(0xFF00F5FF);
const _neonBlue     = Color(0xFF3B82F6);
const _neonGreen    = Color(0xFF34D399);
const _neonRed      = Color(0xFFEF4444);
const _neonYellow   = Color(0xFFFBBF24);
const _mutedText    = Color(0xFF6B7280);
const _foreground   = Color(0xFFF1F5F9);
const _primary      = Color(0xFF8B5CF6);

// Contract info — update if contract changes
const _contractAddress = '0x814D6Ba6eeCc74A40CA42DBfCEb6F64e5F794619';
const _network         = 'Sepolia Testnet';

// ─────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────
class AdminSettingsScreen extends StatelessWidget {
  const AdminSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminDashboardLayout(
      pageTitle: 'Settings',
      child: const _SettingsBody(),
    );
  }
}

// ─────────────────────────────────────────────
// BODY
// ─────────────────────────────────────────────
class _SettingsBody extends StatefulWidget {
  const _SettingsBody();

  @override
  State<_SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends State<_SettingsBody> {
  // ── App toggles ──────────────────────────────
  bool _blockchainEnabled = true;
  bool _notificationsEnabled = false;

  // ── Admin profile data ───────────────────────
  String _adminName  = '';
  String _adminEmail = '';
  bool   _loading    = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _adminEmail = user.email ?? '';

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final name = (doc.data()?['name'] as String?) ?? '';
      // assign outside setState, then call setState({})
      _adminName = name.isNotEmpty ? name : 'Administrator';
    } catch (_) {
      _adminName = 'Administrator';
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _ConfirmDialog(
        title: 'Sign Out',
        message: 'Are you sure you want to sign out?',
        confirmLabel: 'Sign Out',
        destructive: true,
      ),
    );
    if (confirmed != true || !mounted) return;
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Page heading ──────────────────────
          const Text(
            'Admin Settings',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: _foreground,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Manage your profile, blockchain config and system preferences',
            style: TextStyle(fontSize: 13, color: _mutedText),
          ),
          const SizedBox(height: 28),

          // ── 1. Admin Profile ──────────────────
          _SectionLabel(label: 'Admin Profile', icon: Icons.person_rounded),
          const SizedBox(height: 12),
          _SettingsCard(
            child: _loading
                ? const _SkeletonRow()
                : Column(
                    children: [
                      _ProfileRow(
                        name:  _adminName,
                        email: _adminEmail,
                      ),
                      const SizedBox(height: 16),
                      const Divider(color: _borderColor, height: 1),
                      const SizedBox(height: 16),
                      _InfoTile(
                        icon:  Icons.verified_user_rounded,
                        color: _primary,
                        label: 'Role',
                        value: 'Administrator',
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 24),

          // ── 2. Blockchain / System Info ───────
          _SectionLabel(
            label: 'Blockchain & System',
            icon:  Icons.shield_rounded,
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            child: Column(
              children: [
                _InfoTile(
                  icon:  Icons.hub_rounded,
                  color: _neonCyan,
                  label: 'Network',
                  value: _network,
                ),
                const Divider(color: _borderColor, height: 24),
                _CopyTile(
                  icon:    Icons.code_rounded,
                  color:   _neonBlue,
                  label:   'Contract Address',
                  value:   _contractAddress,
                  onCopy:  () => _copyToClipboard(_contractAddress),
                ),
                const Divider(color: _borderColor, height: 24),
                _InfoTile(
                  icon:  Icons.circle,
                  color: _neonGreen,
                  label: 'Status',
                  value: 'Connected',
                  valueColor: _neonGreen,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── 3. App Settings ───────────────────
          _SectionLabel(
            label: 'App Settings',
            icon:  Icons.tune_rounded,
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            child: Column(
              children: [
                _ToggleTile(
                  icon:     Icons.link_rounded,
                  color:    _neonCyan,
                  label:    'Blockchain Verification',
                  subtitle: 'Automatically issue certificates to Sepolia',
                  value:    _blockchainEnabled,
                  onChanged: (v) => setState(() => _blockchainEnabled = v),
                ),
                const Divider(color: _borderColor, height: 24),
                _ToggleTile(
                  icon:     Icons.notifications_rounded,
                  color:    _neonYellow,
                  label:    'Notifications',
                  subtitle: 'Receive alerts for new verifications',
                  value:    _notificationsEnabled,
                  onChanged: (v) => setState(() => _notificationsEnabled = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── 4. Security ───────────────────────
          _SectionLabel(
            label: 'Security',
            icon:  Icons.lock_rounded,
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            child: _ActionTile(
              icon:     Icons.logout_rounded,
              color:    _neonRed,
              label:    'Sign Out',
              subtitle: 'End your admin session',
              onTap:    _logout,
              destructive: true,
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ─────────────────────────────────────────────
// SECTION LABEL
// ─────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  const _SectionLabel({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 15, color: _primary),
      const SizedBox(width: 8),
      Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _mutedText,
          letterSpacing: 1.2,
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────
// SETTINGS CARD
// ─────────────────────────────────────────────
class _SettingsCard extends StatelessWidget {
  final Widget child;
  const _SettingsCard({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: _cardColor,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _borderColor),
    ),
    child: child,
  );
}

// ─────────────────────────────────────────────
// PROFILE ROW
// ─────────────────────────────────────────────
class _ProfileRow extends StatelessWidget {
  final String name;
  final String email;
  const _ProfileRow({required this.name, required this.email});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [_primary, _neonBlue],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : 'A',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _foreground,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              email,
              style: const TextStyle(fontSize: 12, color: _mutedText),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────
// INFO TILE (read-only)
// ─────────────────────────────────────────────
class _InfoTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final Color? valueColor;
  const _InfoTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 16, color: color),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Text(
          label,
          style: const TextStyle(fontSize: 13, color: _mutedText),
        ),
      ),
      Text(
        value,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: valueColor ?? _foreground,
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────
// COPY TILE (truncated value + copy button)
// ─────────────────────────────────────────────
class _CopyTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final VoidCallback onCopy;
  const _CopyTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final short = value.length > 14
        ? '${value.substring(0, 8)}...${value.substring(value.length - 6)}'
        : value;
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: _mutedText),
          ),
        ),
        GestureDetector(
          onTap: onCopy,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  short,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: color,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.copy_rounded, size: 11, color: _mutedText),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// TOGGLE TILE
// ─────────────────────────────────────────────
class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ToggleTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 16, color: color),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _foreground,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: _mutedText),
            ),
          ],
        ),
      ),
      Switch(
        value: value,
        onChanged: onChanged,
        activeColor: _primary,
        activeTrackColor: _primary.withValues(alpha: 0.3),
        inactiveThumbColor: _mutedText,
        inactiveTrackColor: _borderColor,
      ),
    ],
  );
}

// ─────────────────────────────────────────────
// ACTION TILE (logout etc.)
// ─────────────────────────────────────────────
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;
  const _ActionTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: destructive ? color : _foreground,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 11, color: _mutedText),
              ),
            ],
          ),
        ),
        Icon(
          Icons.arrow_forward_ios_rounded,
          size: 13,
          color: _mutedText,
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────
// SKELETON ROW (loading placeholder)
// ─────────────────────────────────────────────
class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: _borderColor,
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 16),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 120,
            height: 13,
            decoration: BoxDecoration(
              color: _borderColor,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: 180,
            height: 11,
            decoration: BoxDecoration(
              color: _borderColor,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ],
      ),
    ],
  );
}

// ─────────────────────────────────────────────
// CONFIRM DIALOG
// ─────────────────────────────────────────────
class _ConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final bool destructive;
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: const Color(0xFF12121F),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: _borderColor),
    ),
    title: Text(
      title,
      style: const TextStyle(color: _foreground, fontSize: 16),
    ),
    content: Text(
      message,
      style: const TextStyle(color: _mutedText, fontSize: 13),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Cancel', style: TextStyle(color: _mutedText)),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, true),
        child: Text(
          confirmLabel,
          style: TextStyle(
            color: destructive ? _neonRed : _primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}
