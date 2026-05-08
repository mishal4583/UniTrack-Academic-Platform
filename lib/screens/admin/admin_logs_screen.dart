import 'dart:ui';
import 'package:flutter/services.dart';
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
const _neonGreen = Color(0xFF34D399);
const _neonYellow = Color(0xFFFBBF24);
const _mutedText = Color(0xFF6B7280);
const _foreground = Color(0xFFF1F5F9);
const _primary = Color(0xFF8B5CF6);
const _destructive = Color(0xFFEF4444);

// ─────────────────────────────────────────────
// LOG ENTRY MODEL
// ─────────────────────────────────────────────
class _LogEntry {
  final String id;
  final String userId;
  final String itemId;
  final String type;
  final int credits;
  final String status;
  final Timestamp? createdAt;
  final String? blockchainHash;
  final String? transactionHash;
  final String studentName;
  final String studentEmail;
  final String itemTitle;

  const _LogEntry({
    required this.id,
    required this.userId,
    required this.itemId,
    required this.type,
    required this.credits,
    required this.status,
    required this.createdAt,
    required this.blockchainHash,
    required this.transactionHash,
    required this.studentName,
    required this.studentEmail,
    required this.itemTitle,
  });
}

// ─────────────────────────────────────────────
// ADMIN LOGS SCREEN
// ─────────────────────────────────────────────
class AdminLogsScreen extends StatelessWidget {
  const AdminLogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminDashboardLayout(
      pageTitle: 'Blockchain Monitor',
      child: const _LogsBody(),
    );
  }
}

// ─────────────────────────────────────────────
// LOGS BODY
// ─────────────────────────────────────────────
class _LogsBody extends StatefulWidget {
  const _LogsBody();

  @override
  State<_LogsBody> createState() => _LogsBodyState();
}

class _LogsBodyState extends State<_LogsBody> {
  String _search = '';
  final _searchController = TextEditingController();

  // ── FIX 1: Memoized future — only recomputed when cert doc IDs change
  Future<List<_LogEntry>>? _cachedFuture;
  Set<String> _lastCertDocIds = {};

  // ── FIX 3: In-memory caches — persist across rebuilds, only fetch missing
  final Map<String, Map<String, dynamic>> _userCache = {};
  final Map<String, Map<String, dynamic>> _activityCache = {};
  final Map<String, Map<String, dynamic>> _volunteerCache = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── FIX 1: Return cached future if cert doc IDs haven't changed
  Future<List<_LogEntry>>? _getOrComputeFuture(
    List<QueryDocumentSnapshot> certDocs,
  ) {
    final currentIds = certDocs
        .map((d) => d.id + (d['status'] ?? '') + (d['blockchainHash'] ?? ''))
        .toSet();
    final hasChanged = !_setEquals(currentIds, _lastCertDocIds);
    if (hasChanged || _cachedFuture == null) {
      _lastCertDocIds = currentIds;
      // ── FIX 4: Logic lives in dedicated method, not inside build()
      _cachedFuture = _loadLogs(certDocs);
    }
    return _cachedFuture;
  }

  bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    return a.every(b.contains);
  }

  // ── FIX 4: Dedicated load method with integrated caching
  Future<List<_LogEntry>> _loadLogs(
    List<QueryDocumentSnapshot> certDocs,
  ) async {
    if (certDocs.isEmpty) return [];

    // Collect only IDs missing from cache
    final missingUserIds = <String>{};
    final missingActivityIds = <String>{};
    final missingVolunteeringIds = <String>{};

    for (final doc in certDocs) {
      final d = doc.data() as Map<String, dynamic>;
      final uid = (d['userId'] as String? ?? '').trim();
      final iid = (d['itemId'] as String? ?? '').trim();
      final type = (d['type'] as String? ?? '').trim();

      // ── FIX 3: Skip already cached entries
      if (uid.isNotEmpty && !_userCache.containsKey(uid)) {
        missingUserIds.add(uid);
      }
      if (iid.isNotEmpty) {
        if (type == 'activity' && !_activityCache.containsKey(iid)) {
          missingActivityIds.add(iid);
        } else if (type != 'activity' && !_volunteerCache.containsKey(iid)) {
          missingVolunteeringIds.add(iid);
        }
      }
    }

    final db = FirebaseFirestore.instance;

    // Parallel batch fetch — only missing IDs
    await Future.wait([
      if (missingUserIds.isNotEmpty)
        _batchGet(db, 'users', missingUserIds.toList(), _userCache),
      if (missingActivityIds.isNotEmpty)
        _batchGet(
          db,
          'activities',
          missingActivityIds.toList(),
          _activityCache,
        ),
      if (missingVolunteeringIds.isNotEmpty)
        _batchGet(
          db,
          'volunteering',
          missingVolunteeringIds.toList(),
          _volunteerCache,
        ),
    ]);

    // ── FIX 5: Safe null handling for all field lookups
    return certDocs.map((doc) {
      final d = doc.data() as Map<String, dynamic>;
      final uid = (d['userId'] as String? ?? '').trim();
      final iid = (d['itemId'] as String? ?? '').trim();
      final type = (d['type'] as String? ?? 'activity').trim();

      final user = uid.isNotEmpty ? _userCache[uid] : null;
      final item = type == 'activity'
          ? (iid.isNotEmpty ? _activityCache[iid] : null)
          : (iid.isNotEmpty ? _volunteerCache[iid] : null);

      return _LogEntry(
        id: doc.id,
        userId: uid,
        itemId: iid,
        type: type,
        credits: (d['credits'] as num? ?? 0).toInt(),
        status: (d['status'] as String? ?? 'issued').trim(),
        createdAt: d['createdAt'] as Timestamp?,
        blockchainHash: d['blockchainHash'] as String?,
        transactionHash: d['transactionHash'] as String?,
        studentName: (user?['name'] as String?)?.trim() ?? 'Unknown User',
        studentEmail: (user?['email'] as String?)?.trim() ?? '',
        itemTitle: (item?['title'] as String?)?.trim() ?? 'Unknown Item',
      );
    }).toList();
  }

  // Chunk whereIn queries (Firestore limit: 30 per call)
  Future<void> _batchGet(
    FirebaseFirestore db,
    String collection,
    List<String> ids,
    Map<String, Map<String, dynamic>> resultMap,
  ) async {
    if (ids.isEmpty) return;
    const chunkSize = 30;
    final futures = <Future>[];
    for (int i = 0; i < ids.length; i += chunkSize) {
      final chunk = ids.skip(i).take(chunkSize).toList();
      futures.add(
        db
            .collection(collection)
            .where(FieldPath.documentId, whereIn: chunk)
            .get()
            .then((snap) {
              for (final doc in snap.docs) {
                resultMap[doc.id] = doc.data();
              }
            }),
      );
    }
    await Future.wait(futures);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('certificates')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, certSnap) {
        // Show spinner only on first load, not on every stream update
        if (certSnap.connectionState == ConnectionState.waiting &&
            !certSnap.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: _primary, strokeWidth: 2),
          );
        }
        if (certSnap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _ErrorCard(message: certSnap.error.toString()),
            ),
          );
        }

        final certDocs = certSnap.data?.docs ?? [];

        if (certDocs.isEmpty) {
          return _buildEmptyBody();
        }

        // ── FIX 1: Memoized — reuses cached Future if docs didn't change
        final resolvedFuture = _getOrComputeFuture(certDocs);

        return FutureBuilder<List<_LogEntry>>(
          future: resolvedFuture,
          builder: (context, resolvedSnap) {
            final loading =
                resolvedSnap.connectionState == ConnectionState.waiting;
            final entries = resolvedSnap.data ?? [];

            // Client-side search — no Firestore reads
            final filtered = entries.where((e) {
              if (_search.isEmpty) return true;
              final q = _search.toLowerCase();
              return e.studentName.toLowerCase().contains(q) ||
                  e.itemTitle.toLowerCase().contains(q) ||
                  e.studentEmail.toLowerCase().contains(q);
            }).toList();

            // Stats computed purely from in-memory list
            final total = entries.length;
            final actCount = entries.where((e) => e.type == 'activity').length;
            final volCount = entries
                .where((e) => e.type == 'volunteering')
                .length;
            final verifiedCount = entries
                .where(
                  (e) =>
                      e.blockchainHash != null && e.blockchainHash!.isNotEmpty,
                )
                .length;
            final verifiedPct = total > 0
                ? '${((verifiedCount / total) * 100).round()}%'
                : '0%';

            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 24),
                  _buildStats(
                    loading,
                    total,
                    actCount,
                    volCount,
                    verifiedCount,
                    verifiedPct,
                  ),
                  const SizedBox(height: 20),
                  _buildSearch(),
                  const SizedBox(height: 16),
                  loading
                      ? const _LoadingCard()
                      : _buildTable(context, filtered),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 24),
          _GlassContainer(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 64),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.find_in_page_rounded,
                      size: 48,
                      color: _mutedText.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No logs found',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: _mutedText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Certificates will appear here once issued',
                      style: TextStyle(fontSize: 12, color: _mutedText),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text(
          'Blockchain Certificate Monitor',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: _foreground,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Live blockchain transaction log for all issued certificates',
          style: TextStyle(fontSize: 13, color: _mutedText),
        ),
      ],
    );
  }

  Widget _buildStats(
    bool loading,
    int total,
    int actCount,
    int volCount,
    int verifiedCount,
    String verifiedPct,
  ) {
    final stats = [
      _StatData(
        label: 'Total Certificates',
        value: total.toString(),
        icon: Icons.card_membership_rounded,
        iconColor: _primary,
        trend: 'All time',
        trendUp: true,
      ),
      _StatData(
        label: 'Activities Verified',
        value: actCount.toString(),
        icon: Icons.menu_book_rounded,
        iconColor: _neonBlue,
      ),
      _StatData(
        label: 'Volunteering Verified',
        value: volCount.toString(),
        icon: Icons.eco_rounded,
        iconColor: _neonGreen,
      ),
      _StatData(
        label: 'Blockchain Verified',
        value: verifiedCount.toString(),
        icon: Icons.shield_rounded,
        iconColor: _neonCyan,
        trend: verifiedPct,
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
          children: stats
              .map((s) => _StatCard(data: s, loading: loading))
              .toList(),
        );
      },
    );
  }

  Widget _buildSearch() {
    return _GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, size: 18, color: _mutedText),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _search = v),
              style: const TextStyle(fontSize: 13, color: _foreground),
              decoration: InputDecoration(
                hintText: 'Search by student name or title...',
                hintStyle: const TextStyle(fontSize: 13, color: _mutedText),
                border: InputBorder.none,
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          Icons.clear_rounded,
                          size: 16,
                          color: _mutedText,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _search = '');
                        },
                      )
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(BuildContext context, List<_LogEntry> entries) {
    if (entries.isEmpty) {
      return _GlassContainer(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 64),
          child: Center(
            child: Column(
              children: [
                Icon(
                  Icons.find_in_page_rounded,
                  size: 48,
                  color: _mutedText.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 12),
                const Text(
                  'No logs found',
                  style: TextStyle(fontSize: 14, color: _mutedText),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Try adjusting your search',
                  style: TextStyle(fontSize: 12, color: _mutedText),
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
              if (states.contains(WidgetState.hovered)) {
                return Colors.white.withValues(alpha: 0.04);
              }
              return Colors.transparent;
            }),
            dividerThickness: 0.5,
            columnSpacing: 20,
            border: const TableBorder(
              horizontalInside: BorderSide(color: _borderColor, width: 0.3),
              top: BorderSide(color: _borderColor, width: 0.5),
            ),
            columns: const [
              DataColumn(label: _TableHeader('Student')),
              DataColumn(label: _TableHeader('Item Title')),
              DataColumn(label: _TableHeader('Type')),
              DataColumn(label: _TableHeader('Credits')),
              DataColumn(label: _TableHeader('Status')),
              DataColumn(label: _TableHeader('Tx Hash')),
              DataColumn(label: _TableHeader('Cert Hash')),
              DataColumn(label: _TableHeader('Date')),
            ],
            rows: entries.map((e) => _buildRow(e)).toList(),
          ),
        ),
      ),
    );
  }

  DataRow _buildRow(_LogEntry e) {
    return DataRow(
      cells: [
        // Student
        DataCell(
          SizedBox(
            width: 180,
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [_neonPurple, _neonBlue],
                    ),
                  ),
                  child: Center(
                    child: Text(
                      e.studentName.isNotEmpty
                          ? e.studentName[0].toUpperCase()
                          : '?',
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
                        e.studentName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: _foreground,
                        ),
                      ),
                      if (e.studentEmail.isNotEmpty)
                        Text(
                          e.studentEmail,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: _mutedText,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Item title
        DataCell(
          SizedBox(
            width: 180,
            child: Text(
              e.itemTitle,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: _foreground),
            ),
          ),
        ),

        // Type badge
        DataCell(_TypeBadge(type: e.type)),

        // Credits
        DataCell(
          Text(
            '${e.credits}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _foreground,
            ),
          ),
        ),

        // Status badge
        DataCell(_CertStatusBadge(status: e.status)),

        // Transaction hash
        DataCell(_HashCell(hash: e.transactionHash, isTransaction: true)),

        // Certificate hash
        DataCell(_HashCell(hash: e.blockchainHash, isTransaction: false)),

        // Date
        DataCell(
          Text(
            _formatDate(e.createdAt),
            style: const TextStyle(fontSize: 12, color: _mutedText),
          ),
        ),
      ],
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
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}

// ─────────────────────────────────────────────
// TYPE BADGE
// ─────────────────────────────────────────────
class _TypeBadge extends StatelessWidget {
  final String type;
  const _TypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final isActivity = type == 'activity';
    final color = isActivity ? _primary : _neonGreen;
    final icon = isActivity ? Icons.menu_book_rounded : Icons.eco_rounded;
    final label = isActivity ? 'Activity' : 'Volunteering';
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
// CERT STATUS BADGE  ← FIX 2: 'issued' is the verified terminal state
// ─────────────────────────────────────────────
class _CertStatusBadge extends StatelessWidget {
  final String status;
  const _CertStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final isVerified = status.toLowerCase() == 'verified';
    final color = isVerified ? _neonCyan : _neonYellow;
    final label = status.isNotEmpty
        ? status[0].toUpperCase() + status.substring(1)
        : '—';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
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
// BLOCKCHAIN BADGE
// ─────────────────────────────────────────────
class _BlockchainBadge extends StatelessWidget {
  final String? hash;
  const _BlockchainBadge({this.hash});

  @override
  Widget build(BuildContext context) {
    final hasHash = hash != null && hash!.isNotEmpty;
    final color = hasHash ? _neonCyan : _mutedText;
    final icon = hasHash ? Icons.check_circle_rounded : Icons.shield_outlined;
    final label = hasHash ? 'Verified on Chain' : 'Not Verified';

    String? shortHash;
    if (hasHash && hash!.length > 10) {
      shortHash =
          '${hash!.substring(0, 6)}...${hash!.substring(hash!.length - 4)}';
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
          if (shortHash != null) ...[
            const SizedBox(width: 4),
            Text(
              shortHash,
              style: TextStyle(
                fontSize: 9,
                color: _mutedText,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }
}


// ─────────────────────────────────────────────
// HASH CELL — truncated hash with copy button
// ─────────────────────────────────────────────
class _HashCell extends StatelessWidget {
  final String? hash;
  final bool isTransaction;
  const _HashCell({this.hash, required this.isTransaction});

  @override
  Widget build(BuildContext context) {
    final hasHash = hash != null && hash!.isNotEmpty;
    if (!hasHash) {
      return const Text('—', style: TextStyle(fontSize: 12, color: _mutedText));
    }
    final short = hash!.length > 12
        ? '${hash!.substring(0, 6)}...${hash!.substring(hash!.length - 4)}'
        : hash!;
    final color = isTransaction ? _neonBlue : _neonCyan;
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: hash!));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hash copied to clipboard'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tag_rounded, size: 10, color: color),
            const SizedBox(width: 4),
            Text(
              short,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.copy_rounded, size: 10, color: _mutedText),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// STAT DATA + CARD
// ─────────────────────────────────────────────
class _StatData {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  final String? trend;
  final bool trendUp;

  const _StatData({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
    this.trend,
    this.trendUp = false,
  });
}

class _StatCard extends StatefulWidget {
  final _StatData data;
  final bool loading;
  const _StatCard({required this.data, required this.loading});

  @override
  State<_StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<_StatCard> {
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
          color: _hovered
              ? widget.data.iconColor.withValues(alpha: 0.4)
              : _borderColor,
        ),
        boxShadow: _hovered
            ? [
                BoxShadow(
                  color: widget.data.iconColor.withValues(alpha: 0.12),
                  blurRadius: 20,
                  spreadRadius: 1,
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
                    letterSpacing: 0.9,
                  ),
                ),
                const SizedBox(height: 6),
                widget.loading
                    ? const SizedBox(
                        width: 70,
                        height: 26,
                        child: _ShimmerBox(),
                      )
                    : Text(
                        widget.data.value,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: _foreground,
                        ),
                      ),
                if (widget.data.trend != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        widget.data.trendUp ? '↑' : '↓',
                        style: TextStyle(
                          fontSize: 11,
                          color: widget.data.trendUp ? _neonCyan : _destructive,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        widget.data.trend!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: widget.data.trendUp ? _neonCyan : _destructive,
                        ),
                      ),
                    ],
                  ),
                ],
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
                  ? widget.data.iconColor.withValues(alpha: 0.2)
                  : widget.data.iconColor.withValues(alpha: 0.1),
            ),
            child: Icon(
              widget.data.icon,
              size: 20,
              color: widget.data.iconColor,
            ),
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────
// SHARED WIDGETS
// ─────────────────────────────────────────────
class _GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  const _GlassContainer({required this.child, this.padding});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
      child: Container(
        padding: padding,
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
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(
      begin: 0.25,
      end: 0.65,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
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
