import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:integrated_home/services/notification_service.dart';

class NotificationHandler {
  static void setupFirestoreListeners() {
    final db = FirebaseFirestore.instance;
    
    // Listen to IR sensor changes
    db.collection('sensors').doc('ir').snapshots().listen((snap) {
      if (!snap.exists) return;
      
      final is_active = snap.data()?['is_active'] == true;
      final prevActive = snap.metadata.hasPendingWrites 
          ? snap.data()?['previous']?['is_active'] ?? false 
          : false;

      // Only notify when state changes to ACTIVE (not on deactivation)
      if (is_active && !prevActive) {
        NotificationService.showSensorNotification('ir', true);
        
        // Send FCM for background delivery
        FirebaseMessaging.instance.sendMessage(
          data: {'type': 'ir_sensor', 'status': 'active'},
        );
      }
    });

    // Listen to door sensor changes
    db.collection('sensors').doc('reed').snapshots().listen((snap) {
      if (!snap.exists) return;
      
      final is_active = snap.data()?['is_active'] == true;
      final prevActive = snap.metadata.hasPendingWrites 
          ? snap.data()?['previous']?['is_active'] ?? false 
          : false;

      // Notify on BOTH open/close events
      if (is_active != prevActive) {
        NotificationService.showSensorNotification('reed', is_active);
      }
    });
  }
}