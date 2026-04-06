import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:unitrack_flutter/screens/admin/admin_dashboard_layout.dart';

// ─────────────────────────────────────────────
// THEME CONSTANTS
// ─────────────────────────────────────────────
const _cardColor = Color(0xFF12121F);
const _borderColor = Color(0xFF1E1E35);
const _neonCyan = Color(0xFF00F5FF);
const _neonPurple = Color(0xFF8B5CF6);
const _neonBlue = Color(0xFF3B82F6);
const _mutedText = Color(0xFF6B7280);
const _foreground = Color(0xFFF1F5F9);
const _primary = Color(0xFF8B5CF6);
const _destructive = Color(0xFFEF4444);

// ─────────────────────────────────────────────
// ADMIN USERS SCREEN
// ─────────────────────────────────────────────
class AdminUsersScreen extends StatelessWidget {
  const AdminUsersScreen({super.key});

  @override
  Widget build(BuildContext context) => AdminDashboardLayout(
    pageTitle: 'User Management',
    child: const _UsersBody(),
  );
}

// ─────────────────────────────────────────────
// USERS BODY
// ─────────────────────────────────────────────
class _UsersBody extends StatefulWidget {
  const _UsersBody();
  @override
  State<_UsersBody> createState() => _UsersBodyState();
}

class _UsersBodyState extends State<_UsersBody> {
  String _search = '';
  String _roleFilter = 'All';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        final loading = snap.connectionState == ConnectionState.waiting;
        final allDocs = snap.data?.docs ?? [];

        final allUsers = allDocs.map((doc) {
          final d = (doc.data() ?? {}) as Map<String, dynamic>;
          return _UserModel.fromDoc(doc.id, d);
        }).toList();

        final filtered = allUsers.where((u) {
          final matchSearch =
              _search.isEmpty ||
              u.name.toLowerCase().contains(_search.toLowerCase()) ||
              u.email.toLowerCase().contains(_search.toLowerCase());
          final matchRole =
              _roleFilter == 'All' ||
              u.role.toLowerCase() == _roleFilter.toLowerCase();
          return matchSearch && matchRole;
        }).toList();

        final total = allUsers.length;
        final students = allUsers
            .where((u) => u.role.toLowerCase() == 'student')
            .length;
        final faculty = allUsers
            .where((u) => u.role.toLowerCase() == 'faculty')
            .length;
        final inactive = allUsers.where((u) => !u.isActive).length;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              const SizedBox(height: 24),
              _buildStatsRow(loading, total, students, faculty, inactive),
              const SizedBox(height: 24),
              _buildSearchFilter(),
              const SizedBox(height: 16),
              if (loading)
                const _LoadingCard()
              else if (snap.hasError)
                _ErrorCard(message: snap.error.toString())
              else
                _buildTable(context, filtered),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 640;
    final buttons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _OutlineButton(
          label: 'Export',
          icon: Icons.download_rounded,
          onTap: () {},
        ),
        const SizedBox(width: 8),
        _NeonButton(
          label: 'Add User',
          icon: Icons.person_add_rounded,
          onTap: () {},
        ),
      ],
    );
    const titleCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'User Management',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: _foreground,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Manage all platform users, roles & activity',
          style: TextStyle(fontSize: 13, color: _mutedText),
        ),
      ],
    );
    if (isWide) {
      return Row(
        children: [
          const Expanded(child: titleCol),
          const SizedBox(width: 16),
          buttons,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [titleCol, const SizedBox(height: 12), buttons],
    );
  }

  // ── Stats row ────────────────────────────────────────────────────────────────
  Widget _buildStatsRow(
    bool loading,
    int total,
    int students,
    int faculty,
    int inactive,
  ) {
    final stats = [
      _StatData(label: 'Total Users', value: total, color: _primary),
      _StatData(label: 'Students', value: students, color: _neonCyan),
      _StatData(label: 'Faculty', value: faculty, color: _neonBlue),
      _StatData(label: 'Inactive', value: inactive, color: _destructive),
    ];
    return LayoutBuilder(
      builder: (ctx, c) {
        final cols = c.maxWidth >= 600 ? 4 : 2;
        return _ResponsiveGrid(
          columns: cols,
          spacing: 12,
          children: stats
              .map((s) => _StatMiniCard(data: s, loading: loading))
              .toList(),
        );
      },
    );
  }

  // ── Search + filter ──────────────────────────────────────────────────────────
  // FIX: filterRow chips are now inside a SingleChildScrollView so they never
  // overflow on narrow widths (272 px sidebar-collapsed mobile layout).
  Widget _buildSearchFilter() {
    return LayoutBuilder(
      builder: (ctx, c) {
        final isWide = c.maxWidth >= 600;

        // Scrollable chip strip — never overflows regardless of available width
        final chipStrip = SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.filter_list_rounded,
                size: 16,
                color: _mutedText,
              ),
              const SizedBox(width: 8),
              ...['All', 'Student', 'Faculty', 'Admin'].map(
                (r) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _FilterChip(
                    label: r,
                    selected: _roleFilter == r,
                    onTap: () => setState(() => _roleFilter = r),
                  ),
                ),
              ),
            ],
          ),
        );

        final searchField = _GlassSearchField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _search = v),
        );

        if (isWide) {
          return Row(
            children: [
              SizedBox(width: 280, child: searchField),
              const SizedBox(width: 16),
              Expanded(
                child: chipStrip,
              ), // Expanded so it fills remaining width
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [searchField, const SizedBox(height: 12), chipStrip],
        );
      },
    );
  }

  // ── Table ────────────────────────────────────────────────────────────────────
  Widget _buildTable(BuildContext context, List<_UserModel> users) {
    if (users.isEmpty) {
      return _GlassContainer(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Center(
            child: Column(
              children: [
                Icon(
                  Icons.people_outline_rounded,
                  size: 40,
                  color: _mutedText.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 12),
                const Text(
                  'No users found',
                  style: TextStyle(fontSize: 14, color: _mutedText),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return _GlassContainer(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: MediaQuery.of(context).size.width - 48,
          ),
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(Colors.transparent),
            dataRowColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.hovered))
                return _borderColor.withValues(alpha: 0.5);
              return Colors.transparent;
            }),
            dividerThickness: 0.5,
            columnSpacing: 24,
            border: const TableBorder(
              horizontalInside: BorderSide(color: _borderColor, width: 0.5),
              top: BorderSide(color: _borderColor, width: 0.5),
            ),
            columns: const [
              DataColumn(label: _TableHeader('Name')),
              DataColumn(label: _TableHeader('Role')),
              DataColumn(label: _TableHeader('Department')),
              DataColumn(label: _TableHeader('Credits')),
              DataColumn(label: _TableHeader('Status')),
              DataColumn(label: _TableHeader('Joined')),
              DataColumn(label: _TableHeader('Actions')),
            ],
            rows: users.map((u) => _buildUserRow(context, u)).toList(),
          ),
        ),
      ),
    );
  }

  DataRow _buildUserRow(BuildContext context, _UserModel user) {
    return DataRow(
      cells: [
        DataCell(
          SizedBox(
            width: 200,
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [_neonPurple, _neonBlue]),
                  ),
                  child: Center(
                    child: Text(
                      user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: _foreground,
                        ),
                      ),
                      Text(
                        user.email,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: _mutedText),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        DataCell(_RoleBadge(role: user.role)),
        DataCell(
          Text(
            user.department.isNotEmpty ? user.department : '—',
            style: const TextStyle(fontSize: 12, color: _mutedText),
          ),
        ),
        DataCell(
          Text(
            user.credits > 0 ? user.credits.toString() : '—',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: _foreground,
            ),
          ),
        ),
        DataCell(_StatusBadge(isActive: user.isActive)),
        DataCell(
          Text(
            _formatDate(user.createdAt),
            style: const TextStyle(fontSize: 11, color: _mutedText),
          ),
        ),
        DataCell(
          _ActionMenu(
            user: user,
            onToggleActive: () => _toggleActive(context, user),
            onDelete: () => _confirmDelete(context, user),
          ),
        ),
      ],
    );
  }

  Future<void> _toggleActive(BuildContext context, _UserModel user) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.id).update({
        'isActive': !user.isActive,
      });
      if (context.mounted)
        _showSnack(
          context,
          user.isActive ? 'User disabled.' : 'User enabled.',
          success: true,
        );
    } catch (e) {
      if (context.mounted) _showSnack(context, 'Error: $e', success: false);
    }
  }

  Future<void> _confirmDelete(BuildContext context, _UserModel user) async {
    if (user.role.toLowerCase() == 'admin') {
      _showSnack(context, 'Cannot delete admin users.', success: false);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteDialog(userName: user.name),
    );
    if (confirmed == true && context.mounted) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.id)
            .delete();
        if (context.mounted)
          _showSnack(context, '${user.name} deleted.', success: true);
      } catch (e) {
        if (context.mounted) _showSnack(context, 'Error: $e', success: false);
      }
    }
  }

  void _showSnack(BuildContext context, String msg, {required bool success}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
        backgroundColor: success
            ? const Color(0xFF1A2E1A)
            : const Color(0xFF2E1A1A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '—';
    final dt = ts.toDate();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.year}';
  }
}

// ─────────────────────────────────────────────
// USER MODEL
// ─────────────────────────────────────────────
class _UserModel {
  final String id, name, email, role, department;
  final int credits;
  final bool isActive;
  final Timestamp? createdAt;

  const _UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.department,
    required this.credits,
    required this.isActive,
    required this.createdAt,
  });

  factory _UserModel.fromDoc(String id, Map<String, dynamic> d) => _UserModel(
    id: id,
    name: d['name'] as String? ?? '',
    email: d['email'] as String? ?? '',
    role: d['role'] as String? ?? 'student',
    department: d['department'] as String? ?? '',
    credits: (d['credits'] as num? ?? 0).toInt(),
    isActive: d['isActive'] as bool? ?? true,
    createdAt: d['createdAt'] as Timestamp?,
  );
}

// ─────────────────────────────────────────────
// ACTION MENU
// ─────────────────────────────────────────────
class _ActionMenu extends StatefulWidget {
  final _UserModel user;
  final VoidCallback onToggleActive, onDelete;
  const _ActionMenu({
    required this.user,
    required this.onToggleActive,
    required this.onDelete,
  });
  @override
  State<_ActionMenu> createState() => _ActionMenuState();
}

class _ActionMenuState extends State<_ActionMenu> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: PopupMenuButton<String>(
      color: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _borderColor),
      ),
      onSelected: (val) {
        if (val == 'toggle') widget.onToggleActive();
        if (val == 'delete') widget.onDelete();
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'toggle',
          child: Row(
            children: [
              Icon(
                widget.user.isActive
                    ? Icons.block_rounded
                    : Icons.check_circle_rounded,
                size: 15,
                color: widget.user.isActive ? _destructive : _neonCyan,
              ),
              const SizedBox(width: 8),
              Text(
                widget.user.isActive ? 'Disable User' : 'Enable User',
                style: TextStyle(
                  fontSize: 13,
                  color: widget.user.isActive ? _destructive : _neonCyan,
                ),
              ),
            ],
          ),
        ),
        if (widget.user.role.toLowerCase() != 'admin')
          const PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_rounded, size: 15, color: _destructive),
                SizedBox(width: 8),
                Text(
                  'Delete User',
                  style: TextStyle(fontSize: 13, color: _destructive),
                ),
              ],
            ),
          ),
      ],
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: _hovered ? _borderColor : Colors.transparent,
        ),
        child: const Icon(
          Icons.more_horiz_rounded,
          size: 16,
          color: _mutedText,
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────
// DELETE DIALOG
// ─────────────────────────────────────────────
class _DeleteDialog extends StatelessWidget {
  final String userName;
  const _DeleteDialog({required this.userName});
  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: const Color(0xFF12121F),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: _borderColor),
    ),
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _destructive.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.delete_rounded,
                  color: _destructive,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Delete User',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _foreground,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          RichText(
            text: TextSpan(
              style: const TextStyle(
                fontSize: 13,
                color: _mutedText,
                height: 1.5,
              ),
              children: [
                const TextSpan(text: 'Are you sure you want to delete '),
                TextSpan(
                  text: userName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _foreground,
                  ),
                ),
                const TextSpan(text: '? This action cannot be undone.'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _OutlineButton(
                label: 'Cancel',
                onTap: () => Navigator.pop(context, false),
              ),
              const SizedBox(width: 10),
              _DangerButton(
                label: 'Delete',
                onTap: () => Navigator.pop(context, true),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────
// STAT MINI CARD
// ─────────────────────────────────────────────
class _StatData {
  final String label;
  final int value;
  final Color color;
  const _StatData({
    required this.label,
    required this.value,
    required this.color,
  });
}

class _StatMiniCard extends StatefulWidget {
  final _StatData data;
  final bool loading;
  const _StatMiniCard({required this.data, required this.loading});
  @override
  State<_StatMiniCard> createState() => _StatMiniCardState();
}

class _StatMiniCardState extends State<_StatMiniCard> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _hovered
              ? widget.data.color.withValues(alpha: 0.4)
              : _borderColor,
        ),
        boxShadow: _hovered
            ? [
                BoxShadow(
                  color: widget.data.color.withValues(alpha: 0.12),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ]
            : [],
      ),
      child: Column(
        children: [
          widget.loading
              ? const SizedBox(width: 60, height: 28, child: _ShimmerBox())
              : Text(
                  widget.data.value.toString(),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: widget.data.color,
                  ),
                ),
          const SizedBox(height: 4),
          Text(
            widget.data.label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: _mutedText),
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────
// BADGES
// ─────────────────────────────────────────────
class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});
  @override
  Widget build(BuildContext context) {
    final lower = role.toLowerCase();
    final color = lower == 'admin'
        ? _neonCyan
        : lower == 'faculty'
        ? _neonBlue
        : _primary;
    final label = role.isNotEmpty
        ? role[0].toUpperCase() + role.substring(1)
        : '—';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isActive;
  const _StatusBadge({required this.isActive});
  @override
  Widget build(BuildContext context) {
    final color = isActive ? _neonCyan : _destructive;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 4),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isActive ? 'Active' : 'Disabled',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// SEARCH FIELD
// ─────────────────────────────────────────────
class _GlassSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _GlassSearchField({required this.controller, required this.onChanged});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: _cardColor,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _borderColor),
    ),
    child: TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 13, color: _foreground),
      decoration: InputDecoration(
        hintText: 'Search by name or email...',
        hintStyle: const TextStyle(fontSize: 13, color: _mutedText),
        prefixIcon: const Icon(
          Icons.search_rounded,
          size: 18,
          color: _mutedText,
        ),
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(
                  Icons.clear_rounded,
                  size: 16,
                  color: _mutedText,
                ),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              )
            : null,
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────
// FILTER CHIP
// ─────────────────────────────────────────────
class _FilterChip extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  @override
  State<_FilterChip> createState() => _FilterChipState();
}

class _FilterChipState extends State<_FilterChip> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: widget.selected
              ? _primary
              : _hovered
              ? _primary.withValues(alpha: 0.1)
              : _cardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: widget.selected
                ? _primary
                : _hovered
                ? _primary.withValues(alpha: 0.4)
                : _borderColor,
          ),
          boxShadow: widget.selected
              ? [
                  BoxShadow(
                    color: _primary.withValues(alpha: 0.35),
                    blurRadius: 10,
                  ),
                ]
              : [],
        ),
        child: Text(
          widget.label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: widget.selected ? Colors.white : _mutedText,
          ),
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────
// BUTTONS
// ─────────────────────────────────────────────
class _NeonButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  const _NeonButton({required this.label, this.icon, required this.onTap});
  @override
  State<_NeonButton> createState() => _NeonButtonState();
}

class _NeonButtonState extends State<_NeonButton> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: _hovered ? _primary : _primary.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(8),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: _primary.withValues(alpha: 0.4),
                    blurRadius: 12,
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.icon != null) ...[
              Icon(widget.icon, size: 14, color: Colors.white),
              const SizedBox(width: 6),
            ],
            Text(
              widget.label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _OutlineButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  const _OutlineButton({required this.label, this.icon, required this.onTap});
  @override
  State<_OutlineButton> createState() => _OutlineButtonState();
}

class _OutlineButtonState extends State<_OutlineButton> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: _hovered ? _borderColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _hovered ? _mutedText : _borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.icon != null) ...[
              Icon(widget.icon, size: 14, color: _mutedText),
              const SizedBox(width: 6),
            ],
            Text(
              widget.label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _mutedText,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DangerButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _DangerButton({required this.label, required this.onTap});
  @override
  State<_DangerButton> createState() => _DangerButtonState();
}

class _DangerButtonState extends State<_DangerButton> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: _hovered ? _destructive : _destructive.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(8),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: _destructive.withValues(alpha: 0.4),
                    blurRadius: 12,
                  ),
                ]
              : [],
        ),
        child: Text(
          widget.label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────
// SHARED WIDGETS
// ─────────────────────────────────────────────
class _GlassContainer extends StatelessWidget {
  final Widget child;
  const _GlassContainer({required this.child});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
      child: Container(
        decoration: BoxDecoration(
          color: _cardColor.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _borderColor),
        ),
        child: child,
      ),
    ),
  );
}

class _TableHeader extends StatelessWidget {
  final String text;
  const _TableHeader(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w600,
      color: _mutedText,
      letterSpacing: 0.8,
    ),
  );
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();
  @override
  Widget build(BuildContext context) => Container(
    height: 120,
    decoration: BoxDecoration(
      color: _cardColor,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _borderColor),
    ),
    child: const Center(
      child: CircularProgressIndicator(color: _primary, strokeWidth: 2),
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _destructive.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _destructive.withValues(alpha: 0.3)),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline_rounded, color: _destructive, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Error: $message',
            style: const TextStyle(fontSize: 12, color: _destructive),
          ),
        ),
      ],
    ),
  );
}

class _ShimmerBox extends StatefulWidget {
  const _ShimmerBox();
  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _anim = Tween(begin: 0.3, end: 0.7).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => Container(
      decoration: BoxDecoration(
        color: _borderColor.withValues(alpha: _anim.value),
        borderRadius: BorderRadius.circular(6),
      ),
    ),
  );
}

class _ResponsiveGrid extends StatelessWidget {
  final int columns;
  final double spacing;
  final List<Widget> children;
  const _ResponsiveGrid({
    required this.columns,
    required this.spacing,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (int i = 0; i < children.length; i += columns) {
      final rowChildren = children.skip(i).take(columns).toList();
      while (rowChildren.length < columns) {
        rowChildren.add(const SizedBox.shrink());
      }
      rows.add(
        Row(
          children: rowChildren
              .asMap()
              .entries
              .expand(
                (e) => [
                  Expanded(child: e.value),
                  if (e.key < columns - 1) SizedBox(width: spacing),
                ],
              )
              .toList(),
        ),
      );
      if (i + columns < children.length) rows.add(SizedBox(height: spacing));
    }
    return Column(children: rows);
  }
}
