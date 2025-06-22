import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:integrated_home/models/visitor_model.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const double similarityThreshold = 0.85;
  final CollectionReference _sensorsCollection =
      FirebaseFirestore.instance.collection('sensors');

  Future<void> updateSensorState(String sensorType, bool is_active) async {
    await _sensorsCollection.doc(sensorType).set({
      'is_active': is_active,
      'timestamp': FieldValue.serverTimestamp(),
    });

    if (sensorType == 'ir' && is_active) {
      // Send FCM notification when IR sensor is activated
      await FirebaseMessaging.instance.sendMessage(
        data: {
          'type': 'ir_sensor',
          'status': 'active',
        },
      );
    }
  }

  Stream<Map<String, dynamic>> getSensorStream(String sensorType) {
    return _sensorsCollection.doc(sensorType).snapshots().map((snap) =>
        snap.data() as Map<String, dynamic>? ?? {'is_active': false});
  }

  // Modify addVisitor method
Future<void> addVisitor(Visitor visitor) async {
  await _db.collection('visitors').doc(visitor.id).set(visitor.toMap());
}

  Future<Visitor?> findSimilarVisitor(List<double> queryEmbedding) async {
    final snapshot = await _db
        .collection('visitors')
        .where('listType', whereIn: ['green', 'black'])
        .get();

    Visitor? closestVisitor;
    double highestSimilarity = similarityThreshold;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (data['embedding'] != null) {
        final storedEmbedding = List<double>.from(data['embedding']);

        if (queryEmbedding.length != storedEmbedding.length) continue;

        final similarity = _cosineSimilarity(queryEmbedding, storedEmbedding);

        if (similarity > highestSimilarity) {
          highestSimilarity = similarity;
          closestVisitor = Visitor.fromMap(data, doc.id).copyWith(
            confidence: similarity,
          );
        }
      }
    }

    return closestVisitor;
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;

    double dot = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    final denominator = sqrt(normA) * sqrt(normB);
    return denominator > 0 ? dot / denominator : 0.0;
  }

  Stream<List<Visitor>> getVisitors() {
    return _db
        .collection('visitors')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Visitor.fromMap(doc.data(), doc.id)).toList());
  }

  Future<void> removeVisitor(String visitorId) async {
    await _db.collection('visitors').doc(visitorId).delete();
  }

  Future<void> updateVisitorLastSeen(String visitorId) async {
    await _db.collection('visitors').doc(visitorId).update({
      'lastSeen': FieldValue.serverTimestamp(),
    });
  }
}