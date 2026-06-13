import 'dart:convert';
import 'package:slfm_salesman_app/services/activity_logger.dart';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:sizer/sizer.dart';
import 'package:slfm_salesman_app/core/services/secure_http_client.dart'
    as http;
import 'package:uuid/uuid.dart';
import '../../core/database/local_db_helper.dart';
import '../../core/utils/network_quality_helper.dart';
import '../../widgets/custom_bottom_bar.dart';

import '../../core/constants/api_urls.dart';
import '../../services/secure_storage_service.dart';
import '../../services/feature_control_service.dart';
import '../attendance_screen/widgets/camera_capture_screen.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../widgets/custom_icon_widget.dart';
import '../../widgets/custom_image_widget.dart';
import '../../services/theme_notifier.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 🍽️ LUNCH SCREEN — Full WhatsApp-style Lunch Attendance Page
// Similar to AttendanceScreen, dedicated page for lunch in/out
// ═══════════════════════════════════════════════════════════════════════════

class LunchScreen extends StatefulWidget {
  const LunchScreen({super.key});

  @override
  State<LunchScreen> createState() => _LunchScreenState();
}

class _LunchScreenState extends State<LunchScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ─── State ─────────────────────────────────────────────────────────────
  String _salesmanId = '';
  String _lunchStatus = 'not_started'; // not_started | in_progress | completed
  String? _lunchInTime;
  String? _lunchOutTime;
  String? _lunchInSelfieUrl;
  String? _lunchOutSelfieUrl;
  String? _extraBreakDisplay;
  int _durationSeconds = 0;
  bool _isLoading = true;
  bool _isActionLoading = false;

  // ─── Cooldown & Notification State ───
  DateTime? _lastActionTime;
  String? _topErrorMessage;
  Timer? _errorHideTimer;

  // 🍽️ Feature Control State
  bool _isInLunchWindow = false;
  String _lunchStartTime = '13:00';
  String _lunchEndTime = '16:00';

  void _showTopError(String message) {
    if (!mounted) return;
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

  // History & Filter
  List<Map<String, dynamic>> _lunchHistory = [];
  bool _isHistoryLoading = true;
  DateTime _selectedMonth = DateTime.now();

  late AnimationController _pulseController;
  late AnimationController _skeletonController;
  StreamSubscription<DatabaseEvent>? _syncSubscription;

  // ─── Lifecycle ─────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _skeletonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _loadSalesmanId();
    _setupFeatureControl();
  }

  void _setupFeatureControl() {
    final service = FeatureControlService();
    service.lunchWindowOpen.addListener(_updateFeatureStates);
    service.lunchStartTime.addListener(_updateFeatureStates);
    service.lunchEndTime.addListener(_updateFeatureStates);
    _updateFeatureStates();
  }

  void _updateFeatureStates() {
    if (mounted) {
      final service = FeatureControlService();
      setState(() {
        // ✅ Trust the service fully:
        //   - Admin ON (manual) → always true (unlimited access)
        //   - Admin OFF → service checks Firebase startTime/endTime range
        _isInLunchWindow = service.lunchWindowOpen.value;

        _lunchStartTime = service.lunchStartTime.value;
        _lunchEndTime = service.lunchEndTime.value;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncSubscription?.cancel();
    _pulseController.dispose();
    _skeletonController.dispose();

    final service = FeatureControlService();
    service.lunchWindowOpen.removeListener(_updateFeatureStates);
    service.lunchStartTime.removeListener(_updateFeatureStates);
    service.lunchEndTime.removeListener(_updateFeatureStates);

    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadSalesmanId() async {
    final id = await SecureStorageService.getSalesmanId();
    if (id != null && id.isNotEmpty) {
      setState(() => _salesmanId = id);
      await Future.wait([
        _fetchLunchStatus(),
        _fetchLunchHistory(),
      ]);
      _listenToLunchSync();
    }
  }

  void _listenToLunchSync() {
    _syncSubscription?.cancel();
    _syncSubscription = FirebaseDatabase.instance
        .ref('salesmen_status/$_salesmanId')
        .onValue
        .listen((event) {
      if (!mounted) return;
      _fetchLunchStatus();
      _fetchLunchHistory();
    });
  }

  Future<void> _overlayLocalPendingLunch() async {
    if (_salesmanId.isEmpty) return;
    try {
      final pendingRecords =
          await LocalDbHelper.instance.getPendingAttendance(_salesmanId);
      if (pendingRecords.isEmpty) return;

      final now = DateTime.now();
      String? localLunchInTime;
      String? localLunchOutTime;
      String? localLunchInSelfie;
      String? localLunchOutSelfie;

      for (var record in pendingRecords) {
        final action = record['action'];
        if (action != 'lunch_in' && action != 'lunch_out') continue;

        final capTimeStr = record['capture_time']?.toString();
        if (capTimeStr == null) continue;

        try {
          final capTime = DateTime.parse(capTimeStr);
          if (DateUtils.isSameDay(capTime, now)) {
            final formatted = DateFormat('hh:mm a').format(capTime);
            final imagePath = record['image_path']?.toString();

            if (action == 'lunch_in') {
              localLunchInTime = formatted;
              localLunchInSelfie = imagePath;
            } else if (action == 'lunch_out') {
              localLunchOutTime = formatted;
              localLunchOutSelfie = imagePath;
            }
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          if (localLunchInTime != null) {
            _lunchInTime = localLunchInTime;
            _lunchInSelfieUrl = localLunchInSelfie;
            if (_lunchStatus == 'not_started') {
              _lunchStatus = 'in_progress';
            }
          }
          if (localLunchOutTime != null) {
            _lunchOutTime = localLunchOutTime;
            _lunchOutSelfieUrl = localLunchOutSelfie;
            _lunchStatus = 'completed';
          }

          // Recalculate duration if lunch_in is set
          if (_lunchInTime != null) {
            try {
              final todayStr = DateFormat('yyyy-MM-dd').format(now);
              final parsedIn = DateFormat('yyyy-MM-dd hh:mm a')
                  .parse('$todayStr $_lunchInTime');
              final end = _lunchOutTime != null
                  ? DateFormat('yyyy-MM-dd hh:mm a')
                      .parse('$todayStr $_lunchOutTime')
                  : now;
              _durationSeconds = end.difference(parsedIn).inSeconds;
              if (_durationSeconds < 0) _durationSeconds = 0;
            } catch (_) {}
          }
        });

        // 🍽️ Update global flags so bottom bar allows access for pending Lunch Out
        final svc = FeatureControlService();
        svc.lunchInProgress.value = (_lunchStatus == 'in_progress');
        svc.lunchCompleted.value = (_lunchStatus == 'completed');
        if (_lunchStatus == 'in_progress' || _lunchStatus == 'completed') {
          final today = DateTime.now();
          svc.lunchStatusDate.value =
              '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
        }
      }
    } catch (e) {
      debugPrint("Error in _overlayLocalPendingLunch: $e");
    }
  }

  Future<void> _overlayLocalPendingHistory() async {
    if (_salesmanId.isEmpty) return;
    try {
      final pendingRecords =
          await LocalDbHelper.instance.getPendingAttendance(_salesmanId);
      if (pendingRecords.isEmpty) return;

      final List<Map<String, dynamic>> updatedHistory =
          List<Map<String, dynamic>>.from(_lunchHistory);

      for (var record in pendingRecords) {
        final action = record['action'];
        if (action != 'lunch_in' && action != 'lunch_out') continue;

        final capTimeStr = record['capture_time']?.toString();
        if (capTimeStr == null) continue;

        try {
          final capTime = DateTime.parse(capTimeStr);
          if (capTime.month == _selectedMonth.month &&
              capTime.year == _selectedMonth.year) {
            final dateKey = DateFormat('yyyy-MM-dd').format(capTime);
            final formattedTime = DateFormat('hh:mm a').format(capTime);
            final imagePath = record['image_path']?.toString();

            // Find existing record in updatedHistory for dateKey
            int idx = updatedHistory.indexWhere((h) => h['date'] == dateKey);
            if (idx != -1) {
              final Map<String, dynamic> existing =
                  Map<String, dynamic>.from(updatedHistory[idx]);
              if (action == 'lunch_in') {
                existing['lunch_in_time'] = formattedTime;
                existing['lunch_in_selfie_url'] = imagePath;
              } else if (action == 'lunch_out') {
                existing['lunch_out_time'] = formattedTime;
                existing['lunch_out_selfie_url'] = imagePath;
              }
              // Recalculate duration
              if (existing['lunch_in_time'] != null) {
                try {
                  final parsedIn = DateFormat('yyyy-MM-dd hh:mm a')
                      .parse('$dateKey ${existing['lunch_in_time']}');
                  final parsedOut = existing['lunch_out_time'] != null
                      ? DateFormat('yyyy-MM-dd hh:mm a')
                          .parse('$dateKey ${existing['lunch_out_time']}')
                      : capTime;
                  existing['duration_seconds'] =
                      parsedOut.difference(parsedIn).inSeconds;
                  if (existing['duration_seconds'] < 0) {
                    existing['duration_seconds'] = 0;
                  }
                } catch (_) {}
              }
              existing['is_pending'] = true;
              updatedHistory[idx] = existing;
            } else {
              // Create new history record
              final Map<String, dynamic> newRecord = {
                'date': dateKey,
                'lunch_in_time': action == 'lunch_in' ? formattedTime : null,
                'lunch_in_selfie_url': action == 'lunch_in' ? imagePath : null,
                'lunch_out_time': action == 'lunch_out' ? formattedTime : null,
                'lunch_out_selfie_url':
                    action == 'lunch_out' ? imagePath : null,
                'duration_seconds': 0,
                'extra_break_display': null,
                'is_pending': true,
              };
              updatedHistory.add(newRecord);
            }
          }
        } catch (_) {}
      }

      // Sort by date descending
      updatedHistory.sort((a, b) =>
          (b['date']?.toString() ?? '').compareTo(a['date']?.toString() ?? ''));

      if (mounted) {
        setState(() {
          _lunchHistory = updatedHistory;
          _isHistoryLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error in _overlayLocalPendingHistory: $e");
    }
  }

  // ─── API: Fetch Lunch Status ───────────────────────────────────────────
  Future<void> _fetchLunchStatus() async {
    if (_salesmanId.isEmpty) return;
    try {
      final res = await http
          .post(
            Uri.parse(ApiUrl.lunch),
            body: jsonEncode({
              "action": "get_lunch_status",
              "salesman_id": _salesmanId,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['status'] == 'success' && body['data'] != null) {
          final data = body['data'];
          if (mounted) {
            setState(() {
              _lunchStatus = data['lunch_status'] ?? 'not_started';
              _lunchInTime = data['lunch_in_time'];
              _lunchOutTime = data['lunch_out_time'];
              _lunchInSelfieUrl = data['lunch_in_selfie_url'];
              _lunchOutSelfieUrl = data['lunch_out_selfie_url'];
              _extraBreakDisplay = data['extra_break_display'];
              _durationSeconds = data['duration_seconds'] ?? 0;
              _isLoading = false;
            });
            // 🍽️ Update global flags so bottom bar allows access for pending Lunch Out
            final svc = FeatureControlService();
            svc.lunchInProgress.value = (_lunchStatus == 'in_progress');
            svc.lunchCompleted.value = (_lunchStatus == 'completed');
            if (_lunchStatus == 'in_progress' || _lunchStatus == 'completed') {
              final now = DateTime.now();
              svc.lunchStatusDate.value =
                  '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
            }
          }
        } else {
          if (mounted) setState(() => _isLoading = false);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    } finally {
      await _overlayLocalPendingLunch();
    }
  }

  // ─── API: Fetch Lunch History ──────────────────────────────────────────
  Future<void> _fetchLunchHistory() async {
    if (_salesmanId.isEmpty) return;
    try {
      final res = await http
          .post(
            Uri.parse(ApiUrl.lunch),
            body: jsonEncode({
              "action": "get_lunch_history",
              "salesman_id": _salesmanId,
              "month": _selectedMonth.month,
              "year": _selectedMonth.year,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['status'] == 'success' && body['data'] != null) {
          if (mounted) {
            setState(() {
              _lunchHistory = List<Map<String, dynamic>>.from(body['data']);
              _isHistoryLoading = false;
            });
          }
        } else {
          if (mounted) setState(() => _isHistoryLoading = false);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isHistoryLoading = false);
    } finally {
      await _overlayLocalPendingHistory();
    }
  }

  String? _pendingImagePath;

  // ─── Lunch In / Out Action ─────────────────────────────────────────────
  Future<void> _handleLunchAction({String? retryImagePath}) async {
    if (_lunchStatus == 'completed') {
      _showSnack('Lunch break already completed for today! ✅', isError: false);
      return;
    }

    // ─── Cooldown Check (5 Minutes) ───
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

    // ─── Lunch Window Check ───
    // 🔥 CRITICAL: If outside window, show LOCK SCREEN regardless of status
    // (Except when lunch is currently in progress, to allow stopping)
    if (!_isInLunchWindow && _lunchStatus != 'in_progress') {
      // Convert 13:00 to 01:00 PM format for display
      String formatTime(String time24) {
        try {
          final parts = time24.split(':');
          if (parts.length != 2) return time24;
          int h = int.parse(parts[0]);
          int m = int.parse(parts[1]);
          String ampm = h >= 12 ? 'PM' : 'AM';
          h = h % 12;
          if (h == 0) h = 12;
          String mm = m.toString().padLeft(2, '0');
          String hh = h.toString().padLeft(2, '0');
          return "$hh:$mm $ampm";
        } catch (_) {
          return time24;
        }
      }

      final displayStart = formatTime(_lunchStartTime);
      final displayEnd = formatTime(_lunchEndTime);

      _showTopError(
          "Lunch window is locked! Available only from $displayStart to $displayEnd.");
      return;
    }

    HapticFeedback.lightImpact();

    String? imagePath = retryImagePath;

    if (imagePath == null) {
      // 1. Capture selfie
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CameraCaptureScreen(
            isClockIn: _lunchStatus == 'not_started',
          ),
        ),
      );

      if (result == null || result is! Map || result['path'] == null) return;
      imagePath = result['path'];
    }

    setState(() => _isActionLoading = true);
    _pendingImagePath = imagePath;

    final String path = imagePath!;
    final String action =
        _lunchStatus == 'not_started' ? 'lunch_in' : 'lunch_out';

    // ─── Network Quality / Presence Check ───
    final hasInternet = await NetworkQualityHelper.hasRealInternet();
    if (!hasInternet) {
      // Offline Flow: Fast, Local SQLite Insertion, Success Toast, Instant Overlay
      double? offlineLat;
      double? offlineLng;

      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 4),
          ),
        );
        offlineLat = pos.latitude;
        offlineLng = pos.longitude;
      } catch (_) {
        try {
          final pos = await Geolocator.getLastKnownPosition();
          if (pos != null) {
            offlineLat = pos.latitude;
            offlineLng = pos.longitude;
          }
        } catch (_) {}
      }

      final now = DateTime.now();
      final nowStr = now.toIso8601String();
      final attUid = const Uuid().v4();

      try {
        final pendingRecords =
            await LocalDbHelper.instance.getPendingAttendance(_salesmanId);
        final hasDuplicate = pendingRecords.any((p) {
          try {
            final t = DateTime.parse(p['capture_time'].toString());
            return DateUtils.isSameDay(t, now) && p['action'] == action;
          } catch (_) {
            return false;
          }
        });

        if (!hasDuplicate) {
          final record = {
            'attendance_uid': attUid,
            'action': action,
            'latitude': offlineLat?.toString() ?? '',
            'longitude': offlineLng?.toString() ?? '',
            'capture_time': nowStr,
            'image_path': path,
            'status': 'pending',
            'created_at': DateTime.now().millisecondsSinceEpoch,
            'retry_count': 0,
          };
          await LocalDbHelper.instance
              .insertPendingAttendance(_salesmanId, record);
        }

        _lastActionTime = now;
        _pendingImagePath = null;

        _showSnack(
            'Offline mode: Lunch status updated locally. Syncing in background! 💾',
            isError: false);

        ActivityLogger.instance.logLunch(
          action,
          details: 'Offline mode: Lunch $action saved locally.',
        );

        await _overlayLocalPendingLunch();
        await _overlayLocalPendingHistory();
      } catch (e) {
        _showSnack('Offline Save Failed: $e', isError: true);
        ActivityLogger.instance.logLunch(
          action,
          details: 'Offline mode: Save failed: $e',
        );
      } finally {
        if (mounted) setState(() => _isActionLoading = false);
      }
      return;
    }

    // 🔥 READ LOCATION FROM RTDB (anti-spoofed, continuously tracked)
    double? rtdbLat;
    double? rtdbLng;
    try {
      final rtdbRef = FirebaseDatabase.instance.ref('locations/$_salesmanId');
      final snapshot = await rtdbRef.get().timeout(const Duration(seconds: 5));
      if (snapshot.exists && snapshot.value != null) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        rtdbLat = double.tryParse(data['lat']?.toString() ?? '');
        rtdbLng = double.tryParse(data['lng']?.toString() ?? '');
      }
    } catch (_) {}

    // Fallback to GPS if RTDB has no data
    if (rtdbLat == null || rtdbLng == null) {
      try {
        if (await Geolocator.isLocationServiceEnabled()) {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 10),
            ),
          );
          rtdbLat = pos.latitude;
          rtdbLng = pos.longitude;
        }
      } catch (_) {}
    }

    // Helper function to handle online failures gracefully (save to SQLite and overlay instantly)
    Future<void> saveToPendingAndOverlay(String reason) async {
      final now = DateTime.now();
      final nowStr = now.toIso8601String();
      final attUid = const Uuid().v4();

      try {
        final pendingRecords =
            await LocalDbHelper.instance.getPendingAttendance(_salesmanId);
        final hasDuplicate = pendingRecords.any((p) {
          try {
            final t = DateTime.parse(p['capture_time'].toString());
            return DateUtils.isSameDay(t, now) && p['action'] == action;
          } catch (_) {
            return false;
          }
        });

        if (!hasDuplicate) {
          final record = {
            'attendance_uid': attUid,
            'action': action,
            'latitude': rtdbLat?.toString() ?? '',
            'longitude': rtdbLng?.toString() ?? '',
            'capture_time': nowStr,
            'image_path': path,
            'status': 'pending',
            'created_at': DateTime.now().millisecondsSinceEpoch,
            'retry_count': 0,
          };
          await LocalDbHelper.instance
              .insertPendingAttendance(_salesmanId, record);
        }

        await _overlayLocalPendingLunch();
        await _overlayLocalPendingHistory();
      } catch (e) {
        debugPrint("Failed to write online fallback to SQLite: $e");
      }

      _showSnack('Syncing in background: $reason', canRetry: true);
    }

    try {
      // 2. Encode image
      final bytes = await File(path).readAsBytes();
      final String base64Image =
          'data:image/jpeg;base64,${base64Encode(bytes)}';

      // 3. Send to API
      final response = await http
          .post(
            Uri.parse(ApiUrl.lunch),
            body: jsonEncode({
              "action": action,
              "salesman_id": _salesmanId,
              "selfie_url": base64Image,
              "latitude": rtdbLat?.toString() ?? '',
              "longitude": rtdbLng?.toString() ?? '',
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final lData = jsonDecode(response.body);
        if (lData['status'] == 'success') {
          _lastActionTime = DateTime.now();
          _pendingImagePath = null;
          _showSnack(lData['message'], isError: false);

          // Clear today's pending record of same action
          try {
            final pending =
                await LocalDbHelper.instance.getPendingAttendance(_salesmanId);
            for (var p in pending) {
              try {
                final t = DateTime.parse(p['capture_time'].toString());
                if (DateUtils.isSameDay(t, DateTime.now()) &&
                    p['action'] == action) {
                  await LocalDbHelper.instance
                      .deletePendingAttendance(p['local_id']);
                }
              } catch (_) {}
            }
          } catch (e) {
            debugPrint("Error clearing pending record: $e");
          }

          // 🔥 LOG SUCCESS
          ActivityLogger.instance.logLunch(
            action,
            details:
                'Lunch $action success at ${DateFormat('hh:mm a').format(DateTime.now())}',
          );

          // Refresh both
          await Future.wait([
            _fetchLunchStatus(),
            _fetchLunchHistory(),
          ]);
        } else {
          String errorMsg = lData['message']?.toString() ?? "";
          if (errorMsg.contains("Already processed") ||
              errorMsg.contains("minutes")) {
            _showTopError(errorMsg);
            _lastActionTime = DateTime.now();
          }

          await saveToPendingAndOverlay('Error: $errorMsg');

          // 🔥 LOG FAILURE
          ActivityLogger.instance.logLunch(
            action,
            details: 'Lunch $action FAILED: $errorMsg',
          );
        }
      } else {
        await saveToPendingAndOverlay('Server Error: ${response.statusCode}');

        // 🔥 LOG SERVER ERROR
        ActivityLogger.instance.logLunch(
          action,
          details: 'Lunch $action SERVER ERROR: HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      await saveToPendingAndOverlay('Failed: $e');

      // 🔥 LOG EXCEPTION
      ActivityLogger.instance.logLunch(
        action,
        details: 'Lunch $action EXCEPTION: $e',
      );
      ActivityLogger.instance.logError('lunch_screen', e.toString());
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  void _showSnack(String msg, {bool isError = true, bool canRetry = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : const Color(0xFF25D366),
        duration:
            canRetry ? const Duration(seconds: 8) : const Duration(seconds: 3),
        action: canRetry
            ? SnackBarAction(
                label: 'RETRY',
                textColor: Colors.white,
                onPressed: () {
                  if (_pendingImagePath != null) {
                    _handleLunchAction(retryImagePath: _pendingImagePath);
                  }
                },
              )
            : null,
      ),
    );
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return "--";
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return "${h}h ${m}m ${s}s";
    if (m > 0) return "${m}m ${s}s";
    return "${s}s";
  }

  String _getTamilGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'காலை வணக்கம்'; // Good Morning
    if (hour < 16) return 'மதிய வணக்கம்'; // Good Afternoon
    return 'மாலை வணக்கம்'; // Good Evening
  }

  // ═══════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    final Color scaffoldBg = theme.scaffoldBackgroundColor;
    final Color appBarBg =
        theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface;
    final Color textPrimary = theme.colorScheme.onSurface;
    final Color textSecondary = theme.colorScheme.onSurfaceVariant;

    return Scaffold(
      backgroundColor: scaffoldBg,
      bottomNavigationBar: CustomBottomBar(currentRoute: '/lunch-screen'),
      appBar: AppBar(
        backgroundColor: appBarBg,
        elevation: isDark ? 0 : 1,
        shadowColor: isDark ? Colors.transparent : Colors.black12,
        automaticallyImplyLeading: false, // 🔥 REMOVE BACK BUTTON
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF25D366).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.restaurant,
                  color: Color(0xFF25D366), size: 20),
            ),
            SizedBox(width: 3.w),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lunch Time',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _lunchStatus == 'not_started'
                      ? 'Not started'
                      : _lunchStatus == 'in_progress'
                          ? 'In progress...'
                          : 'Completed ✅',
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 9.sp,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // 🔥 THEME TOGGLE
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              color: isDark ? Colors.orange : theme.colorScheme.primary,
            ),
            onPressed: () {
              themeNotifier.setThemeMode(
                isDark ? ThemeMode.light : ThemeMode.dark,
              );
            },
            tooltip: 'Toggle Theme',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF25D366)),
            onPressed: () {
              setState(() {
                _isLoading = true;
                _isHistoryLoading = true;
              });
              Future.wait([_fetchLunchStatus(), _fetchLunchHistory()]);
            },
          ),
        ],
      ),
      body: SafeArea(
        bottom: false, // CustomBottomBar handles bottom gesture area
        child: Stack(
          children: [
            _isLoading
                ? _buildSkeletonLoading(theme)
                : RefreshIndicator(
                    color: const Color(0xFF25D366),
                    onRefresh: () async {
                      await Future.wait(
                          [_fetchLunchStatus(), _fetchLunchHistory()]);
                    },
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding:
                          EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
                      children: [
                        // ─── Greeting Message ───
                        Padding(
                          padding: EdgeInsets.only(bottom: 2.h, left: 1.w),
                          child: Text(
                            '${_getTamilGreeting()}, 🍽️',
                            style: TextStyle(
                              color: const Color(0xFF25D366),
                              fontSize: 14.sp,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),

                        // ─── Today's Lunch Card ───
                        _buildTodaySummaryCard(theme),
                        SizedBox(height: 2.h),

                        // ─── Action Button ───
                        if (_lunchStatus != 'completed')
                          _buildActionButton(theme),
                        if (_lunchStatus != 'completed') SizedBox(height: 2.h),

                        // ─── History Section ───
                        _buildHistoryHeader(theme),
                        SizedBox(height: 1.h),
                        _buildHistoryList(theme),
                      ],
                    ),
                  ),
            if (_topErrorMessage != null)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
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
                        onTap: () => setState(() => _topErrorMessage = null),
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
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TODAY'S SUMMARY CARD
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildTodaySummaryCard(ThemeData theme) {
    final bool isDark = theme.brightness == Brightness.dark;
    final Color cardBg = theme.colorScheme.surface;
    final Color textPrimary = theme.colorScheme.onSurface;
    final Color dividerColor = theme.dividerColor;

    final Color statusColor = _lunchStatus == 'completed'
        ? const Color(0xFF25D366)
        : _lunchStatus == 'in_progress'
            ? Colors.orange
            : Colors.grey;

    final String statusLabel = _lunchStatus == 'completed'
        ? '✅ Completed'
        : _lunchStatus == 'in_progress'
            ? '🍽️ In Progress'
            : '⏳ Not Started';

    return Container(
      padding: EdgeInsets.all(4.w),
      decoration: BoxDecoration(
        color: cardBg,
        gradient: isDark
            ? LinearGradient(
                colors: [
                  theme.colorScheme.surface,
                  theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5)
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? statusColor.withValues(alpha: 0.4)
              : theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Today's Lunch",
                style: TextStyle(
                  color: textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13.sp,
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 3.w, vertical: 0.5.h),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 9.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 2.h),

          // In / Out Row
          Row(
            children: [
              // Lunch In
              Expanded(
                child: _buildTimeBlock(
                  theme: theme,
                  icon: Icons.login,
                  label: 'Lunch In',
                  time: _lunchInTime,
                  color: const Color(0xFF25D366),
                  selfieUrl: _lunchInSelfieUrl,
                ),
              ),
              // Divider
              Container(
                height: 8.h,
                width: 1,
                margin: EdgeInsets.symmetric(horizontal: 2.w),
                color: dividerColor,
              ),
              // Lunch Out
              Expanded(
                child: _buildTimeBlock(
                  theme: theme,
                  icon: Icons.logout,
                  label: 'Lunch Out',
                  time: _lunchOutTime,
                  color: Colors.orange,
                  selfieUrl: _lunchOutSelfieUrl,
                ),
              ),
            ],
          ),

          // Duration & Extra Break
          if (_lunchStatus != 'not_started') ...[
            SizedBox(height: 1.5.h),
            Divider(color: dividerColor),
            SizedBox(height: 1.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Duration
                Row(
                  children: [
                    Icon(Icons.timer_outlined,
                        size: 16, color: theme.colorScheme.onSurfaceVariant),
                    SizedBox(width: 1.w),
                    Text(
                      'Duration: ${_formatDuration(_durationSeconds)}',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                // Extra break badge
                if (_extraBreakDisplay != null &&
                    _extraBreakDisplay!.isNotEmpty)
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 2.w, vertical: 0.3.h),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: Colors.red.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 12, color: Colors.red.shade300),
                        SizedBox(width: 1.w),
                        Text(
                          _extraBreakDisplay!,
                          style: TextStyle(
                            color: Colors.red.shade300,
                            fontWeight: FontWeight.bold,
                            fontSize: 9.sp,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimeBlock({
    required ThemeData theme,
    required IconData icon,
    required String label,
    required String? time,
    required Color color,
    String? selfieUrl,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 9.sp,
          ),
        ),
        SizedBox(height: 1.h),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (selfieUrl != null && selfieUrl.isNotEmpty) ...[
              GestureDetector(
                onTap: () => _showImagePreview(selfieUrl),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: color.withValues(alpha: 0.5), width: 1.5),
                  ),
                  child: CustomImageWidget(
                    imageUrl: selfieUrl,
                    fit: BoxFit.cover,
                    radius: BorderRadius.circular(7),
                    placeHolder: 'assets/images/NO_IMAGE.jpg',
                    errorWidget: Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.image_not_supported,
                          size: 18, color: Colors.grey),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 2.w),
            ] else ...[
              GestureDetector(
                onTap: () => _showImagePreview(""),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: CustomImageWidget(
                    imageUrl: "",
                    fit: BoxFit.cover,
                    radius: BorderRadius.circular(8),
                    placeHolder: 'assets/images/NO_IMAGE.jpg',
                  ),
                ),
              ),
              SizedBox(width: 2.w),
            ],
            Flexible(
              child: Text(
                time ?? '--:--',
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 12.sp,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showImagePreview(String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: InteractiveViewer(
            child: CustomImageWidget(
              imageUrl: imageUrl,
              fit: BoxFit.contain,
              placeHolder: 'assets/images/NO_IMAGE.jpg',
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ACTION BUTTON
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildActionButton(ThemeData theme) {
    return ValueListenableBuilder<bool>(
        valueListenable: FeatureControlService().lunchWindowOpen,
        builder: (context, isWindowOpen, child) {
          final bool isLunchIn = _lunchStatus == 'not_started';
          final bool isLocked = !isWindowOpen && isLunchIn;

          final Color btnColor = isLocked
              ? Colors.grey.shade600
              : (isLunchIn ? const Color(0xFF25D366) : Colors.orange);
          final String btnLabel = isLocked
              ? '🔒 Lunch Window Closed'
              : (isLunchIn ? '🍽️ Start Lunch' : '✅ End Lunch');
          final IconData btnIcon = isLocked
              ? Icons.lock
              : (isLunchIn ? Icons.restaurant : Icons.check_circle);

          return AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final scale =
                  isLocked ? 1.0 : 1.0 + (_pulseController.value * 0.02);
              return Transform.scale(
                scale: _isActionLoading ? 1.0 : scale,
                child: Container(
                  width: double.infinity,
                  height: 7.h,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      colors: [
                        btnColor,
                        btnColor.withValues(alpha: 0.8),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: btnColor.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: (_isActionLoading || isLocked)
                          ? null
                          : _handleLunchAction,
                      child: Center(
                        child: _isActionLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(btnIcon, color: Colors.white, size: 22),
                                  SizedBox(width: 2.w),
                                  Text(
                                    btnLabel,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13.sp,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        });
  }

  // ═══════════════════════════════════════════════════════════════════════
  // HISTORY SECTION
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildHistoryHeader(ThemeData theme) {
    final Color cardBg = theme.colorScheme.surface;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFF25D366).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.history, color: Color(0xFF25D366), size: 18),
        ),
        SizedBox(width: 2.w),
        Text(
          'Lunch History',
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.bold,
            fontSize: 12.sp,
          ),
        ),
        const Spacer(),
        // ─── Month Filter Button ───
        GestureDetector(
          onTap: () async {
            // Simplified Month Picker via Dialog
            await _showMonthPicker();
          },
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 3.w, vertical: 0.8.h),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Text(
                  DateFormat('MMM yyyy').format(_selectedMonth),
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 10.sp,
                  ),
                ),
                SizedBox(width: 1.w),
                Icon(Icons.arrow_drop_down,
                    color: theme.colorScheme.onSurfaceVariant, size: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showMonthPicker() async {
    DateTime tempDate = _selectedMonth;

    // Calculate initial indices for controllers
    final int initialMonthIndex = tempDate.month - 1;
    final int startYear = DateTime.now().year - 2;
    final int initialYearIndex = tempDate.year - startYear;

    final monthController =
        FixedExtentScrollController(initialItem: initialMonthIndex);
    final yearController =
        FixedExtentScrollController(initialItem: initialYearIndex);

    await showDialog(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: theme.colorScheme.surface,
              title: Text('Select Month',
                  style: TextStyle(color: theme.colorScheme.onSurface)),
              content: SizedBox(
                height: 200,
                width: 300,
                child: Row(
                  children: [
                    // Month Spinner
                    Expanded(
                      child: ListWheelScrollView.useDelegate(
                        controller: monthController,
                        itemExtent: 40,
                        perspective: 0.005,
                        physics: const FixedExtentScrollPhysics(),
                        onSelectedItemChanged: (index) {
                          setDialogState(() {
                            tempDate = DateTime(tempDate.year, index + 1, 1);
                          });
                        },
                        childDelegate: ListWheelChildBuilderDelegate(
                          childCount: 12,
                          builder: (context, index) {
                            final isSelected = (index + 1) == tempDate.month;
                            return Center(
                              child: Text(
                                DateFormat('MMM')
                                    .format(DateTime(2022, index + 1, 1)),
                                style: TextStyle(
                                  fontSize: isSelected ? 16.sp : 14.sp,
                                  color: isSelected
                                      ? const Color(0xFF25D366)
                                      : theme.colorScheme.onSurfaceVariant
                                          .withValues(alpha: 0.5),
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    // Year Spinner
                    Expanded(
                      child: ListWheelScrollView.useDelegate(
                        controller: yearController,
                        itemExtent: 40,
                        perspective: 0.005,
                        physics: const FixedExtentScrollPhysics(),
                        onSelectedItemChanged: (index) {
                          setDialogState(() {
                            tempDate =
                                DateTime(startYear + index, tempDate.month, 1);
                          });
                        },
                        childDelegate: ListWheelChildBuilderDelegate(
                          childCount: 5,
                          builder: (context, index) {
                            final year = startYear + index;
                            final isSelected = year == tempDate.year;
                            return Center(
                              child: Text(
                                year.toString(),
                                style: TextStyle(
                                  fontSize: isSelected ? 16.sp : 14.sp,
                                  color: isSelected
                                      ? const Color(0xFF25D366)
                                      : theme.colorScheme.onSurfaceVariant
                                          .withValues(alpha: 0.5),
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel',
                      style: TextStyle(color: Colors.grey)),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedMonth = tempDate;
                      _isHistoryLoading = true;
                    });
                    _fetchLunchHistory();
                    Navigator.pop(context);
                  },
                  child: const Text('Apply',
                      style: TextStyle(color: Color(0xFF25D366))),
                ),
              ],
            );
          },
        );
      },
    );

    monthController.dispose();
    yearController.dispose();
  }

  Widget _buildHistoryList(ThemeData theme) {
    if (_isHistoryLoading) {
      return _buildHistorySkeletonList(theme);
    }

    if (_lunchHistory.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(top: 6.h),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.restaurant_menu,
                  size: 48,
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.5)),
              SizedBox(height: 1.h),
              Text(
                'No lunch records yet',
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11.sp,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children:
          _lunchHistory.map((record) => _buildHistoryCard(record)).toList(),
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> record) {
    final String date = record['date']?.toString() ?? '';
    final String? lunchIn = record['lunch_in_time']?.toString();
    final String? lunchOut = record['lunch_out_time']?.toString();
    final String? inUrl = record['lunch_in_selfie_url']?.toString();
    final String? outUrl = record['lunch_out_selfie_url']?.toString();
    final String? extraDisplay = record['extra_break_display']?.toString();
    final int duration = record['duration_seconds'] ?? 0;
    final bool hasExtra = extraDisplay != null && extraDisplay.isNotEmpty;

    // Format date
    String displayDate = date;
    try {
      final parsed = DateFormat('yyyy-MM-dd').parse(date);
      final now = DateTime.now();
      final today = DateFormat('yyyy-MM-dd').format(now);
      final yesterday = DateFormat('yyyy-MM-dd')
          .format(now.subtract(const Duration(days: 1)));
      if (date == today) {
        displayDate = 'Today';
      } else if (date == yesterday) {
        displayDate = 'Yesterday';
      } else {
        displayDate = DateFormat('dd MMM yyyy').format(parsed);
      }
    } catch (_) {}

    final theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color cardBg = theme.colorScheme.surface;
    final Color textPrimary = theme.colorScheme.onSurface;
    final Color dividerColor = theme.dividerColor;

    return Container(
      margin: EdgeInsets.only(bottom: 1.5.h),
      padding: EdgeInsets.all(3.5.w),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasExtra
              ? Colors.red.withValues(alpha: 0.3)
              : const Color(0xFF25D366).withValues(alpha: isDark ? 0.15 : 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date header row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  CustomIconWidget(
                    iconName: 'calendar_today',
                    color: const Color(0xFF25D366),
                    size: 14,
                  ),
                  SizedBox(width: 1.5.w),
                  Text(
                    displayDate,
                    style: TextStyle(
                      color: textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 10.sp,
                    ),
                  ),
                ],
              ),
              // Extra break badge
              if (hasExtra)
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 2.w, vertical: 0.3.h),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    extraDisplay,
                    style: TextStyle(
                      color: Colors.red.shade300,
                      fontWeight: FontWeight.bold,
                      fontSize: 9.sp,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 1.h),
          // In / Out times
          Row(
            children: [
              // In
              Expanded(
                child: Row(
                  children: [
                    if (inUrl != null && inUrl.isNotEmpty)
                      GestureDetector(
                        onTap: () => _showImagePreview(inUrl),
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                          ),
                          child: CustomImageWidget(
                            imageUrl: inUrl,
                            fit: BoxFit.cover,
                            radius: BorderRadius.circular(5),
                            placeHolder: 'assets/images/NO_IMAGE.jpg',
                            errorWidget: Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: const Icon(Icons.image_not_supported,
                                  size: 12, color: Colors.grey),
                            ),
                          ),
                        ),
                      )
                    else
                      GestureDetector(
                        onTap: () => _showImagePreview(""),
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                          ),
                          child: CustomImageWidget(
                            imageUrl: "",
                            fit: BoxFit.cover,
                            radius: BorderRadius.circular(6),
                            placeHolder: 'assets/images/NO_IMAGE.jpg',
                          ),
                        ),
                      ),
                    SizedBox(width: 1.w),
                    Text(
                      lunchIn ?? '--:--',
                      style: TextStyle(
                        color: textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 10.sp,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                height: 3.h,
                width: 1,
                color: dividerColor,
              ),
              // Out
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: 3.w),
                  child: Row(
                    children: [
                      if (outUrl != null && outUrl.isNotEmpty)
                        GestureDetector(
                          onTap: () => _showImagePreview(outUrl),
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                            ),
                            child: CustomImageWidget(
                              imageUrl: outUrl,
                              fit: BoxFit.cover,
                              radius: BorderRadius.circular(5),
                              placeHolder:
                                  'assets/images/entha_payanum_illa.jpg',
                              errorWidget: Container(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                child: const Icon(Icons.image_not_supported,
                                    size: 12, color: Colors.grey),
                              ),
                            ),
                          ),
                        )
                      else
                        GestureDetector(
                          onTap: () => _showImagePreview(""),
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                            ),
                            child: CustomImageWidget(
                              imageUrl: "",
                              fit: BoxFit.cover,
                              radius: BorderRadius.circular(6),
                              placeHolder:
                                  'assets/images/entha_payanum_illa.jpg',
                            ),
                          ),
                        ),
                      SizedBox(width: 1.w),
                      Text(
                        lunchOut ?? '--:--',
                        style: TextStyle(
                          color: textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 10.sp,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Duration
              Text(
                _formatDuration(duration),
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 9.sp,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SKELETON LOADING VIEW
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildSkeletonLoading(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final baseColor = theme.colorScheme.surfaceContainerHighest;
    final cardColor = theme.colorScheme.surface;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Greeting Skeleton
          FadeTransition(
            opacity: Tween<double>(begin: 0.5, end: 1.0)
                .animate(_skeletonController),
            child: Container(
              margin: EdgeInsets.only(bottom: 2.h),
              width: 150,
              height: 20,
              decoration: BoxDecoration(
                  color: baseColor, borderRadius: BorderRadius.circular(4)),
            ),
          ),

          // Card Skeleton
          FadeTransition(
            opacity: Tween<double>(begin: 0.5, end: 1.0)
                .animate(_skeletonController),
            child: Container(
              height: 18.h,
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(16),
                border:
                    !isDark ? Border.all(color: Colors.grey.shade200) : null,
              ),
              padding: EdgeInsets.all(4.w),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(width: 100, height: 16, color: baseColor),
                      Container(
                          width: 80,
                          height: 24,
                          decoration: BoxDecoration(
                              color: baseColor,
                              borderRadius: BorderRadius.circular(12))),
                    ],
                  ),
                  SizedBox(height: 3.h),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          Container(width: 60, height: 12, color: baseColor),
                          SizedBox(height: 1.h),
                          Container(width: 80, height: 20, color: baseColor),
                        ],
                      ),
                      Column(
                        children: [
                          Container(width: 60, height: 12, color: baseColor),
                          SizedBox(height: 1.h),
                          Container(width: 80, height: 20, color: baseColor),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 2.h),

          // Button Skeleton
          FadeTransition(
            opacity: Tween<double>(begin: 0.5, end: 1.0)
                .animate(_skeletonController),
            child: Container(
              width: double.infinity,
              height: 7.h,
              decoration: BoxDecoration(
                  color: baseColor, borderRadius: BorderRadius.circular(14)),
            ),
          ),
          SizedBox(height: 3.h),

          // History Title Skeleton
          FadeTransition(
            opacity: Tween<double>(begin: 0.5, end: 1.0)
                .animate(_skeletonController),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(width: 120, height: 20, color: baseColor),
                Container(
                    width: 80,
                    height: 24,
                    decoration: BoxDecoration(
                        color: baseColor,
                        borderRadius: BorderRadius.circular(12))),
              ],
            ),
          ),
          SizedBox(height: 2.h),

          // History List Skeleton
          Expanded(child: _buildHistorySkeletonList(theme)),
        ],
      ),
    );
  }

  Widget _buildHistorySkeletonList(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final baseColor = theme.colorScheme.surfaceContainerHighest;
    final cardColor = theme.colorScheme.surface;

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 4,
      itemBuilder: (context, index) {
        return FadeTransition(
          opacity:
              Tween<double>(begin: 0.5, end: 1.0).animate(_skeletonController),
          child: Container(
            margin: EdgeInsets.only(bottom: 1.5.h),
            padding: EdgeInsets.all(3.5.w),
            height: 10.h,
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(12),
              border: !isDark ? Border.all(color: Colors.grey.shade200) : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(width: 100, height: 14, color: baseColor),
                    Container(width: 50, height: 14, color: baseColor),
                  ],
                ),
                SizedBox(height: 1.5.h),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(width: 80, height: 18, color: baseColor),
                    Container(width: 80, height: 18, color: baseColor),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
