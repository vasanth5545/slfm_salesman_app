import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';

class LocalDbHelper {
  static final LocalDbHelper instance = LocalDbHelper._init();
  static Database? _database;

  LocalDbHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('app_local.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    debugPrint("🗄️ SQLite: Initializing database at $path");

    final db = await openDatabase(
      path,
      version: 24,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );

    // Hardening: Ensure all required columns exist in attendance_history
    await _ensureAttendanceHistoryColumnsExist(db);
    await _ensureUniqueIdColumnExists(db);

    return db;
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute('ALTER TABLE local_messages ADD COLUMN payload TEXT');
      } catch (e) {
        debugPrint('Migration error (v2): $e');
      }
    }
    if (oldVersion < 4) {
      await db.execute('DROP TABLE IF EXISTS pending_attendance');
      await _createPendingAttendanceTable(db);
    }
    if (oldVersion < 5) {
      await _createAttendanceHistoryTable(db);
      await _createLeaveHistoryTable(db);
    }
    if (oldVersion < 11) {
      try {
        await db.execute(
            'ALTER TABLE attendance_history ADD COLUMN salesman_id TEXT');
        await db
            .execute('ALTER TABLE local_messages ADD COLUMN salesman_id TEXT');
        await db
            .execute('ALTER TABLE leave_history ADD COLUMN salesman_id TEXT');
        await db.execute(
            'ALTER TABLE pending_attendance ADD COLUMN salesman_id TEXT');
      } catch (e) {
        debugPrint("DB Upgrade Error (v11): $e");
      }
    }
    if (oldVersion < 12) {
      try {
        await db.execute('DROP TABLE IF EXISTS attendance_history');
        await _createAttendanceHistoryTable(db);
      } catch (e) {
        debugPrint("DB Upgrade Error (v12): $e");
      }
    }
    if (oldVersion < 13) {
      try {
        await _createPerformanceSummaryTable(db);
      } catch (e) {
        debugPrint("DB Upgrade Error (v13): $e");
      }
    }
    if (oldVersion < 14) {
      try {
        await db.execute('DROP TABLE IF EXISTS leave_history');
        await _createLeaveHistoryTable(db);
        await _createSyncMetadataTable(db);
      } catch (e) {
        debugPrint("DB Upgrade Error (v14): $e");
      }
    }
    if (oldVersion < 15) {
      try {
        await db
            .execute('ALTER TABLE local_messages ADD COLUMN salesman_id TEXT');
      } catch (e) {
        debugPrint(
            "DB Upgrade Error (v15 - local_messages already has column): $e");
      }
    }
    if (oldVersion < 16) {
      try {
        await db.execute(
            'ALTER TABLE attendance_history ADD COLUMN break_out_time TEXT');
        await db.execute(
            'ALTER TABLE attendance_history ADD COLUMN break_out_selfie_url TEXT');
        await db.execute(
            'ALTER TABLE attendance_history ADD COLUMN reentry_time TEXT');
        await db.execute(
            'ALTER TABLE attendance_history ADD COLUMN reentry_selfie_url TEXT');
      } catch (e) {
        debugPrint("DB Upgrade Error (v16): $e");
      }
    }
    if (oldVersion < 17) {
      try {
        await _createWalkingCustomersTable(db);
      } catch (e) {
        debugPrint("DB Upgrade Error (v17): $e");
      }
    }
    if (oldVersion < 18) {
      try {
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_msg_timestamp ON local_messages(timestamp)');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_msg_user ON local_messages(salesman_id)');
      } catch (e) {
        debugPrint("DB Upgrade Error (v18): $e");
      }
    }
    if (oldVersion < 19) {
      await _ensureUniqueIdColumnExists(db);
    }
    if (oldVersion < 20) {
      try {
        await db.execute(
            'ALTER TABLE pending_attendance ADD COLUMN retry_count INTEGER DEFAULT 0');
      } catch (e) {
        debugPrint("DB Upgrade Error (v20): $e");
      }
    }
    if (oldVersion < 21) {
      try {
        await db.execute(
            'ALTER TABLE pending_attendance ADD COLUMN created_at INTEGER');
        // Backfill existing records with current time
        await db.execute(
            'UPDATE pending_attendance SET created_at = ${DateTime.now().millisecondsSinceEpoch} WHERE created_at IS NULL');
      } catch (e) {
        debugPrint("DB Upgrade Error (v21): $e");
      }
    }
    if (oldVersion < 22) {
      try {
        await db.execute(
            'ALTER TABLE attendance_history ADD COLUMN selfie_url TEXT');
        await db.execute(
            'ALTER TABLE attendance_history ADD COLUMN out_selfie_url TEXT');
        await db
            .execute('ALTER TABLE attendance_history ADD COLUMN status TEXT');
        debugPrint(
            "✅ SQLite: Upgraded attendance_history with photo/status columns (v22)");
      } catch (e) {
        debugPrint("DB Upgrade Error (v22): $e");
      }
    }
    if (oldVersion < 23) {
      try {
        await _createOfflineLocationHistoryTable(db);
        debugPrint(
            "✅ SQLite: Upgraded database with offline_location_history (v23)");
      } catch (e) {
        debugPrint("DB Upgrade Error (v23): $e");
      }
    }
    if (oldVersion < 24) {
      try {
        await _createActivityLogsTable(db);
        debugPrint("✅ SQLite: Upgraded database with activity_logs (v24)");
      } catch (e) {
        debugPrint("DB Upgrade Error (v24): $e");
      }
    }
    debugPrint("✅ SQLite: Upgraded database from $oldVersion to $newVersion");
  }

  /// Ensures the unique_id column exists in local_messages table.
  /// This is idempotent and can be called safely multiple times.
  Future<void> _ensureAttendanceHistoryColumnsExist(Database db) async {
    final columns = [
      'selfie_url',
      'out_selfie_url',
      'status',
      'clock_in_time',
      'clock_out_time',
      'break_out_time',
      'reentry_time'
    ];

    try {
      final List<Map<String, dynamic>> existingColumns =
          await db.rawQuery('PRAGMA table_info(attendance_history)');
      final existingNames =
          existingColumns.map((c) => c['name'].toString()).toSet();

      for (var col in columns) {
        if (!existingNames.contains(col)) {
          await db
              .execute('ALTER TABLE attendance_history ADD COLUMN $col TEXT');
          debugPrint(
              "🛠️ SQLite Hardening: Added missing column $col to attendance_history");
        }
      }
    } catch (e) {
      debugPrint("❌ SQLite Hardening Error (attendance_history): $e");
    }
  }

  Future<void> _ensureUniqueIdColumnExists(Database db) async {
    try {
      final List<Map<String, dynamic>> columns =
          await db.rawQuery('PRAGMA table_info(local_messages)');
      final hasColumn = columns.any((column) => column['name'] == 'unique_id');

      if (!hasColumn) {
        debugPrint(
            "🛠️ SQLite: Adding missing 'unique_id' column to local_messages");
        await db
            .execute('ALTER TABLE local_messages ADD COLUMN unique_id TEXT');
      }

      // Also ensure the unique index exists
      await db.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_msg_unique_id ON local_messages(salesman_id, unique_id)');
      debugPrint("✅ SQLite: 'unique_id' column and index verified.");
    } catch (e) {
      debugPrint("❌ SQLite: Error in _ensureUniqueIdColumnExists: $e");
      // If there's a unique constraint violation (existing duplicates),
      // we might need to handle it, but for now we log it.
    }
  }

  Future _createAttendanceHistoryTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS attendance_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        salesman_id TEXT,
        date TEXT,
        clock_in TEXT,
        clock_out TEXT,
        break_out_time TEXT,
        break_out_selfie_url TEXT,
        reentry_time TEXT,
        reentry_selfie_url TEXT,
        thumbnail TEXT,
        selfie_url TEXT,
        out_selfie_url TEXT,
        status TEXT,
        server_data TEXT,
        UNIQUE(salesman_id, date)
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_att_date ON attendance_history(salesman_id, date DESC)');
  }

  Future _createLeaveHistoryTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS leave_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        salesman_id TEXT,
        doc_id TEXT,
        leave_date TEXT,
        leave_type TEXT,
        reason TEXT,
        status TEXT,
        server_data TEXT,
        UNIQUE(salesman_id, doc_id)
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_leave_user ON leave_history(salesman_id)');
  }

  Future _createPerformanceSummaryTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS performance_summary (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        salesman_id TEXT UNIQUE,
        server_data TEXT
      )
    ''');
  }

  Future _createSyncMetadataTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_metadata (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  Future _createPendingAttendanceTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_attendance (
        local_id INTEGER PRIMARY KEY AUTOINCREMENT,
        attendance_uid TEXT,
        action TEXT,
        salesman_id TEXT,
        latitude TEXT,
        longitude TEXT,
        capture_time TEXT,
        image_path TEXT,
        status TEXT,
        created_at INTEGER DEFAULT 0,
        retry_count INTEGER DEFAULT 0
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_pending_user ON pending_attendance(salesman_id)');
  }

  Future _createOfflineLocationHistoryTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS offline_location_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        salesman_id TEXT,
        latitude REAL,
        longitude REAL,
        timestamp INTEGER,
        status TEXT
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_offline_loc_user ON offline_location_history(salesman_id)');
  }

  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textNullableType = 'TEXT';
    const intNullableType = 'INTEGER';

    await _createPendingAttendanceTable(db);

    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_messages (
        local_id $idType,
        salesman_id $textNullableType,
        server_id $intNullableType,
        message_text $textNullableType,
        message_type $textNullableType,
        payload $textNullableType,
        status $textNullableType,
        timestamp $textNullableType,
        unique_id $textNullableType
      )
    ''');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_msg_unique_id ON local_messages(salesman_id, unique_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_msg_user ON local_messages(salesman_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_msg_timestamp ON local_messages(timestamp)');

    await _createAttendanceHistoryTable(db);
    await _createLeaveHistoryTable(db);
    await _createPerformanceSummaryTable(db);
    await _createSyncMetadataTable(db);
    await _createWalkingCustomersTable(db);
    await _createOfflineLocationHistoryTable(db);
    await _createActivityLogsTable(db);
  }

  // --- Offline Location History ---

  Future<int> insertOfflineLocation(String salesmanId, double lat, double lng,
      int timestamp, String status) async {
    final db = await instance.database;
    return await db.insert('offline_location_history', {
      'salesman_id': salesmanId,
      'latitude': lat,
      'longitude': lng,
      'timestamp': timestamp,
      'status': status,
    });
  }

  Future<List<Map<String, dynamic>>> getPendingLocations(
      String salesmanId) async {
    final db = await instance.database;
    return await db.query(
      'offline_location_history',
      where: 'salesman_id = ?',
      whereArgs: [salesmanId],
      orderBy: 'timestamp ASC',
    );
  }

  Future<int> deletePendingLocations(List<int> ids) async {
    if (ids.isEmpty) return 0;
    final db = await instance.database;
    final placeholders = List.filled(ids.length, '?').join(',');
    return await db.delete(
      'offline_location_history',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  // --------------------------------

  Future<void> syncLeaveHistory(
      String salesmanId, List<Map<String, dynamic>> records) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      for (final record in records) {
        await txn.insert(
          'leave_history',
          {
            'salesman_id': salesmanId,
            'doc_id': record['id'],
            'leave_date': record['leave_date'],
            'leave_type': record['leave_type'],
            'reason': record['reason'],
            'status': record['status'],
            'server_data': jsonEncode(record),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// Reconciles local leave history with server state by deleting records that no longer exist on server.
  /// Also cleans up related local_messages using BOTH payload JSON matching AND unique_id pattern matching.
  Future<int> reconcileLeaveHistory(
      String salesmanId, List<String> serverDocIds) async {
    final db = await instance.database;
    int deletedCount = 0;

    await db.transaction((txn) async {
      // 1. Fetch all local doc_ids for this salesman
      final localRecords = await txn.query(
        'leave_history',
        columns: ['doc_id', 'leave_date', 'leave_type'],
        where: 'salesman_id = ?',
        whereArgs: [salesmanId],
      );

      final localDocIds =
          localRecords.map((e) => e['doc_id'].toString()).toList();

      // 2. Identify IDs to delete
      final idsToDelete =
          localDocIds.where((id) => !serverDocIds.contains(id)).toList();

      if (idsToDelete.isNotEmpty) {
        for (final docId in idsToDelete) {
          // Find the leave_date and leave_type for unique_id matching
          final matchingRecord = localRecords.firstWhere(
            (r) => r['doc_id'].toString() == docId,
            orElse: () => <String, Object?>{},
          );

          // Delete from leave_history
          await txn.delete(
            'leave_history',
            where: 'salesman_id = ? AND doc_id = ?',
            whereArgs: [salesmanId, docId],
          );

          // Strategy 1: Delete by payload JSON match (catches MySQL ID format)
          final msgsByPayload = await txn.query(
            'local_messages',
            where: 'salesman_id = ? AND payload LIKE ?',
            whereArgs: [salesmanId, '%"doc_id":"$docId"%'],
          );
          for (final msg in msgsByPayload) {
            await txn.delete(
              'local_messages',
              where: 'local_id = ?',
              whereArgs: [msg['local_id']],
            );
          }

          // Strategy 2: Delete by unique_id pattern (catches string doc_id format)
          if (matchingRecord.isNotEmpty) {
            final leaveDate = matchingRecord['leave_date']?.toString() ?? '';
            final leaveType = matchingRecord['leave_type']?.toString() ?? '';
            if (leaveDate.isNotEmpty && leaveType.isNotEmpty) {
              final uniqueIdPattern =
                  'leave_req_${salesmanId}_${leaveDate}_${leaveType.replaceAll(' ', '')}';
              await txn.delete(
                'local_messages',
                where: 'salesman_id = ? AND unique_id = ?',
                whereArgs: [salesmanId, uniqueIdPattern],
              );
            }
          }

          deletedCount++;
        }
      }
    });

    if (deletedCount > 0) {
      debugPrint(
          "🧹 SQLite: Reconciled leave history. Deleted $deletedCount stale records + messages.");
    }
    return deletedCount;
  }

  /// Reconciles orphaned leave messages in local_messages that have no matching leave_history record.
  /// This catches edge cases where leave_history was cleared but messages survived.
  Future<int> reconcileLeaveMessages(
      String salesmanId, List<String> serverDocIds) async {
    final db = await instance.database;
    int cleanedCount = 0;

    // Find all leave_request messages for this salesman
    final leaveMessages = await db.query(
      'local_messages',
      where: "salesman_id = ? AND message_type = 'leave_request'",
      whereArgs: [salesmanId],
    );

    for (final msg in leaveMessages) {
      final payloadStr = msg['payload']?.toString();
      if (payloadStr == null || payloadStr.isEmpty) continue;

      try {
        final payload = jsonDecode(payloadStr);
        final msgDocId = payload['doc_id']?.toString() ?? '';
        if (msgDocId.isEmpty) continue;

        // Check if this doc_id still exists on server
        if (!serverDocIds.contains(msgDocId)) {
          await db.delete(
            'local_messages',
            where: 'local_id = ?',
            whereArgs: [msg['local_id']],
          );
          cleanedCount++;
        }
      } catch (_) {}
    }

    if (cleanedCount > 0) {
      debugPrint("🧹 SQLite: Cleaned $cleanedCount orphaned leave messages.");
    }
    return cleanedCount;
  }

  Future<void> clearAndInsertLeaveHistory(
      String salesmanId, List<Map<String, dynamic>> records) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.delete('leave_history',
          where: 'salesman_id = ?', whereArgs: [salesmanId]);
      for (final record in records) {
        await txn.insert('leave_history', {
          'salesman_id': salesmanId,
          'doc_id': record['id'],
          'leave_date': record['leave_date'],
          'leave_type': record['leave_type'],
          'reason': record['reason'],
          'status': record['status'],
          'server_data': jsonEncode(record),
        });
      }
    });
  }

  Future<List<Map<String, dynamic>>> getLeaveHistory(String salesmanId) async {
    final db = await instance.database;
    // 🔥 FIX: Only return current month + previous month (performance optimization)
    final now = DateTime.now();
    final firstDayPrevMonth = DateTime(now.year, now.month - 1, 1);
    final cutoffDate =
        '${firstDayPrevMonth.year}-${firstDayPrevMonth.month.toString().padLeft(2, '0')}-01';

    final res = await db.query(
      'leave_history',
      where: 'salesman_id = ? AND leave_date >= ?',
      whereArgs: [salesmanId, cutoffDate],
      orderBy: 'leave_date DESC',
    );
    return res
        .map((e) =>
            jsonDecode(e['server_data'].toString()) as Map<String, dynamic>)
        .toList();
  }

  Future<int> getLeaveRecordCount(String salesmanId) async {
    final db = await instance.database;
    final res = await db.rawQuery(
        'SELECT COUNT(*) as count FROM leave_history WHERE salesman_id = ?',
        [salesmanId]);
    return Sqflite.firstIntValue(res) ?? 0;
  }

  /// Purges leave records older than 2 months from leave_history and related local_messages.
  /// This keeps the local DB lean and consistent with the API's 2-month window.
  Future<int> purgeOldLeaveData(String salesmanId) async {
    final db = await instance.database;
    final now = DateTime.now();
    final firstDayPrevMonth = DateTime(now.year, now.month - 1, 1);
    final cutoffDate =
        '${firstDayPrevMonth.year}-${firstDayPrevMonth.month.toString().padLeft(2, '0')}-01';

    int totalPurged = 0;

    // 1. Find old leave records to purge
    final oldRecords = await db.query(
      'leave_history',
      columns: ['doc_id', 'leave_date', 'leave_type'],
      where: 'salesman_id = ? AND leave_date < ?',
      whereArgs: [salesmanId, cutoffDate],
    );

    if (oldRecords.isEmpty) return 0;

    await db.transaction((txn) async {
      for (final record in oldRecords) {
        final docId = record['doc_id']?.toString() ?? '';
        final leaveDate = record['leave_date']?.toString() ?? '';
        final leaveType = record['leave_type']?.toString() ?? '';

        // Delete from leave_history
        await txn.delete(
          'leave_history',
          where: 'salesman_id = ? AND doc_id = ?',
          whereArgs: [salesmanId, docId],
        );

        // Delete corresponding local_messages (by payload match)
        await txn.delete(
          'local_messages',
          where: 'salesman_id = ? AND payload LIKE ?',
          whereArgs: [salesmanId, '%"doc_id":"$docId"%'],
        );

        // Also try unique_id match
        if (leaveDate.isNotEmpty && leaveType.isNotEmpty) {
          final uniqueIdPattern =
              'leave_req_${salesmanId}_${leaveDate}_${leaveType.replaceAll(' ', '')}';
          await txn.delete(
            'local_messages',
            where: 'salesman_id = ? AND unique_id = ?',
            whereArgs: [salesmanId, uniqueIdPattern],
          );
        }

        totalPurged++;
      }
    });

    if (totalPurged > 0) {
      debugPrint(
          "🧹 SQLite: Purged $totalPurged old leave records (before $cutoffDate)");
    }
    return totalPurged;
  }

  Future<int> deleteLeaveMessageByDocId(String salesmanId, String docId) async {
    final db = await instance.database;
    final allMessages = await db.query(
      'local_messages',
      where: 'salesman_id = ?',
      whereArgs: [salesmanId],
    );

    int deletedCount = 0;
    for (var msg in allMessages) {
      final payloadStr = msg['payload']?.toString();
      if (payloadStr != null && payloadStr.isNotEmpty) {
        try {
          final payload = jsonDecode(payloadStr);
          if (payload['doc_id'] == docId) {
            await db.delete(
              'local_messages',
              where: 'local_id = ?',
              whereArgs: [msg['local_id']],
            );
            deletedCount++;
          }
        } catch (e) {
          debugPrint('Error decoding JSON payload: $e');
        }
      }
    }
    return deletedCount;
  }

  Future<int> deleteLeaveHistoryByDocId(String salesmanId, String docId) async {
    final db = await instance.database;
    return await db.delete(
      'leave_history',
      where: 'salesman_id = ? AND doc_id = ?',
      whereArgs: [salesmanId, docId],
    );
  }

  // 🔥 FIX: Added leaveType parameter to perfectly format Full Day / Half Day
  Future<int> updateLeaveMessageStatusByDocId(
      String salesmanId, String docId, String newStatus, String leaveType,
      {String? newTimestamp}) async {
    final db = await instance.database;
    final allMessages = await db.query(
      'local_messages',
      where: 'salesman_id = ?',
      whereArgs: [salesmanId],
    );

    int updatedCount = 0;
    for (var msg in allMessages) {
      final payloadStr = msg['payload']?.toString();
      if (payloadStr != null && payloadStr.isNotEmpty) {
        try {
          final payload = Map<String, dynamic>.from(jsonDecode(payloadStr));
          if (payload['doc_id'] == docId) {
            payload['status'] = newStatus;

            String newText = msg['message_text'].toString();
            if (msg['message_type'] == 'system') {
              // Ensure we use the exact leave type passed from the listener
              String typeStr = payload['leave_type'] ?? leaveType;
              if (newStatus.toLowerCase() == 'approved') {
                newText =
                    "விடுமுறை விண்ணப்பம் ($typeStr) அங்கீகரிக்கப்பட்டது ✅.";
              } else if (newStatus.toLowerCase() == 'rejected') {
                newText =
                    "விடுமுறை விண்ணப்பம் ($typeStr) நிராகரிக்கப்பட்டது ❌.";
              } else {
                newText = "விடுமுறை விண்ணப்பம் ($typeStr) காத்திருக்கிறது ⏳.";
              }
            }

            Map<String, dynamic> updateData = {
              'payload': jsonEncode(payload),
              'status': newStatus.toLowerCase(),
              'message_text': newText,
            };
            if (newTimestamp != null) {
              updateData['timestamp'] = newTimestamp;
            }

            await db.update(
              'local_messages',
              updateData,
              where: 'local_id = ?',
              whereArgs: [msg['local_id']],
            );
            updatedCount++;
          }
        } catch (e) {
          debugPrint('Error updating JSON payload: $e');
        }
      }
    }
    return updatedCount;
  }

  Future<int> updateLeaveHistoryStatusByDocId(
      String salesmanId, String docId, String newStatus) async {
    final db = await instance.database;
    return await db.update(
      'leave_history',
      {'status': newStatus},
      where: 'salesman_id = ? AND doc_id = ?',
      whereArgs: [salesmanId, docId],
    );
  }

  Future<int> insertMessage(String salesmanId, Map<String, dynamic> row) async {
    try {
      final db = await instance.database;
      final data = Map<String, dynamic>.from(row);
      data['salesman_id'] = salesmanId;
      return await db.insert('local_messages', data,
          conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      debugPrint("❌ SQLite: Error in insertMessage: $e");
      // If we failed due to a missing column, try to fix it once in the background
      if (e.toString().contains('no such column: unique_id')) {
        final db = await instance.database;
        await _ensureUniqueIdColumnExists(db);
      }
      return -1;
    }
  }

  Future<List<Map<String, dynamic>>> getMessages(String salesmanId) async {
    final db = await instance.database;
    return await db.query(
      'local_messages',
      where: 'salesman_id = ?',
      whereArgs: [salesmanId],
      orderBy: 'timestamp ASC',
    );
  }

  Future<int> updateMessageStatus(
      int localId, int serverId, String status) async {
    final db = await instance.database;
    return await db.update(
      'local_messages',
      {'server_id': serverId, 'status': status},
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<int> updateMessageStatusByUniqueId(
      String salesmanId, String uniqueId, String status,
      {String? newText}) async {
    final db = await instance.database;
    final Map<String, dynamic> updateData = {'status': status};
    if (newText != null) {
      updateData['message_text'] = newText;
    }
    return await db.update(
      'local_messages',
      updateData,
      where: 'salesman_id = ? AND unique_id = ?',
      whereArgs: [salesmanId, uniqueId],
    );
  }

  Future<int> updateMessageSent(int localId, int serverId) async {
    return await updateMessageStatus(localId, serverId, 'sent');
  }

  Future<int> deleteMessagesByPrefix(String salesmanId, String prefix) async {
    final db = await instance.database;
    return await db.delete(
      'local_messages',
      where: 'salesman_id = ? AND unique_id LIKE ?',
      whereArgs: [salesmanId, '$prefix%'],
    );
  }

  Future<int> insertPendingAttendance(
      String salesmanId, Map<String, dynamic> row) async {
    final db = await instance.database;
    final data = Map<String, dynamic>.from(row);
    data['salesman_id'] = salesmanId;
    return await db.insert('pending_attendance', data);
  }

  Future<List<Map<String, dynamic>>> getPendingAttendance(
      String salesmanId) async {
    final db = await instance.database;
    return await db.query(
      'pending_attendance',
      where: 'salesman_id = ?',
      whereArgs: [salesmanId],
    );
  }

  Future<int> deletePendingAttendance(int id) async {
    final db = await instance.database;
    return await db.delete(
      'pending_attendance',
      where: 'local_id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updatePendingAttendanceStatus(int id, String status) async {
    final db = await instance.database;
    return await db.update(
      'pending_attendance',
      {'status': status},
      where: 'local_id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deletePendingAttendanceByType(
      String salesmanId, String action) async {
    final db = await instance.database;
    return await db.delete(
      'pending_attendance',
      where: 'salesman_id = ? AND action = ?',
      whereArgs: [salesmanId, action],
    );
  }

  Future<int> deletePendingAttendanceByReentry(String salesmanId) async {
    // Reentry records are stored as 'clock_in' with capture_time significantly after todayClockIn
    // For safety, we can delete all 'clock_in' that are not the primary clock_in,
    // but the easiest is to just delete pending clock_in and let the primary one (which is synced) be untouched,
    // actually, if the primary is synced, it's not pending. If there's any pending 'clock_in', it's the reentry.
    // So if the server says reentry is deleted, we can safely delete any pending clock_in if clockIn is already synced.
    // We will just expose deletePendingAttendanceByType and handle the logic in attendance_screen.
    return 0; // handled above
  }

  Future<void> syncAttendanceHistory(
    String salesmanId,
    List<Map<String, dynamic>> records, {
    int maxRecords = 30,
  }) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      final List<String> serverDates = [];

      for (final record in records) {
        final normalizedDate = _normalizeDate(record['date']);
        if (normalizedDate.isNotEmpty) {
          serverDates.add(normalizedDate);
        }

        await txn.insert(
          'attendance_history',
          {
            'salesman_id': salesmanId,
            'date': normalizedDate,
            'clock_in': record['clock_in_time'] ??
                record['clock_in'] ??
                record['clockIn'] ??
                '',
            'clock_out': record['clock_out_time'] ??
                record['clock_out'] ??
                record['clockOut'] ??
                '',
            'status': record['status'] ?? '',
            'break_out_time': record['break_out_time'] ?? '',
            'break_out_selfie_url': record['break_out_selfie_url'] ?? '',
            'reentry_time':
                record['reentry_time'] ?? record['reEntryTime'] ?? '',
            'reentry_selfie_url': record['reentry_selfie_url'] ?? '',
            'thumbnail': record['thumbnail'] ?? '',
            'server_data': jsonEncode(record),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // 1. Reconcile within the range of fetched records (handles deletions)
      if (serverDates.isNotEmpty) {
        serverDates.sort();
        final minDate = serverDates.first;
        // Extend maxDate to Today to catch recent server-side deletions
        final maxDate = DateTime.now().toIso8601String().substring(0, 10);
        final placeholders = List.filled(serverDates.length, '?').join(',');

        // 🔥 RECONCILIATION: Delete records that are NOT in the server's list,
        // BUT ONLY if they are NOT in the pending_attendance table (protecting offline data).
        final deletedCount = await txn.delete(
          'attendance_history',
          where: '''
            salesman_id = ? 
            AND date >= ? 
            AND date <= ? 
            AND date NOT IN ($placeholders)
            AND date NOT IN (
              SELECT substr(capture_time, 1, 10) 
              FROM pending_attendance 
              WHERE salesman_id = ?
            )
          ''',
          whereArgs: [salesmanId, minDate, maxDate, ...serverDates, salesmanId],
        );

        if (deletedCount > 0) {
          debugPrint(
              "🧹 SQLite: Reconciled attendance history. Deleted $deletedCount stale records between $minDate and $maxDate.");
        }
      } else {
        // 🔥 RECONCILIATION (Empty Case): If server returns ZERO records,
        // we should clear all history EXCEPT pending ones.
        final deletedCount = await txn.delete(
          'attendance_history',
          where: '''
            salesman_id = ? 
            AND date NOT IN (
              SELECT substr(capture_time, 1, 10) 
              FROM pending_attendance 
              WHERE salesman_id = ?
            )
          ''',
          whereArgs: [salesmanId, salesmanId],
        );
        if (deletedCount > 0) {
          debugPrint(
              "🧹 SQLite: Server returned no history. Cleared $deletedCount local records (Remote wipe detected).");
        }
      }

      // 2. Enforce global limit (preserving the most recent records)
      await txn.rawDelete('''
        DELETE FROM attendance_history
        WHERE salesman_id = ? AND date NOT IN (
          SELECT date FROM attendance_history
          WHERE salesman_id = ?
          ORDER BY date DESC
          LIMIT $maxRecords
        )
      ''', [salesmanId, salesmanId]);
    });
  }

  Future<void> clearAndInsertAttendanceHistory(
      String salesmanId, List<Map<String, dynamic>> records) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      // 🔥 SAFE CLEAR: Delete history EXCEPT dates that are currently pending upload
      await txn.delete('attendance_history', where: '''
            salesman_id = ? 
            AND date NOT IN (
              SELECT substr(capture_time, 1, 10) 
              FROM pending_attendance 
              WHERE salesman_id = ?
            )
          ''', whereArgs: [salesmanId, salesmanId]);
    });
    await syncAttendanceHistory(salesmanId, records,
        maxRecords: records.length > 30 ? records.length : 30);
  }

  Future<void> insertOlderAttendanceRecords(
      String salesmanId, List<Map<String, dynamic>> records) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      for (final record in records) {
        await txn.insert(
          'attendance_history',
          {
            'salesman_id': salesmanId,
            'date': _normalizeDate(record['date']),
            'clock_in': record['clock_in_time'] ??
                record['clock_in'] ??
                record['clockIn'] ??
                '',
            'clock_out': record['clock_out_time'] ??
                record['clock_out'] ??
                record['clockOut'] ??
                '',
            'status': record['status'] ?? '',
            'break_out_time': record['break_out_time'] ?? '',
            'break_out_selfie_url': record['break_out_selfie_url'] ?? '',
            'reentry_time':
                record['reentry_time'] ?? record['reEntryTime'] ?? '',
            'reentry_selfie_url': record['reentry_selfie_url'] ?? '',
            'thumbnail': record['thumbnail'] ?? '',
            'server_data': jsonEncode(record),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  Future<void> enforceMaxLimit(String salesmanId,
      {int maxRecords = 100}) async {
    final db = await instance.database;
    await db.rawDelete('''
      DELETE FROM attendance_history
      WHERE salesman_id = ? AND date NOT IN (
        SELECT date FROM attendance_history
        WHERE salesman_id = ?
        ORDER BY date DESC
        LIMIT $maxRecords
      )
    ''', [salesmanId, salesmanId]);
  }

  // 🔥 NEW: Save today's attendance to attendance_history immediately (same as past days)
  // This ensures today's data survives app restart and offline mode.
  Future<void> upsertTodayAttendance(
      String salesmanId, Map<String, dynamic> todayData) async {
    try {
      final db = await instance.database;
      final dateStr = todayData['date'];
      debugPrint(
          "💾 SQLite: Upserting Today Attendance for $salesmanId on $dateStr. Status: ${todayData['status']}");

      await db.insert(
        'attendance_history',
        {
          'salesman_id': salesmanId,
          'date': dateStr,
          'clock_in': todayData['clock_in'] ?? todayData['clock_in_time'] ?? '',
          'clock_out':
              todayData['clock_out'] ?? todayData['clock_out_time'] ?? '',
          'break_out_time': todayData['break_out_time'] ?? '',
          'break_out_selfie_url': todayData['break_out_selfie_url'] ?? '',
          'reentry_time': todayData['reentry_time'] ?? '',
          'reentry_selfie_url': todayData['reentry_selfie_url'] ?? '',
          'thumbnail': todayData['thumbnail'] ?? todayData['selfie_url'] ?? '',
          'selfie_url': todayData['selfie_url'] ??
              todayData['in_selfie_url'] ??
              todayData['clock_in_image'] ??
              '',
          'out_selfie_url': todayData['out_selfie_url'] ??
              todayData['clock_out_selfie_url'] ??
              todayData['final_out_selfie_url'] ??
              todayData['clock_out_image'] ??
              '',
          'status': todayData['status'] ?? '',
          'server_data': jsonEncode(todayData),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint("❌ SQLite Error in upsertTodayAttendance: $e");
    }
  }

  // 🔥 NEW: Prune a specific date from history (e.g., if server says Today is empty)
  // Protected against deleting pending records.
  Future<void> pruneAttendanceByDate(String salesmanId, String dateStr) async {
    try {
      final db = await instance.database;
      final deletedCount = await db.delete(
        'attendance_history',
        where: '''
          salesman_id = ? 
          AND date = ? 
          AND date NOT IN (
            SELECT substr(capture_time, 1, 10) 
            FROM pending_attendance 
            WHERE salesman_id = ?
          )
        ''',
        whereArgs: [salesmanId, dateStr, salesmanId],
      );
      if (deletedCount > 0) {
        debugPrint(
            "🧹 SQLite: Pruned stale history for $dateStr (Remote deletion detected).");
      }
    } catch (e) {
      debugPrint("❌ SQLite Error in pruneAttendanceByDate: $e");
    }
  }

  // ✨ Added normalization helper to ensure dates are always yyyy-MM-dd
  String _normalizeDate(dynamic rawDate) {
    if (rawDate == null) return '';
    String dateStr = rawDate.toString().trim();
    if (dateStr.contains('T')) {
      dateStr = dateStr.split('T')[0];
    } else if (dateStr.contains(' ')) {
      dateStr = dateStr.split(' ')[0];
    }
    // Handle "2026-04-04 to 00:00:00" artifact from legacy code
    if (dateStr.contains(' to ')) {
      dateStr = dateStr.split(' to ')[0].trim();
    }
    return dateStr;
  }

  // 🔥 CRITICAL: Clean up existing duplicate records with messy formats
  Future<void> normalizeAllDates() async {
    final db = await instance.database;
    await db.transaction((txn) async {
      // 1. Fetch all records to process in memory
      final records = await txn.query('attendance_history');
      for (var record in records) {
        String originalDate = record['date'].toString();
        String normalizedDate = _normalizeDate(originalDate);

        if (originalDate != normalizedDate) {
          // Check if normalized version exists
          final existing = await txn.query(
            'attendance_history',
            where: 'salesman_id = ? AND date = ?',
            whereArgs: [record['salesman_id'], normalizedDate],
          );

          if (existing.isNotEmpty) {
            // Duplicate exists - delete the messy one
            await txn.delete(
              'attendance_history',
              where: 'id = ?',
              whereArgs: [record['id']],
            );
          } else {
            // No duplicate, just update the date format
            await txn.update(
              'attendance_history',
              {'date': normalizedDate},
              where: 'id = ?',
              whereArgs: [record['id']],
            );
          }
        }
      }
    });
  }

  Future<List<Map<String, dynamic>>> getAttendanceHistory(
      String salesmanId) async {
    final db = await instance.database;
    final res = await db.query(
      'attendance_history',
      where: 'salesman_id = ?',
      whereArgs: [salesmanId],
      orderBy: 'date DESC',
    );
    return res
        .map((e) =>
            jsonDecode(e['server_data'].toString()) as Map<String, dynamic>)
        .toList();
  }

  // 🔥 FIX: 30-Day Data Retention Policy
  // This method purges records older than 30 days from attendance_history, leave_history, and local_messages.
  // Returns the total number of records deleted.
  Future<int> purgeOldRecords(String salesmanId) async {
    try {
      final db = await instance.database;
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
      // Format as yyyy-MM-dd for SQL comparison
      final dateBoundary =
          "${thirtyDaysAgo.year}-${thirtyDaysAgo.month.toString().padLeft(2, '0')}-${thirtyDaysAgo.day.toString().padLeft(2, '0')}";
      final isoBoundary = thirtyDaysAgo.toIso8601String();

      int count = 0;

      // 1. Purge attendance history (using 'date' column)
      count += await db.delete(
        'attendance_history',
        where: 'salesman_id = ? AND date < ?',
        whereArgs: [salesmanId, dateBoundary],
      );

      // 2. Purge leave history (using 'leave_date' column)
      count += await db.delete(
        'leave_history',
        where: 'salesman_id = ? AND leave_date < ?',
        whereArgs: [salesmanId, dateBoundary],
      );

      // 3. Purge local messages (chat history using 'timestamp' column)
      count += await db.delete(
        'local_messages',
        where: 'salesman_id = ? AND timestamp < ?',
        whereArgs: [salesmanId, isoBoundary],
      );

      if (count > 0) {
        debugPrint("🧹 SQLite: Purged $count records older than 30 days.");
      }
      return count;
    } catch (e) {
      debugPrint("❌ SQLite: Error purging old records: $e");
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> getAttendanceHistoryPage(
    String salesmanId, {
    int offset = 0,
    int limit = 10,
  }) async {
    final db = await instance.database;
    final res = await db.query(
      'attendance_history',
      where: 'salesman_id = ?',
      whereArgs: [salesmanId],
      orderBy: 'date DESC',
      limit: limit,
      offset: offset,
    );
    return res
        .map((e) =>
            jsonDecode(e['server_data'].toString()) as Map<String, dynamic>)
        .toList();
  }

  Future<int> getAttendanceHistoryCount(String salesmanId) async {
    final db = await instance.database;
    final count = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM attendance_history WHERE salesman_id = ?',
        [salesmanId]));
    return count ?? 0;
  }

  Future<String?> getLastSyncTimestamp(String key) async {
    final db = await instance.database;
    final res = await db.query(
      'sync_metadata',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
    );
    if (res.isNotEmpty) return res.first['value'] as String?;
    return null;
  }

  Future<void> setLastSyncTimestamp(String key, String? timestamp) async {
    final db = await instance.database;
    if (timestamp == null) {
      await db.delete('sync_metadata', where: 'key = ?', whereArgs: [key]);
    } else {
      await db.insert(
        'sync_metadata',
        {'key': key, 'value': timestamp},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<int> getAttendanceRecordCount(String salesmanId) async {
    final db = await instance.database;
    final res = await db.rawQuery(
        'SELECT COUNT(*) as count FROM attendance_history WHERE salesman_id = ?',
        [salesmanId]);
    return Sqflite.firstIntValue(res) ?? 0;
  }

  Future<int> insertPerformanceSummary(
      String salesmanId, Map<String, dynamic> data) async {
    final db = await instance.database;
    return await db.insert(
      'performance_summary',
      {
        'salesman_id': salesmanId,
        'server_data': jsonEncode(data),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getPerformanceSummary(String salesmanId) async {
    final db = await instance.database;
    final res = await db.query(
      'performance_summary',
      where: 'salesman_id = ?',
      whereArgs: [salesmanId],
    );
    if (res.isNotEmpty) {
      return jsonDecode(res.first['server_data'].toString())
          as Map<String, dynamic>;
    }
    return null;
  }

  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }

  // ========== WALKING CUSTOMERS LOCAL CACHE ==========

  Future _createWalkingCustomersTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS walking_customers (
        doc_id TEXT PRIMARY KEY,
        salesman_id TEXT,
        customer_name TEXT,
        phone TEXT,
        product_interest TEXT,
        status TEXT,
        bill_photo TEXT,
        created_at TEXT,
        billed_at TEXT,
        created_date_fmt TEXT,
        billed_date_fmt TEXT,
        feedback_text TEXT,
        feedback_by TEXT,
        feedback_date TEXT,
        server_data TEXT
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_walking_user ON walking_customers(salesman_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_walking_status ON walking_customers(salesman_id, status)');
  }

  /// Sync walking customers from server to local DB
  Future<void> syncWalkingCustomers(
      String salesmanId, List<Map<String, dynamic>> records) async {
    final db = await instance.database;
    debugPrint(
        "📥 Syncing ${records.length} walking customers to Local SQLite for $salesmanId...");

    // 🔥 Adding debug print to show data being saved
    for (var item in records) {
      debugPrint(
          "   ✅ Saving to DB: ${item['customer_name']} | Status: ${item['status']} | Billed: ${item['billed_date_fmt'] ?? 'Not Billed'}");
    }

    await db.transaction((txn) async {
      // Clear old data for this salesman
      await txn.delete('walking_customers',
          where: 'salesman_id = ?', whereArgs: [salesmanId]);
      // Insert fresh data
      for (final record in records) {
        await txn.insert(
            'walking_customers',
            {
              'doc_id': record['id'] ?? '',
              'salesman_id': record['salesman_id'] ?? salesmanId,
              'customer_name': record['customer_name'] ?? '',
              'phone': record['phone'] ?? '',
              'product_interest': record['product_interest'] ?? '',
              'status': record['status'] ?? 'Pending',
              'bill_photo': record['bill_photo'],
              'created_at': record['created_at'] ?? '',
              'billed_at': record['billed_at'],
              'created_date_fmt': record['created_date_fmt'] ?? '',
              'billed_date_fmt': record['billed_date_fmt'] ?? 'Not Billed',
              'feedback_text': record['feedback_text'],
              'feedback_by': record['feedback_by'],
              'feedback_date': record['feedback_date'],
              'server_data': jsonEncode(record),
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });

    debugPrint("✅ Local Sync Complete: Saved ${records.length} records logic!");
  }

  /// Get all walking customers for a salesman from local DB
  Future<List<Map<String, dynamic>>> getWalkingCustomers(
      String salesmanId) async {
    final db = await instance.database;
    final res = await db.query(
      'walking_customers',
      where: 'salesman_id = ?',
      whereArgs: [salesmanId],
      orderBy: 'created_at DESC',
    );
    return res.map((e) {
      if (e['server_data'] != null) {
        return jsonDecode(e['server_data'].toString()) as Map<String, dynamic>;
      }
      return Map<String, dynamic>.from(e);
    }).toList();
  }

  /// Get walking customer stats (pending/billed counts) from local DB
  Future<Map<String, int>> getWalkingStats(String salesmanId) async {
    final db = await instance.database;
    final pendingRes = await db.rawQuery(
        'SELECT COUNT(*) as count FROM walking_customers WHERE salesman_id = ? AND status = ?',
        [salesmanId, 'Pending']);
    final billedRes = await db.rawQuery(
        'SELECT COUNT(*) as count FROM walking_customers WHERE salesman_id = ? AND status = ?',
        [salesmanId, 'Billed']);
    return {
      'pending': Sqflite.firstIntValue(pendingRes) ?? 0,
      'billed': Sqflite.firstIntValue(billedRes) ?? 0,
    };
  }

  /// Update a single walking customer record locally (e.g., after bill upload)
  Future<void> updateWalkingCustomer(
      String docId, Map<String, dynamic> updates) async {
    final db = await instance.database;
    await db.update(
      'walking_customers',
      updates,
      where: 'doc_id = ?',
      whereArgs: [docId],
    );
  }

  /// Get walking customer record count
  Future<int> getWalkingCustomerCount(String salesmanId) async {
    final db = await instance.database;
    final res = await db.rawQuery(
        'SELECT COUNT(*) as count FROM walking_customers WHERE salesman_id = ?',
        [salesmanId]);
    return Sqflite.firstIntValue(res) ?? 0;
  }

  // ─── Activity Logs (Admin Audit Trail) ─────────────────────────

  Future _createActivityLogsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS activity_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER NOT NULL,
        category TEXT NOT NULL,
        action TEXT NOT NULL,
        details TEXT NOT NULL,
        network_type TEXT,
        salesman_id TEXT,
        extra TEXT
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_actlog_ts ON activity_logs(timestamp DESC)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_actlog_cat ON activity_logs(category)');
  }

  /// Insert a single activity log entry
  Future<int> insertActivityLog(Map<String, dynamic> log) async {
    final db = await instance.database;
    return await db.insert('activity_logs', log);
  }

  /// Get activity logs for the last N days, ordered by newest first
  Future<List<Map<String, dynamic>>> getActivityLogs(int days) async {
    final db = await instance.database;
    final cutoff =
        DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    return await db.query(
      'activity_logs',
      where: 'timestamp >= ?',
      whereArgs: [cutoff],
      orderBy: 'timestamp DESC',
    );
  }

  /// Purge activity logs older than N days. Returns count of deleted rows.
  Future<int> purgeOldActivityLogs(int days) async {
    final db = await instance.database;
    final cutoff =
        DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    return await db.delete(
      'activity_logs',
      where: 'timestamp < ?',
      whereArgs: [cutoff],
    );
  }
}
