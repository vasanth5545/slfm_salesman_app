import 'package:firebase_database/firebase_database.dart';
import 'secure_storage_service.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';

class Announcement {
  final String id;
  final String message;
  final String target; // 'global' or showroom name
  final int timestamp;
  final Map<String, dynamic> readBy;

  Announcement({
    required this.id,
    required this.message,
    required this.target,
    required this.timestamp,
    this.readBy = const {},
  });

  factory Announcement.fromMap(String id, Map<dynamic, dynamic> map) {
    return Announcement(
      id: id,
      message: map['message'] ?? '',
      target: map['target'] ?? 'global',
      timestamp: map['timestamp'] ?? 0,
      readBy: Map<String, dynamic>.from(map['read_by'] ?? {}),
    );
  }
}

class AnnouncementService {
  final _database = FirebaseDatabase.instance.ref('announcements');

  // Stream of all announcements that match the user's criteria (target)
  Stream<List<Announcement>> getAnnouncements(
      String showroomName, String salesmanId) {
    return _database.onValue.map((event) {
      if (event.snapshot.value == null) return [];

      final dynamic data = event.snapshot.value;
      final List<Announcement> announcements = [];

      if (data is Map) {
        data.forEach((key, value) {
          if (value is Map) {
            final announcement = Announcement.fromMap(key.toString(), value);

            // Filter by target: global, showroom match, or individual salesman match
            // Supports comma-separated multi-targets (e.g., '123,456')
            final targetList =
                announcement.target.split(',').map((e) => e.trim()).toList();

            // AND ensure user hasn't already read it in RTDB
            if ((targetList.contains('global') ||
                    targetList.contains(showroomName) ||
                    targetList.contains(salesmanId)) &&
                !announcement.readBy.containsKey(salesmanId)) {
              announcements.add(announcement);
            }
          }
        });
      }

      // Sort by timestamp descending
      announcements.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      return announcements;
    });
  }

  // Stream of ALL announcements (including read ones) for history
  Stream<List<Announcement>> getAllAnnouncements(
      String showroomName, String salesmanId) {
    return _database.onValue.map((event) {
      if (event.snapshot.value == null) return [];

      final dynamic data = event.snapshot.value;
      final List<Announcement> announcements = [];

      if (data is Map) {
        data.forEach((key, value) {
          if (value is Map) {
            final announcement = Announcement.fromMap(key.toString(), value);

            // Filter only by target (ignore read status for history)
            // Supports comma-separated multi-targets (e.g., '123,456')
            final targetList =
                announcement.target.split(',').map((e) => e.trim()).toList();

            if (targetList.contains('global') ||
                targetList.contains(showroomName) ||
                targetList.contains(salesmanId)) {
              announcements.add(announcement);
            }
          }
        });
      }

      announcements.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return announcements;
    });
  }

  // Filter out acknowledged ones from the list
  Future<List<Announcement>> filterUnacknowledged(
      List<Announcement> announcements) async {
    final acknowledgedIds =
        await SecureStorageService.getAcknowledgedAnnouncements();
    return announcements.where((a) => !acknowledgedIds.contains(a.id)).toList();
  }

  Future<void> acknowledgeAnnouncement(String id, String salesmanId) async {
    // 1. Update RTDB for real-time cross-device sync
    try {
      await _database.child(id).child('read_by').child(salesmanId).set(true);
    } catch (e) {
      debugPrint('Error updating RTDB read status: $e');
    }

    // 2. Maintain local fallback (SecureStorage)
    final acknowledgedIds =
        await SecureStorageService.getAcknowledgedAnnouncements();
    if (!acknowledgedIds.contains(id)) {
      acknowledgedIds.add(id);
      await SecureStorageService.saveAcknowledgedAnnouncements(acknowledgedIds);
    }
  }
}
