import 'dart:async';
import 'package:uuid/uuid.dart';
import '../models/attendance_record.dart';
import '../../../../core/database/local_db_helper.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

class AttendanceRepository {
  final LocalDbHelper _dbHelper = LocalDbHelper.instance;
  final _uuid = const Uuid();

  Future<dynamic> getDb() async => await _dbHelper.database;

  // Stream controller for real-time UI updates
  final _attendanceStreamController =
      StreamController<List<AttendanceRecord>>.broadcast();
  Stream<List<AttendanceRecord>> get attendanceStream =>
      _attendanceStreamController.stream;

  Future<AttendanceRecord> markAttendance({
    required String salesmanId,
    required String type,
    required String latitude,
    required String longitude,
    String? imagePath,
    DateTime? timestamp,
  }) async {
    final record = AttendanceRecord(
      uid: _uuid.v4(),
      salesmanId: salesmanId,
      type: type,
      timestamp: (timestamp ?? DateTime.now()).toIso8601String(),
      latitude: latitude,
      longitude: longitude,
      imagePath: imagePath,
      syncStatus: SyncStatus.pending,
    );

    // 1. Save locally immediately
    final db = await _dbHelper.database;
    final id = await db.insert('pending_attendance', record.toMap());

    final savedRecord = record.copyWith(localId: id);

    // 2. Refresh stream for UI
    await refreshAttendanceList(salesmanId);

    // 3. Notify Background Service to restart aggressive retry timer
    try {
      FlutterBackgroundService().invoke('force_sync');
    } catch (e) {
      // Ignore errors if service is not running
    }

    return savedRecord;
  }

  Future<void> refreshAttendanceList(String salesmanId) async {
    final pending = await _dbHelper.getPendingAttendance(salesmanId);
    final records = pending.map((m) => AttendanceRecord.fromMap(m)).toList();
    _attendanceStreamController.add(records);
  }

  Future<List<AttendanceRecord>> getAllPendingRecords(String salesmanId) async {
    final pending = await _dbHelper.getPendingAttendance(salesmanId);
    return pending.map((m) => AttendanceRecord.fromMap(m)).toList();
  }

  Future<void> updateSyncStatus(int localId, SyncStatus status,
      {int? retryCount}) async {
    final db = await _dbHelper.database;
    await db.update(
      'pending_attendance',
      {
        'status': status.name,
        if (retryCount != null) 'retry_count': retryCount,
      },
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> removeRecord(int localId, {String? salesmanId}) async {
    await _dbHelper.deletePendingAttendance(localId);
    if (salesmanId != null) {
      await refreshAttendanceList(salesmanId);
    }
  }
}
