// faculty_manage_detail_screen.dart — Task 3 capacity guard added
// See inline comments for every change vs previous version.

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'faculty_dashboard_layout.dart';

class _C {
  static const card = Color(0xFF111827);
  static const primary = Color(0xFF8B5CF6);
  static const neonBlue = Color(0xFF3B82F6);
  static const neonCyan = Color(0xFF06B6D4);
  static const neonGreen = Color(0xFF10B981);
  static const amber = Color(0xFFF59E0B);
  static const rose = Color(0xFFF43F5E);
  static const text = Color(0xFFEFF3F8);
  static const muted = Color(0xFF7E8A9A);
  static const border = Color(0xFF1F2937);
  static const secondary = Color(0xFF1A2235);
}

class _ItemDetail {
  final String id, title, description, type, status, date, department;
  final int credits, participants, capacity;
  final bool blockchainVerified, isActivity;
  const _ItemDetail({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.status,
    required this.date,
    required this.department,
    required this.credits,
    required this.participants,
    required this.capacity,
    required this.blockchainVerified,
    required this.isActivity,
  });
}

class _Participant {
  final String docId, userId, name, email, status, joinDate;
  const _Participant({
    required this.docId,
    required this.userId,
    required this.name,
    required this.email,
    required this.status,
    required this.joinDate,
  });
}

class _DetailData {
  final _ItemDetail item;
  final List<_Participant> participants;
  const _DetailData({required this.item, required this.participants});
}

class _DetailService {
  static final _db = FirebaseFirestore.instance;
  static Map<String, dynamic> _safe(DocumentSnapshot doc) =>
      (doc.data() as Map<String, dynamic>?) ?? {};

  static Future<_DetailData> load(String id, bool isActivity) async {
    final col = isActivity ? 'activities' : 'volunteering';
    final itemDoc = await _db.collection(col).doc(id).get();
    final d = _safe(itemDoc);
    final item = isActivity
        ? _ItemDetail(
            id: id,
            isActivity: true,
            title: (d['title'] as String?) ?? '',
            description: (d['description'] as String?) ?? '',
            type: (d['type'] as String?) ?? '',
            status: (d['status'] as String?) ?? 'open',
            date: (d['date'] as String?) ?? '',
            department: (d['department'] as String?) ?? '',
            credits: (d['credits'] as int?) ?? 0,
            participants: (d['enrolled'] as int?) ?? 0,
            capacity: (d['capacity'] as int?) ?? 0,
            blockchainVerified: (d['blockchainVerified'] as bool?) ?? false,
          )
        : _ItemDetail(
            id: id,
            isActivity: false,
            title: (d['title'] as String?) ?? '',
            description: (d['description'] as String?) ?? '',
            type: (d['category'] as String?) ?? '',
            status: (d['status'] as String?) ?? 'open',
            date: (d['date'] as String?) ?? '',
            department: (d['organization'] as String?) ?? '',
            credits: (d['credits'] as int?) ?? 0,
            participants: (d['currentParticipants'] as int?) ?? 0,
            capacity: (d['maxParticipants'] as int?) ?? 0,
            blockchainVerified: (d['blockchainCert'] as bool?) ?? false,
          );

    final QuerySnapshot relSnap = isActivity
        ? await _db
              .collection('enrollments')
              .where('activityId', isEqualTo: id)
              .get()
        : await _db
              .collection('applications')
              .where('volunteeringId', isEqualTo: id)
              .get();

    if (relSnap.docs.isEmpty) return _DetailData(item: item, participants: []);

    final userIds = <String>{};
    for (final doc in relSnap.docs) {
      final uid = (_safe(doc)['userId'] as String?) ?? '';
      if (uid.isNotEmpty) userIds.add(uid);
    }
    final userMap = <String, Map<String, dynamic>>{};
    final uidList = userIds.toList();
    for (int i = 0; i < uidList.length; i += 30) {
      final chunk = uidList.sublist(i, (i + 30).clamp(0, uidList.length));
      final snap = await _db
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snap.docs) userMap[doc.id] = _safe(doc);
    }

    final participants = relSnap.docs.map((doc) {
      final r = _safe(doc);
      final uid = (r['userId'] as String?) ?? '';
      final user = userMap[uid] ?? {};
      final name = (user['name'] as String?) ?? '';
      final email =
          (user['email'] as String?) ??
          uid.substring(0, uid.length.clamp(0, 8));
      final joinTs = r['appliedAt'] ?? r['enrolledAt'];
      String joinDate = '';
      if (joinTs is Timestamp) {
        final dt = joinTs.toDate();
        joinDate =
            '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
      }
      return _Participant(
        docId: doc.id,
        userId: uid,
        name: name.isNotEmpty
            ? name
            : (email.contains('@') ? email.split('@').first : email),
        email: email,
        status: (r['status'] as String?) ?? '',
        joinDate: joinDate,
      );
    }).toList()..sort((a, b) => a.name.compareTo(b.name));

    return _DetailData(item: item, participants: participants);
  }

  // ── TASK 3: capacity check before approve ─────────────────────────────────
  static Future<void> approveEnrollment(
    String docId,
    bool isActivity,
    String itemId,
  ) async {
    final itemCol = isActivity ? 'activities' : 'volunteering';
    final itemDoc = await _db.collection(itemCol).doc(itemId).get();
    final data = (itemDoc.data() as Map<String, dynamic>?) ?? {};

    final enrolled = isActivity
        ? (data['enrolled'] as int?) ?? 0
        : (data['currentParticipants'] as int?) ?? 0;
    final capacity = isActivity
        ? (data['capacity'] as int?) ?? 0
        : (data['maxParticipants'] as int?) ?? 0;
    final status = (data['status'] as String?) ?? 'open';

    // Task 5: 'full' is the item-level status, 'Approved' is enrollment status
    if (status == 'full' || (capacity > 0 && enrolled >= capacity)) {
      throw Exception('Activity is full — cannot approve more participants');
    }

    await _db
        .collection(isActivity ? 'enrollments' : 'applications')
        .doc(docId)
        .update({'status': 'Approved'});
  }

  static Future<void> markCompleted(
    String docId,
    String userId,
    bool isActivity,
  ) async {
    final relCol = isActivity ? 'enrollments' : 'applications';
    final docRef = _db.collection(relCol).doc(docId);
    final relDoc = await docRef.get();
    final data = relDoc.data() ?? {};
    final itemId = isActivity ? data['activityId'] : data['volunteeringId'];
    if (itemId == null) return;
    final itemDoc = await _db
        .collection(isActivity ? 'activities' : 'volunteering')
        .doc(itemId as String)
        .get();
    final credits = ((itemDoc.data() ?? {})['credits'] ?? 0) as int;
    await _db.runTransaction((txn) async {
      txn.update(docRef, {'status': 'Completed'});
      txn.update(_db.collection('users').doc(userId), {
        'credits': FieldValue.increment(credits),
      });
    });
  }

  static Future<void> verifyEnrollment(
    String docId,
    String userId,
    bool isActivity,
  ) async {
    final relCol = isActivity ? 'enrollments' : 'applications';
    await _db.collection(relCol).doc(docId).update({'status': 'Verified'});
    final relDoc = await _db.collection(relCol).doc(docId).get();
    final relData = (relDoc.data() as Map<String, dynamic>?) ?? {};
    final itemId = isActivity
        ? (relData['activityId'] as String?) ?? ''
        : (relData['volunteeringId'] as String?) ?? '';
    if (itemId.isEmpty) return;
    final itemDoc = await _db
        .collection(isActivity ? 'activities' : 'volunteering')
        .doc(itemId)
        .get();
    final credits = ((itemDoc.data() ?? {})['credits'] as int?) ?? 0;
    final existing = await _db
        .collection('certificates')
        .where('userId', isEqualTo: userId)
        .where('itemId', isEqualTo: itemId)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) return;
    await _db.collection('certificates').add({
      'userId': userId,
      'itemId': itemId,
      'type': isActivity ? 'activity' : 'volunteering',
      'credits': credits,
      'status': 'issued',
      'createdAt': FieldValue.serverTimestamp(),
      'blockchainHash': null,
    });
  }
}

Color _statusColor(String s) {
  switch (s) {
    case 'Enrolled':
    case 'Applied':
      return _C.primary;
    case 'Approved':
      return _C.neonBlue;
    case 'Completed':
      return _C.amber;
    case 'Verified':
      return _C.neonCyan;
    case 'Rejected':
      return _C.rose;
    case 'open':
      return _C.neonGreen;
    case 'full':
      return _C.muted;
    default:
      return _C.muted;
  }
}

Widget _badge(String label) {
  final color = _statusColor(label);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Text(
      label.isNotEmpty ? label : 'unknown',
      style: TextStyle(
        color: color,
        fontSize: 9,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    ),
  );
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final Color? glowColor;
  const _GlassCard({required this.child, this.glowColor});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _C.card.withValues(alpha: 0.75),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: glowColor?.withValues(alpha: 0.4) ?? _C.border),
      boxShadow: glowColor != null
          ? [
              BoxShadow(
                color: glowColor!.withValues(alpha: 0.12),
                blurRadius: 14,
              ),
            ]
          : [],
    ),
    child: child,
  );
}

class FacultyManageDetailScreen extends StatefulWidget {
  const FacultyManageDetailScreen({super.key});
  @override
  State<FacultyManageDetailScreen> createState() =>
      _FacultyManageDetailScreenState();
}

class _FacultyManageDetailScreenState extends State<FacultyManageDetailScreen> {
  Future<_DetailData>? _future;
  String? _id;
  bool _isActivity = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_future != null) return;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      _id = args['id'] as String?;
      _isActivity = args['isActivity'] as bool? ?? true;
    }
    if (_id != null) _future = _DetailService.load(_id!, _isActivity);
  }

  void _reload() {
    if (_id == null || !mounted) return;
    setState(() => _future = _DetailService.load(_id!, _isActivity));
  }

  @override
  Widget build(BuildContext context) {
    if (_future == null) {
      return FacultyDashboardLayout(
        currentRoute: '/faculty/manage',
        userName: '',
        child: const Center(
          child: Text('No item selected', style: TextStyle(color: _C.muted)),
        ),
      );
    }
    return FacultyDashboardLayout(
      currentRoute: '/faculty/manage',
      userName: '',
      child: FutureBuilder<_DetailData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 80),
              child: Center(
                child: CircularProgressIndicator(color: _C.primary),
              ),
            );
          }
          if (snap.hasError || snap.data == null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: Colors.redAccent,
                    size: 36,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Failed to load details',
                    style: TextStyle(color: _C.text, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: _reload,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_C.primary, _C.neonBlue],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.refresh_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Retry',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          return _DetailBody(data: snap.data!, onReload: _reload, itemId: _id!);
        },
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  final _DetailData data;
  final VoidCallback onReload;
  final String itemId;
  const _DetailBody({
    required this.data,
    required this.onReload,
    required this.itemId,
  });

  @override
  Widget build(BuildContext context) {
    final item = data.item;
    final width = MediaQuery.of(context).size.width;
    final fillPct = item.capacity > 0
        ? (item.participants / item.capacity).clamp(0.0, 1.0)
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () =>
              Navigator.pushReplacementNamed(context, '/faculty/manage'),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _C.secondary,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _C.border),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: _C.muted,
                  size: 14,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Back to Manage',
                style: TextStyle(color: _C.muted, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        _GlassCard(
          glowColor: item.isActivity ? _C.primary : _C.neonGreen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: (item.isActivity ? _C.primary : _C.neonGreen)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      item.isActivity
                          ? Icons.menu_book_rounded
                          : Icons.eco_rounded,
                      size: 20,
                      color: item.isActivity ? _C.primary : _C.neonGreen,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: width * 0.55,
                              ),
                              child: Text(
                                item.title,
                                style: const TextStyle(
                                  color: _C.text,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            _badge(item.status),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (item.type.isNotEmpty)
                              _MetaChip(label: item.type),
                            if (item.blockchainVerified) _BlockchainChip(),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (item.description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  item.description,
                  style: const TextStyle(
                    color: _C.muted,
                    fontSize: 12,
                    height: 1.5,
                  ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 14),
              const Divider(color: _C.border, height: 1),
              const SizedBox(height: 14),
              _StatsGrid(item: item, width: width),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Text(
                    'Capacity',
                    style: TextStyle(color: _C.muted, fontSize: 10),
                  ),
                  const Spacer(),
                  Text(
                    '${(fillPct * 100).round()}% filled',
                    style: const TextStyle(color: _C.muted, fontSize: 10),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 6,
                  child: Stack(
                    children: [
                      Container(color: _C.secondary),
                      FractionallySizedBox(
                        widthFactor: fillPct,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: fillPct >= 1.0
                                  ? [_C.muted, _C.muted]
                                  : [_C.primary, _C.neonBlue],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        Row(
          children: [
            Icon(Icons.people_rounded, size: 16, color: _C.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${item.isActivity ? 'Enrolled Students' : 'Applicants'} (${data.participants.length})',
                style: const TextStyle(
                  color: _C.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            GestureDetector(
              onTap: onReload,
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: _C.secondary,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _C.border),
                ),
                child: const Icon(
                  Icons.refresh_rounded,
                  color: _C.muted,
                  size: 14,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (data.participants.isEmpty)
          _GlassCard(
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_outline_rounded, color: _C.muted, size: 32),
                  SizedBox(height: 8),
                  Text(
                    'No participants yet',
                    style: TextStyle(color: _C.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
          )
        else
          ...data.participants.map(
            (p) => _ParticipantCard(
              participant: p,
              isActivity: item.isActivity,
              itemId: itemId,
              onAction: onReload,
            ),
          ),

        const SizedBox(height: 4),
        _GlassCard(
          glowColor: _C.neonCyan,
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _C.neonCyan.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  color: _C.neonCyan,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Smart Contract',
                      style: TextStyle(
                        color: _C.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Issue blockchain certificates',
                      style: TextStyle(color: _C.muted, fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_C.neonCyan, _C.neonBlue],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Execute',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final _ItemDetail item;
  final double width;
  const _StatsGrid({required this.item, required this.width});
  @override
  Widget build(BuildContext context) {
    final stats = [
      (
        label: 'Credits',
        value: '${item.credits}',
        icon: Icons.star_rounded,
        color: _C.primary,
      ),
      (
        label: 'Enrolled',
        value: '${item.participants}',
        icon: Icons.people_rounded,
        color: _C.neonBlue,
      ),
      (
        label: 'Capacity',
        value: '${item.capacity}',
        icon: Icons.event_seat_rounded,
        color: _C.neonCyan,
      ),
      (
        label: 'Date',
        value: item.date.isNotEmpty ? item.date : '—',
        icon: Icons.calendar_today_rounded,
        color: _C.amber,
      ),
    ];
    final cardW = (width - 32 - 10) / 2;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: stats
          .map(
            (s) => SizedBox(
              width: cardW,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 10,
                ),
                decoration: BoxDecoration(
                  color: _C.card.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: s.color.withValues(alpha: 0.22)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(s.icon, size: 16, color: s.color),
                    const SizedBox(height: 5),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        s.value,
                        style: TextStyle(
                          color: s.color,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.label,
                      style: const TextStyle(color: _C.muted, fontSize: 9),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  const _MetaChip({required this.label});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: _C.secondary,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: _C.border),
    ),
    child: Text(
      label,
      style: const TextStyle(color: _C.muted, fontSize: 10),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  );
}

class _BlockchainChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: _C.neonCyan.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: _C.neonCyan.withValues(alpha: 0.3)),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.verified_rounded, size: 9, color: _C.neonCyan),
        SizedBox(width: 3),
        Text(
          'Blockchain',
          style: TextStyle(color: _C.neonCyan, fontSize: 9),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ),
  );
}

class _ParticipantCard extends StatefulWidget {
  final _Participant participant;
  final bool isActivity;
  final String itemId;
  final VoidCallback onAction;
  const _ParticipantCard({
    required this.participant,
    required this.isActivity,
    required this.itemId,
    required this.onAction,
  });
  @override
  State<_ParticipantCard> createState() => _ParticipantCardState();
}

class _ParticipantCardState extends State<_ParticipantCard> {
  bool _processing = false;

  Future<void> _act(String action) async {
    if (!mounted) return;
    setState(() => _processing = true);
    try {
      final p = widget.participant;
      switch (action) {
        case 'approve':
          await _DetailService.approveEnrollment(
            p.docId,
            widget.isActivity,
            widget.itemId,
          );
          break;
        case 'complete':
          await _DetailService.markCompleted(
            p.docId,
            p.userId,
            widget.isActivity,
          );
          break;
        case 'verify':
          await _DetailService.verifyEnrollment(
            p.docId,
            p.userId,
            widget.isActivity,
          );
          break;
      }
      if (mounted) widget.onAction();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().replaceAll('Exception: ', ''),
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: _C.rose.withValues(alpha: 0.9),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.participant;
    final initials = p.name.isNotEmpty
        ? (p.name.trim().split(' ').length >= 2
              ? '${p.name.trim().split(' ')[0][0]}${p.name.trim().split(' ')[1][0]}'
                    .toUpperCase()
              : p.name[0].toUpperCase())
        : '?';
    final showApprove = p.status == 'Enrolled' || p.status == 'Applied';
    final showComplete = p.status == 'Approved';
    final showVerify = p.status == 'Completed';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _C.card.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_C.primary, _C.neonBlue]),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  style: const TextStyle(
                    color: _C.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 8,
                  runSpacing: 3,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.email_rounded,
                          size: 10,
                          color: _C.muted,
                        ),
                        const SizedBox(width: 3),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: Text(
                            p.email,
                            style: const TextStyle(
                              color: _C.muted,
                              fontSize: 10,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (p.joinDate.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.calendar_today_rounded,
                            size: 10,
                            color: _C.muted,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            p.joinDate,
                            style: const TextStyle(
                              color: _C.muted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _badge(p.status.isNotEmpty ? p.status : 'unknown'),
              if (_processing)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _C.primary,
                    ),
                  ),
                )
              else if (showApprove) ...[
                const SizedBox(height: 6),
                _ActionBtn(
                  label: 'Approve',
                  icon: Icons.check_circle_rounded,
                  colors: [_C.primary, _C.neonBlue],
                  onTap: () => _act('approve'),
                ),
              ] else if (showComplete) ...[
                const SizedBox(height: 6),
                _ActionBtn(
                  label: 'Complete',
                  icon: Icons.task_alt_rounded,
                  colors: [_C.amber, const Color(0xFFEF6C00)],
                  onTap: () => _act('complete'),
                ),
              ] else if (showVerify) ...[
                const SizedBox(height: 6),
                _ActionBtn(
                  label: 'Verify',
                  icon: Icons.verified_rounded,
                  colors: [_C.neonCyan, _C.neonGreen],
                  onTap: () => _act('verify'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;
  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.colors,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 11),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    ),
  );
}
