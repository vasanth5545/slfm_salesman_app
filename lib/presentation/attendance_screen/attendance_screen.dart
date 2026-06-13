import 'dart:async';
import 'package:slfm_salesman_app/services/activity_logger.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:slfm_salesman_app/core/services/secure_http_client.dart'
    as http;
import 'package:intl/intl.dart';
import '../../services/secure_storage_service.dart';
import 'package:slfm_salesman_app/services/api_service.dart';
import '../../core/utils/network_quality_helper.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'package:audioplayers/audioplayers.dart'; // 🔥 Tick Sound Support
import '../../core/app_export.dart';
import '../../core/database/local_db_helper.dart';

import '../../core/utils/greeting_helper.dart';
import '../../core/utils/permission_guard.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../widgets/custom_app_bar.dart';
import './models/attendance_chat_message.dart';
import './widgets/chat_message_bubble.dart';
import './widgets/camera_capture_screen.dart';
import './widgets/today_summary_dialog.dart';
import './widgets/attendance_history_list_widget.dart';
import './widgets/attendance_skeleton_views.dart';
import './widgets/attendance_chat_view.dart';
import './repositories/attendance_repository.dart';
import '../../services/attendance_sync_service.dart';
import './models/attendance_record.dart';
import '../../core/services/offline_sync_service.dart';
import '../../core/utils/sync_event_bus.dart';

Future<List<int>?> _processImageIsolate(Map<String, dynamic> params) async {
  try {
    final String imagePath = params['imagePath'];
    final bool isFrontCamera = params['isFrontCamera'] as bool? ?? true;

    final bytes = await File(imagePath).readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) {
      return null;
    }

    image = img.bakeOrientation(image);

    if (isFrontCamera) {
      image = img.flip(image, direction: img.FlipDirection.horizontal);
    }

    if (image.width > image.height) {
      image = img.copyRotate(image, angle: 90);
    }

    int maxW = 480;
    if (image.width > maxW) {
      int targetH = (image.height * (maxW / image.width)).round();
      image = img.copyResize(image, width: maxW, height: targetH);
    }

    return img.encodeJpg(image, quality: 70);
  } catch (e) {
    debugPrint("Isolate Error: $e");
    return null;
  }
}

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late AnimationController _skeletonController;
  final AudioPlayer _audioPlayer = AudioPlayer(); // 🔥 Tick Sound Player
  bool _isClockInMode = true;
  bool _isCapturing = false;
  bool _isNavigatingCamera = false;

  bool _showHistory = false;
  bool _allowRemoteAttendance = false;
  bool _isInitialLoading = true;
  bool _isHistoryLoading = false;
  bool _isRefreshing = false;

  int _daysToShow = 3;
  bool _isLoadingMore = false;
  bool _hasMoreHistory = true;

  String _salesmanId = "";
  String _salesmanName = "";
  String _showroomName = "SLFM Furniture";

  DateTime? _lastActionTime;
  String? _topErrorMessage;
  Timer? _errorHideTimer;

  void _showTopError(String message) {
    if (!mounted) return;
    try {
      ActivityLogger.instance.logError('UI', message);
    } catch (_) {}
    _errorHideTimer?.cancel();
    setState(() {
      _topErrorMessage = message;
    });
    _errorHideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _topErrorMessage = null);
      }
    });
  }

  DateTime? _todayClockIn;
  DateTime? _todayBreakOutTime;
  DateTime? _todayReentryTime;
  DateTime? _todayClockOut;

  String? _todayInImageUrl;
  String? _todayOutImageUrl;
  String? _todayReentryImageUrl;
  String? _todayBreakOutImageUrl;

  String? _todayInUid;
  String? _todayOutUid;
  String? _todayReentryUid;
  String? _todayBreakOutUid;

  UploadStatus _todayInUploadStatus = UploadStatus.success;
  UploadStatus _todayOutUploadStatus = UploadStatus.success;
  UploadStatus _todayReentryUploadStatus = UploadStatus.success;
  UploadStatus _todayBreakOutUploadStatus = UploadStatus.success;

  String _attendanceRate = "0%";
  String _weeklyTotal = "0h 0m";
  String _monthlyTotal = "0h 0m";
  String _totalWorkedDays = "0";
  String _totalLeavesUsed = "0";

  List<Map<String, dynamic>> _monthlyPerformanceList = [];
  List<String> _excludedDates = [];
  int _resumeCount = 0;
  bool _isInternetConnected = true;

  bool _allowLateEntry = false;
  String _clockInLimitTime = '15:00:00';
  String _reentryLimitTime = '19:30:00';
  int get _clockInLimitHour =>
      int.tryParse(_clockInLimitTime.split(':')[0]) ?? 15;
  int get _clockInLimitMinute => _clockInLimitTime.split(':').length > 1
      ? (int.tryParse(_clockInLimitTime.split(':')[1]) ?? 0)
      : 0;
  int get _reentryLimitHour =>
      int.tryParse(_reentryLimitTime.split(':')[0]) ?? 19;
  int get _reentryLimitMinute => _reentryLimitTime.split(':').length > 1
      ? (int.tryParse(_reentryLimitTime.split(':')[1]) ?? 30)
      : 30;
  bool _isSendingLeave = false;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  String _currentStatusStr = "Not Marked";
  String? _holidayReason;
  String? _customLateCutoff;

  String get _hostingerDomain {
    final base = ApiUrl.baseUrl;
    String domain = base;
    if (domain.endsWith('/api')) {
      domain = domain.substring(0, domain.length - 4);
    }
    return domain;
  }

  List<Map<String, dynamic>> _attendanceHistory = [];
  List<Map<String, dynamic>> _leaveHistory = [];

  StreamSubscription<Position>? _positionStream;
  StreamSubscription? _leaveRequestsSubscription;
  StreamSubscription? _holidaysSubscription;
  StreamSubscription? _attendanceSubscription;
  StreamSubscription? _salesmanSubscription;
  StreamSubscription? _syncEventSubscription;
  Position? _cachedPosition;

  Timer? _uiRefreshTimer;

  Timer? _offlineRetryTimer;
  Timer? _statusPollingTimer;
  Timer? _rebuildTimer;

  bool _isBuildingChat = false;
  bool _needsRebuild = false;

  final Set<String> _recentlySubmittedLeaveKeys = {};
  final Map<String, Map<String, String>> _deferredLeaveStatuses = {};

  final ValueNotifier<List<AttendanceChatMessage>> _chatMessagesNotifier =
      ValueNotifier<List<AttendanceChatMessage>>([]);

  late final AttendanceRepository _attendanceRepo;
  late final AttendanceSyncService _syncService;
  StreamSubscription<List<AttendanceRecord>>? _attendanceStreamSub;

  int _lastSyncTimestamp = 0;
  bool _isFirstSalesmanEvent = true;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();

  String? _selectedLeaveType;
  DateTimeRange? _selectedRange;

  final ValueNotifier<bool> _showScrollToBottom = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    ChatMessageBubble.resetAnimations();
    _skeletonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_scrollListener);
    _loadUserData();

    _startConnectivityMonitoring();
    _updatePresence(true);

    _attendanceRepo = AttendanceRepository();
    _syncService = AttendanceSyncService(_attendanceRepo);

    _attendanceStreamSub = _attendanceRepo.attendanceStream.listen((records) {
      if (mounted) {
        _triggerChatBuild();
      }
    });

    _uiRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      if (mounted && !_isCapturing) {
        _triggerChatBuild();
      }
    });

    _syncEventSubscription = SyncEventBus.onSyncCompleted.listen((_) async {
      if (mounted) {
        debugPrint(
            "🔄 Background Sync Completed! Refreshing UI sequentially...");
        await _fetchAttendanceStatus();
        await _fetchAttendanceHistory(forceFullSync: true);
      }
    });
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args != null && args.containsKey('remote_enabled')) {
      final bool remoteArg = args['remote_enabled'] as bool;
      if (_isInitialLoading) {
        _allowRemoteAttendance = remoteArg;
        if (_allowRemoteAttendance) {
          _showHistory = true;
        }
      }
    }
  }

  void _handleBackNavigation() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacementNamed(context, '/dashboard');
    }
  }

  void _setupAttendanceUpdateListener() {
    if (_salesmanId.isEmpty) return;

    _attendanceSubscription?.cancel();
    bool isInitialLoad = true;

    _attendanceSubscription = FirebaseDatabase.instance
        .ref('attendance_updates/$_salesmanId')
        .onValue
        .listen((event) {
      if (isInitialLoad) {
        isInitialLoad = false;
        return;
      }
      if (mounted) {
        debugPrint("🔥 Firebase: Admin updated attendance! Force fetching...");
        _fetchAttendanceStatus(forceFullSync: true);
        _fetchAttendanceHistory(forceFullSync: true);
      }
    }, onError: (error) {
      debugPrint("⚠️ attendance_updates listener error: $error");
    });
  }

  void _setupSalesmanListener() {
    if (_salesmanId.isEmpty) {
      return;
    }
    _salesmanSubscription?.cancel();
    _isFirstSalesmanEvent = true;

    _salesmanSubscription = FirebaseDatabase.instance
        .ref('salesmen_status/$_salesmanId')
        .onValue
        .listen((event) async {
      final snapshot = event.snapshot;
      if (snapshot.value != null) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);

        bool isSuspended = false;
        if (data['status'] != null &&
            data['status'].toString().toLowerCase() == 'suspended') {
          isSuspended = true;
        }

        if (isSuspended && mounted) {
          _salesmanSubscription?.cancel();

          await SecureStorageService.clearSession();
          FlutterBackgroundService().invoke("updateSalesmanId", {"id": ""});

          if (mounted) {
            try {
              ActivityLogger.instance
                  .logError('UI', 'Account suspended - logged out');
            } catch (_) {}
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    "⚠️ Your account has been suspended by the Admin. You have been logged out."),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 5),
              ),
            );
            Navigator.pushNamedAndRemoveUntil(
              context,
              AppRoutes.login,
              (route) => false,
            );
          }
          return;
        }

        if (mounted) {
          setState(() {
            final wasAllowed = _allowRemoteAttendance;
            _allowRemoteAttendance =
                data['remote_attendance_enabled'] == true ||
                    data['remote_attendance_enabled'] == 'true' ||
                    data['remote_attendance_enabled'] == 1 ||
                    data['remote_attendance_enabled'] == "1";

            SecureStorageService.writeString(
                'remote_attendance_enabled_$_salesmanId',
                _allowRemoteAttendance ? "1" : "0");

            if (_allowRemoteAttendance && !wasAllowed) {
              _showHistory = true;
              _fetchAttendanceHistory(background: true, forceFullSync: true);
            } else if (!_allowRemoteAttendance && wasAllowed) {
              _showHistory = false;
            }

            _allowLateEntry = data['allow_late_entry'] == true ||
                data['allow_late_entry'] == 'true' ||
                data['allow_late_entry'] == 1 ||
                data['allow_late_entry'] == "1";

            if (data['clock_in_limit'] != null &&
                data['clock_in_limit'].toString().isNotEmpty) {
              _clockInLimitTime = data['clock_in_limit'].toString();
            }
            if (data['reentry_limit'] != null &&
                data['reentry_limit'].toString().isNotEmpty) {
              _reentryLimitTime = data['reentry_limit'].toString();
            }

            if (data['data_sync_timestamp'] != null) {
              final newSyncTs =
                  int.tryParse(data['data_sync_timestamp'].toString());
              if (newSyncTs != null) {
                if (_isFirstSalesmanEvent) {
                  _isFirstSalesmanEvent = false;
                  _lastSyncTimestamp = newSyncTs;
                } else if (newSyncTs > _lastSyncTimestamp) {
                  _lastSyncTimestamp = newSyncTs;
                  debugPrint(
                      "🔄 Admin Altered Data! Sync Signal Received ($newSyncTs): Triggering UI Refresh...");
                  // 🔥 FIX: Guard with pending check — don't wipe local data
                  // when offline records may still be syncing.
                  LocalDbHelper.instance
                      .getPendingAttendance(_salesmanId)
                      .then((pending) {
                    if (pending.isEmpty) {
                      _refreshAllData(forceFullSync: true).then((_) {
                        _determineClockInMode();
                        _triggerChatBuild();
                      });
                    } else {
                      // Has pending — just rebuild UI safely
                      _determineClockInMode();
                      _triggerChatBuild();
                    }
                  });
                }
              }
            } else {
              if (_isFirstSalesmanEvent) {
                _isFirstSalesmanEvent = false;
              }
            }
          });
        }
      }
    }, onError: (error, stackTrace) {
      debugPrint("Salesman Listener Error: $error\n$stackTrace");
    });
  }

  int _lastPendingCount = 0;

  void _startStatusPolling() {
    _statusPollingTimer?.cancel();
    _statusPollingTimer =
        Timer.periodic(const Duration(seconds: 30), (_) async {
      if (mounted && !_isCapturing && _isInternetConnected) {
        try {
          final db = await LocalDbHelper.instance.database;
          final pendingRecords = await db.query('pending_attendance',
              where: 'salesman_id = ?', whereArgs: [_salesmanId]);
          int currentPendingCount = pendingRecords.length;

          await _fetchAttendanceStatus(forceFullSync: false);

          if (currentPendingCount < _lastPendingCount) {
            debugPrint(
                "🔄 Detected background sync completion. Fetching history...");
            await _fetchAttendanceHistory(
                background: true, forceFullSync: true);
          }
          _lastPendingCount = currentPendingCount;

          if (mounted) {
            _triggerChatBuild();
          }
        } catch (e) {
          debugPrint("Status Polling Error: $e");
        }
      }
    });
  }

  void _setupHolidaysListener() {
    if (_salesmanId.isEmpty) {
      return;
    }

    _holidaysSubscription?.cancel();
    _fetchHolidaysFromApi();
    _holidaysSubscription = Stream.periodic(const Duration(minutes: 5))
        .listen((_) => _fetchHolidaysFromApi());
  }

  Future<void> _fetchHolidaysFromApi() async {
    try {
      final response = await ApiService().client.get(
        ApiUrl.attendance,
        queryParameters: {
          'action': 'get_history',
          'salesman_id': _salesmanId,
        },
      );

      Map<String, dynamic> responseData;
      if (response.statusCode != 200 || response.data == null) {
        return;
      }
      if (response.data is String) {
        responseData = jsonDecode(response.data);
      } else {
        responseData = response.data;
      }

      if (responseData['status'] != 'success' || responseData['data'] == null) {
        return;
      }

      final List<dynamic> historyList = responseData['data'];
      bool localChanged = false;

      for (var record in historyList) {
        if (record['status']?.toString() == 'Holiday') {
          final dateStr = record['date']?.toString() ?? '';
          final reason = record['holiday_reason']?.toString() ?? 'Holiday';
          if (dateStr.isEmpty) {
            continue;
          }

          final docId = 'hol_$dateStr';
          DateTime hDate;
          try {
            hDate = DateTime.parse(dateStr);
          } catch (_) {
            continue;
          }

          final db = await LocalDbHelper.instance.database;
          final existing = await db.query('local_messages',
              where: 'salesman_id = ? AND payload LIKE ?',
              whereArgs: [_salesmanId, '%"holiday_id":"$docId"%']);

          DateTime timestampToUse = hDate;
          if (DateUtils.isSameDay(hDate, DateTime.now())) {
            timestampToUse = DateTime.now();
          }

          String msg = "🎉 $dateStr அன்று விடுமுறை: $reason";

          if (existing.isEmpty) {
            await LocalDbHelper.instance.insertMessage(_salesmanId, {
              'message_text': msg,
              'message_type': 'system',
              'unique_id': "h_sys_$docId",
              'status': 'sent',
              'payload': jsonEncode({'holiday_id': docId}),
              'timestamp': timestampToUse.toIso8601String(),
            });
            localChanged = true;
          } else {
            await db.update(
                'local_messages',
                {
                  'message_text': msg,
                  'timestamp': timestampToUse.toIso8601String()
                },
                where: 'local_id = ?',
                whereArgs: [existing.first['local_id']]);
            localChanged = true;
          }
        }
      }

      if (localChanged && mounted) {
        await _loadHistoryFromSQLite();
        _triggerChatBuild();
      }
    } catch (e, stackTrace) {
      debugPrint("Holidays API Fetch Error: $e\n$stackTrace");
    }
  }

  void _setupLeaveRequestsListener() {
    if (_salesmanId.isEmpty) return;

    _leaveRequestsSubscription?.cancel();
    _fetchLeaveRequestsFromApi();
    _leaveRequestsSubscription = Stream.periodic(const Duration(minutes: 2))
        .listen((_) => _fetchLeaveRequestsFromApi());
  }

  Future<void> _fetchLeaveRequestsFromApi() async {
    try {
      final response = await http
          .post(
            Uri.parse(ApiUrl.leave),
            body: jsonEncode({
              "action": "get_history",
              "salesman_id": _salesmanId,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return;
      }
      final responseData = jsonDecode(response.body);
      if (responseData['status'] != 'success' || responseData['data'] == null) {
        return;
      }

      final List<dynamic> serverLeaves = responseData['data'];
      final List<String> serverDocIds = [];

      for (var leaveItem in serverLeaves) {
        final docId = leaveItem['id']?.toString() ?? '';
        if (docId.isEmpty) {
          continue;
        }
        serverDocIds.add(docId);

        final sanitizedData = <String, dynamic>{
          'id': docId,
          'salesman_id': _salesmanId,
          'leave_date': leaveItem['leave_date']?.toString() ?? '',
          'leave_type': leaveItem['leave_type']?.toString() ?? 'Leave',
          'reason': leaveItem['reason']?.toString() ?? '',
          'status': leaveItem['status']?.toString() ?? 'Pending',
          'created_at': leaveItem['created_at']?.toString() ??
              DateTime.now().toIso8601String(),
          'updated_at': leaveItem['updated_at']?.toString(),
        };

        await LocalDbHelper.instance
            .syncLeaveHistory(_salesmanId, [sanitizedData]);

        final newStatus = sanitizedData['status'] ?? 'Pending';
        final leaveType = sanitizedData['leave_type'] ?? 'Leave';
        final leaveDate = sanitizedData['leave_date']?.toString() ?? '';

        final dedupeKey = '${leaveDate}_${leaveType.replaceAll(' ', '')}';
        if (_recentlySubmittedLeaveKeys.contains(dedupeKey)) {
          _deferredLeaveStatuses[dedupeKey] = {
            'status': newStatus,
            'leave_type': leaveType,
            'doc_id': docId,
          };
          continue;
        }

        final db = await LocalDbHelper.instance.database;

        final String stdUniqueId =
            "leave_req_${_salesmanId}_${leaveDate}_${leaveType.replaceAll(' ', '')}";

        final existing = await db.query('local_messages',
            where: 'salesman_id = ? AND unique_id = ?',
            whereArgs: [_salesmanId, stdUniqueId]);

        if (existing.isEmpty) {
          DateTime createdAt;
          try {
            createdAt = DateTime.parse(sanitizedData['created_at'].toString());
          } catch (_) {
            createdAt = DateTime.now();
          }

          final payload = {
            'doc_id': docId,
            'leave_type': leaveType,
            'leave_date': leaveDate,
            'reason': sanitizedData['reason']?.toString() ?? '',
            'status': newStatus,
          };

          await LocalDbHelper.instance.insertMessage(_salesmanId, {
            'message_text': "Leave Application ($leaveType)",
            'message_type': 'leave_request',
            'unique_id': stdUniqueId,
            'status': newStatus.toLowerCase(),
            'payload': jsonEncode(payload),
            'timestamp': createdAt.toIso8601String(),
          });
        } else {
          String? newTimestamp;
          try {
            if (sanitizedData['updated_at'] != null) {
              newTimestamp = sanitizedData['updated_at'].toString();
            } else if (sanitizedData['created_at'] != null) {
              newTimestamp = sanitizedData['created_at'].toString();
            }
          } catch (_) {}

          try {
            final existingPayload =
                jsonDecode(existing.first['payload'].toString());
            existingPayload['doc_id'] = docId;
            existingPayload['status'] = newStatus;
            await db.update(
              'local_messages',
              {
                'payload': jsonEncode(existingPayload),
                'status': newStatus.toLowerCase(),
                if (newTimestamp != null) 'timestamp': newTimestamp,
              },
              where: 'local_id = ?',
              whereArgs: [existing.first['local_id']],
            );
          } catch (_) {
            await LocalDbHelper.instance.updateLeaveMessageStatusByDocId(
                _salesmanId, docId, newStatus, leaveType,
                newTimestamp: newTimestamp);
          }
        }
      }

      await LocalDbHelper.instance
          .reconcileLeaveHistory(_salesmanId, serverDocIds);
      await LocalDbHelper.instance
          .reconcileLeaveMessages(_salesmanId, serverDocIds);

      final List<Map<String, dynamic>> serverLeaveForHistory =
          serverLeaves.map((item) {
        return <String, dynamic>{
          'id': item['id']?.toString() ?? '',
          'salesman_id': _salesmanId,
          'leave_date': item['leave_date']?.toString() ?? '',
          'leave_type': item['leave_type']?.toString() ?? 'Unknown',
          'reason': item['reason']?.toString() ?? '',
          'status': item['status']?.toString() ?? 'Pending',
          'created_at': item['created_at']?.toString() ?? '',
          'updated_at': item['updated_at']?.toString() ?? '',
        };
      }).toList();
      await LocalDbHelper.instance
          .clearAndInsertLeaveHistory(_salesmanId, serverLeaveForHistory);

      await LocalDbHelper.instance.purgeOldLeaveData(_salesmanId);

      if (mounted) {
        final offlineAttendance =
            await LocalDbHelper.instance.getAttendanceHistory(_salesmanId);
        final offlineLeaves =
            await LocalDbHelper.instance.getLeaveHistory(_salesmanId);
        setState(() {
          _attendanceHistory = offlineAttendance;
          _leaveHistory = offlineLeaves;
        });
        _triggerChatBuild();
      }
    } catch (e, stackTrace) {
      debugPrint("Leave Requests API Fetch Error: $e\n$stackTrace");
    }
  }

  String _formatDbTime(String timeStr) {
    if (timeStr.isEmpty || timeStr == "00:00:00" || timeStr == "0h 0m") {
      return "0h 0m";
    }
    if (timeStr.contains('h')) {
      return timeStr;
    }
    final parts = timeStr.split(':');
    if (parts.length >= 2) {
      int h = int.tryParse(parts[0]) ?? 0;
      int m = int.tryParse(parts[1]) ?? 0;
      return "${h}h ${m}m";
    }
    return timeStr;
  }

  void _updatePerformanceState(Map<String, dynamic> pData) {
    if (!mounted) {
      return;
    }
    setState(() {
      _attendanceRate = pData['attendance_percentage'] != null
          ? "${pData['attendance_percentage']}%"
          : (pData['attendance_rate'] != null
              ? "${pData['attendance_rate']}%"
              : "0%");

      _monthlyTotal = _formatDbTime(pData['total_working_hours']?.toString() ??
          pData['monthly_total']?.toString() ??
          pData['month_hours']?.toString() ??
          pData['month_total_hours']?.toString() ??
          "00:00:00");
      _weeklyTotal = _formatDbTime(pData['weekly_working_hours']?.toString() ??
          pData['weekly_total']?.toString() ??
          pData['week_hours']?.toString() ??
          pData['week_total_hours']?.toString() ??
          "00:00:00");

      _totalWorkedDays = (pData['total_worked_days'] ??
              pData['working_days'] ??
              pData['days_worked'] ??
              0)
          .toString();
      _totalLeavesUsed = (pData['total_days_consumed'] ??
              pData['total_leaves_used'] ??
              pData['leaves_used'] ??
              0)
          .toString();

      _excludedDates = (pData['excluded_dates'] is List)
          ? List<String>.from(pData['excluded_dates'])
          : [];
    });
  }

  void _scrollListener() async {
    if (!_scrollController.hasClients) {
      return;
    }

    final bool isScrolledUp = _scrollController.position.pixels > 200;
    if (_showScrollToBottom.value != isScrolledUp) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showScrollToBottom.value = isScrolledUp;
      });
    }

    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 50) {
      if (!_isLoadingMore && _hasMoreHistory) {
        setState(() => _isLoadingMore = true);

        String? oldestDate;
        if (_attendanceHistory.isNotEmpty) {
          final sorted = _attendanceHistory
              .map((r) => r['date']?.toString() ?? '')
              .where((d) => d.isNotEmpty)
              .toList()
            ..sort();
          if (sorted.isNotEmpty) oldestDate = sorted.first;
        }

        _daysToShow += 5;

        _fetchAttendanceHistory(
          limit: 5,
          beforeDate: oldestDate,
          isLoadMore: true,
        ).then((_) {
          if (mounted) _buildChatFromStatus();
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!mounted) {
      return;
    }

    try {
      if (state == AppLifecycleState.resumed) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (mounted) {
            // 🔥 FIX: Check for pending records BEFORE doing a full refresh.
            // _refreshAllData wipes local history, which destroys pending offline records.
            final pendingAtts =
                await LocalDbHelper.instance.getPendingAttendance(_salesmanId);
            if (pendingAtts.isEmpty) {
              _refreshAllData(forceFullSync: true);
            } else {
              // Pending records exist — just rebuild the chat, don't wipe history
              _triggerChatBuild();
            }
            _updatePresence(true).catchError((e, stackTrace) {
              return null;
            });
          }
        });
      } else if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.inactive) {
        _updatePresence(false).catchError((_) {});
      }
    } catch (e, stackTrace) {
      debugPrint("Lifecycle Error Completely Prevented: $e\n$stackTrace");
    }
  }

  Future<void> _startConnectivityMonitoring() async {
    final bool isNowOnline = await NetworkQualityHelper.hasRealInternet();
    if (mounted) setState(() => _isInternetConnected = isNowOnline);

    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) async {
      final bool wasOnline = _isInternetConnected;

      final bool hasAnyInterface =
          results.any((r) => r != ConnectivityResult.none);
      if (!hasAnyInterface) {
        if (mounted) setState(() => _isInternetConnected = false);
        _updatePresence(false);
        return;
      }

      final bool isCurrentlyOnline =
          await NetworkQualityHelper.hasRealInternet();

      if (isCurrentlyOnline != wasOnline) {
        if (mounted) setState(() => _isInternetConnected = isCurrentlyOnline);

        _updatePresence(isCurrentlyOnline);

        if (isCurrentlyOnline) {
          // 🔥 FIX: Only trigger a chat rebuild — do NOT call _refreshAllData here.
          // _refreshAllData wipes local DB before server confirms the sync.
          // The status polling timer (every 30s) will pick up the change safely.
          await OfflineSyncService().syncPendingData();
          if (mounted) {
            _triggerChatBuild(); // Always rebuild from local DB (includes pending records)
          }
        }
      }
    });
  }

  Future<void> _updatePresence(bool isOnline) async {
    if (_salesmanId.isEmpty) {
      return;
    }

    try {
      final rtdb =
          FirebaseDatabase.instance.ref('tracking_status/$_salesmanId');
      await rtdb.update({
        'is_online': isOnline,
        'last_online': ServerValue.timestamp,
      });
    } catch (e, stackTrace) {
      debugPrint("Update Presence Error: $e\n$stackTrace");
    }
  }

  Future<void> _startLocationUpdates() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission =
          await PermissionGuard.run(() => Geolocator.requestPermission()) ??
              await Geolocator.checkPermission();
    }

    if (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always) {
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          distanceFilter: 10,
        ),
      ).listen(
        (Position position) {
          if (mounted) setState(() => _cachedPosition = position);
        },
        onError: (error) {
          debugPrint("Position Stream Error: $error");
        },
      );
    }
  }

  Future<void> _loadUserData() async {
    final name = await SecureStorageService.getSalesmanName();
    final id = await SecureStorageService.getSalesmanId();
    final showroom = await SecureStorageService.getShowroomName();
    final cutoff = await SecureStorageService.getCustomLateCutoff();

    if (!mounted) return;
    setState(() {
      _salesmanName = (name ?? "Salesman").trim();
      _salesmanId = (id ?? "").trim();
      _showroomName = (showroom ?? "SLFM Furniture").trim();
      _customLateCutoff = cutoff;
    });

    if (_salesmanId.isNotEmpty) {
      final cachedRemote = await SecureStorageService.readString(
          'remote_attendance_enabled_$_salesmanId');
      if (cachedRemote != null && mounted) {
        setState(() {
          _allowRemoteAttendance =
              (cachedRemote == "1" || cachedRemote == "true");
          if (_allowRemoteAttendance) {
            _showHistory = true;
          }
        });
      }
    }

    if (_salesmanId.isNotEmpty) {
      LocalDbHelper.instance
          .purgeOldRecords(_salesmanId)
          .then((int count) async {
        await LocalDbHelper.instance.normalizeAllDates();

        if (mounted) {
          _loadHistoryFromSQLite();
        }
      });
    }

    if (_salesmanId.isNotEmpty) {
      try {
        final db = await LocalDbHelper.instance.database;
        await db.delete('local_messages',
            where:
                "message_text LIKE '%❌ Server Error%' AND message_type = 'system'");
        await db.delete('local_messages',
            where:
                "message_text LIKE '%❌ Leave already applied%' AND message_type = 'system'");
        await db.delete('local_messages',
            where: "unique_id LIKE 'leave_sys_%' AND message_type = 'system'");
        await db.delete('local_messages',
            where:
                "message_text LIKE 'விடுமுறை விண்ணப்பம் %' AND message_type = 'system'");

        await LocalDbHelper.instance.purgeOldRecords(_salesmanId);
      } catch (e, stackTrace) {
        debugPrint("Load User Data Cleanup Error: $e\n$stackTrace");
      }

      try {
        final localPerf =
            await LocalDbHelper.instance.getPerformanceSummary(_salesmanId);
        if (localPerf != null) _updatePerformanceState(localPerf);
      } catch (e, stackTrace) {
        debugPrint("Performance Load Error: $e\n$stackTrace");
      }
    }

    await _loadHistoryFromSQLite();
    _setupAttendanceUpdateListener();
    _setupSalesmanListener();
    await _startLocationUpdates();
    await _determineClockInMode();

    try {
      await _persistDailyGreeting();

      await Future.wait([
        _fetchAttendanceStatus(forceFullSync: true),
        _fetchAttendanceHistory(background: true, forceFullSync: true),
        _syncMessagesFromServer(),
      ]);
    } catch (e) {
      debugPrint("Init Fetch Error: $e");
    }

    if (mounted) {
      _buildChatFromStatus();
      _setupLeaveRequestsListener();
      _setupHolidaysListener();
      _startStatusPolling();
      _triggerChatBuild();
    }
  }

  Future<void> _persistDailyGreeting() async {
    if (_salesmanId.isEmpty) return;
    final now = DateTime.now();
    final hour = now.hour;
    final todayStr1 = DateFormat('yyyyMMdd').format(now);

    String greeting;
    String periodKey;
    if (hour < 12) {
      greeting =
          "காலை வணக்கம், $_salesmanName! ☀️\nதேதி: ${DateFormat('dd MMM yyyy, EEEE').format(now)}";
      periodKey = "morning";
    } else if (hour < 17) {
      greeting =
          "மதிய வணக்கம், $_salesmanName! 🌤️\nதேதி: ${DateFormat('dd MMM yyyy, EEEE').format(now)}";
      periodKey = "afternoon";
    } else {
      greeting =
          "மாலை வணக்கம், $_salesmanName! 🌙\nதேதி: ${DateFormat('dd MMM yyyy, EEEE').format(now)}";
      periodKey = "evening";
    }

    final uniqueId = "sys_greet_${todayStr1}_$periodKey";

    final db = await LocalDbHelper.instance.database;
    final existing = await db.query('local_messages',
        where: 'salesman_id = ? AND unique_id = ?',
        whereArgs: [_salesmanId, uniqueId]);

    if (existing.isEmpty) {
      await _addSystemMessage(greeting, persist: true, uniqueId: uniqueId);
    }
  }

  Future<void> _loadHistoryFromSQLite() async {
    try {
      if (_salesmanId.isEmpty) {
        return;
      }
      final offlineAttendance =
          await LocalDbHelper.instance.getAttendanceHistory(_salesmanId);
      final offlineLeaves =
          await LocalDbHelper.instance.getLeaveHistory(_salesmanId);
      if (mounted) {
        setState(() {
          _attendanceHistory = offlineAttendance;
          _leaveHistory = offlineLeaves;
        });
      }
    } catch (e, stackTrace) {
      debugPrint("SQLite Load Error: $e\n$stackTrace");
    }
  }

  Future<void> _syncMessagesFromServer() async {
    if (_salesmanId.isEmpty) return;
    try {
      int lastId =
          await SecureStorageService.readInt('last_message_id_$_salesmanId') ??
              0;
      final String messagesUrl = ApiUrl.messages;
      final response = await http
          .get(Uri.parse(
              '$messagesUrl?action=sync_messages&salesman_id=$_salesmanId&last_id=$lastId'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          List msgs = data['data'];
          for (var msg in msgs) {
            String ts = msg['created_at']?.toString() ??
                DateTime.now().toIso8601String();
            await LocalDbHelper.instance.insertMessage(_salesmanId, {
              'server_id': int.tryParse(msg['id']?.toString() ?? '0') ?? 0,
              'unique_id': "server_${msg['id']}",
              'message_text': msg['message_text'],
              'message_type': msg['message_type'],
              'status': msg['status'],
              'timestamp': ts,
            });
            lastId = int.tryParse(msg['id']?.toString() ?? '0') ?? lastId;
          }
          if (msgs.isNotEmpty) {
            await SecureStorageService.writeInt(
                'last_message_id_$_salesmanId', lastId);
          }
        }
      }
    } catch (e, stackTrace) {
      debugPrint("Sync Messages Error: $e\n$stackTrace");
    }
  }

  Future<void> _refreshAllData({bool forceFullSync = true}) async {
    if (!mounted || _isRefreshing) return;
    _isRefreshing = true;

    try {
      await _fetchAttendanceStatus(forceFullSync: forceFullSync);
      await _fetchAttendanceHistory(
          background: true, forceFullSync: forceFullSync);
      await _fetchLeaveRequestsFromApi();
      await _syncMessagesFromServer();

      if (mounted) {
        _triggerChatBuild();
        debugPrint("✅ Attendance data refreshed successfully via sync signal.");
      }
    } catch (e) {
      debugPrint("❌ Error during real-time refresh: $e");
    } finally {
      if (mounted) {
        _isRefreshing = false;
      }
    }
  }

  Future<void> _cleanupLocalPendingRecords() async {
    // Empty to prevent hiding pending bubbles mistakenly
  }

  Future<void> _saveTodayToLocalHistory() async {
    if (_salesmanId.isEmpty) return;
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final todayData = <String, dynamic>{
      'date': todayStr,
      'clock_in': _todayClockIn != null
          ? DateFormat('HH:mm:ss').format(_todayClockIn!)
          : '',
      'clock_in_time': _todayClockIn != null
          ? DateFormat('hh:mm a').format(_todayClockIn!)
          : '',
      'clock_out': _todayClockOut != null
          ? DateFormat('HH:mm:ss').format(_todayClockOut!)
          : '',
      'clock_out_time': _todayClockOut != null
          ? DateFormat('hh:mm a').format(_todayClockOut!)
          : '',
      'break_out_time': _todayBreakOutTime != null
          ? DateFormat('HH:mm:ss').format(_todayBreakOutTime!)
          : '',
      'break_out_selfie_url': _todayBreakOutImageUrl ?? '',
      'reentry_time': _todayReentryTime != null
          ? DateFormat('HH:mm:ss').format(_todayReentryTime!)
          : '',
      'reentry_selfie_url': _todayReentryImageUrl ?? '',
      'selfie_url': _todayInImageUrl ?? '',
      'in_selfie_url': _todayInImageUrl ?? '',
      'out_selfie_url': _todayOutImageUrl ?? '',
      'clock_out_selfie_url': _todayOutImageUrl ?? '',
      'thumbnail': _todayInImageUrl ?? '',
      'status': _currentStatusStr,
      'salesman_id': _salesmanId,
      'showroom': _showroomName,
    };

    try {
      await LocalDbHelper.instance
          .upsertTodayAttendance(_salesmanId, todayData);
      debugPrint("✅ Today's record persisted to SQLite for Activity Log.");
    } catch (e) {
      debugPrint("❌ Error saving today to local history: $e");
    }
  }

  Future<void> _determineClockInMode() async {
    bool shouldBeClockIn = true;
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);

    if (_todayClockIn == null) {
      try {
        final lastIn = await SecureStorageService.readString(
            'fc_last_synced_in_$_salesmanId');
        if (lastIn != null) {
          final parsedIn = DateTime.parse(lastIn);
          if (DateUtils.isSameDay(parsedIn, now)) {
            _todayClockIn = parsedIn;
          }
        }
        final lastOut = await SecureStorageService.readString(
            'fc_last_synced_out_$_salesmanId');
        if (lastOut != null) {
          final parsedOut = DateTime.parse(lastOut);
          if (DateUtils.isSameDay(parsedOut, now)) {
            _todayClockOut = parsedOut;
          }
        }
      } catch (e) {
        debugPrint("Secure Storage restore failed: $e");
      }
    }

    if (_todayClockIn != null) {
      if (_todayClockOut != null) {
        shouldBeClockIn = true;
      } else if (_todayBreakOutTime != null && _todayReentryTime == null) {
        shouldBeClockIn = true;
      } else {
        shouldBeClockIn = false;
      }
    } else {
      try {
        final offlineHistory =
            await LocalDbHelper.instance.getAttendanceHistory(_salesmanId);

        final todayRecord = offlineHistory.firstWhere(
          (r) =>
              r['date']?.toString().contains(todayStr) == true ||
              r['date']?.toString() == DateFormat('dd MMM yyyy').format(now),
          orElse: () => <String, dynamic>{},
        );

        if (todayRecord.isNotEmpty) {
          final cIn = todayRecord['clock_in'] ?? todayRecord['clock_in_time'];
          final cOut =
              todayRecord['clock_out'] ?? todayRecord['clock_out_time'];
          final cBreak = todayRecord['break_out_time'];
          final cRe = todayRecord['reentry_time'];

          if (mounted) {
            setState(() {
              if (cIn != null &&
                  cIn.toString().isNotEmpty &&
                  cIn.toString() != "--:--") {
                _todayClockIn ??= _combineDateAndTime(now, cIn.toString());
              }
              if (cOut != null &&
                  cOut.toString().isNotEmpty &&
                  cOut.toString() != "--:--") {
                _todayClockOut ??= _combineDateAndTime(now, cOut.toString());
              }

              if (cBreak != null &&
                  cBreak.toString().isNotEmpty &&
                  cBreak.toString() != "--:--") {
                _todayBreakOutTime ??=
                    _combineDateAndTime(now, cBreak.toString());
              }
              if (cRe != null &&
                  cRe.toString().isNotEmpty &&
                  cRe.toString() != "--:--" &&
                  _todayBreakOutTime != null) {
                _todayReentryTime ??= _combineDateAndTime(now, cRe.toString());
              }

              final recordStatus = todayRecord['status']?.toString();
              if (recordStatus != null && recordStatus.isNotEmpty) {
                _currentStatusStr = recordStatus;
              }

              if (cIn != null &&
                  cIn.toString().isNotEmpty &&
                  cIn.toString() != "--:--") {
                final inImg = (todayRecord['selfie_url'] ??
                        todayRecord['in_selfie_url'] ??
                        todayRecord['thumbnail'] ??
                        todayRecord['clock_in_image'])
                    ?.toString();
                if (inImg != null &&
                    inImg.isNotEmpty &&
                    (_todayInImageUrl == null || _todayInImageUrl!.isEmpty)) {
                  _todayInImageUrl = inImg;
                }
              }

              if (cOut != null &&
                  cOut.toString().isNotEmpty &&
                  cOut.toString() != "--:--") {
                final outImg = (todayRecord['out_selfie_url'] ??
                        todayRecord['clock_out_selfie_url'] ??
                        todayRecord['clock_out_image'] ??
                        todayRecord['out_thumbnail'])
                    ?.toString();
                if (outImg != null &&
                    outImg.isNotEmpty &&
                    (_todayOutImageUrl == null || _todayOutImageUrl!.isEmpty)) {
                  _todayOutImageUrl = outImg;
                }
              }

              if (cRe != null &&
                  cRe.toString().isNotEmpty &&
                  cRe.toString() != "--:--") {
                final reImg = todayRecord['reentry_selfie_url']?.toString();
                if (reImg != null &&
                    reImg.isNotEmpty &&
                    (_todayReentryImageUrl == null ||
                        _todayReentryImageUrl!.isEmpty)) {
                  _todayReentryImageUrl = reImg;
                }
              }

              if (cBreak != null &&
                  cBreak.toString().isNotEmpty &&
                  cBreak.toString() != "--:--") {
                final brImg = (todayRecord['break_out_selfie_url'] ??
                        todayRecord['breakout_selfie_url'])
                    ?.toString();
                if (brImg != null &&
                    brImg.isNotEmpty &&
                    (_todayBreakOutImageUrl == null ||
                        _todayBreakOutImageUrl!.isEmpty)) {
                  _todayBreakOutImageUrl = brImg;
                }
              }
            });
          }

          if (cRe != null &&
              cRe.toString().isNotEmpty &&
              cRe.toString() != "--:--" &&
              _todayBreakOutTime == null) {
            final cleanupTodayStr = DateFormat('yyyyMMdd').format(now);
            try {
              final db = await LocalDbHelper.instance.database;
              await db.delete('local_messages',
                  where: 'salesman_id = ? AND unique_id = ?',
                  whereArgs: [_salesmanId, 'sys_reentry_$cleanupTodayStr']);
              todayRecord['reentry_time'] = '';
              todayRecord['reentry_selfie_url'] = '';
              await LocalDbHelper.instance
                  .upsertTodayAttendance(_salesmanId, todayRecord);
            } catch (e) {
              debugPrint("🧹 Cleanup error: $e");
            }
          }

          if (cIn != null &&
              cIn.toString().isNotEmpty &&
              cIn.toString() != "--:--") {
            if (cOut != null &&
                cOut.toString().isNotEmpty &&
                cOut.toString() != "--:--") {
              shouldBeClockIn = true;
            } else if (cBreak != null &&
                cBreak.toString().isNotEmpty &&
                (cRe == null ||
                    cRe.toString().isEmpty ||
                    cRe.toString() == "--:--")) {
              shouldBeClockIn = true;
            } else {
              shouldBeClockIn = false;
            }
          }
        }
      } catch (e) {
        debugPrint("Offline mode check error: $e");
      }
    }

    try {
      final pendingAtts =
          await LocalDbHelper.instance.getPendingAttendance(_salesmanId);
      final todayPending = pendingAtts.where((a) {
        DateTime t = DateTime.parse(a['capture_time'].toString());
        return DateUtils.isSameDay(t, now);
      }).toList();

      todayPending
          .sort((a, b) => a['capture_time'].compareTo(b['capture_time']));

      // 🔥 FIX: Reset upload statuses here, AFTER the async database query.
      if (mounted) {
        _todayInUploadStatus = UploadStatus.success;
        _todayOutUploadStatus = UploadStatus.success;
        _todayBreakOutUploadStatus = UploadStatus.success;
        _todayReentryUploadStatus = UploadStatus.success;
      }

      for (var p in todayPending) {
        DateTime captureTime = DateTime.parse(p['capture_time'].toString());
        String? localImgPath = p['image_path']?.toString();
        String? attUid = p['attendance_uid']?.toString();
        String dbStatus = p['status']?.toString() ?? '';

        UploadStatus upStatus = UploadStatus.sending;

        if (_retryingUids.contains(attUid)) {
          upStatus = UploadStatus.sending;
        } else if (dbStatus == SyncStatus.failed.name ||
            dbStatus == 'failed' ||
            dbStatus == 'duplicate' ||
            dbStatus == 'retry_needed' ||
            dbStatus == 'pending') {
          // 🔥 FIX: Treat pending as failed to show Retry Button!
          upStatus = UploadStatus.failed;
        } else if (dbStatus == SyncStatus.synced.name || dbStatus == 'synced') {
          upStatus = UploadStatus.success;
        }

        // 🔥 FIX: Always bind the pending Uid and Status so manual retry works.
        if (p['action'] == 'clock_in') {
          _todayClockIn ??= captureTime;
          _todayInUid = attUid;
          _todayInUploadStatus = upStatus;
          if (localImgPath != null && localImgPath.isNotEmpty) {
            _todayInImageUrl ??= localImgPath;
          }
          _currentStatusStr = "Present";
          shouldBeClockIn = false;
        } else if (p['action'] == 'clock_out') {
          _todayClockOut ??= captureTime;
          _todayOutUid = attUid;
          _todayOutUploadStatus = upStatus;
          if (localImgPath != null && localImgPath.isNotEmpty) {
            _todayOutImageUrl ??= localImgPath;
          }
          if (upStatus == UploadStatus.success) {
            shouldBeClockIn = true;
          } else {
            shouldBeClockIn = false;
          }
        } else if (p['action'] == 'break_out') {
          _todayBreakOutTime ??= captureTime;
          _todayBreakOutUid = attUid;
          _todayBreakOutUploadStatus = upStatus;
          if (localImgPath != null && localImgPath.isNotEmpty) {
            _todayBreakOutImageUrl ??= localImgPath;
          }
          if (upStatus == UploadStatus.success) {
            shouldBeClockIn = true;
          }
        } else if (p['action'] == 'reentry') {
          _todayReentryTime ??= captureTime;
          _todayReentryUid = attUid;
          _todayReentryUploadStatus = upStatus;
          if (localImgPath != null && localImgPath.isNotEmpty) {
            _todayReentryImageUrl ??= localImgPath;
          }
          _todayClockOut = null;
          if (upStatus == UploadStatus.success) {
            shouldBeClockIn = false;
          }
        }
      }
    } catch (e) {
      debugPrint("Error checking pending actions for mode: $e");
    }

    await _updateNotificationFromState();

    if (mounted) {
      setState(() {
        _isClockInMode = shouldBeClockIn;
      });
    }
  }

  Future<Map<String, dynamic>?> _fetchAttendanceStatus(
      {bool forceFullSync = false}) async {
    if (_salesmanId.isEmpty) {
      return null;
    }

    DateTime? oldReentry = _todayReentryTime;
    DateTime? oldBreakOut = _todayBreakOutTime;
    String? oldReentryImg = _todayReentryImageUrl;
    String? oldBreakOutImg = _todayBreakOutImageUrl;

    try {
      final now = DateTime.now();

      final response = await http
          .post(
            Uri.parse(ApiUrl.attendance),
            body: jsonEncode({
              'action': 'get_summary',
              'salesman_id': _salesmanId,
            }),
          )
          .timeout(const Duration(seconds: 10));

      Map<String, dynamic> responseData;
      if (response.statusCode != 200 || response.body.isEmpty) {
        responseData = {'status': 'error'};
      } else {
        try {
          responseData = jsonDecode(response.body);
        } catch (_) {
          responseData = {'status': 'error'};
        }
      }

      if (responseData['status'] != 'success' || responseData['data'] == null) {
        await _determineClockInMode();
        return {
          'performance_data': null,
          'today_clock_in': _todayClockIn,
          'today_clock_out': _todayClockOut,
          'status':
              _currentStatusStr.isEmpty ? "Not Marked" : _currentStatusStr,
          'excluded_dates': <String>[],
        };
      }

      final data = responseData['data'] as Map<String, dynamic>;

      // 🔥 Admin Panel Delete Trigger logic
      final todayStr = DateFormat('yyyy-MM-dd').format(now);
      bool serverSaysDeleted =
          data['clock_in'] == null && data['attendance_status'] == "Not Marked";

      if (serverSaysDeleted) {
        bool hasTodayPending = false;
        try {
          final pendingAtts =
              await LocalDbHelper.instance.getPendingAttendance(_salesmanId);
          hasTodayPending = pendingAtts.any((p) {
            try {
              final t = DateTime.parse(p['capture_time'].toString());
              return DateUtils.isSameDay(t, now);
            } catch (_) {
              return false;
            }
          });
        } catch (_) {}

        if (!hasTodayPending) {
          // Clear History
          await LocalDbHelper.instance
              .pruneAttendanceByDate(_salesmanId, todayStr);

          // Clear Secure Storage
          await SecureStorageService.deleteKey(
              'fc_last_synced_in_$_salesmanId');
          await SecureStorageService.deleteKey(
              'fc_last_synced_out_$_salesmanId');
          await SecureStorageService.deleteKey(
              'fc_last_synced_break_out_$_salesmanId');
          await SecureStorageService.deleteKey(
              'fc_last_synced_reentry_$_salesmanId');

          // 🔥 REQUIREMENT 4 & 5: Wipe today's attendance chat bubbles, but KEEP greeting!
          try {
            final db = await LocalDbHelper.instance.database;
            await db.delete('local_messages',
                where:
                    "salesman_id = ? AND timestamp LIKE ? AND unique_id NOT LIKE 'sys_greet_%' AND unique_id NOT LIKE 'sys_date_%' AND message_type NOT LIKE '%leave%'",
                whereArgs: [_salesmanId, '$todayStr%']);
            await _persistDailyGreeting(); // Ensure Good Morning/Afternoon is preserved
            debugPrint(
                "✅ Chat bubbles successfully cleared due to Admin Deletion.");
          } catch (e) {
            debugPrint("🧹 Chat cleanup error on server delete: $e");
          }

          // Reset Variables
          _todayClockIn = null;
          _todayClockOut = null;
          _todayBreakOutTime = null;
          _todayReentryTime = null;
          _todayInImageUrl = null;
          _todayOutImageUrl = null;
          _todayBreakOutImageUrl = null;
          _todayReentryImageUrl = null;
          _resumeCount = 0;
          _currentStatusStr = "Not Marked";

          await _determineClockInMode();
          await _updateNotificationFromState();

          if (mounted) {
            _triggerChatBuild();
          }

          return {
            'performance_data': null,
            'today_clock_in': null,
            'today_clock_out': null,
            'status': "Not Marked",
            'excluded_dates': <String>[],
          };
        }
      }

      final savedInImageUrl = _todayInImageUrl;
      final savedOutImageUrl = _todayOutImageUrl;
      final savedBreakOutImageUrl = _todayBreakOutImageUrl;
      final savedReentryImageUrl = _todayReentryImageUrl;
      _currentStatusStr = data['attendance_status'] ?? "Not Marked";

      bool hasUnsyncedClockIn = false;
      try {
        final pendingAtts =
            await LocalDbHelper.instance.getPendingAttendance(_salesmanId);
        hasUnsyncedClockIn = pendingAtts.any((p) {
          final action = p['action']?.toString() ?? '';
          final status = p['status']?.toString() ?? '';
          final isTodayRecord = () {
            try {
              final t = DateTime.parse(p['capture_time'].toString());
              return DateUtils.isSameDay(t, now);
            } catch (_) {
              return false;
            }
          }();
          return isTodayRecord &&
              action == 'clock_in' &&
              (status == 'pending' ||
                  status == 'failed' ||
                  status == 'retry_needed' ||
                  status == 'duplicate');
        });
      } catch (_) {}

      // 🔥 FIX 1: Admin Panel-ல் Clock In அழிக்கப்பட்டால் லோக்கலிலும் அழிக்க வேண்டும் (Ghost Bubble Issue Fix)
      if (data['clock_in'] != null) {
        if (!hasUnsyncedClockIn) {
          _todayClockIn = _combineDateAndTime(now, data['clock_in'].toString());
          if (_todayClockIn != null) {
            await SecureStorageService.writeString(
                'fc_last_synced_in_$_salesmanId',
                _todayClockIn!.toIso8601String());
          }
        }
      } else {
        if (!hasUnsyncedClockIn) {
          _todayClockIn = null;
          await SecureStorageService.deleteKey(
              'fc_last_synced_in_$_salesmanId');
          try {
            await LocalDbHelper.instance
                .deleteMessagesByPrefix(_salesmanId, 'clock_in_$todayStr');
            await LocalDbHelper.instance
                .deleteMessagesByPrefix(_salesmanId, 'sys_welcome_$todayStr');
            await LocalDbHelper.instance
                .deleteMessagesByPrefix(_salesmanId, 'sys_late_$todayStr');
          } catch (e) {
            debugPrint("Failed to delete stale clock_in messages: $e");
          }
        } else {
          debugPrint(
              "⚠️ Server has no clock_in but local pending records exist — preserving for sync retry.");
        }
      }

      final serverInImg = data['selfie_url']?.toString();
      final serverOutImg = data['clock_out_selfie_url']?.toString();
      final serverReentryImg =
          (data['reentry_selfie_url'] ?? data['reentry_image'])?.toString();
      final serverBreakOutImg = (data['break_out_selfie_url'] ??
              data['breakout_selfie_url'] ??
              data['clock_out_selfie_url'])
          ?.toString();

      int rawResumeCount =
          int.tryParse(data['resume_count']?.toString() ?? "0") ?? 0;
      _resumeCount = (serverReentryImg == null || serverReentryImg.isEmpty)
          ? 0
          : rawResumeCount;

      bool hasUnsyncedClockOut = false;
      try {
        final pendingAtts =
            await LocalDbHelper.instance.getPendingAttendance(_salesmanId);
        hasUnsyncedClockOut = pendingAtts.any((p) {
          final action = p['action']?.toString() ?? '';
          final status = p['status']?.toString() ?? '';
          final isTodayRecord = () {
            try {
              final t = DateTime.parse(p['capture_time'].toString());
              return DateUtils.isSameDay(t, now);
            } catch (_) {
              return false;
            }
          }();
          return isTodayRecord &&
              (action == 'clock_out' || action == 'break_out') &&
              (status == 'pending' ||
                  status == 'failed' ||
                  status == 'retry_needed' ||
                  status == 'duplicate');
        });
      } catch (_) {}

      if (data['clock_out'] != null && _resumeCount == 0) {
        if (!hasUnsyncedClockOut) {
          _todayClockOut =
              _combineDateAndTime(now, data['clock_out'].toString());
          if (_todayClockOut != null) {
            await SecureStorageService.writeString(
                'fc_last_synced_out_$_salesmanId',
                _todayClockOut!.toIso8601String());
          }
        }
      } else {
        if (!hasUnsyncedClockOut) {
          _todayClockOut = null;
          _todayBreakOutTime = null;

          await SecureStorageService.deleteKey(
              'fc_last_synced_out_$_salesmanId');
          try {
            await LocalDbHelper.instance
                .deleteMessagesByPrefix(_salesmanId, 'clock_out_$todayStr');
            await LocalDbHelper.instance
                .deleteMessagesByPrefix(_salesmanId, 'sys_bye_$todayStr');
            await LocalDbHelper.instance
                .deleteMessagesByPrefix(_salesmanId, 'break_out_$todayStr');
            await LocalDbHelper.instance
                .deleteMessagesByPrefix(_salesmanId, 'sys_break_$todayStr');
          } catch (e) {
            debugPrint("Failed to delete stale out messages: $e");
          }
        } else {
          debugPrint(
              "⚠️ Server has no clock_out but local pending records exist — preserving for sync retry.");
        }
      }

      bool hasUnsyncedReentry = false;
      try {
        final pendingAtts =
            await LocalDbHelper.instance.getPendingAttendance(_salesmanId);
        hasUnsyncedReentry = pendingAtts.any((p) {
          final action = p['action']?.toString() ?? '';
          final status = p['status']?.toString() ?? '';
          final isTodayRecord = () {
            try {
              final t = DateTime.parse(p['capture_time'].toString());
              return DateUtils.isSameDay(t, now);
            } catch (_) {
              return false;
            }
          }();

          bool isReentryAction = (action == 'reentry');
          if (action == 'clock_in' && _todayClockIn != null) {
            try {
              DateTime captureTime =
                  DateTime.parse(p['capture_time'].toString());
              if (captureTime
                  .isAfter(_todayClockIn!.add(const Duration(minutes: 2)))) {
                isReentryAction = true;
              }
            } catch (_) {}
          }

          return isTodayRecord &&
              isReentryAction &&
              (status == 'pending' ||
                  status == 'failed' ||
                  status == 'retry_needed' ||
                  status == 'duplicate');
        });
      } catch (_) {}

      if (serverReentryImg == null || serverReentryImg.isEmpty) {
        if (!hasUnsyncedReentry) {
          _todayReentryTime = null;
          _todayReentryImageUrl = null;

          await SecureStorageService.deleteKey(
              'fc_last_synced_reentry_$_salesmanId');
          try {
            await LocalDbHelper.instance
                .deleteMessagesByPrefix(_salesmanId, 'reentry_$todayStr');
            await LocalDbHelper.instance
                .deleteMessagesByPrefix(_salesmanId, 'sys_reentry_$todayStr');

            if (_todayClockIn != null) {
              final pending = await LocalDbHelper.instance
                  .getPendingAttendance(_salesmanId);
              for (var p in pending) {
                if (p['action'] == 'clock_in') {
                  DateTime msgTime =
                      DateTime.parse(p['capture_time'].toString());
                  if (msgTime.isAfter(
                      _todayClockIn!.add(const Duration(minutes: 2)))) {
                    await LocalDbHelper.instance
                        .deletePendingAttendance(p['local_id']);
                  }
                }
              }
            }
          } catch (e) {
            debugPrint("Failed to delete stale reentry messages: $e");
          }
        } else {
          debugPrint(
              "⚠️ Server has no reentry but local pending records exist — preserving for sync retry.");
        }
      } else {
        await SecureStorageService.writeString(
            'fc_last_synced_reentry_$_salesmanId', serverReentryImg);
      }

      _todayInImageUrl = (serverInImg != null && serverInImg.isNotEmpty)
          ? serverInImg
          : savedInImageUrl;
      _todayOutImageUrl = (serverOutImg != null && serverOutImg.isNotEmpty)
          ? serverOutImg
          : savedOutImageUrl;
      _todayReentryImageUrl =
          (serverReentryImg != null && serverReentryImg.isNotEmpty)
              ? serverReentryImg
              : savedReentryImageUrl;
      _todayBreakOutImageUrl =
          (serverBreakOutImg != null && serverBreakOutImg.isNotEmpty)
              ? serverBreakOutImg
              : savedBreakOutImageUrl;

      if (data['showroom_name'] != null) {
        _showroomName = data['showroom_name'].toString();
      }

      _currentStatusStr = data['attendance_status'] ?? "Not Marked";
      _holidayReason = data['holiday_reason']?.toString();

      if (data['last_action_time'] != null) {
        String timeStr = data['last_action_time'].toString();
        _lastActionTime = DateTime.tryParse(timeStr.replaceAll(' ', 'T'));
      }

      if (data['custom_late_cutoff'] != null) {
        _customLateCutoff = data['custom_late_cutoff'].toString();
        await SecureStorageService.saveCustomLateCutoff(_customLateCutoff!);
      }

      if (_todayClockIn != null) {
        if (_resumeCount > 0) {
          DateTime safeBreakOut =
              _todayClockIn!.add(const Duration(seconds: 1));
          DateTime safeReEntry = _todayClockIn!.add(const Duration(seconds: 2));

          if (_todayClockOut != null) {
            final diffSeconds =
                _todayClockOut!.difference(_todayClockIn!).inSeconds;
            if (diffSeconds > 3) {
              safeBreakOut =
                  _todayClockIn!.add(Duration(seconds: diffSeconds ~/ 3));
              safeReEntry =
                  _todayClockIn!.add(Duration(seconds: (diffSeconds ~/ 3) * 2));
            }
          }

          _todayReentryTime = oldReentry ?? safeReEntry;
          _todayReentryImageUrl = oldReentryImg ?? _todayReentryImageUrl;
          _todayBreakOutTime = oldBreakOut ?? safeBreakOut;
          _todayBreakOutImageUrl = oldBreakOutImg ?? savedBreakOutImageUrl;

          _todayClockOut = null;
          _todayOutImageUrl = null;
        }
      }

      await _updateNotificationFromState();
      await _determineClockInMode();

      if (_isInternetConnected && data['attendance_rate'] != null) {
        final pData = <String, dynamic>{
          'attendance_percentage':
              data['attendance_rate'].toString().replaceAll('%', ''),
          'total_working_hours': data['month_hours']?.toString() ?? '0h 0m',
          'weekly_working_hours': data['week_hours']?.toString() ?? '0h 0m',
          'total_worked_days': data['total_worked_days']?.toString() ?? '0',
          'total_days_consumed': data['total_leaves_used']?.toString() ?? '0',
          'total_present': data['total_present'] ?? 0,
          'total_absent': data['total_absent'] ?? 0,
          'total_half_days': data['total_half_days'] ?? 0,
          'total_full_leaves': data['total_full_leaves'] ?? 0,
          'report_month': DateFormat('yyyy-MM').format(now),
          'salesman_id': _salesmanId,
        };

        if (data['excluded_dates'] != null && data['excluded_dates'] is List) {
          _excludedDates = (data['excluded_dates'] as List)
              .map((e) => e.toString())
              .toList();
        }

        await LocalDbHelper.instance
            .insertPerformanceSummary(_salesmanId, pData);
        _updatePerformanceState(pData);
      }

      await _cleanupLocalPendingRecords();
      await _saveTodayToLocalHistory();

      return {
        'performance_data':
            await LocalDbHelper.instance.getPerformanceSummary(_salesmanId),
        'today_clock_in': _todayClockIn,
        'today_clock_out': _todayClockOut,
        'status': _currentStatusStr,
        'excluded_dates': _excludedDates,
      };
    } catch (e, stackTrace) {
      debugPrint("Status Error: $e\n$stackTrace");
      await _determineClockInMode();
      return null;
    }
  }

  Future<void> _fetchAttendanceHistory({
    int limit = 30,
    String? beforeDate,
    bool isLoadMore = false,
    bool background = false,
    bool forceFullSync = false,
  }) async {
    if (_salesmanId.isEmpty) return;
    try {
      if (forceFullSync) {
        await LocalDbHelper.instance
            .setLastSyncTimestamp('attendance_$_salesmanId', null);
      }

      final responses = await Future.wait([
        http
            .post(
              Uri.parse(ApiUrl.attendance),
              body: jsonEncode({
                'action': 'get_history',
                'salesman_id': _salesmanId,
              }),
            )
            .timeout(const Duration(seconds: 15)),
        http
            .post(
              Uri.parse(ApiUrl.lunch),
              body: jsonEncode({
                'action': 'get_lunch_history',
                'salesman_id': _salesmanId,
              }),
            )
            .timeout(const Duration(seconds: 15))
            .catchError((_) => http.Response('{"status":"error"}', 500)),
      ]);

      final response = responses[0];
      final lunchResponse = responses[1];

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        Map<String, dynamic> responseData;
        try {
          responseData = jsonDecode(response.body);
        } catch (_) {
          responseData = {'status': 'error'};
        }

        if (responseData['status'] == 'success') {
          List<dynamic> historyData = responseData['data'] ?? [];

          Map<String, dynamic> lunchDataMap = {};
          if (lunchResponse.statusCode == 200 &&
              lunchResponse.body.isNotEmpty) {
            try {
              final lData = jsonDecode(lunchResponse.body);
              if (lData['status'] == 'success' && lData['data'] != null) {
                for (var item in lData['data']) {
                  if (item['date'] != null) {
                    lunchDataMap[item['date']] = item;
                  }
                }
              }
            } catch (_) {}
          }

          List<Map<String, dynamic>> serverHistory = historyData.map((e) {
            Map<String, dynamic> d = Map<String, dynamic>.from(e);
            d['id'] = d['id']?.toString() ?? '';
            String originalDateStr = d['date'] ?? '';
            if (originalDateStr.contains('T')) {
              d['date'] = originalDateStr.split('T')[0];
            } else if (originalDateStr.contains(' ')) {
              d['date'] = originalDateStr.split(' ')[0];
            }

            if (lunchDataMap.containsKey(d['date'])) {
              final l = lunchDataMap[d['date']];
              d['lunch_in_time'] = l['lunch_in_time'];
              d['lunch_out_time'] = l['lunch_out_time'];
              d['lunch_in_selfie_url'] = l['lunch_in_selfie_url'];
              d['lunch_out_selfie_url'] = l['lunch_out_selfie_url'];
              d['lunch_extra_break_display'] = l['extra_break_display'];
            }

            return d;
          }).toList();

          if (responseData['monthly_performance'] != null) {
            List<dynamic> perfList = responseData['monthly_performance'];
            List<Map<String, dynamic>> perfConfigs = [];
            for (var perf in perfList) {
              perfConfigs.add(Map<String, dynamic>.from(perf));
            }
            if (mounted) {
              setState(() {
                _monthlyPerformanceList = perfConfigs;
              });
            }
          }

          final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
          bool hasTodayPending = false;
          try {
            final pendingAtts =
                await LocalDbHelper.instance.getPendingAttendance(_salesmanId);
            hasTodayPending = pendingAtts.any((p) {
              try {
                final t = DateTime.parse(p['capture_time'].toString());
                return DateUtils.isSameDay(t, DateTime.now());
              } catch (_) {
                return false;
              }
            });
          } catch (_) {}

          if (hasTodayPending) {
            serverHistory.removeWhere(
                (r) => r['date']?.toString().startsWith(todayStr) == true);
          }

          if (isLoadMore) {
            await LocalDbHelper.instance
                .insertOlderAttendanceRecords(_salesmanId, serverHistory);
            if (mounted) setState(() => _hasMoreHistory = false);
          } else {
            final allPending =
                await LocalDbHelper.instance.getPendingAttendance(_salesmanId);
            if (forceFullSync && allPending.isEmpty) {
              await LocalDbHelper.instance
                  .clearAndInsertAttendanceHistory(_salesmanId, serverHistory);
            } else {
              await LocalDbHelper.instance.syncAttendanceHistory(
                  _salesmanId, serverHistory,
                  maxRecords: 1000);
            }
          }

          if (mounted) {
            await _loadHistoryFromSQLite();
            _triggerChatBuild();
          }
        }
      }
    } catch (e, stackTrace) {
      debugPrint("Fetch Attendance History Error from MySQL: $e\n$stackTrace");
    } finally {
      if (mounted) {
        setState(() {
          _isHistoryLoading = false;
        });
      }
    }
  }

  DateTime? _parseDateSafely(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return null;
    try {
      if (dateStr.contains('-')) {
        return DateFormat('yyyy-MM-dd').parse(dateStr);
      } else {
        return DateFormat('dd MMM yyyy').parse(dateStr);
      }
    } catch (_) {
      return null;
    }
  }

  DateTime? _parseFullDateTimeSafely(String? dtStr) {
    if (dtStr == null || dtStr.trim().isEmpty || dtStr == "null") return null;
    try {
      return DateTime.parse(dtStr);
    } catch (e) {
      try {
        return DateFormat('yyyy-MM-dd HH:mm:ss').parse(dtStr);
      } catch (_) {
        try {
          if (dtStr.contains(" at ")) {
            final clean = dtStr.split(RegExp(r'UTC|GMT'))[0].trim();
            final parts = clean.split(" at ");
            return DateFormat('dd MMMM yyyy HH:mm:ss')
                .parse("${parts[0].trim()} ${parts[1].trim()}");
          }
        } catch (_) {}
        return null;
      }
    }
  }

  DateTime? _combineDateAndTime(DateTime date, String timeStr) {
    if (timeStr.isEmpty || timeStr == "--:--" || timeStr == "null") return null;
    try {
      if (timeStr.contains('-')) return DateTime.parse(timeStr);

      DateTime? pt;

      if (timeStr.toUpperCase().contains('AM') ||
          timeStr.toUpperCase().contains('PM')) {
        try {
          pt = DateFormat('hh:mm:ss a').parse(timeStr);
        } catch (_) {
          try {
            pt = DateFormat('hh:mm a').parse(timeStr);
          } catch (_) {}
        }
      }

      if (pt == null) {
        try {
          pt = DateFormat('HH:mm:ss').parse(timeStr);
        } catch (_) {
          try {
            pt = DateFormat('HH:mm').parse(timeStr);
          } catch (_) {}
        }
      }

      if (pt == null) return null;
      return DateTime(
          date.year, date.month, date.day, pt.hour, pt.minute, pt.second);
    } catch (e) {
      return null;
    }
  }

  void _triggerChatBuild() {
    _rebuildTimer?.cancel();
    _rebuildTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        _buildChatFromStatus();
      }
    });
  }

  Future<void> _updateNotificationFromState() async {
    String notifInTime = '--:--';

    if (_todayClockIn != null) {
      notifInTime = DateFormat('hh:mm a').format(_todayClockIn!);
    } else {
      if (_currentStatusStr.toLowerCase() == 'absent') {
        notifInTime = 'Absent';
      } else if (_currentStatusStr.toLowerCase().contains('leave')) {
        notifInTime = 'Leave';
      } else if (_currentStatusStr.toLowerCase().contains('holiday')) {
        notifInTime = 'Holiday';
      }
    }

    final String notifOutTime = (_isClockInMode && _todayClockOut != null)
        ? DateFormat('hh:mm a').format(_todayClockOut!)
        : '--:--';

    try {
      await SecureStorageService.writeString(
          'saved_notification_date_$_salesmanId',
          DateFormat('yyyy-MM-dd').format(DateTime.now()));
      await SecureStorageService.writeString(
          'saved_in_time_$_salesmanId', notifInTime);
      await SecureStorageService.writeString(
          'saved_out_time_$_salesmanId', notifOutTime);

      FlutterBackgroundService().invoke('update_notification_times', {
        'in_time': notifInTime,
        'out_time': notifOutTime,
      });
    } catch (e) {
      debugPrint("Notification update error: $e");
    }
  }

  Future<void> _buildChatFromStatus() async {
    if (_isBuildingChat) {
      _needsRebuild = true;
      return;
    }
    _isBuildingChat = true;
    _needsRebuild = false;

    try {
      final List<AttendanceChatMessage> newChatMessages = [];
      final Set<String> processedIds = {};
      final Set<String> processedContentKeys = {};

      void addUnique(AttendanceChatMessage msg) {
        String contentKey = "";
        if (msg.type == ChatMessageType.system ||
            msg.type == ChatMessageType.dateHeader) {
          final datePrefix = DateFormat('yyyy-MM-dd').format(msg.timestamp);
          contentKey = "${msg.type}_${datePrefix}_${msg.text.trim()}";
        } else if (msg.type == ChatMessageType.clockIn ||
            msg.type == ChatMessageType.clockOut ||
            msg.type == ChatMessageType.leaveRequest ||
            msg.type == ChatMessageType.reEntry) {
          contentKey =
              "${msg.type}_${msg.timestamp.millisecondsSinceEpoch ~/ 1000}";
        }

        if (_resumeCount > 0 &&
            DateUtils.isSameDay(msg.timestamp, DateTime.now())) {
          if (msg.type == ChatMessageType.clockOut ||
              (msg.type == ChatMessageType.clockIn &&
                  _todayReentryTime != null)) {
            return;
          }
        }

        bool idExists = processedIds.contains(msg.id);
        bool contentExists =
            contentKey.isNotEmpty && processedContentKeys.contains(contentKey);

        if (!idExists && !contentExists) {
          newChatMessages.add(msg);
          processedIds.add(msg.id);
          if (contentKey.isNotEmpty) {
            processedContentKeys.add(contentKey);
          }
        }
      }

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final todayStr1 = DateFormat('yyyy-MM-dd').format(now);

      final localDataFutures = await Future.wait([
        SecureStorageService.readString(
            'leave_balance_msg_${_salesmanId}_${DateFormat('yyyy-MM').format(now)}'),
        LocalDbHelper.instance.getPendingAttendance(_salesmanId),
        LocalDbHelper.instance.getMessages(_salesmanId),
      ]);

      final String? savedLeaveBalance = localDataFutures[0] as String?;
      final List<Map<String, dynamic>> pendingAttsBatch =
          localDataFutures[1] as List<Map<String, dynamic>>;
      final List<Map<String, dynamic>> localMsgsBatch =
          localDataFutures[2] as List<Map<String, dynamic>>;

      Set<String> localLeaveDocIds = {};
      Set<String> localSysDocIds = {};
      Map<DateTime, List<Map<String, dynamic>>> dailyRecords = {};

      for (var msg in localMsgsBatch) {
        DateTime? d;
        try {
          d = DateTime.parse(msg['timestamp']?.toString() ?? '');
        } catch (_) {
          d = _parseDateSafely(msg['timestamp']?.toString()) ??
              _combineDateAndTime(now, msg['timestamp']?.toString() ?? "");
        }
        d ??= now;
        final dateOnly = DateTime(d.year, d.month, d.day);

        final bool isLeave =
            msg['message_type']?.toString().toLowerCase() == 'leave' ||
                msg['message_type'] == 'leave_request';
        final bool isSystem =
            msg['message_type']?.toString().toLowerCase() == 'system';

        String msgText = msg['message_text']?.toString() ?? "";

        if (dateOnly.isAtSameMomentAs(today)) {
          if (msgText.contains('Status:') || msgText.contains('Status :')) {
            msgText = msgText.replaceAll(
                RegExp(r'Status\s*:\s*.*'), 'Status : $_currentStatusStr');
          }
        }

        bool isAttendanceRelatedLocalMessage = msgText.contains('Clock In') ||
            msgText.contains('Clock Out') ||
            msgText.contains('Re-Entry') ||
            msgText.contains('Status :') ||
            msgText.contains('Status:') ||
            msgText.contains('இன்றைய பணி ஆரம்பம்') ||
            msgText.contains('இனிதே நிறைவடைந்தது') ||
            msgText.contains('மீண்டும் வேலைக்கு') ||
            msgText.contains('இந்த மாதம் Leave Status:') ||
            (msg['unique_id']?.toString().startsWith('sys_') ?? false);

        if (isAttendanceRelatedLocalMessage && !isLeave) {
          continue;
        }

        String? leaveType;
        DateTime? leaveDate;
        String? reason;
        String? docId;

        if (msg['payload'] != null && msg['payload'].toString().isNotEmpty) {
          try {
            final p = jsonDecode(msg['payload'].toString());
            leaveType = p['leave_type'];
            reason = p['reason'];
            docId = (p['doc_id'] ?? p['holiday_id'])?.toString();
            if (p['leave_date'] != null) {
              leaveDate = DateTime.parse(p['leave_date']);
            }
          } catch (e) {
            debugPrint('Payload parse error: $e');
          }
        }

        if (docId != null) {
          if (isLeave) localLeaveDocIds.add(docId.toString());
          if (isSystem) localSysDocIds.add(docId.toString());
        }

        LeaveStatus ls = LeaveStatus.none;
        if (isLeave) {
          ls = LeaveStatus.pending;
          if (msg['status'] != null) {
            String s = msg['status'].toString().toLowerCase();
            if (s == 'approved') ls = LeaveStatus.approved;
            if (s == 'rejected') ls = LeaveStatus.rejected;
          }
        }

        if (dateOnly.isBefore(today)) {
          dailyRecords.putIfAbsent(dateOnly, () => []).add({
            'source': 'local_message',
            'data': msg,
            'time': d,
            'leaveType': leaveType,
            'leaveDate': leaveDate,
            'reason': reason,
            'ls': ls
          });
        } else {
          addUnique(AttendanceChatMessage(
              id: msg['unique_id']?.toString() ??
                  "local_msg_${msg['local_id']}",
              type: isLeave
                  ? ChatMessageType.leaveRequest
                  : (msgText.contains('Clock In')
                      ? ChatMessageType.clockIn
                      : (msgText.contains('Clock Out')
                          ? ChatMessageType.clockOut
                          : ChatMessageType.system)),
              text: msgText,
              timestamp: d,
              isSentByMe: msg['message_type'] == 'user' || isLeave,
              leaveType: leaveType,
              leaveStartDate: leaveDate,
              leaveReason: reason,
              leaveStatus: ls,
              uploadStatus: msg['status'] == 'pending_upload'
                  ? UploadStatus.sending
                  : UploadStatus.success));
        }
      }

      addUnique(AttendanceChatMessage(
          id: "sys_date_$todayStr1",
          type: ChatMessageType.dateHeader,
          text: "Today",
          timestamp: today,
          isSentByMe: false));

      if (savedLeaveBalance != null && savedLeaveBalance.isNotEmpty) {
        addUnique(AttendanceChatMessage(
            id: "sys_leave_bal_$todayStr1",
            type: ChatMessageType.system,
            text: "📋 இந்த மாதம் Leave Status:\n$savedLeaveBalance",
            timestamp:
                DateTime(now.year, now.month, now.day, now.hour, now.minute, 1),
            isSentByMe: false));
      }

      if (_currentStatusStr.contains('Holiday')) {
        addUnique(AttendanceChatMessage(
            id: "sys_holiday_$todayStr1",
            type: ChatMessageType.system,
            text:
                "🎉 இன்று ${_holidayReason ?? 'Holiday'} விடுமுறை நாள்!\nஓய்வெடுங்கள், Attendance கட்டாயமில்லை.",
            timestamp: today,
            isSentByMe: false));
      }

      if (_todayClockIn != null &&
          _todayReentryTime == null &&
          _resumeCount == 0) {
        final String resolvedInUrl =
            _resolvePhotoUrl(_todayInImageUrl, todayStr1);
        final bool isLocalIn = (resolvedInUrl.startsWith('/') ||
            resolvedInUrl.startsWith('file://') ||
            resolvedInUrl.contains('/storage/') ||
            RegExp(r'^[a-zA-Z]:[/\\]').hasMatch(resolvedInUrl));

        bool isLocalInPending =
            pendingAttsBatch.any((p) => p['action'] == 'clock_in');

        addUnique(AttendanceChatMessage(
            id: "clock_in_$todayStr1",
            type: ChatMessageType.clockIn,
            text:
                "Clock In : ${DateFormat('hh:mm:ss a').format(_todayClockIn!)}\nStatus : $_currentStatusStr",
            timestamp: _todayClockIn!,
            isSentByMe: true,
            imageUrl: isLocalIn ? null : resolvedInUrl,
            imagePath: isLocalIn ? resolvedInUrl : null,
            uploadStatus:
                isLocalInPending ? _todayInUploadStatus : UploadStatus.success,
            attendanceStatus: _currentStatusStr,
            attendanceUid: _todayInUid));

        if (isLocalIn ? _todayInUploadStatus == UploadStatus.success : true) {
          addUnique(AttendanceChatMessage(
              id: "sys_welcome_$todayStr1",
              type: ChatMessageType.system,
              text:
                  "வணக்கம்! இன்றைய பணி ஆரம்பம். 💪\nStatus: $_currentStatusStr",
              timestamp: _todayClockIn!.add(const Duration(seconds: 1)),
              isSentByMe: false));

          final lateMsg = GreetingHelper.getLateClockInMessage(
            _todayClockIn!,
            customCutoff: _customLateCutoff,
          );
          if (lateMsg != null) {
            addUnique(AttendanceChatMessage(
              id: "sys_late_$todayStr1",
              type: ChatMessageType.system,
              text: lateMsg,
              timestamp: _todayClockIn!.add(const Duration(seconds: 2)),
              isSentByMe: false,
            ));
          }
        }
      } else if (_currentStatusStr.toLowerCase() == 'absent') {
        DateTime tTime = today.add(const Duration(hours: 10, minutes: 15));
        if (tTime.isAfter(DateTime.now())) tTime = DateTime.now();
        addUnique(AttendanceChatMessage(
            id: "sys_absent_$todayStr1",
            type: ChatMessageType.system,
            text: "⚠️ வருகை பதிவு செய்யப்படவில்லை. Status: Absent",
            timestamp: tTime,
            isSentByMe: false));
      } else if (_currentStatusStr.toLowerCase() == 'on leave' ||
          _currentStatusStr.toLowerCase() == 'leave') {
        DateTime tTime = today.add(const Duration(hours: 10, minutes: 15));
        if (tTime.isAfter(DateTime.now())) tTime = DateTime.now();
        addUnique(AttendanceChatMessage(
            id: "sys_leave_$todayStr1",
            type: ChatMessageType.system,
            text: "📋 விடுப்பு (Leave) எடுக்கப்பட்டுள்ளது.",
            timestamp: tTime,
            isSentByMe: false));
      }

      if (_todayClockIn == null &&
          !_currentStatusStr.toLowerCase().contains('leave') &&
          !_currentStatusStr.toLowerCase().contains('holiday') &&
          (now.hour > _clockInLimitHour ||
              (now.hour == _clockInLimitHour &&
                  now.minute > _clockInLimitMinute)) &&
          !_allowLateEntry) {
        int displayHour = _clockInLimitHour > 12
            ? _clockInLimitHour - 12
            : _clockInLimitHour == 0
                ? 12
                : _clockInLimitHour;
        String amPm = _clockInLimitHour >= 12 ? 'PM' : 'AM';
        String minStr = _clockInLimitMinute.toString().padLeft(2, '0');
        addUnique(AttendanceChatMessage(
            id: "sys_time_exceeded_$todayStr1",
            type: ChatMessageType.system,
            text:
                "❌ நேரம் முடிந்துவிட்டது ($displayHour:$minStr $amPm). உங்களால் வருகை பதிவு செய்ய முடியாது. Admin-ஐ தொடர்பு கொள்ளவும்.",
            timestamp: today.add(Duration(
                hours: _clockInLimitHour, minutes: _clockInLimitMinute + 5)),
            isSentByMe: false));
      }

      if (_todayBreakOutTime != null && _todayReentryTime == null) {
        final String resolvedBreakUrl =
            _resolvePhotoUrl(_todayBreakOutImageUrl, todayStr1);
        final bool isLocalBreak = (resolvedBreakUrl.startsWith('/') ||
            resolvedBreakUrl.startsWith('file://') ||
            resolvedBreakUrl.contains('/data/') ||
            resolvedBreakUrl.contains('/storage/') ||
            RegExp(r'^[a-zA-Z]:[/\\]').hasMatch(resolvedBreakUrl));

        bool isLocalBreakPending =
            pendingAttsBatch.any((p) => p['action'] == 'break_out');

        addUnique(AttendanceChatMessage(
            id: "break_out_$todayStr1",
            type: ChatMessageType.clockOut,
            text:
                "Clock Out : ${DateFormat('hh:mm:ss a').format(_todayBreakOutTime!)}\nStatus : $_currentStatusStr",
            timestamp: _todayBreakOutTime!,
            isSentByMe: true,
            imageUrl: isLocalBreak ? null : resolvedBreakUrl,
            imagePath: isLocalBreak ? resolvedBreakUrl : null,
            uploadStatus: isLocalBreakPending
                ? _todayBreakOutUploadStatus
                : UploadStatus.success,
            attendanceStatus: _currentStatusStr,
            attendanceUid: _todayBreakOutUid));

        if (isLocalBreak
            ? _todayBreakOutUploadStatus == UploadStatus.success
            : true) {
          addUnique(AttendanceChatMessage(
              id: "sys_break_$todayStr1",
              type: ChatMessageType.system,
              text: GreetingHelper.getOutTimeGreeting(
                  _todayClockIn, _todayBreakOutTime!, _currentStatusStr),
              timestamp: _todayBreakOutTime!.add(const Duration(seconds: 1)),
              isSentByMe: false));
        }
      }

      if (_todayReentryTime != null) {
        String clockInTimeStr = _todayClockIn != null
            ? DateFormat('hh:mm:ss a').format(_todayClockIn!)
            : "--:--";
        final String resolvedReentryUrl =
            _resolvePhotoUrl(_todayReentryImageUrl, todayStr1);
        final bool isLocalReentry = (resolvedReentryUrl.startsWith('/') ||
            resolvedReentryUrl.startsWith('file://') ||
            resolvedReentryUrl.contains('/data/') ||
            resolvedReentryUrl.contains('/storage/') ||
            RegExp(r'^[a-zA-Z]:[/\\]').hasMatch(resolvedReentryUrl));

        bool isLocalReentryPending =
            pendingAttsBatch.any((p) => p['action'] == 'reentry');

        addUnique(AttendanceChatMessage(
            id: "reentry_$todayStr1",
            type: ChatMessageType.reEntry,
            text:
                "Re-Entry : ${DateFormat('hh:mm:ss a').format(_todayReentryTime!)}\nClock In : $clockInTimeStr\nStatus : $_currentStatusStr",
            timestamp: _todayReentryTime!,
            isSentByMe: true,
            imageUrl: isLocalReentry ? null : resolvedReentryUrl,
            imagePath: isLocalReentry ? resolvedReentryUrl : null,
            uploadStatus: isLocalReentryPending
                ? _todayReentryUploadStatus
                : UploadStatus.success,
            attendanceStatus: _currentStatusStr,
            attendanceUid: _todayReentryUid));

        if (isLocalReentry
            ? _todayReentryUploadStatus == UploadStatus.success
            : true) {
          addUnique(AttendanceChatMessage(
              id: "sys_reentry_$todayStr1",
              type: ChatMessageType.system,
              text:
                  "மீண்டும் வேலைக்கு திரும்பியமைக்கு நன்றி! 💪\nStatus: $_currentStatusStr",
              timestamp: _todayReentryTime!.add(const Duration(seconds: 1)),
              isSentByMe: false));
        }
      }

      if (_todayClockOut != null && _resumeCount == 0) {
        final String resolvedOutUrl =
            _resolvePhotoUrl(_todayOutImageUrl, todayStr1);
        final bool isLocalOut = (resolvedOutUrl.startsWith('/') ||
            resolvedOutUrl.startsWith('file://') ||
            resolvedOutUrl.contains('/data/') ||
            resolvedOutUrl.contains('/storage/') ||
            RegExp(r'^[a-zA-Z]:[/\\]').hasMatch(resolvedOutUrl));

        bool isLocalOutPending =
            pendingAttsBatch.any((p) => p['action'] == 'clock_out');

        addUnique(AttendanceChatMessage(
            id: "clock_out_$todayStr1",
            type: ChatMessageType.clockOut,
            text:
                "Clock Out : ${DateFormat('hh:mm:ss a').format(_todayClockOut!)}\nStatus : $_currentStatusStr",
            timestamp: _todayClockOut!,
            isSentByMe: true,
            imageUrl: isLocalOut ? null : resolvedOutUrl,
            imagePath: isLocalOut ? resolvedOutUrl : null,
            uploadStatus: isLocalOutPending
                ? _todayOutUploadStatus
                : UploadStatus.success,
            attendanceStatus: _currentStatusStr,
            attendanceUid: _todayOutUid));

        if (isLocalOut ? _todayOutUploadStatus == UploadStatus.success : true) {
          addUnique(AttendanceChatMessage(
              id: "sys_bye_$todayStr1",
              type: ChatMessageType.system,
              text: GreetingHelper.getOutTimeGreeting(
                  _todayClockIn, _todayClockOut!, _currentStatusStr),
              timestamp: _todayClockOut!.add(const Duration(seconds: 1)),
              isSentByMe: false));
        }
      }

      for (var att in pendingAttsBatch) {
        DateTime msgTime = DateTime.parse(att['capture_time'].toString());
        if (DateUtils.isSameDay(msgTime, today)) {
          bool alreadyCovered = false;
          if (att['action'] == 'clock_in' && _todayClockIn == msgTime) {
            alreadyCovered = true;
          }
          if (att['action'] == 'clock_out' && _todayClockOut == msgTime) {
            alreadyCovered = true;
          }
          if (att['action'] == 'reentry' && _todayReentryTime == msgTime) {
            alreadyCovered = true;
          }
          if (att['action'] == 'break_out' && _todayBreakOutTime == msgTime) {
            alreadyCovered = true;
          }
          if (alreadyCovered) continue;

          bool isPendingReentry = att['action'] == 'reentry' ||
              (att['action'] == 'clock_in' &&
                  _todayClockIn != null &&
                  msgTime
                      .isAfter(_todayClockIn!.add(const Duration(minutes: 2))));

          String dbStatus = att['status']?.toString() ?? '';

          UploadStatus upStatus = UploadStatus.sending;
          String statusText = 'Sending...';

          if (_retryingUids.contains(att['attendance_uid'])) {
            upStatus = UploadStatus.sending;
            statusText = 'Syncing... Please wait...';
          } else if (dbStatus == 'duplicate') {
            upStatus = UploadStatus.failed;
            statusText = 'ஏற்கனவே பதிவு செய்துவிட்டீர்கள், அதனால் Failed';
          } else if (dbStatus == SyncStatus.failed.name ||
              dbStatus == 'failed') {
            upStatus = UploadStatus.failed;
            statusText = 'Failed (Tap Retry)';
          } else if (dbStatus == 'pending') {
            upStatus = UploadStatus.failed; // 🔥 FIX: Show Retry for Pending
            statusText = 'Pending (Tap Retry)';
          } else if (dbStatus == SyncStatus.synced.name ||
              dbStatus == 'synced') {
            upStatus = UploadStatus.success;
            statusText = 'Sent';
          }

          addUnique(AttendanceChatMessage(
              id: "local_att_${att['local_id']}",
              type: isPendingReentry
                  ? ChatMessageType.reEntry
                  : (att['action'] == 'clock_in'
                      ? ChatMessageType.clockIn
                      : ChatMessageType.clockOut),
              text:
                  "Offline Record : ${DateFormat('hh:mm:ss a').format(msgTime)}\nSync : $statusText\nStatus : $_currentStatusStr",
              timestamp: msgTime,
              isSentByMe: true,
              imagePath: att['image_path'].toString(),
              uploadStatus: upStatus,
              attendanceUid: att['attendance_uid']?.toString()));
        }
      }

      for (var record in _attendanceHistory) {
        DateTime? d = _parseDateSafely(record['date']?.toString());
        if (d == null) continue;

        if (d.isBefore(today)) {
          DateTime itemTime = d;
          String? cIn =
              record['clock_in']?.toString() ?? record['clockIn']?.toString();
          if (cIn != null && cIn.isNotEmpty && cIn != "--:--") {
            itemTime = _combineDateAndTime(d, cIn) ?? d;
          }
          dailyRecords
              .putIfAbsent(d, () => [])
              .add({'source': 'attendance', 'data': record, 'time': itemTime});
        }
      }

      for (var record in _leaveHistory) {
        DateTime? d = _parseDateSafely(record['leave_date']?.toString());
        DateTime? createdAt =
            _parseFullDateTimeSafely(record['created_at']?.toString());

        DateTime messageTime = createdAt ?? d ?? today;
        DateTime dateOnly =
            DateTime(messageTime.year, messageTime.month, messageTime.day);

        String docId =
            record['id']?.toString() ?? record['doc_id']?.toString() ?? '';
        LeaveStatus ls = LeaveStatus.none;
        String currentStatus = record['status']?.toString().toLowerCase() ?? '';
        if (currentStatus == 'approved') {
          ls = LeaveStatus.approved;
        } else if (currentStatus == 'rejected') {
          ls = LeaveStatus.rejected;
        }

        if (dateOnly.isBefore(today)) {
          dailyRecords.putIfAbsent(dateOnly, () => []).add({
            'source': 'leave',
            'data': record,
            'time': messageTime,
            'docId': docId,
            'ls': ls,
            'd': d
          });
        } else {
          if (!localLeaveDocIds.contains(docId)) {
            addUnique(AttendanceChatMessage(
                id: "hist_leave_$docId",
                type: ChatMessageType.leaveRequest,
                text: "Holiday Application (${record['leave_type']})",
                timestamp: messageTime,
                isSentByMe: true,
                leaveType: record['leave_type'],
                leaveStatus: ls,
                leaveStartDate: d,
                uploadStatus: UploadStatus.success));
          }
          if (!localSysDocIds.contains(docId)) {
            String statusTxt = ls == LeaveStatus.approved
                ? "அங்கீகரிக்கப்பட்டது ✅"
                : (ls == LeaveStatus.rejected
                    ? "நிராகரிக்கப்பட்டது ❌"
                    : "காத்திருக்கிறது ⏳");

            addUnique(AttendanceChatMessage(
                id: "hist_leave_sys_$docId",
                type: ChatMessageType.system,
                text:
                    "விடுமுறை விண்ணப்பம் (${record['leave_type']}) $statusTxt.",
                timestamp: messageTime.add(const Duration(seconds: 1)),
                isSentByMe: false));
          }
        }
      }

      for (var att in pendingAttsBatch) {
        DateTime msgTime = DateTime.parse(att['capture_time'].toString());
        DateTime dateOnly = DateTime(msgTime.year, msgTime.month, msgTime.day);
        if (dateOnly.isBefore(today)) {
          dailyRecords.putIfAbsent(dateOnly, () => []).add(
              {'source': 'local_attendance', 'data': att, 'time': msgTime});
        }
      }

      List<DateTime> sortedDates = dailyRecords.keys.toList()
        ..sort((a, b) => b.compareTo(a));
      _hasMoreHistory = _daysToShow < sortedDates.length;
      List<DateTime> datesToShow =
          sortedDates.take(_daysToShow).toList().reversed.toList();

      List<AttendanceChatMessage> historyMessages = [];

      for (var date in datesToShow) {
        if (!DateUtils.isSameDay(date, today)) {
          String dateHeaderText =
              DateUtils.isSameDay(date, now.subtract(const Duration(days: 1)))
                  ? "Yesterday"
                  : DateFormat('dd MMM yyyy, EEEE').format(date);
          addUnique(AttendanceChatMessage(
              id: "sys_date_${date.millisecondsSinceEpoch}",
              type: ChatMessageType.dateHeader,
              text: dateHeaderText,
              timestamp: date,
              isSentByMe: false));
        }

        var recordsForDay = dailyRecords[date] ?? [];
        recordsForDay.sort((a, b) {
          DateTime tA = a['time'] ?? date;
          DateTime tB = b['time'] ?? date;
          return tA.compareTo(tB);
        });

        // 🔥 Find exact Database status for this specific history day
        String dayDbStatus = "";
        for (var item in recordsForDay) {
          if (item['source'] == 'attendance') {
            dayDbStatus = item['data']['status']?.toString() ?? "";
            break;
          }
        }

        // 🔥 FIX: Prevent History Ghost Bubbles by checking if Pending Record exists
        bool hasPendingIn = recordsForDay.any((i) =>
            i['source'] == 'local_attendance' &&
            i['data']['action'] == 'clock_in');
        bool hasPendingOut = recordsForDay.any((i) =>
            i['source'] == 'local_attendance' &&
            i['data']['action'] == 'clock_out');
        bool hasPendingBr = recordsForDay.any((i) =>
            i['source'] == 'local_attendance' &&
            i['data']['action'] == 'break_out');
        bool hasPendingRe = recordsForDay.any((i) =>
            i['source'] == 'local_attendance' &&
            i['data']['action'] == 'reentry');

        for (var item in recordsForDay) {
          if (item['source'] == 'attendance') {
            var record = item['data'];
            String cIn = record['clock_in_time']?.toString() ??
                record['clock_in']?.toString() ??
                record['clockIn']?.toString() ??
                "--:--";
            String cBreakOut = record['break_out_time']?.toString() ??
                record['break_out']?.toString() ??
                "";
            String cOut = record['clock_out_time']?.toString() ??
                record['clock_out']?.toString() ??
                record['clockOut']?.toString() ??
                "--:--";
            String cRe = record['reentry_time']?.toString() ??
                record['reEntryTime']?.toString() ??
                record['reentryTime']?.toString() ??
                "";

            String? inImg = (record['in_selfie_url'] ??
                    record['selfie_url'] ??
                    record['thumbnail'] ??
                    record['clock_in_image'])
                ?.toString();
            String? breakOutImgRaw = (record['break_out_selfie_url'] ??
                    record['breakout_selfie_url'])
                ?.toString();
            String? outImg = (record['out_selfie_url'] ??
                    record['clock_out_selfie_url'] ??
                    record['clock_out_image'] ??
                    record['out_thumbnail'] ??
                    record['outSelfieUrl'])
                ?.toString();
            String? reImg = (record['reentry_selfie_url'] ??
                    record['reentry_image'] ??
                    record['reentrySelfieUrl'])
                ?.toString();

            String dStr = record['date']?.toString() ?? "";
            String sh = record['showroom']?.toString() ?? _showroomName;
            String st = record['status']?.toString() ?? "";

            DateTime? parsedInTime;

            if (cIn != "--:--" &&
                cIn.isNotEmpty &&
                (cRe.isEmpty || cRe == "--:--")) {
              if (!hasPendingIn) {
                // 🔥 FIX: Hide DB Success bubble if offline retry bubble exists
                final DateTime inTime = _combineDateAndTime(date, cIn) ?? date;
                parsedInTime = inTime;
                addUnique(AttendanceChatMessage(
                    id: "hist_in_${record['id']}_$dStr",
                    type: ChatMessageType.clockIn,
                    text:
                        "Clock In : ${DateFormat('hh:mm:ss a').format(inTime)}\nStatus : $st",
                    timestamp: inTime,
                    isSentByMe: true,
                    imageUrl: _resolvePhotoUrl(inImg, dStr, sh),
                    uploadStatus: UploadStatus.success,
                    attendanceStatus: st));

                addUnique(AttendanceChatMessage(
                    id: "hist_sys_welcome_${record['id']}_$dStr",
                    type: ChatMessageType.system,
                    text: "வணக்கம்! இன்றைய பணி ஆரம்பம். 💪\nStatus: $st",
                    timestamp: inTime.add(const Duration(seconds: 1)),
                    isSentByMe: false));
              }
            }
            if (cBreakOut.isNotEmpty &&
                cBreakOut != "--:--" &&
                (cRe.isEmpty || cRe == "--:--")) {
              if (!hasPendingBr) {
                final DateTime brTime = _combineDateAndTime(date, cBreakOut) ??
                    (parsedInTime?.add(const Duration(seconds: 1)) ??
                        date.add(const Duration(hours: 4)));
                addUnique(AttendanceChatMessage(
                    id: "hist_br_${record['id']}_$dStr",
                    type: ChatMessageType.clockOut,
                    text:
                        "Clock Out : ${DateFormat('hh:mm:ss a').format(brTime)}\nStatus : $st",
                    timestamp: brTime,
                    isSentByMe: true,
                    imageUrl: _resolvePhotoUrl(breakOutImgRaw, dStr, sh),
                    uploadStatus: UploadStatus.success,
                    attendanceStatus: st));

                addUnique(AttendanceChatMessage(
                    id: "hist_sys_bye_${record['id']}_$dStr",
                    type: ChatMessageType.system,
                    text: GreetingHelper.getOutTimeGreeting(
                        parsedInTime, brTime, st),
                    timestamp: brTime.add(const Duration(seconds: 1)),
                    isSentByMe: false));
              }
            }
            if (cRe.isNotEmpty && cRe != "--:--") {
              if (!hasPendingRe) {
                final DateTime inTimeForRe = parsedInTime ?? date;
                final DateTime? outTimeForRe =
                    cOut != "--:--" && cOut.isNotEmpty
                        ? _combineDateAndTime(date, cOut)
                        : null;

                DateTime reTime = _combineDateAndTime(date, cRe) ??
                    inTimeForRe.add(const Duration(minutes: 1));

                if (outTimeForRe != null && reTime.isAfter(outTimeForRe)) {
                  final diffSeconds =
                      outTimeForRe.difference(inTimeForRe).inSeconds;
                  reTime = inTimeForRe
                      .add(Duration(seconds: (diffSeconds ~/ 3) * 2));
                }

                String clockInTimeStr =
                    DateFormat('hh:mm:ss a').format(inTimeForRe);

                addUnique(AttendanceChatMessage(
                    id: "hist_re_${record['id']}_$dStr",
                    type: ChatMessageType.reEntry,
                    text:
                        "Re-Entry : ${DateFormat('hh:mm:ss a').format(reTime)}\nClock In : $clockInTimeStr\nStatus : $st",
                    timestamp: reTime,
                    isSentByMe: true,
                    imageUrl: _resolvePhotoUrl(reImg, dStr, sh),
                    uploadStatus: UploadStatus.success,
                    attendanceStatus: st));

                addUnique(AttendanceChatMessage(
                    id: "hist_sys_reentry_${record['id']}_$dStr",
                    type: ChatMessageType.system,
                    text:
                        "மீண்டும் வேலைக்கு திரும்பியமைக்கு நன்றி! 💪\nStatus: $st",
                    timestamp: reTime.add(const Duration(seconds: 1)),
                    isSentByMe: false));
              }
            }
            if (cOut != "--:--" && cOut.isNotEmpty) {
              if (!hasPendingOut) {
                // 🔥 FIX: Hide DB Success bubble if offline retry bubble exists
                final DateTime outTime = _combineDateAndTime(date, cOut) ??
                    date.add(const Duration(hours: 9));
                addUnique(AttendanceChatMessage(
                    id: "hist_out_${record['id']}_$dStr",
                    type: ChatMessageType.clockOut,
                    text:
                        "Clock Out : ${DateFormat('hh:mm:ss a').format(outTime)}\nStatus : $st",
                    timestamp: outTime,
                    isSentByMe: true,
                    imageUrl: _resolvePhotoUrl(outImg, dStr, sh),
                    uploadStatus: UploadStatus.success,
                    attendanceStatus: st));

                addUnique(AttendanceChatMessage(
                    id: "hist_sys_bye_${record['id']}_$dStr",
                    type: ChatMessageType.system,
                    text: GreetingHelper.getOutTimeGreeting(
                        parsedInTime, outTime, st),
                    timestamp: outTime.add(const Duration(seconds: 1)),
                    isSentByMe: false));
              }
            }

            if (st.toLowerCase() == 'absent') {
              addUnique(AttendanceChatMessage(
                  id: "hist_st_abs_${record['id']}_$dStr",
                  type: ChatMessageType.system,
                  text: "⚠️ வருகை பதிவு செய்யப்படவில்லை. Status: Absent",
                  timestamp: date.add(const Duration(hours: 23, minutes: 58)),
                  isSentByMe: false));
            } else if (st.toLowerCase().contains('holiday')) {
              addUnique(AttendanceChatMessage(
                  id: "hist_st_hol_${record['id']}_$dStr",
                  type: ChatMessageType.system,
                  text: "🎉 அன்று விடுமுறை நாள் (Holiday).",
                  timestamp: date.add(const Duration(hours: 23, minutes: 58)),
                  isSentByMe: false));
            } else if (st.toLowerCase() == 'half day') {
              addUnique(AttendanceChatMessage(
                  id: "hist_st_hd_${record['id']}_$dStr",
                  type: ChatMessageType.system,
                  text: "📉 அன்று 'Half Day' என கணக்கிடப்பட்டுள்ளது.",
                  timestamp: date.add(const Duration(hours: 23, minutes: 59)),
                  isSentByMe: false));
            } else if (st.toLowerCase().contains('leave')) {
              addUnique(AttendanceChatMessage(
                  id: "hist_st_lv_${record['id']}_$dStr",
                  type: ChatMessageType.system,
                  text: "📋 அன்று விடுப்பு (Leave) எடுக்கப்பட்டுள்ளது.",
                  timestamp: date.add(const Duration(hours: 23, minutes: 59)),
                  isSentByMe: false));
            } else if (st.isNotEmpty && parsedInTime == null) {
              addUnique(AttendanceChatMessage(
                  id: "hist_st_gen_${record['id']}_$dStr",
                  type: ChatMessageType.system,
                  text: "📋 Status: $st",
                  timestamp: date.add(const Duration(hours: 10)),
                  isSentByMe: false));
            }
          } else if (item['source'] == 'leave') {
            var record = item['data'];
            String docId = item['docId'];
            LeaveStatus ls = item['ls'];
            DateTime? d = item['d'];

            if (!localLeaveDocIds.contains(docId)) {
              addUnique(AttendanceChatMessage(
                  id: "hist_leave_$docId",
                  type: ChatMessageType.leaveRequest,
                  text: "Holiday Application (${record['leave_type']})",
                  timestamp: item['time'],
                  isSentByMe: true,
                  leaveType: record['leave_type'],
                  leaveStatus: ls,
                  leaveStartDate: d,
                  uploadStatus: UploadStatus.success));
            }

            if (!localSysDocIds.contains(docId)) {
              String statusTxt = ls == LeaveStatus.approved
                  ? "அங்கீகரிக்கப்பட்டது ✅"
                  : (ls == LeaveStatus.rejected
                      ? "நிராகரிக்கப்பட்டது ❌"
                      : "காத்திருக்கிறது ⏳");

              addUnique(AttendanceChatMessage(
                  id: "hist_leave_sys_$docId",
                  type: ChatMessageType.system,
                  text:
                      "விடுமுறை விண்ணப்பம் (${record['leave_type']}) $statusTxt.",
                  timestamp: (item['time'] as DateTime)
                      .add(const Duration(seconds: 1)),
                  isSentByMe: false));
            }
          } else if (item['source'] == 'local_message') {
            var msg = item['data'];
            bool isLeave = msg['message_type'] == 'leave_request';

            String msgText = msg['message_text']?.toString() ?? "";

            // 🔥 Fix older messages to accurately show Database Status
            if (dayDbStatus.isNotEmpty &&
                (msgText.contains('Status:') || msgText.contains('Status :'))) {
              msgText = msgText.replaceAll(
                  RegExp(r'Status\s*:\s*.*'), 'Status : $dayDbStatus');
            }

            addUnique(AttendanceChatMessage(
                id: msg['unique_id']?.toString() ??
                    "local_msg_${msg['local_id']}",
                type: isLeave
                    ? ChatMessageType.leaveRequest
                    : ChatMessageType.system,
                text: msgText,
                timestamp: item['time'] ?? date,
                isSentByMe: msg['message_type'] == 'user' || isLeave,
                leaveType: item['leaveType'],
                leaveStartDate: item['leaveDate'],
                leaveReason: item['reason'],
                leaveStatus: item['ls'],
                uploadStatus: msg['status'] == 'pending_upload'
                    ? UploadStatus.sending
                    : UploadStatus.success));
          } else if (item['source'] == 'local_attendance') {
            var att = item['data'];
            DateTime msgTime = item['time'] ?? date;
            String dbStatus = att['status']?.toString() ?? '';

            UploadStatus prevDayStatus = UploadStatus.sending;
            String statusLabel = 'Sending...';

            if (dbStatus == 'duplicate') {
              prevDayStatus = UploadStatus.failed;
              statusLabel = 'ஏற்கனவே பதிவு செய்துவிட்டீர்கள், அதனால் Failed';
            } else if (dbStatus == 'failed' ||
                dbStatus == SyncStatus.failed.name) {
              prevDayStatus = UploadStatus.failed;
              statusLabel = 'Failed (Tap Retry)';
            } else if (dbStatus == 'synced' ||
                dbStatus == SyncStatus.synced.name) {
              prevDayStatus = UploadStatus.success;
              statusLabel = 'Sent';
            } else if (dbStatus == 'pending') {
              prevDayStatus = UploadStatus
                  .failed; // 🔥 FIX: Show Retry UI for older pendings
              statusLabel = 'Pending (Tap Retry)';
            }

            String attStatus = dayDbStatus.isNotEmpty ? dayDbStatus : "Pending";

            addUnique(AttendanceChatMessage(
                id: "hist_local_att_${att['local_id']}",
                type: att['action'] == 'clock_in'
                    ? ChatMessageType.clockIn
                    : (att['action'] == 'clock_out'
                        ? ChatMessageType.clockOut
                        : (att['action'] == 'break_out'
                            ? ChatMessageType.clockOut
                            : ChatMessageType.reEntry)),
                text:
                    "⚠️ Offline Record : ${DateFormat('hh:mm:ss a').format(msgTime)}\nSync : $statusLabel\nStatus : $attStatus",
                timestamp: msgTime,
                isSentByMe: true,
                imagePath: att['image_path'].toString(),
                uploadStatus: prevDayStatus,
                attendanceUid: att['attendance_uid']?.toString()));
          }
        }
      }

      final finalMessages = [...historyMessages, ...newChatMessages];
      finalMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      if (mounted) {
        _chatMessagesNotifier.value = List.from(finalMessages);
        setState(() {
          _isLoadingMore = false;
          if (_isInitialLoading) {
            _isInitialLoading = false;
          }
        });
      }
    } catch (e, stacktrace) {
      debugPrint("Chat Build Safe Catch: $e\n$stacktrace");
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    } finally {
      _isBuildingChat = false;
      if (_needsRebuild) {
        Future.microtask(() => _buildChatFromStatus());
      }
    }
  }

  Future<void> _addSystemMessage(String text,
      {bool persist = false, String? uniqueId}) async {
    final now = DateTime.now();
    if (persist) {
      String finalUniqueId = uniqueId ??
          "sys_${text.hashCode}_${DateFormat('yyyyMMdd').format(now)}";

      await LocalDbHelper.instance.insertMessage(_salesmanId, {
        'message_text': text,
        'message_type': 'system',
        'unique_id': finalUniqueId,
        'status': 'sent',
        'timestamp': now.toIso8601String(),
      });

      if (mounted) {
        _triggerChatBuild();
      }
    } else {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;

      final newMessages =
          List<AttendanceChatMessage>.from(_chatMessagesNotifier.value);
      newMessages.add(AttendanceChatMessage(
        id: "sys_${now.millisecondsSinceEpoch}",
        type: ChatMessageType.system,
        text: text,
        timestamp: now,
        isSentByMe: false,
      ));
      _chatMessagesNotifier.value = newMessages;

      if (mounted) {
        _scrollToBottom();
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) _scrollToBottom(force: true);
        });
      }
    }
  }

  final Set<String> _retryingUids = {};

  Future<void> _manualRetry(AttendanceChatMessage message) async {
    if (message.attendanceUid == null) return;

    if (_retryingUids.contains(message.attendanceUid)) {
      debugPrint(
          "⚠️ Manual Retry: Already retrying this record, ignoring duplicate tap.");
      return;
    }
    _retryingUids.add(message.attendanceUid!);

    debugPrint("🔄 Manual Retry Triggered for ${message.attendanceUid}");

    _updateLastMessageStatus(UploadStatus.sending,
        specificMsgId: message.id,
        attendanceStatus: "Syncing... Please wait...");

    try {
      final List<Map<String, dynamic>> pending =
          await LocalDbHelper.instance.getPendingAttendance(_salesmanId);

      final recordData = pending.firstWhere(
          (r) => r['attendance_uid'] == message.attendanceUid,
          orElse: () => <String, Object?>{});

      if (recordData.isEmpty) {
        debugPrint(
            "✅ Manual Retry: Record not found in local DB. Already synced in background.");
        await Future.delayed(const Duration(seconds: 1));

        _updateLastMessageStatus(UploadStatus.success,
            specificMsgId: message.id,
            attendanceStatus: "Sync வெற்றி! Record சர்வரில் சேமிக்கப்பட்டது.");

        _retryingUids.remove(message.attendanceUid!);
        _fetchAttendanceStatus(forceFullSync: true);
        _fetchAttendanceHistory(forceFullSync: true);
        return;
      }

      final record = AttendanceRecord.fromMap(recordData);

      if (record.imagePath != null && record.imagePath!.isNotEmpty) {
        final imageFile = File(record.imagePath!);
        if (!await imageFile.exists()) {
          debugPrint(
              "⚠️ Manual Retry: Image file missing at ${record.imagePath}");
        }
      }

      final syncRes = await _syncService.uploadRecord(record);

      if (syncRes['success'] == true) {
        debugPrint("✅ Manual Retry Success! (or Already Synced)");
        final result = syncRes['data'];
        String? serverImageUrl = result['image_url']?.toString();

        bool isDuplicate = syncRes['isDuplicate'] == true;

        String finalStatusDisplay;
        if (isDuplicate) {
          finalStatusDisplay = syncRes['message']?.toString() ??
              'ஏற்கனவே பதிவாகிவிட்டது (Already Synced)';
        } else {
          finalStatusDisplay = result['status']?.toString() ??
              'Sync வெற்றி! Record சர்வரில் சேமிக்கப்பட்டது.';
        }

        _updateLastMessageStatus(UploadStatus.success,
            specificMsgId: message.id,
            imageUrl: serverImageUrl,
            attendanceStatus: finalStatusDisplay);

        if (record.localId != null) {
          await LocalDbHelper.instance.deletePendingAttendance(record.localId!);
        }

        _fetchAttendanceStatus(forceFullSync: true);
        _fetchAttendanceHistory(forceFullSync: true);
      } else {
        debugPrint("❌ Manual Retry Failed.");
        bool isDuplicate = syncRes['isDuplicate'] == true;

        if (isDuplicate) {
          _updateLastMessageStatus(UploadStatus.success,
              specificMsgId: message.id,
              attendanceStatus:
                  'ஏற்கனவே பதிவு செய்துவிட்டீர்கள் (Already Synced)');

          if (record.localId != null) {
            await LocalDbHelper.instance
                .deletePendingAttendance(record.localId!);
          }
          _fetchAttendanceStatus(forceFullSync: true);
          _fetchAttendanceHistory(forceFullSync: true);
        } else {
          String errorMsg = syncRes['message']?.toString() ?? 'சர்வர் பிழை';

          if (errorMsg.toLowerCase().contains('socketexception') ||
              errorMsg.toLowerCase().contains('network is unreachable') ||
              errorMsg.toLowerCase().contains('failed host lookup')) {
            errorMsg = 'இணையத் தொடர்பு இல்லை (No Internet Connection)';
          } else if (errorMsg.toLowerCase().contains('timeoutexception') ||
              errorMsg.toLowerCase().contains('connection timed out')) {
            errorMsg =
                'சர்வர் மிகவும் தாமதமாக பதிலளிக்கிறது (Connection Timeout)';
          }

          _showTopError(errorMsg);

          _updateLastMessageStatus(UploadStatus.failed,
              specificMsgId: message.id,
              attendanceStatus:
                  "Sync தோல்வி: $errorMsg. மீண்டும் முயற்சிக்கவும்.");
        }
      }
    } catch (e) {
      debugPrint("❌ Manual Retry Exception: $e");
      String errorMsg = e.toString();
      if (errorMsg.toLowerCase().contains('socketexception') ||
          errorMsg.toLowerCase().contains('network is unreachable') ||
          errorMsg.toLowerCase().contains('failed host lookup')) {
        errorMsg = 'இணையத் தொடர்பு இல்லை (No Internet Connection)';
      } else if (errorMsg.toLowerCase().contains('timeoutexception') ||
          errorMsg.toLowerCase().contains('connection timed out')) {
        errorMsg = 'சர்வர் மிகவும் தாமதமாக பதிலளிக்கிறது (Connection Timeout)';
      } else {
        errorMsg = 'எதிர்பாராத பிழை ஏற்பட்டது';
      }

      _updateLastMessageStatus(UploadStatus.failed,
          specificMsgId: message.id,
          attendanceStatus: "Sync தோல்வி: $errorMsg. மீண்டும் முயற்சிக்கவும்.");
    } finally {
      _retryingUids.remove(message.attendanceUid!);
    }
  }

  Future<void> _manualDelete(AttendanceChatMessage message) async {
    if (message.attendanceUid == null) return;

    debugPrint("🗑️ Manual Delete Triggered for ${message.attendanceUid}");

    bool? confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Delete Record? 🗑️",
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
            "இந்த பதிவையும் புகைப்படத்தையும் நீக்க வேண்டுமா?\n(Are you sure you want to delete this record and photo?)"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete",
                style:
                    TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final List<Map<String, dynamic>> pending =
          await LocalDbHelper.instance.getPendingAttendance(_salesmanId);

      final recordData = pending.firstWhere(
          (r) => r['attendance_uid'] == message.attendanceUid,
          orElse: () => <String, Object?>{});

      if (recordData.isEmpty) {
        debugPrint("❌ Manual Delete Error: Record not found in local DB.");
        await _addSystemMessage(
            "❌ இந்த record கிடைக்கவில்லை. ஏற்கனவே sync அல்லது நீக்கப்பட்டிருக்கலாம்.\n(Record not found. It may have already been synced or deleted.)",
            persist: false);
        return;
      }

      final localId = recordData['local_id'];
      final imagePath = recordData['image_path']?.toString();

      if (imagePath != null && imagePath.isNotEmpty) {
        final imageFile = File(imagePath);
        if (await imageFile.exists()) {
          try {
            await imageFile.delete();
            debugPrint("🗑️ Photo file deleted at: $imagePath");
          } catch (e) {
            debugPrint("⚠️ Failed to delete photo file: $e");
          }
        }
      }

      if (localId is int) {
        await LocalDbHelper.instance.deletePendingAttendance(localId);
        debugPrint("🗑️ SQLite pending record deleted for local_id: $localId");
      }

      await _addSystemMessage(
          "✅ Record மற்றும் புகைப்படம் வெற்றிகரமாக நீக்கப்பட்டது.\n(Record and photo successfully deleted.)",
          persist: false);

      await _fetchAttendanceStatus(forceFullSync: true);
      await _loadHistoryFromSQLite();
      _triggerChatBuild();
    } catch (e) {
      debugPrint("❌ Manual Delete Exception: $e");
      await _addSystemMessage(
          "❌ நீக்குவதில் பிழை ஏற்பட்டது. மீண்டும் முயற்சிக்கவும்.\n(Error deleting. Please try again.)",
          persist: false);
    }
  }

  void _updateLastMessageStatus(UploadStatus status,
      {String? specificMsgId,
      LeaveStatus? leaveStatus,
      String? imageUrl,
      String? attendanceStatus}) {
    if (!mounted) return;

    final messages = _chatMessagesNotifier.value;
    if (messages.isEmpty) return;

    final newMessages = List<AttendanceChatMessage>.from(messages);
    int indexToUpdate = -1;

    if (specificMsgId != null) {
      indexToUpdate = newMessages.indexWhere((m) => m.id == specificMsgId);
    } else {
      indexToUpdate = newMessages.lastIndexWhere((m) => m.isSentByMe);
    }

    if (indexToUpdate != -1) {
      final oldMsg = newMessages[indexToUpdate];
      String updatedText = oldMsg.text;

      // 🔥 PLAY SOUND ON SUCCESS TRANSITION
      if (status == UploadStatus.success &&
          oldMsg.uploadStatus != UploadStatus.success) {
        _playSuccessSound();
      }

      if (attendanceStatus != null && attendanceStatus.isNotEmpty) {
        updatedText = updatedText.replaceAll(
            RegExp(r'Status\s*:\s*.*'), 'Status : $attendanceStatus');
      }

      newMessages[indexToUpdate] = AttendanceChatMessage(
        id: oldMsg.id,
        type: oldMsg.type,
        text: updatedText,
        timestamp: oldMsg.timestamp,
        isSentByMe: oldMsg.isSentByMe,
        imagePath: oldMsg.imagePath,
        imageUrl: imageUrl ?? oldMsg.imageUrl,
        uploadStatus: status,
        leaveType: oldMsg.leaveType,
        leaveStartDate: oldMsg.leaveStartDate,
        leaveEndDate: oldMsg.leaveEndDate,
        leaveReason: oldMsg.leaveReason,
        leaveStatus: leaveStatus ?? oldMsg.leaveStatus,
        leaveDays: oldMsg.leaveDays,
        attendanceStatus: attendanceStatus ?? oldMsg.attendanceStatus,
      );

      _chatMessagesNotifier.value = newMessages;

      // 🔥 Update SQLite immediately so _loadHistoryFromSQLite doesn't overwrite it with 'failed'
      String sqlStatus = 'sent';
      if (status == UploadStatus.failed) {
        sqlStatus = 'failed';
      } else if (status == UploadStatus.sending) {
        sqlStatus = 'sending';
      }

      LocalDbHelper.instance
          .updateMessageStatusByUniqueId(
        _salesmanId,
        oldMsg.id,
        sqlStatus,
        newText: updatedText,
      )
          .catchError((e) {
        debugPrint("❌ Failed to update SQLite message status: $e");
        return -1;
      });
    }
  }

  // 🔥 Tick Sound Player
  Future<void> _playSuccessSound() async {
    try {
      HapticFeedback.mediumImpact(); // Trigger vibration for silent mode users

      final soundFile = await SecureStorageService.getTickSound();

      // Configure audio context to respect device silent switch/volume
      await _audioPlayer.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: false,
          stayAwake: false,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.notificationEvent,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
        iOS: AudioContextIOS(
          category:
              AVAudioSessionCategory.ambient, // Respects physical silent switch
        ),
      ));

      await _audioPlayer.play(AssetSource('sounds/$soundFile'));
    } catch (e) {
      debugPrint("Error playing tick sound: $e");
    }
  }

  void _scrollToBottom({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        final pos = _scrollController.position;
        final bool isNearBottom = pos.pixels <= 200;

        if (force || isNearBottom || _isCapturing) {
          if (force && !isNearBottom) {
            _scrollController.jumpTo(0.0);
          } else if (pos.pixels > 0) {
            _scrollController.animateTo(
              0.0,
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutQuart,
            );
          }
        }
      }
    });
  }

  Future<void> _openCamera() async {
    if (_isNavigatingCamera) return;

    if (_lastActionTime != null) {
      final diff = DateTime.now().difference(_lastActionTime!);
      if (diff.inSeconds < 120) {
        final remainingSec = 120 - diff.inSeconds;
        final min = remainingSec ~/ 60;
        final sec = remainingSec % 60;
        _showTopError(
            "Please wait ${min > 0 ? '$min min ' : ''}$sec sec to process next request.");
        return;
      }
    }

    _isNavigatingCamera = true;
    String targetAction = 'clock_in';

    try {
      // 🔥 Fetch Latest Status from Server before deciding which camera to open
      if (_isInternetConnected) {
        debugPrint(
            "🔍 Network available! Fetching real-time status before opening camera...");
        await _fetchAttendanceStatus(forceFullSync: true);
        await _determineClockInMode();
      }

      if (_todayClockIn == null) {
        targetAction = 'clock_in';
      } else if (_todayClockOut != null) {
        if (_todayOutUploadStatus == UploadStatus.success || _resumeCount > 0) {
          targetAction = 'reentry';
        } else {
          targetAction = 'clock_out';
        }
      } else if (_todayBreakOutTime != null && _todayReentryTime == null) {
        if (_todayBreakOutUploadStatus == UploadStatus.success ||
            _resumeCount > 0) {
          targetAction = 'reentry';
        } else {
          targetAction = 'break_out';
        }
      } else if (_resumeCount > 0) {
        targetAction = 'reentry';
      } else {
        targetAction = 'clock_out';

        final now = DateTime.now();
        if (now.hour >= 13 && now.hour < 16 && _todayBreakOutTime == null) {
          bool alreadyTookLunch = false;
          final todayStr = DateFormat('yyyy-MM-dd').format(now);
          if (_attendanceHistory.isNotEmpty) {
            for (var record in _attendanceHistory) {
              if (record['date'] == todayStr) {
                if (record['lunch_in_time'] != null &&
                    record['lunch_in_time'].toString().isNotEmpty &&
                    record['lunch_in_time'].toString() != "null") {
                  alreadyTookLunch = true;
                }
                break;
              }
            }
          }

          if (!alreadyTookLunch) {
            if (!mounted) return;
            bool? proceed = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                title: const Text("Lunch Time? 🍽️",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                content: const Text("நீங்கள் மதிய உணவுக்கு செல்கிறீர்களா?\n\n"
                    "மதிய உணவுக்கு என்றால், Dashboard-ல் உள்ள 'Lunch Time'-ஐ பயன்படுத்தவும். "
                    "இங்கு 'Break-Out' செய்தால் ஷோரூமை விட்டு வெளியேறுவதாக பதிவாகும்."),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text("Go to Lunch",
                        style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text("No, Break-Out",
                        style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            );

            if (proceed != true) {
              _isNavigatingCamera = false;
              if (mounted && Navigator.canPop(context)) {
                Navigator.pop(context);
              }
              return;
            } else {
              targetAction = 'break_out';
            }
          }
        }
      }

      // 🚫 Blocker 1: Do not allow Clock-In after limit without approval
      final now = DateTime.now();
      if (targetAction == 'clock_in' &&
          (now.hour > _clockInLimitHour ||
              (now.hour == _clockInLimitHour &&
                  now.minute > _clockInLimitMinute)) &&
          !_allowLateEntry) {
        _isNavigatingCamera = false;
        final limitTimeStr =
            TimeOfDay(hour: _clockInLimitHour, minute: _clockInLimitMinute)
                .format(context);
        _showTopError(
            "நேரம் முடிந்து விட்டது ($limitTimeStr) தாண்டிவிட்டது! அட்மின் அனுமதி தேவை.");
        return;
      }

      // 🚫 Blocker 2: Do not allow Re-entry or Clock-in after limit without approval
      if ((targetAction == 'reentry' || targetAction == 'clock_in') &&
          (now.hour > _reentryLimitHour ||
              (now.hour == _reentryLimitHour &&
                  now.minute > _reentryLimitMinute)) &&
          !_allowLateEntry) {
        _isNavigatingCamera = false;
        final limitTimeStr =
            TimeOfDay(hour: _reentryLimitHour, minute: _reentryLimitMinute)
                .format(context);
        _showTopError(
            "மன்னிக்கவும்! நேரம் $limitTimeStr தாண்டிவிட்டது, இனி உங்களால் $targetAction செய்ய முடியாது. 🙏");
        return;
      }

      bool hasCameraPermission = await PermissionGuard.run(() async {
            var status = await Permission.camera.status;
            if (status.isDenied) {
              status = await Permission.camera.request();
            }
            return status.isGranted;
          }) ??
          false;

      if (!hasCameraPermission) {
        if (mounted) {
          try {
            ActivityLogger.instance.logError('UI', 'Camera permission denied');
          } catch (_) {}
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Camera permission is required to capture photos."),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      if (!mounted) return;

      final Map? captureResult = await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => CameraCaptureScreen(
                isClockIn:
                    (targetAction == 'clock_in' || targetAction == 'reentry'))),
      );

      if (captureResult != null &&
          captureResult['path'] != null &&
          captureResult['captureTime'] != null &&
          mounted) {
        final String imagePath = captureResult['path'] as String;
        final DateTime captureTime = captureResult['captureTime'] as DateTime;
        final bool isFrontCamera =
            captureResult['isFrontCamera'] as bool? ?? true;
        await _performUpload(imagePath, captureTime,
            isFrontCamera: isFrontCamera, explicitAction: targetAction);
      }
    } finally {
      _isNavigatingCamera = false;
    }
  }

  Future<File> _applyWatermarkLocally(File originalImage, DateTime captureTime,
      String action, bool isFrontCamera) async {
    try {
      final processedBytes = await compute(_processImageIsolate, {
        'imagePath': originalImage.path,
        'captureTime': captureTime.toIso8601String(),
        'action': action,
        'salesmanName': _salesmanName,
        'showroomName': _showroomName,
        'isFrontCamera': isFrontCamera,
      });

      if (processedBytes != null) {
        await originalImage.writeAsBytes(processedBytes);
      }
      return originalImage;
    } catch (e, stackTrace) {
      debugPrint("Watermark failed: $e\n$stackTrace");
      return originalImage;
    }
  }

  Future<void> _performUpload(String imagePath, DateTime captureTime,
      {bool isFrontCamera = true, String? explicitAction}) async {
    if (_isCapturing) {
      return;
    }
    setState(() => _isCapturing = true);

    String action = explicitAction ?? 'clock_out';

    if (explicitAction == null) {
      if (_todayClockIn == null) {
        action = 'clock_in';
      } else if (_todayClockOut != null) {
        action =
            (_todayOutUploadStatus == UploadStatus.success || _resumeCount > 0)
                ? 'reentry'
                : 'clock_out';
      } else if (_todayBreakOutTime != null && _todayReentryTime == null) {
        action = (_todayBreakOutUploadStatus == UploadStatus.success ||
                _resumeCount > 0)
            ? 'reentry'
            : 'break_out';
      } else if (_resumeCount > 0) {
        action = 'reentry';
      } else {
        action = 'clock_out';
      }
    }

    final msgId = "msg_${captureTime.millisecondsSinceEpoch}";

    String optimisticStatus =
        _currentStatusStr == "Not Marked" || _currentStatusStr == "Absent"
            ? "Present"
            : _currentStatusStr;

    final bool isReEntry = (action == 'reentry');
    final bool isBreakOut = (action == 'break_out');

    ChatMessageType msgType;
    String msgText;

    if (isReEntry) {
      String originalInTime = _todayClockIn != null
          ? DateFormat('hh:mm:ss a').format(_todayClockIn!)
          : "--:--";
      msgType = ChatMessageType.reEntry;
      msgText =
          "Re-Entry : ${DateFormat('hh:mm:ss a').format(captureTime)}\nClock In : $originalInTime\nStatus : $optimisticStatus";
    } else if (isBreakOut) {
      msgType = ChatMessageType.clockOut;
      msgText =
          "Break-Out : ${DateFormat('hh:mm:ss a').format(captureTime)}\nStatus : $optimisticStatus";
    } else if (action == 'clock_in') {
      msgType = ChatMessageType.clockIn;
      msgText =
          "Clock In : ${DateFormat('hh:mm:ss a').format(captureTime)}\nStatus : $optimisticStatus";
    } else {
      msgType = ChatMessageType.clockOut;
      msgText =
          "Clock Out : ${DateFormat('hh:mm:ss a').format(captureTime)}\nStatus : $optimisticStatus";
    }

    final currentMsgs =
        List<AttendanceChatMessage>.from(_chatMessagesNotifier.value);

    if (isReEntry) {
      currentMsgs.removeWhere((msg) =>
          (msg.type == ChatMessageType.clockIn ||
              msg.type == ChatMessageType.clockOut) &&
          DateUtils.isSameDay(msg.timestamp, captureTime));
    }

    currentMsgs.add(AttendanceChatMessage(
      id: msgId,
      type: msgType,
      text: msgText,
      timestamp: captureTime,
      isSentByMe: true,
      imagePath: imagePath,
      uploadStatus: UploadStatus.sending,
    ));
    _chatMessagesNotifier.value = currentMsgs;

    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) _scrollToBottom(force: true);
    });

    Position? finalPosition = _cachedPosition;
    if (finalPosition == null) {
      try {
        if (!await Geolocator.isLocationServiceEnabled()) {
          _addSystemMessage(
              "❌ GPS Location ஆஃப் செய்யப்பட்டுள்ளது. தயவுசெய்து GPS-ஐ ஆன் செய்யவும்.",
              persist: false);
          _updateLastMessageStatus(UploadStatus.failed, specificMsgId: msgId);
          setState(() => _isCapturing = false);
          return;
        }

        finalPosition = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.high,
                timeLimit: Duration(seconds: 15)));
      } catch (e, stackTrace) {
        debugPrint("Location GPS Error: $e\n$stackTrace");
        try {
          finalPosition = await Geolocator.getLastKnownPosition();
        } catch (innerE) {
          debugPrint("LastKnownPosition also failed: $innerE");
          finalPosition = null;
        }
      }

      if (!mounted) return;

      if (finalPosition == null) {
        _addSystemMessage("❌ GPS Location கிடைக்கவில்லை. GPS ஆன் செய்யவும்.",
            persist: false);
        _updateLastMessageStatus(UploadStatus.failed, specificMsgId: msgId);
        setState(() => _isCapturing = false);
        return;
      }
    }

    String savedImagePath = imagePath;
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final attendanceDir = Directory('${appDir.path}/attendance');
      if (!await attendanceDir.exists()) {
        await attendanceDir.create(recursive: true);
      }
      final fileName = 'attendance_${captureTime.millisecondsSinceEpoch}.jpg';
      File processedImage = await _applyWatermarkLocally(
          File(imagePath), captureTime, action, isFrontCamera);
      final savedFile =
          await processedImage.copy('${attendanceDir.path}/$fileName');
      savedImagePath = savedFile.path;
    } catch (e, stackTrace) {
      debugPrint("File Save Error: $e\n$stackTrace");
    }

    if (mounted) {
      setState(() {
        _currentStatusStr = optimisticStatus;
        if (action == 'clock_in') {
          _todayClockIn = captureTime;
          _todayInImageUrl = savedImagePath;
          _todayInUploadStatus = UploadStatus.sending;
        } else if (action == 'reentry') {
          _todayReentryTime = captureTime;
          _todayReentryImageUrl = savedImagePath;
          _todayReentryUploadStatus = UploadStatus.sending;

          _todayClockOut = null;
          _todayOutImageUrl = null;
          SecureStorageService.deleteKey('fc_last_synced_out_$_salesmanId');
        } else if (action == 'break_out') {
          _todayBreakOutTime = captureTime;
          _todayBreakOutImageUrl = savedImagePath;
          _todayBreakOutUploadStatus = UploadStatus.sending;
        } else if (action == 'clock_out') {
          _todayClockOut = captureTime;
          _todayOutImageUrl = savedImagePath;
          _todayOutUploadStatus = UploadStatus.sending;
        }
      });
      _triggerChatBuild();
    }

    await _saveTodayToLocalHistory();

    try {
      final record = await _attendanceRepo.markAttendance(
        salesmanId: _salesmanId,
        type: action,
        latitude: finalPosition.latitude.toString(),
        longitude: finalPosition.longitude.toString(),
        imagePath: savedImagePath,
        timestamp: captureTime,
      );

      if (mounted) {
        await _determineClockInMode();
      }

      final syncResult = await _syncService.uploadRecord(record);

      if (syncResult['success']) {
        bool isDuplicate = syncResult['isDuplicate'] == true;

        ActivityLogger.instance.logAttendance(
          action,
          captureTime: captureTime.toIso8601String(),
          status: 'success',
          details:
              'Attendance sync successful: $action (Duplicate: $isDuplicate)',
        );
        _lastActionTime = DateTime.now();
        final result = syncResult['data'];

        // 🔥 FIX 2: Delete pending record immediately on success so it doesn't show as Retry/Ghost Bubble
        if (record.localId != null) {
          await LocalDbHelper.instance.deletePendingAttendance(record.localId!);
        }

        if (isDuplicate) {
          String dupMsg = result['message']?.toString() ?? "Already recorded";
          _showTopError(dupMsg);

          final currentMsgs =
              List<AttendanceChatMessage>.from(_chatMessagesNotifier.value);
          currentMsgs.removeWhere((msg) => msg.id == msgId);
          _chatMessagesNotifier.value = currentMsgs;

          if (mounted) {
            await _fetchAttendanceStatus(forceFullSync: false);
            await _determineClockInMode();
            setState(() => _isCapturing = false);
          }
          return;
        }

        String? serverImageUrl = result['image_url']?.toString();

        if (action == 'clock_in') {
          _todayClockIn = captureTime;
          _todayInImageUrl = serverImageUrl;
          _todayInUploadStatus = UploadStatus.success;
        } else if (action == 'reentry') {
          _todayReentryTime = captureTime;
          _todayReentryImageUrl = serverImageUrl;
          _todayReentryUploadStatus = UploadStatus.success;
          _todayClockOut = null;
          _todayOutImageUrl = null;
        } else if (action == 'break_out') {
          _todayBreakOutTime = captureTime;
          _todayBreakOutImageUrl = serverImageUrl;
          _todayBreakOutUploadStatus = UploadStatus.success;
        } else if (action == 'clock_out') {
          _todayClockOut = captureTime;
          _todayOutImageUrl = serverImageUrl;
          _todayOutUploadStatus = UploadStatus.success;
        }

        await _saveTodayToLocalHistory();

        final todayStr1 = DateFormat('yyyy-MM-dd').format(captureTime);
        if (action == 'clock_in') {
          await _addSystemMessage(
              result['message']?.toString() ??
                  "வணக்கம்! இன்றைய பணி ஆரம்பம். 💪",
              persist: true,
              uniqueId: "sys_welcome_$todayStr1");

          final lateMsg = GreetingHelper.getLateClockInMessage(
            captureTime,
            customCutoff: _customLateCutoff,
          );
          if (lateMsg != null) {
            await _addSystemMessage(lateMsg,
                persist: true, uniqueId: "sys_late_$todayStr1");
          }
        } else if (action == 'reentry') {
          await _addSystemMessage(
              result['message']?.toString() ??
                  "மீண்டும் வேலைக்கு திரும்பியமைக்கு நன்றி! 🔄",
              persist: true,
              uniqueId: "sys_reentry_$todayStr1");
        } else if (action == 'break_out') {
          final greeting = GreetingHelper.getOutTimeGreeting(
              _todayClockIn, captureTime, _currentStatusStr);
          await _addSystemMessage(greeting,
              persist: true, uniqueId: "sys_break_$todayStr1");
        } else if (action == 'clock_out') {
          final greeting = GreetingHelper.getOutTimeGreeting(
              _todayClockIn, captureTime, _currentStatusStr);
          await _addSystemMessage(greeting,
              persist: true, uniqueId: "sys_bye_$todayStr1");
        }

        final timeStr = DateFormat('hh:mm a').format(captureTime);
        if (action == 'clock_in') {
          await SecureStorageService.writeString(
              'saved_in_time_$_salesmanId', timeStr);
          await SecureStorageService.writeString(
              'saved_out_time_$_salesmanId', '--:--');
        } else if (action == 'clock_out') {
          await SecureStorageService.writeString(
              'saved_out_time_$_salesmanId', timeStr);
        }

        try {
          String notifIn = await SecureStorageService.readString(
                  'saved_in_time_$_salesmanId') ??
              '--:--';
          String notifOut = await SecureStorageService.readString(
                  'saved_out_time_$_salesmanId') ??
              '--:--';

          FlutterBackgroundService().invoke("update_notification_times", {
            'in_time': notifIn,
            'out_time': notifOut,
          });
        } catch (e) {
          debugPrint("Bg Service Invoke Error: $e");
        }

        if (mounted) {
          final freshStatusMap =
              await _fetchAttendanceStatus(forceFullSync: true);

          String accurateStatus =
              freshStatusMap?['status']?.toString() ?? optimisticStatus;

          _updateLastMessageStatus(UploadStatus.success,
              specificMsgId: msgId,
              imageUrl: serverImageUrl,
              attendanceStatus: accurateStatus);

          if (result['performance_data'] != null) {
            _updatePerformanceState(result['performance_data']);
          }

          await Future.delayed(const Duration(milliseconds: 800));

          if (mounted) {
            await _fetchAttendanceHistory();
            _triggerChatBuild();
          }
        }
      } else {
        String errorMsg = syncResult['message']?.toString() ?? "";

        ActivityLogger.instance.logAttendance(
          action,
          captureTime: captureTime.toIso8601String(),
          status: 'failed',
          details: 'Attendance sync failed ($action): $errorMsg',
        );

        if (errorMsg.contains("Already processed") ||
            errorMsg.contains("2 நிமிடங்கள்") ||
            errorMsg.contains("5 minutes")) {
          _showTopError(errorMsg);
          _lastActionTime = DateTime.now();
        }

        bool isNetworkError = errorMsg.toLowerCase().contains('socket') ||
            errorMsg.toLowerCase().contains('timeout') ||
            errorMsg.toLowerCase().contains('connection') ||
            errorMsg.toLowerCase().contains('http');

        if (isNetworkError || errorMsg.isEmpty) {
          if (mounted) {
            setState(() {
              if (action == 'clock_in') {
                _todayInUploadStatus = UploadStatus.failed;
              } else if (action == 'reentry') {
                _todayReentryUploadStatus = UploadStatus.failed;
              } else if (action == 'break_out') {
                _todayBreakOutUploadStatus = UploadStatus.failed;
              } else if (action == 'clock_out') {
                _todayOutUploadStatus = UploadStatus.failed;
              }
            });

            _updateLastMessageStatus(UploadStatus.failed, specificMsgId: msgId);
            _triggerChatBuild();
          }
        } else {
          if (mounted) {
            if (errorMsg.isNotEmpty &&
                !errorMsg.contains("Already processed") &&
                !errorMsg.contains("2 நிமிடங்கள்") &&
                !errorMsg.contains("5 minutes")) {
              _showTopError(errorMsg);
            }
            _updateLastMessageStatus(UploadStatus.failed, specificMsgId: msgId);
            _triggerChatBuild();
          }

          await _addSystemMessage("❌ $errorMsg", persist: true);

          if (record.localId != null) {
            await _attendanceRepo.removeRecord(record.localId!,
                salesmanId: _salesmanId);
          }

          if (mounted) {
            await _fetchAttendanceStatus(forceFullSync: true);
            await _determineClockInMode();
            setState(() {});
          }
        }
      }
    } catch (e, stackTrace) {
      debugPrint("Production Sync Error: $e\n$stackTrace");
      ActivityLogger.instance.logAttendance(
        action,
        captureTime: captureTime.toIso8601String(),
        status: 'error',
        details: 'Attendance sync exception ($action): $e',
      );
      ActivityLogger.instance.logError(
        "mark_attendance_sync",
        e.toString(),
        stackTrace: stackTrace.toString(),
      );
      if (mounted) {
        setState(() {
          if (action == 'clock_in') {
            _todayInUploadStatus = UploadStatus.failed;
          } else if (action == 'reentry') {
            _todayReentryUploadStatus = UploadStatus.failed;
          } else if (action == 'break_out') {
            _todayBreakOutUploadStatus = UploadStatus.failed;
          } else if (action == 'clock_out') {
            _todayOutUploadStatus = UploadStatus.failed;
          }
        });

        _updateLastMessageStatus(UploadStatus.failed, specificMsgId: msgId);
        _triggerChatBuild();
      }
    }

    if (mounted) {
      setState(() => _isCapturing = false);
    }
  }

  Future<void> _pickDate(String type) async {
    final DateTime now = DateTime.now();
    final DateTime lastDayOfMonth = DateTime(now.year, now.month + 1, 0);
    final DateTime firstSelectableDate = DateTime(now.year, now.month, now.day);

    final DateTime? pickedDate = await showDatePicker(
      context: context,
      helpText: "Select Date ($type)",
      cancelText: "CANCEL",
      confirmText: "CONFIRM",
      initialDate: firstSelectableDate,
      firstDate: firstSelectableDate,
      lastDate: lastDayOfMonth,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );

    if (pickedDate != null) {
      setState(() {
        _selectedLeaveType = type;
        _selectedRange = DateTimeRange(start: pickedDate, end: pickedDate);
      });
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          FocusScope.of(context).requestFocus(_messageFocusNode);
        }
      });
    } else {
      _clearLeaveSelection();
    }
  }

  void _clearLeaveSelection() {
    setState(() {
      _selectedLeaveType = null;
      _selectedRange = null;
      _messageController.clear();
    });
  }

  Future<void> _sendLeaveRequest() async {
    if (_isSendingLeave) {
      return;
    }
    if (!_isInternetConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("No Internet Connection. Cannot apply for leave.",
                style: TextStyle(fontFamily: 'Roboto'))),
      );
      return;
    }

    if (_selectedLeaveType == null || _selectedRange == null) {
      return;
    }

    final leaveDate = _selectedRange!.start;
    final now = DateTime.now();

    final dateStr = DateFormat('yyyy-MM-dd').format(leaveDate);
    final msgId = "msg_leave_${now.millisecondsSinceEpoch}";
    final String leaveType = _selectedLeaveType!;
    final String leaveReason = _messageController.text;

    final dedupeKey = '${dateStr}_${leaveType.replaceAll(' ', '')}';
    _recentlySubmittedLeaveKeys.add(dedupeKey);
    Future.delayed(const Duration(seconds: 15), () {
      _recentlySubmittedLeaveKeys.remove(dedupeKey);
    });

    final currentMsgs =
        List<AttendanceChatMessage>.from(_chatMessagesNotifier.value);
    currentMsgs.add(AttendanceChatMessage(
      id: msgId,
      type: ChatMessageType.leaveRequest,
      text: "Holiday Application ($leaveType)",
      timestamp: now,
      isSentByMe: true,
      leaveStartDate: leaveDate,
      leaveEndDate: leaveDate,
      leaveType: leaveType,
      leaveReason: leaveReason,
      leaveStatus: LeaveStatus.pending,
      uploadStatus: UploadStatus.sending,
    ));
    _chatMessagesNotifier.value = currentMsgs;
    _scrollToBottom();
    _clearLeaveSelection();

    setState(() => _isSendingLeave = true);

    try {
      final String leaveApiUrl = ApiUrl.leave;

      final Map<String, dynamic> payload = {
        'action': 'apply_leave',
        'salesman_id': _salesmanId,
        'date': dateStr,
        'type': leaveType,
        'reason': leaveReason,
      };

      final response = await http
          .post(Uri.parse(leaveApiUrl),
              headers: {"Content-Type": "application/json"},
              body: jsonEncode(payload))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['status'] == 'success') {
          final String realDocId = result['leave_id']?.toString() ?? '';
          final String serverLeaveStatus =
              result['leave_status']?.toString() ?? 'Pending';

          final localPayload = {
            'doc_id': realDocId,
            'leave_type': leaveType,
            'leave_date': dateStr,
            'reason': leaveReason,
            'status': serverLeaveStatus,
          };

          final String stdUniqueId =
              "leave_req_${_salesmanId}_${dateStr}_${leaveType.replaceAll(' ', '')}";

          await LocalDbHelper.instance.insertMessage(_salesmanId, {
            'message_text': "Holiday Application ($leaveType)",
            'message_type': 'leave_request',
            'unique_id': stdUniqueId,
            'status': serverLeaveStatus.toLowerCase(),
            'payload': jsonEncode(localPayload),
            'timestamp': now.toIso8601String(),
          });

          _recentlySubmittedLeaveKeys.remove(dedupeKey);

          LeaveStatus activeLeaveStatus = LeaveStatus.pending;

          if (serverLeaveStatus.toLowerCase() == 'approved') {
            activeLeaveStatus = LeaveStatus.approved;
          }

          if (_deferredLeaveStatuses.containsKey(dedupeKey)) {
            final deferred = _deferredLeaveStatuses.remove(dedupeKey)!;
            final deferredStatus = deferred['status'] ?? serverLeaveStatus;
            final deferredType = deferred['leave_type'] ?? leaveType;
            final deferredDocId = deferred['doc_id'] ?? realDocId;

            await LocalDbHelper.instance.updateLeaveMessageStatusByDocId(
                _salesmanId, deferredDocId, deferredStatus, deferredType);

            if (deferredStatus.toLowerCase() == 'approved') {
              activeLeaveStatus = LeaveStatus.approved;
            } else if (deferredStatus.toLowerCase() == 'rejected') {
              activeLeaveStatus = LeaveStatus.rejected;
            }
          }

          ActivityLogger.instance.logLeave(
            'apply',
            leaveType: leaveType,
            leaveDate: dateStr,
            status: 'success',
          );

          _updateLastMessageStatus(UploadStatus.success,
              specificMsgId: msgId, leaveStatus: activeLeaveStatus);

          if (result['performance_data'] != null) {
            _updatePerformanceState(result['performance_data']);
          }
          _fetchAttendanceStatus();
        } else {
          ActivityLogger.instance.logLeave(
            'apply',
            leaveType: leaveType,
            leaveDate: dateStr,
            status: 'failed - ${result['message']}',
          );
          _updateLastMessageStatus(UploadStatus.failed, specificMsgId: msgId);
          _addSystemMessage("❌ ${result['message']}", persist: false);
        }
      } else {
        ActivityLogger.instance.logLeave(
          'apply',
          leaveType: leaveType,
          leaveDate: dateStr,
          status: 'failed - HTTP ${response.statusCode}',
        );
        _updateLastMessageStatus(UploadStatus.failed, specificMsgId: msgId);
        _addSystemMessage("❌ Server Error: HTTP ${response.statusCode}",
            persist: false);
      }
    } catch (e, stackTrace) {
      debugPrint("Send Leave Request Error: $e\n$stackTrace");
      ActivityLogger.instance.logLeave(
        'apply',
        leaveType: leaveType,
        leaveDate: dateStr,
        status: 'error - network/timeout',
      );
      ActivityLogger.instance.logError('leave_apply', e.toString());
      _updateLastMessageStatus(UploadStatus.failed, specificMsgId: msgId);
      _addSystemMessage("❌ Failed to Submit Leave: Network/Timeout Error",
          persist: false);
    } finally {
      if (mounted) {
        setState(() => _isSendingLeave = false);
      }
    }
  }

  bool get _isDayComplete {
    return false;
  }

  String _resolvePhotoUrl(String? url,
      [String? fallbackDateStr, String? recordShowroom]) {
    const String dummyPhotoUrl = "";

    if (url == null ||
        url.trim().isEmpty ||
        url.contains('mock_url') ||
        url == 'null' ||
        url.contains('no-image')) {
      return dummyPhotoUrl;
    }
    if (url.startsWith('http://') ||
        url.startsWith('https://') ||
        url.startsWith('/') ||
        url.startsWith('file://') ||
        RegExp(r'^[a-zA-Z]:[/\\]').hasMatch(url) ||
        url.contains('/data/user/') ||
        url.contains('/storage/emulated/')) {
      return url;
    }

    String domain = _hostingerDomain;
    String dateStr =
        fallbackDateStr ?? DateFormat('yyyy-MM-dd').format(DateTime.now());

    try {
      if (!dateStr.contains('-')) {
        dateStr = DateFormat('yyyy-MM-dd')
            .format(DateFormat('dd MMM yyyy').parse(dateStr));
      }
    } catch (_) {}

    String safeShowroom =
        (recordShowroom ?? _showroomName).replaceAll(' ', '_');

    String resolvedUrl = "";
    if (url.startsWith("firebase_photo_uploads/")) {
      resolvedUrl = "$domain/api/$url";
    } else if (url.startsWith("/firebase_photo_uploads/")) {
      resolvedUrl = "$domain/api$url";
    } else if (url.startsWith("uploads/")) {
      resolvedUrl = "$domain/api/$url";
    } else if (url.startsWith("/uploads/")) {
      resolvedUrl = "$domain/api$url";
    } else if (url.startsWith("api/uploads/")) {
      resolvedUrl = "$domain/$url";
    } else if (url.startsWith("/api/uploads/")) {
      resolvedUrl = "$domain$url";
    } else {
      try {
        DateTime recordDate = DateTime.parse(dateStr);
        DateTime cutoffDate = DateTime(2026, 3, 31);

        if (recordDate.isAfter(cutoffDate)) {
          resolvedUrl =
              "$domain/api/firebase_photo_uploads/attendance/$safeShowroom/$dateStr/$url";
        } else {
          resolvedUrl =
              "$domain/api/uploads/attendance/$safeShowroom/$dateStr/$url";
        }
      } catch (_) {
        resolvedUrl =
            "$domain/api/firebase_photo_uploads/attendance/$safeShowroom/$dateStr/$url";
      }
    }

    debugPrint("📸 Resolving Photo: $url -> $resolvedUrl");
    return resolvedUrl;
  }

  List<Map<String, dynamic>> _getEnhancedHistory() {
    try {
      List<Map<String, dynamic>> enhanced = [];
      final now = DateTime.now();
      final todayStr = DateFormat('yyyy-MM-dd').format(now);
      final todayHuman = DateFormat('dd MMM yyyy').format(now);

      enhanced = List<Map<String, dynamic>>.from(_attendanceHistory);

      bool hasToday = false;
      for (int i = 0; i < enhanced.length; i++) {
        if (enhanced[i]['date'] == todayStr ||
            enhanced[i]['date'] == todayHuman) {
          hasToday = true;
          var record = Map<String, dynamic>.from(enhanced[i]);

          if (_todayClockIn != null) {
            record['clock_in'] = DateFormat('HH:mm:ss').format(_todayClockIn!);
            record['clock_in_time'] = record['clock_in'];
            record['clockIn'] = DateFormat('hh:mm:ss a').format(_todayClockIn!);
          }
          if (_todayClockOut != null && _resumeCount == 0) {
            record['clock_out'] =
                DateFormat('HH:mm:ss').format(_todayClockOut!);
            record['clock_out_time'] = record['clock_out'];
            record['clockOut'] =
                DateFormat('hh:mm:ss a').format(_todayClockOut!);
          } else {
            record['clock_out'] = '--:--';
            record['clock_out_time'] = '--:--';
            record['clockOut'] = '--:--';
          }

          if (_todayInImageUrl != null && _todayInImageUrl!.isNotEmpty) {
            record['thumbnail'] = _todayInImageUrl;
            record['selfie_url'] = _todayInImageUrl;
            record['in_selfie_url'] = _todayInImageUrl;
          }
          if (_todayOutImageUrl != null &&
              _todayOutImageUrl!.isNotEmpty &&
              _resumeCount == 0) {
            record['out_selfie_url'] = _todayOutImageUrl;
            record['clock_out_selfie_url'] = _todayOutImageUrl;
          } else {
            record['out_selfie_url'] = '';
            record['clock_out_selfie_url'] = '';
          }
          if (_todayReentryImageUrl != null &&
              _todayReentryImageUrl!.isNotEmpty) {
            record['reentry_selfie_url'] = _todayReentryImageUrl;
          }
          if (_todayBreakOutImageUrl != null &&
              _todayBreakOutImageUrl!.isNotEmpty) {
            record['break_out_selfie_url'] = _todayBreakOutImageUrl;
          }

          record['status'] = _currentStatusStr;
          enhanced[i] = record;
          break;
        }
      }

      if (!hasToday && (_todayClockIn != null || _todayClockOut != null)) {
        enhanced.insert(0, {
          'id': 'today_synthetic',
          'date': todayHuman,
          'clock_in': _todayClockIn != null
              ? DateFormat('HH:mm:ss').format(_todayClockIn!)
              : '--:--',
          'clock_in_time': _todayClockIn != null
              ? DateFormat('HH:mm:ss').format(_todayClockIn!)
              : '--:--',
          'clockIn': _todayClockIn != null
              ? DateFormat('hh:mm:ss a').format(_todayClockIn!)
              : '--:--',
          'clock_out': (_todayClockOut != null && _resumeCount == 0)
              ? DateFormat('HH:mm:ss').format(_todayClockOut!)
              : '--:--',
          'clock_out_time': (_todayClockOut != null && _resumeCount == 0)
              ? DateFormat('HH:mm:ss').format(_todayClockOut!)
              : '--:--',
          'clockOut': (_todayClockOut != null && _resumeCount == 0)
              ? DateFormat('hh:mm:ss a').format(_todayClockOut!)
              : '--:--',
          'status': _currentStatusStr,
          'thumbnail': _todayInImageUrl ?? '',
          'selfie_url': _todayInImageUrl ?? '',
          'in_selfie_url': _todayInImageUrl ?? '',
          'out_selfie_url': (_todayOutImageUrl != null && _resumeCount == 0)
              ? _todayOutImageUrl
              : '',
          'clock_out_selfie_url':
              (_todayOutImageUrl != null && _resumeCount == 0)
                  ? _todayOutImageUrl
                  : '',
          'reentry_selfie_url': _todayReentryImageUrl ?? '',
          'break_out_selfie_url': _todayBreakOutImageUrl ?? '',
        });
      }

      for (var i = 0; i < enhanced.length; i++) {
        var record = Map<String, dynamic>.from(enhanced[i]);
        String dStr = record['date']?.toString() ?? todayStr;

        String? inUrlRaw = (record['in_selfie_url'] ??
                record['selfie_url'] ??
                record['thumbnail'] ??
                record['clock_in_image'])
            ?.toString();
        String? outUrlRaw = (record['out_selfie_url'] ??
                record['clock_out_selfie_url'] ??
                record['clock_out_image'] ??
                record['out_thumbnail'])
            ?.toString();
        String? reUrlRaw = record['reentry_selfie_url']?.toString();
        String? brUrlRaw =
            (record['break_out_selfie_url'] ?? record['breakout_selfie_url'])
                ?.toString();

        record['thumbnail'] = _resolvePhotoUrl(inUrlRaw, dStr);
        record['selfie_url'] = record['thumbnail'];
        record['in_selfie_url'] = record['thumbnail'];
        record['clock_in_image'] = record['thumbnail'];

        record['out_selfie_url'] = _resolvePhotoUrl(outUrlRaw, dStr);
        record['clock_out_selfie_url'] = record['out_selfie_url'];
        record['clock_out_image'] = record['out_selfie_url'];
        record['out_thumbnail'] = record['out_selfie_url'];

        if (reUrlRaw != null && reUrlRaw.isNotEmpty) {
          record['reentry_selfie_url'] = _resolvePhotoUrl(reUrlRaw, dStr);
        }
        if (brUrlRaw != null && brUrlRaw.isNotEmpty) {
          record['break_out_selfie_url'] = _resolvePhotoUrl(brUrlRaw, dStr);
        }

        enhanced[i] = record;
      }
      return enhanced;
    } catch (e, stackTrace) {
      debugPrint("Enhanced history error: $e\n$stackTrace");
      return [];
    }
  }

  @override
  void dispose() {
    _leaveRequestsSubscription?.cancel();
    _holidaysSubscription?.cancel();
    _statusPollingTimer?.cancel();
    _rebuildTimer?.cancel();
    _errorHideTimer?.cancel();
    _attendanceSubscription?.cancel();
    _salesmanSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    _positionStream?.cancel();
    _uiRefreshTimer?.cancel();
    _offlineRetryTimer?.cancel();
    _attendanceStreamSub?.cancel();
    _syncEventSubscription?.cancel();
    _syncService.dispose();
    _scrollController.removeListener(_scrollListener);
    _showScrollToBottom.dispose();
    _scrollController.dispose();
    _messageController.dispose();
    _messageFocusNode.dispose();
    _chatMessagesNotifier.dispose();
    _skeletonController.dispose();
    _audioPlayer.dispose(); // 🔥 Dispose audio player
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }
        _handleBackNavigation();
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: CustomAppBar(
          title: 'Attendance',
          isOnline: _isInternetConnected,
          showBackButton: true,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: theme.colorScheme.onSurface),
            onPressed: _handleBackNavigation,
          ),
          actions: [
            if (!_allowRemoteAttendance)
              IconButton(
                icon: Icon(
                    _showHistory ? Icons.chat_rounded : Icons.history_rounded,
                    color: theme.colorScheme.onSurface,
                    size: 22),
                tooltip: _showHistory ? "Chat" : "Activity Log",
                onPressed: () {
                  final willShowHistory = !_showHistory;
                  setState(() {
                    _showHistory = willShowHistory;
                    if (willShowHistory) {
                      _isHistoryLoading = true;
                    }
                  });
                  if (willShowHistory) {
                    _fetchAttendanceHistory(
                        background: true, forceFullSync: true);
                  }
                },
              ),
            IconButton(
              icon: Icon(Icons.analytics_outlined,
                  color: theme.colorScheme.onSurface, size: 22),
              tooltip: "Today's Summary",
              onPressed: () {
                Future.delayed(const Duration(milliseconds: 50), () {
                  if (context.mounted) {
                    TodaySummaryDialog.show(
                      context,
                      todayClockIn: _todayClockIn,
                      todayClockOut: _todayClockOut,
                      attendanceRate: _attendanceRate,
                      weeklyTotal: _weeklyTotal,
                      monthlyTotal: _monthlyTotal,
                      totalWorkedDays: _totalWorkedDays,
                      totalLeavesUsed: _totalLeavesUsed,
                      excludedDates: _excludedDates,
                      currentStatus: _currentStatusStr,
                      onRefresh: () async {
                        final newData =
                            await _fetchAttendanceStatus(forceFullSync: true);
                        if (mounted) {
                          setState(() {});
                        }
                        return newData;
                      },
                    );
                  }
                });
              },
            ),
          ],
        ),
        body: SafeArea(
          bottom: false,
          child: AbsorbPointer(
            absorbing: _isInitialLoading || _isHistoryLoading,
            child: Stack(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder:
                      (Widget child, Animation<double> animation) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                  child: _isInitialLoading
                      ? KeyedSubtree(
                          key: const ValueKey('skeleton'),
                          child:
                              AttendanceSkeletonViews.buildSkeletonLoadingView(
                            theme: theme,
                            allowRemoteAttendance: _allowRemoteAttendance,
                            showHistory: _showHistory,
                            skeletonController: _skeletonController,
                            bottomPadding:
                                MediaQuery.viewPaddingOf(context).bottom,
                          ),
                        )
                      : (_showHistory || _allowRemoteAttendance)
                          ? (_isHistoryLoading
                              ? KeyedSubtree(
                                  key: const ValueKey('history_skeleton'),
                                  child: AttendanceSkeletonViews
                                      .buildHistorySkeleton(
                                    theme: theme,
                                    skeletonController: _skeletonController,
                                    bottomPadding:
                                        MediaQuery.viewPaddingOf(context)
                                            .bottom,
                                  ),
                                )
                              : KeyedSubtree(
                                  key: const ValueKey('history_data'),
                                  child: AttendanceHistoryListWidget(
                                    attendanceHistory: _getEnhancedHistory(),
                                    performanceDataList:
                                        _monthlyPerformanceList,
                                  ),
                                ))
                          : KeyedSubtree(
                              key: const ValueKey('chat_view'),
                              child: AttendanceChatView(
                                theme: theme,
                                isLoadingMore: _isLoadingMore,
                                chatMessagesNotifier: _chatMessagesNotifier,
                                scrollController: _scrollController,
                                showScrollToBottom: _showScrollToBottom,
                                messageController: _messageController,
                                messageFocusNode: _messageFocusNode,
                                selectedLeaveType: _selectedLeaveType,
                                selectedRange: _selectedRange,
                                isDayComplete: _isDayComplete,
                                isClockInMode: _isClockInMode,
                                onCameraTap: _openCamera,
                                onSendTap: _sendLeaveRequest,
                                onLeaveChipSelected: (type) async {
                                  setState(() {
                                    _selectedLeaveType = type;
                                    _selectedRange = null;
                                  });
                                  await Future.delayed(
                                      const Duration(milliseconds: 300));
                                  if (mounted) {
                                    _pickDate(type);
                                  }
                                },
                                onClearSelection: _clearLeaveSelection,
                                onManualRetry: _manualRetry,
                                onManualDelete: _manualDelete,
                              ),
                            ),
                ),
                if (_topErrorMessage != null)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade800.withValues(alpha: 0.95),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.timer_outlined,
                              color: Colors.white, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _topErrorMessage!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () =>
                                setState(() => _topErrorMessage = null),
                            child: const Icon(Icons.close,
                                color: Colors.white, size: 18),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
