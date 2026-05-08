import 'package:cloud_firestore/cloud_firestore.dart';

class Certificate {
  final String docId;
  final String userId;
  final String itemId;
  final String type;

  final String title;
  final String facultyName;

  final int credits;
  final int rating;
  final String feedback;

  final String? blockchainHash;
  final String? transactionHash;

  final String status;
  final DateTime? createdAt;

  Certificate({
    required this.docId,
    required this.userId,
    required this.itemId,
    required this.type,
    required this.title,
    required this.facultyName,
    required this.credits,
    required this.rating,
    required this.feedback,
    required this.status,
    this.blockchainHash,
    this.transactionHash,
    this.createdAt,
  });

  // 🔥 FROM FIRESTORE
  factory Certificate.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};

    return Certificate(
      docId: doc.id,
      userId: d['userId'] ?? '',
      itemId: d['itemId'] ?? '',
      type: d['type'] ?? '',

      title: d['title'] ?? '',
      facultyName: d['facultyName'] ?? '',

      credits: d['credits'] ?? 0,
      rating: d['rating'] ?? 0,
      feedback: d['feedback'] ?? '',

      blockchainHash: d['blockchainHash'],
      transactionHash: d['transactionHash'],

      status: d['status'] ?? 'issued',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
