import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../core/database/local_db_helper.dart';

/// Log categories for the admin audit trail
enum LogCategory {
  login,
  attendance,
  leave,
  lunch,
  network,
  error,
  navigation,
  system,
  sync,
}

/// A single activity log entry
class ActivityLog {
  final int? id;
  final DateTime timestamp;
  final LogCategory category;
  final String action;
  final String details;
  final String? networkType;
  final String? salesmanId;
  final String? extra;

  ActivityLog({
    this.id,
    required this.timestamp,
    required this.category,
    required this.action,
    required this.details,
    this.networkType,
    this.salesmanId,
    this.extra,
  });

  Map<String, dynamic> toMap() => {
        'timestamp': timestamp.millisecondsSinceEpoch,
        'category': category.name,
        'action': action,
        'details': details,
        'network_type': networkType,
        'salesman_id': salesmanId,
        'extra': extra,
      };

  factory ActivityLog.fromMap(Map<String, dynamic> map) => ActivityLog(
        id: map['id'] as int?,
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int? ?? 0),
        category: LogCategory.values.firstWhere(
          (c) => c.name == map['category'],
          orElse: () => LogCategory.system,
        ),
        action: map['action']?.toString() ?? '',
        details: map['details']?.toString() ?? '',
        networkType: map['network_type']?.toString(),
        salesmanId: map['salesman_id']?.toString(),
        extra: map['extra']?.toString(),
      );
}

/// Global singleton activity logger for admin audit trail.
///
/// Usage: `ActivityLogger.instance.logAttendance('clock_in', details: '...');`
///
/// Records are stored in SQLite and auto-purged after 3 days.
/// User CANNOT delete these records — only viewable via password-protected admin screen.
class ActivityLogger {
  static final ActivityLogger instance = ActivityLogger._();
  ActivityLogger._();

  String? _currentSalesmanId;

  /// Initialize with current salesman ID. Call once after login.
  void init(String salesmanId) {
    _currentSalesmanId = salesmanId;
    // Auto-purge old records on init
    purgeOldLogs();
  }

  /// Get current network type string for logging
  Future<String> _getNetworkType() async {
    try {
      final result = await Connectivity().checkConnectivity();
      if (result.contains(ConnectivityResult.wifi)) return 'wifi';
      if (result.contains(ConnectivityResult.mobile)) return 'mobile';
      if (result.contains(ConnectivityResult.ethernet)) return 'ethernet';
      return 'offline';
    } catch (_) {
      return 'unknown';
    }
  }

  // ─── CORE LOG METHOD ───────────────────────────────

  /// Master log method — all other methods call this.
  Future<void> log({
    required LogCategory category,
    required String action,
    required String details,
    String? networkType,
    String? salesmanId,
    Map<String, dynamic>? extraData,
  }) async {
    try {
      final netType = networkType ?? await _getNetworkType();
      final entry = ActivityLog(
        timestamp: DateTime.now(),
        category: category,
        action: action,
        details: details,
        networkType: netType,
        salesmanId: salesmanId ?? _currentSalesmanId,
        extra: extraData != null ? jsonEncode(extraData) : null,
      );

      await LocalDbHelper.instance.insertActivityLog(entry.toMap());
      debugPrint(
          "📋 ActivityLog: [${category.name}] $action — $details (net: $netType)");
    } catch (e) {
      // Silently fail — logging should never crash the app
      debugPrint("⚠️ ActivityLogger Error: $e");
    }
  }

  // ─── CONVENIENCE METHODS ───────────────────────────

  /// Log attendance actions (clock_in, clock_out, break_out, re_entry)
  Future<void> logAttendance(
    String action, {
    String? captureTime,
    String? status,
    bool? isOffline,
    String? details,
  }) async {
    await log(
      category: LogCategory.attendance,
      action: action,
      details: details ??
          'Attendance $action${captureTime != null ? ' at $captureTime' : ''}${status != null ? ' | Status: $status' : ''}${isOffline == true ? ' | ⚠️ OFFLINE' : ''}',
      extraData: {
        if (captureTime != null) 'capture_time': captureTime,
        if (status != null) 'status': status,
        if (isOffline != null) 'is_offline': isOffline,
      },
    );
  }

  /// Log leave actions (apply, approve, reject)
  Future<void> logLeave(
    String action, {
    String? leaveType,
    String? leaveDate,
    String? status,
  }) async {
    await log(
      category: LogCategory.leave,
      action: action,
      details:
          'Leave $action${leaveType != null ? ' ($leaveType)' : ''}${leaveDate != null ? ' for $leaveDate' : ''}${status != null ? ' | Status: $status' : ''}',
      extraData: {
        if (leaveType != null) 'leave_type': leaveType,
        if (leaveDate != null) 'leave_date': leaveDate,
        if (status != null) 'status': status,
      },
    );
  }

  /// Log lunch actions
  Future<void> logLunch(String action, {String? details}) async {
    await log(
      category: LogCategory.lunch,
      action: action,
      details: details ?? 'Lunch $action',
    );
  }

  /// Log network status changes
  Future<void> logNetwork(String type, bool isConnected) async {
    await log(
      category: LogCategory.network,
      action: isConnected ? 'connected' : 'disconnected',
      details: 'Network ${isConnected ? "ONLINE" : "OFFLINE"} (Type: $type)',
      networkType: isConnected ? type : 'offline',
    );
  }

  /// Log errors from any screen/service
  Future<void> logError(String source, String error,
      {String? stackTrace}) async {
    await log(
      category: LogCategory.error,
      action: 'error',
      details: '[$source] $error',
      extraData: {
        'source': source,
        'error': error,
        if (stackTrace != null) 'stack_trace': stackTrace,
      },
    );
  }

  /// Log login events
  Future<void> logLogin(String action,
      {String? salesmanId, bool? success, String? reason}) async {
    await log(
      category: LogCategory.login,
      action: action,
      details:
          'Login $action${salesmanId != null ? ' (ID: $salesmanId)' : ''}${success == true ? ' ✅ SUCCESS' : success == false ? ' ❌ FAILED' : ''}${reason != null ? ' | $reason' : ''}',
      salesmanId: salesmanId,
      extraData: {
        if (salesmanId != null) 'salesman_id': salesmanId,
        if (success != null) 'success': success,
        if (reason != null) 'reason': reason,
      },
    );
  }

  /// Log sync events
  Future<void> logSync(String action,
      {String? recordUid, bool? success, String? error}) async {
    await log(
      category: LogCategory.sync,
      action: action,
      details:
          'Sync $action${recordUid != null ? ' [UID: $recordUid]' : ''}${success == true ? ' ✅' : success == false ? ' ❌' : ''}${error != null ? ' | Error: $error' : ''}',
      extraData: {
        if (recordUid != null) 'record_uid': recordUid,
        if (success != null) 'success': success,
        if (error != null) 'error': error,
      },
    );
  }

  /// Log navigation / screen open events
  Future<void> logNavigation(String screenName) async {
    await log(
      category: LogCategory.navigation,
      action: 'open_screen',
      details: 'Opened $screenName',
    );
  }

  /// Log system events (app launch, etc.)
  Future<void> logSystem(String action, {String? details}) async {
    await log(
      category: LogCategory.system,
      action: action,
      details: details ?? 'System $action',
    );
  }

  // ─── FETCH & CLEANUP ──────────────────────────────

  /// Get logs for the last N days (default 3)
  Future<List<ActivityLog>> getLogs({int days = 3}) async {
    final rows = await LocalDbHelper.instance.getActivityLogs(days);
    return rows.map((m) => ActivityLog.fromMap(m)).toList();
  }

  /// Delete logs older than 3 days. Called automatically on init.
  Future<void> purgeOldLogs({int days = 3}) async {
    final deleted = await LocalDbHelper.instance.purgeOldActivityLogs(days);
    if (deleted > 0) {
      debugPrint("🧹 ActivityLogger: Purged $deleted old logs (>$days days)");
    }
  }
}
