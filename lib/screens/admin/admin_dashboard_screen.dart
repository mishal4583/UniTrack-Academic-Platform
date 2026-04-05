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
const _neonYellow = Color(0xFFFBBF24);
const _mutedText = Color(0xFF6B7280);
const _foreground = Color(0xFFF1F5F9);
const _primary = Color(0xFF8B5CF6);

// ─────────────────────────────────────────────
// ADMIN DASHBOARD SCREEN
// ─────────────────────────────────────────────
class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminDashboardLayout(
      pageTitle: 'Admin Dashboard',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: _DashboardBody(), // your existing body widget
      ),
    );
  }
}

// ─────────────────────────────────────────────
// DASHBOARD BODY
// ─────────────────────────────────────────────
class _DashboardBody extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        const Text(
          'Admin Console',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: _foreground,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'System overview, user management & blockchain governance',
          style: TextStyle(fontSize: 13, color: _mutedText),
        ),
        const SizedBox(height: 24),

        // Stats Grid
        _StatsGrid(),
        const SizedBox(height: 24),

        // User Management
        _UserManagementSection(),
        const SizedBox(height: 24),

        // Blockchain Transactions
        _BlockchainTransactionsSection(),
        const SizedBox(height: 24),

        // Community Stats
        _CommunityStatsSection(),
        const SizedBox(height: 24),

        // Governance
        _GovernanceCard(),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// STATS GRID
// ─────────────────────────────────────────────
class _StatsGrid extends StatelessWidget {
  Future<Map<String, dynamic>> _fetchStats() async {
    final db = FirebaseFirestore.instance;
    final results = await Future.wait([
      db.collection('users').get(),
      db.collection('activities').get(),
      db.collection('volunteering').get(),
    ]);

    final usersSnap = results[0];
    final activitiesSnap = results[1];
    final volunteeringSnap = results[2];

    int totalCredits = 0;
    for (final doc in usersSnap.docs) {
      totalCredits += (doc.data()['credits'] as num? ?? 0).toInt();
    }

    return {
      'totalUsers': usersSnap.size,
      'activeActivities': activitiesSnap.docs
          .where((d) => d.data()['status'] == 'active')
          .length,
      'volunteering': volunteeringSnap.size,
      'totalCredits': totalCredits,
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _fetchStats(),
      builder: (context, snap) {
        final data = snap.data;
        final loading = snap.connectionState == ConnectionState.waiting;

        final cards = [
          _StatCardData(
            label: 'Total Users',
            value: data?['totalUsers'],
            icon: Icons.people_rounded,
            trend: 'Live count',
            trendUp: true,
          ),
          _StatCardData(
            label: 'Active Activities',
            value: data?['activeActivities'],
            icon: Icons.menu_book_rounded,
            trend: 'From Firestore',
            trendUp: true,
          ),
          _StatCardData(
            label: 'Volunteering',
            value: data?['volunteering'],
            icon: Icons.eco_rounded,
            trend: 'All records',
            trendUp: true,
          ),
          _StatCardData(
            label: 'Total Credits Issued',
            value: data?['totalCredits'],
            icon: Icons.shield_rounded,
            trend: 'Sum of credits',
            trendUp: true,
          ),
        ];

        return LayoutBuilder(
          builder: (ctx, constraints) {
            final cols = constraints.maxWidth >= 700
                ? 4
                : constraints.maxWidth >= 400
                ? 2
                : 1;
            return _ResponsiveGrid(
              columns: cols,
              spacing: 16,
              children: cards
                  .map((c) => _GlassStatCard(data: c, loading: loading))
                  .toList(),
            );
          },
        );
      },
    );
  }
}

class _StatCardData {
  final String label;
  final dynamic value;
  final IconData icon;
  final String trend;
  final bool trendUp;
  const _StatCardData({
    required this.label,
    required this.value,
    required this.icon,
    required this.trend,
    required this.trendUp,
  });
}

class _GlassStatCard extends StatefulWidget {
  final _StatCardData data;
  final bool loading;
  const _GlassStatCard({required this.data, required this.loading});

  @override
  State<_GlassStatCard> createState() => _GlassStatCardState();
}

class _GlassStatCardState extends State<_GlassStatCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _hovered ? _primary.withValues(alpha: 0.4) : _borderColor,
        ),
        boxShadow: _hovered
            ? [
                BoxShadow(
                  color: _primary.withValues(alpha: 0.15),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ]
            : [],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.data.label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _mutedText,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 6),
                widget.loading
                    ? const SizedBox(
                        width: 80,
                        height: 28,
                        child: _ShimmerBox(),
                      )
                    : Text(
                        widget.data.value?.toString() ?? '—',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: _foreground,
                        ),
                      ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      widget.data.trendUp ? '↑' : '↓',
                      style: TextStyle(
                        fontSize: 11,
                        color: widget.data.trendUp
                            ? _neonCyan
                            : Colors.redAccent,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      widget.data.trend,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: widget.data.trendUp
                            ? _neonCyan
                            : Colors.redAccent,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: _hovered
                  ? _primary.withValues(alpha: 0.2)
                  : _primary.withValues(alpha: 0.1),
            ),
            child: Icon(widget.data.icon, size: 20, color: _primary),
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────
// USER MANAGEMENT TABLE
// ─────────────────────────────────────────────
class _UserManagementSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'User Management',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _foreground,
              ),
            ),
            const Spacer(),
            _GlassButton(label: 'Add User', onTap: () {}),
          ],
        ),
        const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .limit(20)
              .snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const _LoadingCard();
            }
            if (snap.hasError) {
              return _ErrorCard(message: snap.error.toString());
            }
            final docs = snap.data?.docs ?? [];
            return _GlassContainer(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(Colors.transparent),
                  dataRowColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.hovered)) {
                      return _borderColor.withValues(alpha: 0.5);
                    }
                    return Colors.transparent;
                  }),
                  dividerThickness: 0.5,
                  border: const TableBorder(
                    horizontalInside: BorderSide(
                      color: _borderColor,
                      width: 0.5,
                    ),
                  ),
                  columns: const [
                    DataColumn(label: _TableHeader('Name')),
                    DataColumn(label: _TableHeader('Role')),
                    DataColumn(label: _TableHeader('Department')),
                    DataColumn(label: _TableHeader('Credits')),
                    DataColumn(label: _TableHeader('Status')),
                  ],
                  rows: docs.map((doc) {
                    final d = doc.data() as Map<String, dynamic>;
                    final name = d['name'] as String? ?? '—';
                    final role = d['role'] as String? ?? '—';
                    final dept = d['department'] as String? ?? '—';
                    final credits = d['credits'] as num? ?? 0;
                    final isActive = (d['isActive'] ?? true) as bool;
                    return DataRow(
                      cells: [
                        DataCell(
                          Row(
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const LinearGradient(
                                    colors: [_neonPurple, _neonBlue],
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    name.isNotEmpty
                                        ? name[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: _foreground,
                                ),
                              ),
                            ],
                          ),
                        ),
                        DataCell(_RoleBadge(role: role)),
                        DataCell(
                          Text(
                            dept,
                            style: const TextStyle(
                              fontSize: 12,
                              color: _mutedText,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            credits.toString(),
                            style: const TextStyle(
                              fontSize: 12,
                              color: _foreground,
                            ),
                          ),
                        ),
                        DataCell(
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isActive
                                      ? _neonCyan
                                      : Colors.redAccent,
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          (isActive
                                                  ? _neonCyan
                                                  : Colors.redAccent)
                                              .withValues(alpha: 0.6),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isActive ? 'Active' : 'Disabled',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: isActive
                                      ? _neonCyan
                                      : Colors.redAccent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
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

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final isFaculty = role.toLowerCase() == 'faculty';
    final isAdmin = role.toLowerCase() == 'admin';
    final color = isAdmin
        ? _neonCyan
        : isFaculty
        ? _neonBlue
        : _primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        role[0].toUpperCase() + role.substring(1),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// BLOCKCHAIN TRANSACTIONS
// ─────────────────────────────────────────────
class _BlockchainTransactionsSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Blockchain Transaction Log',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _foreground,
          ),
        ),
        const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('certificates')
              .orderBy('createdAt', descending: true)
              .limit(10)
              .snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const _LoadingCard();
            }
            if (snap.hasError) {
              return _ErrorCard(message: snap.error.toString());
            }
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) {
              return _GlassContainer(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'No transactions yet',
                      style: TextStyle(color: _mutedText, fontSize: 13),
                    ),
                  ),
                ),
              );
            }
            return Column(
              children: docs.map((doc) {
                final d = doc.data() as Map<String, dynamic>;
                final type = d['type'] as String? ?? 'unknown';
                final credits = d['credits'] as num? ?? 0;
                final status = d['status'] as String? ?? 'unverified';
                final blockchainHash = d['blockchainHash'] as String?;
                final createdAt = d['createdAt'];
                String timeStr = '—';
                if (createdAt is Timestamp) {
                  final dt = createdAt.toDate();
                  final diff = DateTime.now().difference(dt);
                  if (diff.inMinutes < 60) {
                    timeStr = '${diff.inMinutes}m ago';
                  } else if (diff.inHours < 24) {
                    timeStr = '${diff.inHours}h ago';
                  } else {
                    timeStr = '${diff.inDays}d ago';
                  }
                }
                final hashShort =
                    blockchainHash != null && blockchainHash.length > 10
                    ? '${blockchainHash.substring(0, 6)}...${blockchainHash.substring(blockchainHash.length - 4)}'
                    : blockchainHash ?? '—';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _GlassContainer(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: _neonCyan.withValues(alpha: 0.1),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.asset(
                                'assets/logo/logo.png',
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  type[0].toUpperCase() + type.substring(1),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: _foreground,
                                  ),
                                ),
                                Text(
                                  '$credits credits',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: _mutedText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                hashShort,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  color: _mutedText,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                    timeStr,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: _mutedText,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _BlockchainBadge(status: status),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

class _BlockchainBadge extends StatelessWidget {
  final String status;
  const _BlockchainBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;
    String label;
    switch (status) {
      case 'verified':
        color = _neonCyan;
        icon = Icons.check_circle_rounded;
        label = 'Verified on Chain';
        break;
      case 'pending':
        color = _neonYellow;
        icon = Icons.access_time_rounded;
        label = 'Pending';
        break;
      default:
        color = _mutedText;
        icon = Icons.shield_outlined;
        label = 'Not Verified';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
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
// COMMUNITY STATS
// ─────────────────────────────────────────────
class _CommunityStatsSection extends StatelessWidget {
  Future<Map<String, int>> _fetchCommunityStats() async {
    final db = FirebaseFirestore.instance;
    final results = await Future.wait([
      db.collection('volunteering').where('status', isEqualTo: 'active').get(),
      db.collection('volunteering').where('status', isEqualTo: 'open').get(),
      db.collection('certificates').get(),
    ]);

    final activeVol = results[0].size;
    final openReq = results[1].size;
    final certsSnap = results[2];

    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    int completedThisMonth = 0;
    for (final doc in certsSnap.docs) {
      final d = doc.data();
      final ts = d['createdAt'];
      if (ts is Timestamp && ts.toDate().isAfter(startOfMonth)) {
        completedThisMonth++;
      }
    }

    return {
      'activeVolunteers': activeVol,
      'openRequests': openReq,
      'completedThisMonth': completedThisMonth,
      'certificatesIssued': certsSnap.size,
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, int>>(
      future: _fetchCommunityStats(),
      builder: (context, snap) {
        final loading = snap.connectionState == ConnectionState.waiting;
        final data = snap.data;
        final items = [
          {'label': 'Active Volunteers', 'value': data?['activeVolunteers']},
          {'label': 'Open Requests', 'value': data?['openRequests']},
          {
            'label': 'Completed This Month',
            'value': data?['completedThisMonth'],
          },
          {
            'label': 'Certificates Issued',
            'value': data?['certificatesIssued'],
          },
        ];
        return _GlassContainer(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.eco_rounded, size: 20, color: Colors.green[400]),
                    const SizedBox(width: 8),
                    const Text(
                      'Community Engagement Stats',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _foreground,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (ctx, constraints) {
                    final cols = constraints.maxWidth >= 500 ? 4 : 2;
                    return _ResponsiveGrid(
                      columns: cols,
                      spacing: 12,
                      children: items
                          .map(
                            (item) => Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A1A2E),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  loading
                                      ? const SizedBox(
                                          width: 50,
                                          height: 22,
                                          child: _ShimmerBox(),
                                        )
                                      : Text(
                                          item['value']?.toString() ?? '—',
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: _foreground,
                                          ),
                                        ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item['label'] as String,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: _mutedText,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// GOVERNANCE CARD
// ─────────────────────────────────────────────
class _GovernanceCard extends StatefulWidget {
  @override
  State<_GovernanceCard> createState() => _GovernanceCardState();
}

class _GovernanceCardState extends State<_GovernanceCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _hovered ? _primary.withValues(alpha: 0.5) : _borderColor,
        ),
        boxShadow: _hovered
            ? [
                BoxShadow(
                  color: _primary.withValues(alpha: 0.2),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ]
            : [],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: _primary.withValues(alpha: 0.1),
            ),
            child: const Icon(
              Icons.settings_rounded,
              size: 22,
              color: _primary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Governance Settings',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _foreground,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Configure credit rules, smart contract parameters & access control',
                  style: TextStyle(fontSize: 12, color: _mutedText),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          _GlassButton(label: 'Configure', onTap: () {}, outlined: true),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────
// REUSABLE WIDGETS
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
          color: _cardColor.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _borderColor),
        ),
        child: child,
      ),
    ),
  );
}

class _GlassButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool outlined;
  const _GlassButton({
    required this.label,
    required this.onTap,
    this.outlined = false,
  });

  @override
  State<_GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<_GlassButton> {
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
          color: widget.outlined
              ? Colors.transparent
              : (_hovered ? _primary : _primary.withValues(alpha: 0.85)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: widget.outlined
                ? (_hovered ? _neonCyan : _primary)
                : Colors.transparent,
          ),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: _primary.withValues(alpha: 0.4),
                    blurRadius: 12,
                  ),
                ]
              : [],
        ),
        child: Text(
          widget.label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: widget.outlined
                ? (_hovered ? _neonCyan : _primary)
                : Colors.white,
          ),
        ),
      ),
    ),
  );
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) => Container(
    height: 100,
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
      color: Colors.red.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.error_outline_rounded,
          color: Colors.redAccent,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Error: $message',
            style: const TextStyle(fontSize: 12, color: Colors.redAccent),
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
    builder: (_, _) => Container(
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
              .map((e) {
                return [
                  Expanded(child: e.value),
                  if (e.key < columns - 1) SizedBox(width: spacing),
                ];
              })
              .expand((x) => x)
              .toList(),
        ),
      );
      if (i + columns < children.length) rows.add(SizedBox(height: spacing));
    }
    return Column(children: rows);
  }
}
