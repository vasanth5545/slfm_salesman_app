import 'dart:convert';

enum SyncStatus { pending, synced, failed, retryNeeded }

class AttendanceRecord {
  final int? localId;
  final String uid; // UUID for duplicate prevention
  final String salesmanId;
  final String type; // 'clock_in', 'clock_out', 'break_out', 'reentry'
  final String timestamp;
  final String latitude;
  final String longitude;
  final String? imagePath;
  SyncStatus syncStatus;
  int retryCount;
  final DateTime
      createdAt; // 🔥 When this record was first created (for same-day check)

  AttendanceRecord({
    this.localId,
    required this.uid,
    required this.salesmanId,
    required this.type,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    this.imagePath,
    this.syncStatus = SyncStatus.pending,
    this.retryCount = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    String statusStr = syncStatus.name;
    if (syncStatus == SyncStatus.retryNeeded) statusStr = 'retry_needed';

    return {
      'local_id': localId,
      'attendance_uid': uid,
      'action': type,
      'salesman_id': salesmanId,
      'latitude': latitude,
      'longitude': longitude,
      'capture_time': timestamp,
      'image_path': imagePath,
      'status': statusStr,
      'retry_count': retryCount,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory AttendanceRecord.fromMap(Map<String, dynamic> map) {
    return AttendanceRecord(
      localId: map['local_id'],
      uid: map['attendance_uid'] ?? '',
      salesmanId: map['salesman_id'] ?? '',
      type: map['action'] ?? '',
      latitude: map['latitude'] ?? '',
      longitude: map['longitude'] ?? '',
      timestamp: map['capture_time'] ?? '',
      imagePath: map['image_path'],
      syncStatus: _parseSyncStatus(map['status']),
      retryCount: map['retry_count'] ?? 0,
      createdAt: _parseCreatedAt(map['created_at']),
    );
  }

  static SyncStatus _parseSyncStatus(String? status) {
    switch (status) {
      case 'synced':
        return SyncStatus.synced;
      case 'failed':
        return SyncStatus.failed;
      case 'retry_needed':
        return SyncStatus.retryNeeded;
      case 'duplicate':
        return SyncStatus.failed; // For simplicity, duplicate acts like failed in UI, or add duplicate to SyncStatus. We map it to failed.
      default:
        return SyncStatus.pending;
    }
  }

  /// 🔥 Safely parse created_at from DB — handles int, String, null, and 0
  static DateTime _parseCreatedAt(dynamic value) {
    if (value == null || value == 0) return DateTime.now();
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null && parsed > 0) {
        return DateTime.fromMillisecondsSinceEpoch(parsed);
      }
    }
    return DateTime.now();
  }

  /// 🔥 Check if this record was created today (same calendar day)
  bool get isSameDay {
    final now = DateTime.now();
    return createdAt.year == now.year &&
        createdAt.month == now.month &&
        createdAt.day == now.day;
  }

  /// 🔥 FIX 2: Removed 15-minute auto-retry window — retry is now immediate

  String toJson() => json.encode(toMap());

  AttendanceRecord copyWith({
    int? localId,
    SyncStatus? syncStatus,
    int? retryCount,
  }) {
    return AttendanceRecord(
      localId: localId ?? this.localId,
      uid: uid,
      salesmanId: salesmanId,
      type: type,
      timestamp: timestamp,
      latitude: latitude,
      longitude: longitude,
      imagePath: imagePath,
      syncStatus: syncStatus ?? this.syncStatus,
      retryCount: retryCount ?? this.retryCount,
      createdAt: createdAt,
    );
  }
}
