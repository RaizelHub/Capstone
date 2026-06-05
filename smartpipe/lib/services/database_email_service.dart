import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

class DatabaseEmailService {
  static final DatabaseReference _database = FirebaseDatabase.instance.ref();

  // Send water leak notification to database
  static Future<void> sendWaterLeakNotification({
    required String to,
    required String deviceName,
    required String message,
    String? flowRate,
    String? timestamp,
    String? systemName,
    String? subject,
  }) async {
    try {
      final notificationData = {
        'to': to,
        'deviceName': deviceName,
        'message': message,
        'flowRate': flowRate,
        'timestamp': timestamp ?? DateTime.now().toIso8601String(),
        'systemName': systemName ?? 'SmartPipe Water Management System',
        'subject': subject ?? 'Water Leak Alert',
        'status': 'pending',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'type': 'water_leak_alert',
      };

      final newNotificationRef =
          _database.child('notifications').child('water_leaks').push();

      await newNotificationRef.set(notificationData);

      debugPrint('✅ Water leak notification queued for email');
    } catch (e) {
      debugPrint('❌ Error sending water leak notification: $e');
      rethrow;
    }
  }

  // Send manual activities report to database
  static Future<void> sendManualActivitiesReport({
    required String to,
    required String deviceId,
    required List<Map<String, dynamic>> activities,
    String? reportDate,
    String? summary,
    String? subject,
  }) async {
    try {
      final notificationData = {
        'to': to,
        'deviceId': deviceId,
        'activities': activities,
        'reportDate':
            reportDate ?? DateTime.now().toIso8601String().split('T')[0],
        'summary': summary,
        'subject': subject ?? 'Manual Activities Report - $deviceId',
        'status': 'pending',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'type': 'manual_activities_report',
      };

      final newNotificationRef =
          _database.child('notifications').child('manual_activities').push();

      await newNotificationRef.set(notificationData);

      debugPrint('✅ Manual activities report queued for email');
    } catch (e) {
      print('❌ Error sending manual activities report: $e');
      rethrow;
    }
  }

  // Send comprehensive report email with attachment
  static Future<void> sendReportEmail({
    required List<String> recipients,
    required String subject,
    required String message,
    required String attachmentBase64,
    required String fileName,
    String? reportPeriod,
    int? deviceCount,
    int? totalLeaks,
    int? totalManual,
    Map<String, double>? consumption,
    Map<String, String>? deviceLabels,
  }) async {
    if (recipients.isEmpty) {
      debugPrint('⚠️ No recipients provided for report email.');
      return;
    }

    try {
      final notificationData = {
        'recipients': recipients,
        'subject': subject,
        'message': message,
        'attachment': attachmentBase64,
        'fileName': fileName,
        'reportPeriod': reportPeriod,
        'deviceCount': deviceCount,
        'totalLeaks': totalLeaks,
        'totalManual': totalManual,
        'consumption': consumption,
        'deviceLabels': deviceLabels,
        'generatedAt': DateTime.now().toIso8601String(),
        'status': 'pending',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'type': 'comprehensive_report',
      };

      final newNotificationRef =
          _database.child('notifications').child('reports').push();

      await newNotificationRef.set(notificationData);

      debugPrint('✅ Comprehensive report queued for email');
    } catch (e) {
      debugPrint('❌ Error queuing report email: $e');
      rethrow;
    }
  }

  // Send generic notification to database
  static Future<void> sendGenericNotification({
    required String to,
    required String subject,
    required String content,
    String contentType = 'text',
    String priority = 'normal',
  }) async {
    try {
      final notificationData = {
        'to': to,
        'subject': subject,
        'content': content,
        'contentType': contentType,
        'priority': priority,
        'status': 'pending',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'type': 'generic_notification',
      };

      final newNotificationRef =
          _database.child('notifications').child('generic').push();

      await newNotificationRef.set(notificationData);

      debugPrint('✅ Generic notification queued for email');
    } catch (e) {
      print('❌ Error sending generic notification: $e');
      rethrow;
    }
  }

  // Get notification status
  static Future<Map<String, dynamic>?> getNotificationStatus(
    String notificationId,
  ) async {
    try {
      final snapshot =
          await _database
              .child('notifications')
              .child('all')
              .child(notificationId)
              .get();

      if (snapshot.exists) {
        return Map<String, dynamic>.from(snapshot.value as Map);
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error getting notification status: $e');
      return null;
    }
  }

  // Get pending notifications count
  static Future<int> getPendingNotificationsCount() async {
    try {
      final snapshot = await _database.child('notifications').get();

      if (snapshot.exists) {
        int count = 0;
        final data = snapshot.value as Map<dynamic, dynamic>;

        // Count pending notifications in all categories
        for (final category in data.keys) {
          final categoryData = data[category] as Map<dynamic, dynamic>;
          for (final notification in categoryData.values) {
            final notificationData = notification as Map<dynamic, dynamic>;
            if (notificationData['status'] == 'pending') {
              count++;
            }
          }
        }

        return count;
      }
      return 0;
    } catch (e) {
      debugPrint('❌ Error getting pending notifications count: $e');
      return 0;
    }
  }

  // Clean up old sent notifications (optional - for maintenance)
  static Future<void> cleanupOldNotifications({int daysOld = 30}) async {
    try {
      final cutoffTime =
          DateTime.now()
              .subtract(Duration(days: daysOld))
              .millisecondsSinceEpoch;

      final snapshot = await _database.child('notifications').get();

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;

        for (final category in data.keys) {
          final categoryData = data[category] as Map<dynamic, dynamic>;
          final categoryRef = _database.child('notifications').child(category);

          for (final entry in categoryData.entries) {
            final notificationId = entry.key;
            final notificationData = entry.value as Map<dynamic, dynamic>;

            // Check if notification is old and sent
            if (notificationData['status'] == 'sent' &&
                notificationData['sentAt'] != null &&
                notificationData['sentAt'] < cutoffTime) {
              await categoryRef.child(notificationId).remove();
              debugPrint('🗑️ Cleaned up old notification: $notificationId');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Error cleaning up old notifications: $e');
    }
  }
}
