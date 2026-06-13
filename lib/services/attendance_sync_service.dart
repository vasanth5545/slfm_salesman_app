import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../presentation/attendance_screen/models/attendance_record.dart';
import '../presentation/attendance_screen/repositories/attendance_repository.dart';
import '../core/constants/api_urls.dart';
import '../core/services/secure_http_client.dart' as http;

class AttendanceSyncService {
  final AttendanceRepository _repository;
  bool _isSyncing = false;

  AttendanceSyncService(this._repository) {
    // 🔥 FIX 1: User Requested STRICT MANUAL RETRY ONLY.
    // Removed auto-sync on startup and network connection.
    // Attendance will ONLY sync when the user manually taps the "Retry" button.
  }

  Future<void> syncPendingRecords() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final db = await _repository.getDb();
      final List<Map<String, dynamic>> pending =
          await db.query('pending_attendance', orderBy: 'capture_time ASC');

      if (pending.isEmpty) {
        _isSyncing = false;
        return;
      }

      debugPrint("🔄 Syncing ${pending.length} pending attendance records...");

      for (var map in pending) {
        final record = AttendanceRecord.fromMap(map);

        if (!record.isSameDay) {
          debugPrint(
              "⏭️ Skipping ${record.uid}: Created on ${record.createdAt.toIso8601String()} (not today)");
          continue;
        }

        try {
          final now = DateTime.now();
          final recordTime = DateTime.parse(record.timestamp);
          if (now.difference(recordTime).inMinutes >= 5) {
            debugPrint(
                "⏭️ FG Auto-Sync: Record ${record.uid} is older than 5 mins. Stopping auto-retry.");
            await _repository.updateSyncStatus(
                record.localId!, SyncStatus.retryNeeded,
                retryCount: record.retryCount);
            continue;
          }
        } catch (e) {
          debugPrint(
              "⚠️ FG Auto-Sync: Could not parse record timestamp ${record.timestamp}: $e");
        }

        await uploadRecord(record);
      }
    } catch (e) {
      debugPrint("❌ AttendanceSyncService Error: $e");
    } finally {
      _isSyncing = false;
    }
  }

  Future<Map<String, dynamic>> uploadRecord(AttendanceRecord record) async {
    try {
      final url = Uri.parse(ApiUrl.attendance);

      // Read image bytes if available
      String base64Image = "";
      if (record.imagePath != null && record.imagePath!.isNotEmpty) {
        final file = File(record.imagePath!);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          base64Image = base64Encode(bytes);
        }
      }

      final payload = {
        'attendance_uid': record.uid,
        'action': record.type,
        'salesman_id': record.salesmanId,
        'lat': record.latitude,
        'lng': record.longitude,
        'capture_time': record.timestamp,
        'image_base64': base64Image,
        'selfie_url': base64Image,
      };

      debugPrint(
          "🚀 Attempting to sync record: ${record.uid} (Type: ${record.type})");

      final response = await http.postWithRetry(
        url,
        body: jsonEncode(payload),
        headers: {'Content-Type': 'application/json'},
      );

      debugPrint(
          "📡 Server Response (${response.statusCode}) for ${record.uid}: ${response.body}");

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        bool isSuccess = result['status'] == 'success';

        // 🔥 User requested strict pass-through of API response.
        // success => success
        // failed => failed
        // DO NOT automatically assume duplicate means success.

        if (isSuccess) {
          if (record.localId != null) {
            await _repository.removeRecord(record.localId!,
                salesmanId: record.salesmanId);
          }
          debugPrint(
              "✅ Attendance record ${record.uid} synced and deleted locally.");

          return {'success': true, 'data': result, 'isDuplicate': false};
        } else {
          // It's an error, duplicate, or anything else.
          debugPrint(
              "⚠️ Server returned failure/duplicate for ${record.uid}: ${result['message']}");
          
          await _repository.updateSyncStatus(record.localId!, SyncStatus.failed,
              retryCount: record.retryCount + 1);

          bool isDuplicate = result['status'] == 'duplicate' ||
              (result['status'] == 'error' &&
                  result['message']
                      .toString()
                      .toLowerCase()
                      .contains('already')) ||
              (result['status'] == 'error' &&
                  result['message']
                      .toString()
                      .contains('ஏற்கனவே பதிவு செய்துவிட்டீர்கள்'));

          return {
            'success': false,
            'message': result['message'] ?? 'சர்வர் பிழை',
            'isDuplicate': isDuplicate
          };
        }
      }

      await _repository.updateSyncStatus(record.localId!, SyncStatus.failed,
          retryCount: record.retryCount + 1);
      return {'success': false, 'message': 'HTTP ${response.statusCode}'};
    } catch (e) {
      debugPrint("❌ Sync failed for record ${record.uid}: $e");
      await _repository.updateSyncStatus(record.localId!, SyncStatus.failed,
          retryCount: record.retryCount + 1);
      return {'success': false, 'message': e.toString()};
    }
  }

  void dispose() {
    // No resources to dispose.
  }
}
