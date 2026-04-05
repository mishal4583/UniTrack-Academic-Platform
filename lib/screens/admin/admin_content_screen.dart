import 'dart:async';
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
const _neonAmber = Color(0xFFF59E0B);
const _mutedText = Color(0xFF6B7280);
const _foreground = Color(0xFFF1F5F9);
const _primary = Color(0xFF8B5CF6);
const _destructive = Color(0xFFEF4444);

// ─────────────────────────────────────────────
// CONTENT MODEL (normalized)
// ─────────────────────────────────────────────
class _ContentItem {
  final String id;
  final String title;
  final String description;
  final int credits;
  final int currentParticipants;
  final int maxParticipants;
  final String status; // 'open' | 'closed'
  final String type; // 'activity' | 'volunteering'
  final Timestamp? createdAt;
  final String createdBy;

  const _ContentItem({
    required this.id,
    required this.title,
    required this.description,
    required this.credits,
    required this.currentParticipants,
    required this.maxParticipants,
    required this.status,
    required this.type,
    required this.createdAt,
    required this.createdBy,
  });

  factory _ContentItem.fromActivity(String id, Map<String, dynamic> d) {
    return _ContentItem(
      id: id,
      title: d['title'] as String? ?? '—',
      description: d['description'] as String? ?? '',
      credits: (d['credits'] as num? ?? 0).toInt(),
      currentParticipants: (d['enrolled'] as num? ?? 0).toInt(),
      maxParticipants: (d['capacity'] as num? ?? 0).toInt(),
      status: d['status'] as String? ?? 'open',
      type: 'activity',
      createdAt: d['createdAt'] as Timestamp?,
      createdBy: d['createdBy'] as String? ?? '—',
    );
  }

  factory _ContentItem.fromVolunteering(String id, Map<String, dynamic> d) {
    return _ContentItem(
      id: id,
      title: d['title'] as String? ?? '—',
      description: d['description'] as String? ?? '',
      credits: (d['credits'] as num? ?? 0).toInt(),
      currentParticipants: (d['currentParticipants'] as num? ?? 0).toInt(),
      maxParticipants: (d['maxParticipants'] as num? ?? 0).toInt(),
      status: d['status'] as String? ?? 'open',
      type: 'volunteering',
      createdAt: d['createdAt'] as Timestamp?,
      createdBy: d['createdBy'] as String? ?? '—',
    );
  }
}

// ─────────────────────────────────────────────
// ADMIN CONTENT SCREEN
// ─────────────────────────────────────────────
class AdminContentScreen extends StatelessWidget {
  const AdminContentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminDashboardLayout(
      pageTitle: 'Content Management',
      child: const _ContentBody(),
    );
  }
}

// ─────────────────────────────────────────────
// CONTENT BODY
// ─────────────────────────────────────────────
class _ContentBody extends StatefulWidget {
  const _ContentBody();

  @override
  State<_ContentBody> createState() => _ContentBodyState();
}

class _ContentBodyState extends State<_ContentBody>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String _search = '';
  String _statusFilter = 'All';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(
      () => setState(() {
        _search = '';
        _statusFilter = 'All';
        _searchController.clear();
      }),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<QuerySnapshot>>(
      stream: _mergedStream(),
      builder: (context, snap) {
        final loading = snap.connectionState == ConnectionState.waiting;
        final error = snap.error;

        List<_ContentItem> allItems = [];
        if (snap.hasData) {
          final actSnap = snap.data![0];
          final volSnap = snap.data![1];
          final acts = actSnap.docs.map(
            (d) => _ContentItem.fromActivity(
              d.id,
              d.data() as Map<String, dynamic>,
            ),
          );
          final vols = volSnap.docs.map(
            (d) => _ContentItem.fromVolunteering(
              d.id,
              d.data() as Map<String, dynamic>,
            ),
          );
          allItems = [...acts, ...vols];
          allItems.sort((a, b) {
            final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
            final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
            return bt.compareTo(at);
          });
        }

        // Filter by active tab
        final tabType = _tabController.index == 0 ? 'activity' : 'volunteering';
        final tabItems = allItems.where((i) => i.type == tabType).toList();

        // Client-side search + status filter
        final filtered = tabItems.where((i) {
          final matchSearch =
              _search.isEmpty ||
              i.title.toLowerCase().contains(_search.toLowerCase());
          final matchStatus =
              _statusFilter == 'All' ||
              i.status.toLowerCase() == _statusFilter.toLowerCase();
          return matchSearch && matchStatus;
        }).toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              _buildHeader(context),
              const SizedBox(height: 24),

              // Tab switch
              _buildTabs(),
              const SizedBox(height: 20),

              // Stats row
              if (loading)
                const _LoadingCard()
              else if (error != null)
                _ErrorCard(message: error.toString())
              else
                _buildStats(tabItems),
              const SizedBox(height: 20),

              // Search + filter
              _buildSearchFilter(),
              const SizedBox(height: 16),

              // Table
              if (loading)
                const _LoadingCard()
              else if (error != null)
                _ErrorCard(message: error.toString())
              else
                _buildTable(context, filtered),

              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  // Combine both streams into a single event using Stream.periodic workaround:
  // We use a simple approach — individual StreamBuilders nested or a manual zip.
  // Best practice: use rxdart or manual combineLatest. Here we use a clean approach.
  Stream<List<QuerySnapshot>> _mergedStream() {
    final db = FirebaseFirestore.instance;
    final actStream = db
        .collection('activities')
        .orderBy('createdAt', descending: true)
        .snapshots();
    final volStream = db
        .collection('volunteering')
        .orderBy('createdAt', descending: true)
        .snapshots();

    // Manual zip using StreamBuilder + async expansion
    return _combineLatest2(actStream, volStream);
  }

  // Simple combineLatest2 implementation
  Stream<List<QuerySnapshot>> _combineLatest2(
    Stream<QuerySnapshot> a,
    Stream<QuerySnapshot> b,
  ) async* {
    QuerySnapshot? latestA;
    QuerySnapshot? latestB;
    final controller = StreamController<List<QuerySnapshot>>();

    a.listen((snap) {
      latestA = snap;
      if (latestA != null && latestB != null) {
        controller.add([latestA!, latestB!]);
      }
    });
    b.listen((snap) {
      latestB = snap;
      if (latestA != null && latestB != null) {
        controller.add([latestA!, latestB!]);
      }
    });

    yield* controller.stream;
  }

  Widget _buildHeader(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 640;
    return isWide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Content Management',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: _foreground,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Manage all activities and volunteering programs',
                      style: TextStyle(fontSize: 13, color: _mutedText),
                    ),
                  ],
                ),
              ),
              _NeonButton(
                label: 'Create Activity',
                icon: Icons.add_rounded,
                onTap: () {},
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Content Management',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _foreground,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Manage all activities and volunteering programs',
                style: TextStyle(fontSize: 13, color: _mutedText),
              ),
              const SizedBox(height: 12),
              _NeonButton(
                label: 'Create Activity',
                icon: Icons.add_rounded,
                onTap: () {},
              ),
            ],
          );
  }

  Widget _buildTabs() {
    return _GlassContainer(
      padding: const EdgeInsets.all(4),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: _primary.withOpacity(0.2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _primary.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(color: _primary.withOpacity(0.15), blurRadius: 8),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: _primary,
        unselectedLabelColor: _mutedText,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        tabs: const [
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.menu_book_rounded, size: 15),
                SizedBox(width: 6),
                Text('Activities'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.eco_rounded, size: 15),
                SizedBox(width: 6),
                Text('Volunteering'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats(List<_ContentItem> items) {
    final isActivity = _tabController.index == 0;
    final open = items.where((i) => i.status.toLowerCase() == 'open').length;
    final closed = items
        .where((i) => i.status.toLowerCase() == 'closed')
        .length;
    final totalParticipants = items.fold<int>(
      0,
      (sum, i) => sum + i.currentParticipants,
    );

    final stats = [
      _StatData(
        label: isActivity ? 'Total Activities' : 'Total Programs',
        value: items.length.toString(),
        color: _primary,
      ),
      _StatData(label: 'Open', value: open.toString(), color: _neonCyan),
      _StatData(label: 'Closed', value: closed.toString(), color: _destructive),
      _StatData(
        label: isActivity ? 'Total Enrolled' : 'Total Participants',
        value: totalParticipants.toString(),
        color: _neonAmber,
      ),
    ];

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final cols = constraints.maxWidth >= 600 ? 4 : 2;
        return _ResponsiveGrid(
          columns: cols,
          spacing: 12,
          children: stats.map((s) => _StatMiniCard(data: s)).toList(),
        );
      },
    );
  }

  Widget _buildSearchFilter() {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final isWide = constraints.maxWidth >= 600;
        final searchField = _GlassSearchField(
          controller: _searchController,
          hint: 'Search activities...',
          onChanged: (v) => setState(() => _search = v),
        );
        final filterRow = Row(
          children: [
            const Icon(Icons.filter_list_rounded, size: 16, color: _mutedText),
            const SizedBox(width: 8),
            ...['All', 'Open', 'Closed'].map(
              (f) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _FilterChip(
                  label: f,
                  selected: _statusFilter == f,
                  onTap: () => setState(() => _statusFilter = f),
                ),
              ),
            ),
          ],
        );

        return isWide
            ? Row(
                children: [
                  SizedBox(width: 280, child: searchField),
                  const SizedBox(width: 16),
                  filterRow,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [searchField, const SizedBox(height: 12), filterRow],
              );
      },
    );
  }

  Widget _buildTable(BuildContext context, List<_ContentItem> items) {
    if (items.isEmpty) {
      return _GlassContainer(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Center(
            child: Column(
              children: [
                Icon(
                  Icons.inbox_rounded,
                  size: 40,
                  color: _mutedText.withOpacity(0.4),
                ),
                const SizedBox(height: 12),
                const Text(
                  'No content found',
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
              if (states.contains(WidgetState.hovered)) {
                return _borderColor.withOpacity(0.5);
              }
              return Colors.transparent;
            }),
            dividerThickness: 0.5,
            columnSpacing: 20,
            border: const TableBorder(
              horizontalInside: BorderSide(color: _borderColor, width: 0.5),
              top: BorderSide(color: _borderColor, width: 0.5),
            ),
            columns: const [
              DataColumn(label: _TableHeader('Activity')),
              DataColumn(label: _TableHeader('Credits')),
              DataColumn(label: _TableHeader('Participants')),
              DataColumn(label: _TableHeader('Status')),
              DataColumn(label: _TableHeader('Created')),
              DataColumn(label: _TableHeader('Actions')),
            ],
            rows: items.map((item) => _buildRow(context, item)).toList(),
          ),
        ),
      ),
    );
  }

  DataRow _buildRow(BuildContext context, _ContentItem item) {
    final fill = item.maxParticipants > 0
        ? (item.currentParticipants / item.maxParticipants).clamp(0.0, 1.0)
        : 0.0;

    return DataRow(
      cells: [
        // Title
        DataCell(
          SizedBox(
            width: 200,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _foreground,
                  ),
                ),
                Text(
                  _formatDate(item.createdAt),
                  style: const TextStyle(fontSize: 11, color: _mutedText),
                ),
              ],
            ),
          ),
        ),

        // Credits
        DataCell(
          Text(
            '${item.credits} pts',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _primary,
            ),
          ),
        ),

        // Participants + progress bar
        DataCell(
          SizedBox(
            width: 120,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.currentParticipants}/${item.maxParticipants}',
                  style: const TextStyle(fontSize: 12, color: _mutedText),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: fill,
                    minHeight: 5,
                    backgroundColor: _borderColor,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      fill >= 1.0 ? _neonAmber : _primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Status badge
        DataCell(_StatusBadge(status: item.status)),

        // Created date
        DataCell(
          Text(
            _formatDate(item.createdAt),
            style: const TextStyle(fontSize: 11, color: _mutedText),
          ),
        ),

        // Actions
        DataCell(
          _RowActions(
            item: item,
            onToggle: () => _toggleStatus(context, item),
            onDelete: () => _confirmDelete(context, item),
          ),
        ),
      ],
    );
  }

  Future<void> _toggleStatus(BuildContext context, _ContentItem item) async {
    final newStatus = item.status.toLowerCase() == 'open' ? 'closed' : 'open';
    final collection = item.type == 'activity' ? 'activities' : 'volunteering';
    try {
      await FirebaseFirestore.instance
          .collection(collection)
          .doc(item.id)
          .update({'status': newStatus});
      if (context.mounted) {
        _showSnack(context, 'Status updated to $newStatus.', success: true);
      }
    } catch (e) {
      if (context.mounted) _showSnack(context, 'Error: $e', success: false);
    }
  }

  Future<void> _confirmDelete(BuildContext context, _ContentItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteDialog(title: item.title),
    );
    if (confirmed == true && context.mounted) {
      final collection = item.type == 'activity'
          ? 'activities'
          : 'volunteering';
      try {
        await FirebaseFirestore.instance
            .collection(collection)
            .doc(item.id)
            .delete();
        if (context.mounted) {
          _showSnack(context, '"${item.title}" deleted.', success: true);
        }
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
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

// ─────────────────────────────────────────────
// STATUS BADGE
// ─────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final isOpen = status.toLowerCase() == 'open';
    final isFull = status.toLowerCase() == 'full';
    final color = isOpen
        ? _neonCyan
        : isFull
        ? _neonAmber
        : _mutedText;
    final label = status.isNotEmpty
        ? status[0].toUpperCase() + status.substring(1)
        : '—';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(color: color.withOpacity(0.7), blurRadius: 4),
              ],
            ),
          ),
          const SizedBox(width: 5),
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
// ROW ACTIONS
// ─────────────────────────────────────────────
class _RowActions extends StatelessWidget {
  final _ContentItem item;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _RowActions({
    required this.item,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isOpen = item.status.toLowerCase() == 'open';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _IconAction(
          icon: isOpen ? Icons.block_rounded : Icons.check_circle_rounded,
          color: isOpen ? _neonAmber : _neonCyan,
          tooltip: isOpen ? 'Close' : 'Open',
          onTap: onToggle,
        ),
        const SizedBox(width: 4),
        _IconAction(
          icon: Icons.delete_rounded,
          color: _destructive,
          tooltip: 'Delete',
          onTap: onDelete,
        ),
      ],
    );
  }
}

class _IconAction extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;
  const _IconAction({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_IconAction> createState() => _IconActionState();
}

class _IconActionState extends State<_IconAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: widget.tooltip,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: _hovered
                ? widget.color.withOpacity(0.12)
                : Colors.transparent,
          ),
          child: Icon(widget.icon, size: 15, color: widget.color),
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────
// DELETE DIALOG
// ─────────────────────────────────────────────
class _DeleteDialog extends StatelessWidget {
  final String title;
  const _DeleteDialog({required this.title});

  @override
  Widget build(BuildContext context) {
    return Dialog(
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
                    color: _destructive.withOpacity(0.1),
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
                  'Delete Content',
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
                    text: '"$title"',
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
}

// ─────────────────────────────────────────────
// STAT DATA + MINI CARD
// ─────────────────────────────────────────────
class _StatData {
  final String label;
  final String value;
  final Color color;
  const _StatData({
    required this.label,
    required this.value,
    required this.color,
  });
}

class _StatMiniCard extends StatefulWidget {
  final _StatData data;
  const _StatMiniCard({required this.data});

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
          color: _hovered ? widget.data.color.withOpacity(0.4) : _borderColor,
        ),
        boxShadow: _hovered
            ? [
                BoxShadow(
                  color: widget.data.color.withOpacity(0.12),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ]
            : [],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            widget.data.value,
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
// GLASS SEARCH FIELD
// ─────────────────────────────────────────────
class _GlassSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  const _GlassSearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

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
        hintText: hint,
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
              ? _primary.withOpacity(0.1)
              : _cardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: widget.selected
                ? _primary
                : _hovered
                ? _primary.withOpacity(0.4)
                : _borderColor,
          ),
          boxShadow: widget.selected
              ? [BoxShadow(color: _primary.withOpacity(0.35), blurRadius: 10)]
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: _hovered ? _primary : _primary.withOpacity(0.88),
          borderRadius: BorderRadius.circular(8),
          boxShadow: _hovered
              ? [BoxShadow(color: _primary.withOpacity(0.45), blurRadius: 14)]
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
  final VoidCallback onTap;
  const _OutlineButton({required this.label, required this.onTap});

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
        child: Text(
          widget.label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _mutedText,
          ),
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
          color: _hovered ? _destructive : _destructive.withOpacity(0.85),
          borderRadius: BorderRadius.circular(8),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: _destructive.withOpacity(0.4),
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
          color: _cardColor.withOpacity(0.85),
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
      color: _destructive.withOpacity(0.08),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _destructive.withOpacity(0.3)),
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
