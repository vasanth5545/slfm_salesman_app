import 'dart:async';
import 'dart:convert';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:slfm_salesman_app/core/services/secure_http_client.dart'
    as http;
import 'package:intl/intl.dart';
import '../../services/secure_storage_service.dart';
import 'package:sizer/sizer.dart';
import 'package:flutter_background_service/flutter_background_service.dart'; // 🔥 ADDED FOR SUSPENSION
import 'package:geolocator/geolocator.dart'; // 🔥 ADDED FOR PERMISSIONS
import '../../services/background_service.dart'; // 🔥 ADDED FOR BACKGROUND TASKS

import '../../core/app_export.dart';
import '../../core/services/version_check_service.dart';
import '../../widgets/custom_bottom_bar.dart';
import './widgets/attendance_tile_widget.dart';
import './widgets/order_book_tile_widget.dart';
import './widgets/stock_checking_tile_widget.dart';
import './widgets/customer_followup_tile_widget.dart';
import './widgets/service_report_tile_widget.dart'; // NEW
import '../service/service_screen.dart'; // NEW
import '../../widgets/maintenance_banner.dart';
import './../walking_notes/walking_notes_screen.dart';
import '../damage/damage_screen.dart';
import '../../core/database/local_db_helper.dart';
import './widgets/top_3_podium_widget.dart';
import './widgets/profile_setup_overlay.dart';
import 'widgets/account_switcher_overlay.dart';
import '../../widgets/profile_image_widget.dart';
import 'widgets/yesterday_status_widget.dart';
import '../../services/announcement_service.dart';
import '../notifications/announcement_history_screen.dart';
import '../../core/services/notification_service.dart';
import '../../services/feature_control_service.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard>
    with AutomaticKeepAliveClientMixin<Dashboard>, WidgetsBindingObserver {
  // Salesman information
  String _salesmanName = "Loading...";
  String _salesmanId = "";
  String _showroomName = "";

  // Visibility Flags
  bool _isPodiumVisible = true;
  StreamSubscription<DatabaseEvent>? _rtdbPodiumSubscription;

  // Dashboard data
  int _selectedIndex = 0; // 🔥 ADDED THIS
  bool _hasLeaveAlert = false;
  String _attendanceStatus = "--";
  String _lastAttendanceTime = "--:--";
  final int _lastStockCount = 0;
  final int _pendingOrdersCount = 0;

  // Yesterday's Status variables
  bool _showYesterdayAlert = false;
  String _yesterdayStatus = "";
  String _yesterdayReason = "";

  // 🔥 NEW VARIABLES FOR WALKING NOTES
  int _pendingWalkingCount = 0;
  int _billedWalkingCount = 0;

  // 🔥 NEW VARIABLES FOR SERVICE REPORTS
  int _servicePendingCount = 0;
  int _serviceFinishedCount = 0;

  // --- 🔒 FEATURE CONTROL FLAGS (Default True) ---
  bool _isWalkingEnabled = true;
  bool _isDamageEnabled = true;
  bool _isServiceEnabled = true; // NEW

  // 🔥 MAINTENANCE MODE
  bool _isMaintenanceMode = false;
  final int _currentMaintenanceMode = 0; // 0=Off, 1=Full, 2=Partial
  String _maintenanceMessage =
      "Maintenance work please few minz wait any doubt to contact to devoloper !!";

  // 🔥 NEW: Connectivity Check
  bool _isOnline = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // 🔥 NEW: Status Indicator Color (Default Green)
  Color _statusIndicatorColor = Colors.green;

  // 🔥 NEW: Real-time Sync Tracking
  int _lastSyncTimestamp = 0;
  bool _isRemoteEnabled = false; // 🔥 Track remote attendance flag

  // 🏆 LEADERBOARD DATA (Static cache to pass full list to podium widget)
  static List<dynamic> _cachedAllSalesmen = [];

  List<dynamic> _allSalesmen = [];
  bool _isLoadingLeaderboard = true;
  bool _showProfileSetup = false;
  String _profilePhoto = "";
  String _avatarAnimal = "";
  String _userRole = "salesman"; // 🔥 NEW: Track user role for service widget
  int _scarfaceLimit = 1000; // 🔥 NEW: Track dynamic reward limit

  // --- Announcements ---
  final AnnouncementService _announcementService = AnnouncementService();
  StreamSubscription<List<Announcement>>? _announcementSubscription;
  List<Announcement> _activeAnnouncements = [];
  bool _announcementExpanded = false; // 🔥 Toggle for read more
  int _currentAnnouncementIndex = 0; // 🔥 Sequential navigation index

  // 🔥 FIX: Firebase Cloud Function API Endpoint
  final String _walkingApiUrl = ApiUrl.walkingCustomer;

  StreamSubscription<QuerySnapshot>? _maintenanceSubscription;
  Timer? _featureControlTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 🔥 FIX: Clear stale static leaderboard cache on fresh Dashboard creation
    // (happens on account switch when a new Dashboard widget is created)
    _cachedAllSalesmen = [];

    _isLoadingLeaderboard = true;

    // 🔥 START: Centralized Feature Control
    _setupFeatureControl();

    // 🔥 Real-time Maintenance Mode Listener
    _listenToMaintenanceMode();

    // 🔥 Start Connectivity Monitoring
    _startConnectivityMonitoring();

    // 🔥 FIX: Sequential initialization — ensures _salesmanId is loaded
    // BEFORE cache reads and server fetches happen
    _initDashboard();

    // 🍽️ Lunch Window Open/Close notification
    FeatureControlService().lunchWindowOpen.addListener(_onLunchWindowChanged);

    // 🔥 Check for Updates (post-frame to avoid blocking first paint)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      VersionCheckService().checkVersion(context);
      _initAnnouncements();
      _runBackgroundInitTasks(); // 🔥 Run heavy tasks AFTER UI render
    });
  }

  /// 🔥 NEW: Sequential dashboard init — prevents stale cache reads
  Future<void> _initDashboard() async {
    await _checkLoginStatus(); // Redirects to login if needed
    await _loadUserData(); // Sets _salesmanId & _showroomName, starts _fetchServerData
    await _initFromCache(); // Now _salesmanId is guaranteed to be set
    // 🔥 Feature flags already loaded by Splash Screen via FeatureControlService().init()
    // Dashboard only listens to ValueNotifier changes via _setupFeatureControl()
  }

  /// 🔥 NEW: Heavy initialization tasks that shouldn't block the UI
  Future<void> _runBackgroundInitTasks() async {
    try {
      // 1. Check Location Permissions
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }

      // 2. Initialize Foreground Service
      try {
        await initializeService();
      } catch (e) {
        debugPrint("Service Init Error: $e");
      }

      // 3. Force Sync Features (Timeout 2s)
      FeatureControlService().syncImmediately();

      // 4. Sync Session to Switcher
      SecureStorageService.syncCurrentSessionToSwitcher();
    } catch (e) {
      debugPrint("Background Init Tasks Error: $e");
    }
  }

  void _setupFeatureControl() {
    final service = FeatureControlService();
    // Listen to changes
    service.podiumVisible.addListener(_updateFeatureStates);
    service.walkingVisible.addListener(_updateFeatureStates);
    service.damageVisible.addListener(_updateFeatureStates);
    service.serviceWidgetVisible.addListener(_updateFeatureStates); // NEW

    // Initial sync — features are already loaded correctly by Splash Screen
    _updateFeatureStates();
  }

  void _updateFeatureStates() {
    if (mounted) {
      final service = FeatureControlService();
      setState(() {
        bool oldPodiumVisible = _isPodiumVisible;
        _isPodiumVisible = service.podiumVisible.value;
        _isWalkingEnabled = service.walkingVisible.value;
        _isDamageEnabled = service.damageVisible.value;
        _isServiceEnabled = service.serviceWidgetVisible.value; // NEW

        debugPrint(
            "📊 Service Module Visibility: $_isServiceEnabled (Source: ${service.serviceWidgetVisible.value})");

        // 🔥 If it was hidden and now visible, fetch the data!
        if (!oldPodiumVisible && _isPodiumVisible) {
          _fetchWalkingLeaderboard();
        }
      });
    }
  }

  /// 🔥 FIX 9: Load feature flags from local cache instantly
  Future<void> _initFromCache() async {
    try {
      // 🔥 Get cached remote attendance preference
      final cachedRemote = await SecureStorageService.readString(
          'remote_attendance_enabled_$_salesmanId');
      if (cachedRemote != null && mounted) {
        setState(() {
          _isRemoteEnabled = (cachedRemote == "1" || cachedRemote == "true");
        });
      }

      // 🔥 Feature flags are now loaded by FeatureControlService().init() in _initDashboard()
      // Don't load them here to avoid stale cross-account flag flashes.

      // Get cached attendance status
      final cachedStatus = await SecureStorageService.readString(
          'attendance_status_$_salesmanId');
      final cachedTime =
          await SecureStorageService.readString('clock_in_time_$_salesmanId');
      if (cachedStatus != null && mounted) {
        setState(() {
          _attendanceStatus = cachedStatus;
          _lastAttendanceTime = cachedTime ?? '--:--';
        });
      }
    } catch (e) {
      debugPrint("⚠️ Dashboard Cache Load Failed: $e");
    }
  }

  // 🍽️ Lunch window open/close real-time notification
  void _onLunchWindowChanged() {
    if (!mounted) return;
    final isOpen = FeatureControlService().lunchWindowOpen.value;
    final isManual = FeatureControlService().lunchIsManual.value;

    // Don't show notification for manual override changes
    if (isManual) return;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isOpen
              ? '🍽️ Lunch Break Open! இப்போது Lunch page access செய்யலாம்.'
              : '🔒 Lunch Break முடிந்தது! Lunch page lock ஆகிவிட்டது.',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            isOpen ? Colors.green.shade800 : Colors.orange.shade900,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _maintenanceSubscription?.cancel();
    _featureControlTimer?.cancel();
    _connectivitySubscription?.cancel();
    _rtdbSalesmanSubscription?.cancel();
    _rtdbPodiumSubscription?.cancel();
    _announcementSubscription?.cancel();

    // Remove listeners
    final service = FeatureControlService();
    service.podiumVisible.removeListener(_updateFeatureStates);
    service.walkingVisible.removeListener(_updateFeatureStates);
    service.damageVisible.removeListener(_updateFeatureStates);
    service.serviceWidgetVisible.removeListener(_updateFeatureStates); // NEW
    service.lunchWindowOpen.removeListener(_onLunchWindowChanged);

    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (mounted) {
      setState(() {});
    }
  }

  void _startConnectivityMonitoring() {
    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      final bool isNowOnline = results.contains(ConnectivityResult.mobile) ||
          results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet);

      if (mounted) {
        setState(() {
          _isOnline = isNowOnline;
          _statusIndicatorColor = isNowOnline ? Colors.green : Colors.grey;
        });
      }
    });
  }

  void _listenToMaintenanceMode() {
    _maintenanceSubscription?.cancel();
    _maintenanceSubscription = FirebaseFirestore.instance
        .collection('app_settings')
        .snapshots()
        .listen((snapshot) {
      if (!mounted) {
        return;
      }

      int modeID = 0;
      String? customMessage;
      Color newStatusColor = Colors.green;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final key = doc.id;
        final val = data['setting_value'];

        if (key == 'maintenance_mode') {
          if (val == true || val == 1) {
            modeID = 1;
          } else if (val is int) {
            modeID = val;
          }
        } else if (key == 'maintenance_message') {
          customMessage = val?.toString();
        } else if (key == 'status_color') {
          final colorStr = val?.toString().toLowerCase();
          if (colorStr == 'red') {
            newStatusColor = Colors.red;
          } else if (colorStr == 'amber') {
            newStatusColor = Colors.amber;
          } else if (colorStr == 'green') {
            newStatusColor = Colors.green;
          }
        }
      }

      setState(() {
        _statusIndicatorColor = newStatusColor;
        if (modeID == 1) {
          _isMaintenanceMode = true;
          _maintenanceMessage = customMessage ?? "App is under maintenance.";
          if (mounted) {
            _showHardMaintenanceOverlay(_maintenanceMessage);
          }
        } else {
          _isMaintenanceMode = false;
          _hideHardMaintenanceOverlay();
        }
      });
    }, onError: (error) => debugPrint("🛑 Maintenance Listener Error: $error"));
  }

  bool _isHardMaintenanceDialogShowing = false;

  void _showHardMaintenanceOverlay(String message) {
    if (_isHardMaintenanceDialogShowing) {
      return;
    }
    _isHardMaintenanceDialogShowing = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text("⚠️ Under Maintenance"),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => SystemNavigator.pop(),
                child: const Text("Close App"),
              ),
            ],
          ),
        );
      },
    ).then((_) {
      _isHardMaintenanceDialogShowing = false;
    });
  }

  void _hideHardMaintenanceOverlay() {
    if (_isHardMaintenanceDialogShowing) {
      Navigator.of(context, rootNavigator: true).pop();
      _isHardMaintenanceDialogShowing = false;
    }
  }

  void _initAnnouncements() async {
    final showroom = await SecureStorageService.getShowroomName() ?? '';
    final salesmanId = await SecureStorageService.getSalesmanId() ?? '';

    // 🔥 START: Global listener for in-app popups (works on any screen)
    NotificationService().startAnnouncementListener(showroom, salesmanId);

    _announcementSubscription?.cancel();
    _announcementSubscription = _announcementService
        .getAnnouncements(showroom, salesmanId)
        .listen((allAnnouncements) async {
      final unacknowledged =
          await _announcementService.filterUnacknowledged(allAnnouncements);

      // 🔥 SYSTEM NOTIFICATION LOGIC REMOVED AS PER USER REQUEST
      // User preferred seeing announcements only on the Dashboard.

      if (mounted) {
        setState(() {
          _activeAnnouncements = unacknowledged;
          // Reset index if it's out of bounds after update
          if (_currentAnnouncementIndex >= _activeAnnouncements.length) {
            _currentAnnouncementIndex = 0;
          }
        });

        // 🔥 SYNC: Update background notification with the current announcement
        if (unacknowledged.isNotEmpty) {
          FlutterBackgroundService().invoke('show_announcement_in_bg', {
            'message': unacknowledged[_currentAnnouncementIndex].message,
          });
        } else {
          FlutterBackgroundService().invoke('hide_announcement_in_bg');
        }
      }
    }, onError: (e) {
      debugPrint("⚠️ Announcement Listener Error: $e");
    });
  }

  void _openNotifications() {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) => const AnnouncementHistoryScreen()),
    );
  }

  Widget _buildStickyAnnouncements() {
    final theme = Theme.of(context);
    if (_activeAnnouncements.isEmpty) return const SizedBox.shrink();

    // Safety check for index
    if (_currentAnnouncementIndex >= _activeAnnouncements.length) {
      _currentAnnouncementIndex = 0;
    }

    final latest = _activeAnnouncements[_currentAnnouncementIndex];

    // 🔥 TRUNCATION LOGIC
    const int charLimit = 120;
    bool needsTruncation = latest.message.length > charLimit;
    String displayMessage = (needsTruncation && !_announcementExpanded)
        ? "${latest.message.substring(0, charLimit)}..."
        : latest.message;

    return Container(
      margin: EdgeInsets.fromLTRB(4.w, 0, 4.w, 2.h),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.amber.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.08),
            offset: const Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            // Left accent bar
            Positioned(
              left: 0,
              top: 12,
              bottom: 12,
              child: Container(
                width: 4,
                decoration: BoxDecoration(
                  color: Colors.amber,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(5.w, 3.w, 4.w, 2.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.campaign_rounded,
                          color: Colors.amber.shade700, size: 20),
                      SizedBox(width: 2.w),
                      Expanded(
                        child: Text(
                          "Announcement (${_currentAnnouncementIndex + 1}/${_activeAnnouncements.length})",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (_activeAnnouncements.length > 1)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.navigate_before, size: 20),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                setState(() {
                                  _currentAnnouncementIndex =
                                      (_currentAnnouncementIndex -
                                              1 +
                                              _activeAnnouncements.length) %
                                          _activeAnnouncements.length;
                                  _announcementExpanded = false;
                                });
                                // 🔥 SYNC: Update background notification
                                FlutterBackgroundService()
                                    .invoke('show_announcement_in_bg', {
                                  'message': _activeAnnouncements[
                                          _currentAnnouncementIndex]
                                      .message,
                                });
                              },
                            ),
                            SizedBox(width: 2.w),
                            IconButton(
                              icon: const Icon(Icons.navigate_next, size: 20),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                setState(() {
                                  _currentAnnouncementIndex =
                                      (_currentAnnouncementIndex + 1) %
                                          _activeAnnouncements.length;
                                  _announcementExpanded = false;
                                });
                                // 🔥 SYNC: Update background notification
                                FlutterBackgroundService()
                                    .invoke('show_announcement_in_bg', {
                                  'message': _activeAnnouncements[
                                          _currentAnnouncementIndex]
                                      .message,
                                });
                              },
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _announcementExpanded = !_announcementExpanded;
                      });
                    },
                    child: RichText(
                      text: TextSpan(
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.8),
                          height: 1.4,
                          fontSize: 13,
                        ),
                        children: [
                          TextSpan(text: displayMessage),
                          if (needsTruncation && !_announcementExpanded)
                            TextSpan(
                              text: " read more...",
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 30), // Space for dismiss button
                ],
              ),
            ),
            // Absolute positioned close button at bottom right
            Positioned(
              bottom: 4,
              right: 4,
              child: TextButton(
                onPressed: () async {
                  HapticFeedback.mediumImpact();
                  await _announcementService.acknowledgeAnnouncement(
                      latest.id, _salesmanId);
                  if (mounted) {
                    setState(() {
                      _announcementExpanded = false;
                      _activeAnnouncements
                          .removeWhere((a) => a.id == latest.id);
                      if (_currentAnnouncementIndex >=
                          _activeAnnouncements.length) {
                        _currentAnnouncementIndex =
                            _activeAnnouncements.isNotEmpty
                                ? _activeAnnouncements.length - 1
                                : 0;
                      }
                    });

                    // 🔥 SYNC: Update background notification
                    if (_activeAnnouncements.isNotEmpty) {
                      FlutterBackgroundService()
                          .invoke('show_announcement_in_bg', {
                        'message':
                            _activeAnnouncements[_currentAnnouncementIndex]
                                .message,
                      });
                    } else {
                      FlutterBackgroundService()
                          .invoke('hide_announcement_in_bg');
                    }

                    // 🔥 REDIRECT: Go to Notification Page
                    if (mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              const AnnouncementHistoryScreen(),
                        ),
                      );
                    }
                  }
                },
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  minimumSize: const Size(0, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Dismiss",
                      style: TextStyle(
                        color: Colors.amber.shade900,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.close, size: 14, color: Colors.amber.shade900),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _checkLoginStatus() async {
    final isLoggedIn = await SecureStorageService.isLoggedIn();

    if (!isLoggedIn && mounted) {
      Navigator.pushReplacementNamed(context, '/login-screen');
    }
  }

  Future<void> _loadUserData() async {
    final name = await SecureStorageService.getSalesmanName();
    final id = await SecureStorageService.getSalesmanId();
    final showroom = await SecureStorageService.getShowroomName();
    final role = await SecureStorageService.getUserRole();
    String? photo = await SecureStorageService.readString('profile_photo');
    String? animal = await SecureStorageService.readString('avatar_animal');

    // 🔥 ROLE CHECK: Only Salesmen and Promoters need mandatory profile setup
    final bool isTargetRole =
        role.toLowerCase() == 'salesman' || role.toLowerCase() == 'promoter';

    // 🔥 FIX: Check the PERMANENT flag first — if profile was ever set up, NEVER show overlay again
    bool isSetupAlreadyDone = await SecureStorageService.isProfileSetupDone();

    // If they aren't a salesman/promoter, they don't get the setup overlay
    if (!isTargetRole) {
      isSetupAlreadyDone = true;
    }

    if (isSetupAlreadyDone) {
      // Profile was previously set up. Just load the data, never show overlay.
      debugPrint("✅ Profile setup flag is TRUE. Skipping overlay permanently.");
      setState(() {
        _salesmanName = name ?? _salesmanName;
        _salesmanId = id ?? _salesmanId;
        _showroomName = showroom ?? ""; // 🔥 FIX: MISSING SHOWROOM
        _userRole = role; // 🔥 NEW: Track role for widgets
        if (photo != null && photo.isNotEmpty) _profilePhoto = photo;
        if (animal != null && animal.isNotEmpty) _avatarAnimal = animal;
        _showProfileSetup = false; // 🔒 LOCKED OFF
      });
      // _listenToFeatureVisibility(); // Handled by FeatureControlService now
    } else {
      // Flag not set — check if server has data (first-time or cleared storage)
      if ((photo == null || photo.isEmpty) ||
          (animal == null || animal.isEmpty)) {
        if (id != null && id.isNotEmpty) {
          debugPrint("🔍 Local profile missing for $id. Checking server...");
          final serverProfile = await _fetchProfileFromServer(id);
          if (serverProfile != null) {
            final serverPhoto = serverProfile['profile_photo'] ?? '';
            final serverAnimal = serverProfile['avatar_animal'] ?? '';

            // Only overwrite with non-empty values
            if (serverPhoto.isNotEmpty) {
              photo = serverPhoto;
              await SecureStorageService.writeString(
                  'profile_photo', serverPhoto);
            }
            if (serverAnimal.isNotEmpty) {
              animal = serverAnimal;
              await SecureStorageService.writeString(
                  'avatar_animal', serverAnimal);
            }

            // 🔥 If server had BOTH, mark as permanently done
            if (serverPhoto.isNotEmpty && serverAnimal.isNotEmpty) {
              await SecureStorageService.setProfileSetupDone(true);
              debugPrint(
                  "✅ Server has profile data. Marked setup as done permanently.");
            }
          }
        }
      } else {
        // Local storage has both values but flag wasn't set (edge case from old versions)
        await SecureStorageService.setProfileSetupDone(true);
        debugPrint("✅ Local data found without flag. Setting flag now.");
      }

      setState(() {
        _salesmanName = name ?? _salesmanName;
        _salesmanId = id ?? _salesmanId;
        _showroomName = showroom ?? "";
        _userRole = role; // 🔥 NEW: Track role for widgets
        if (photo != null && photo.isNotEmpty) _profilePhoto = photo;
        if (animal != null && animal.isNotEmpty) _avatarAnimal = animal;

        // Only show overlay if TRULY missing from everywhere
        if (_profilePhoto.isEmpty || _avatarAnimal.isEmpty) {
          _showProfileSetup = true;
          if (_selectedIndex == 0) {
            _selectedIndex = 1;
          }
        } else {
          _showProfileSetup = false;
        }
      });
    }

    // 🔥 ALWAYS START LISTENER (Ensures visibility works even after profile setup)
    // _listenToFeatureVisibility(); // Handled by FeatureControlService now

    if (_salesmanId.isNotEmpty) {
      _listenToSalesmanStatus(); // 🔥 Monitoring suspension
      _fetchServerData();
    } else {
      if (mounted) {
        setState(() => _isInitialLoading = false);
      }
    }
  }

  /// 🔥 NEW: Fetches profile details from server (salesman_check.php)
  Future<Map<String, String>?> _fetchProfileFromServer(String id) async {
    try {
      final url = Uri.parse(ApiUrl.salesmanCheck);
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'salesman_id': id}),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success' && data['data'] != null) {
          final sData = data['data'];
          return {
            'profile_photo': sData['profile_photo']?.toString() ?? '',
            'avatar_animal': sData['avatar_animal']?.toString() ?? '',
          };
        }
      }
    } catch (e) {
      debugPrint("🛑 Error fetching profile from server: $e");
    }
    return null;
  }

  bool _isSuspendedDialogShowing = false; // 🔥 Track suspension dialog

  StreamSubscription<DatabaseEvent>? _rtdbSalesmanSubscription;

  void _listenToSalesmanStatus() {
    if (_salesmanId.isEmpty) return;
    _rtdbSalesmanSubscription?.cancel();

    // Pre-fetch initial timestamp to prevent redundant sync on load
    FirebaseDatabase.instance
        .ref('salesmen_status/$_salesmanId/data_sync_timestamp')
        .get()
        .then((snap) {
      if (snap.exists) {
        _lastSyncTimestamp = int.tryParse(snap.value.toString()) ?? 0;
      }
    }).catchError((e) {
      debugPrint("Firebase RTDB pre-fetch error in Dashboard (handled): $e");
    });

    // Listen to Realtime Database at /salesmen_status/{salesmanId}
    _rtdbSalesmanSubscription = FirebaseDatabase.instance
        .ref('salesmen_status/$_salesmanId')
        .onValue
        .listen((DatabaseEvent event) async {
      try {
        if (event.snapshot.value == null) return;

        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        bool isSuspended = false;

        if (data['status'] != null &&
            data['status'].toString().toLowerCase() == 'suspended') {
          isSuspended = true;
        }

        // 🔥 REAL-TIME SYNC TRIGGER: Check for data_sync_timestamp
        if (data['data_sync_timestamp'] != null) {
          int? syncTs;
          final val = data['data_sync_timestamp'];
          if (val is num) {
            syncTs = val.toInt();
          } else if (val != null) {
            syncTs = num.tryParse(val.toString())?.toInt();
          }

          if (syncTs != null && syncTs > _lastSyncTimestamp) {
            _lastSyncTimestamp = syncTs;
            debugPrint(
                "🔄 Real-time Sync Signal Received: $syncTs. Refreshing Dashbord...");

            // 🔥 Safety Delay: Allow server-side summary tasks to finish
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted) _fetchServerData();
            });
          }
        }

        // 🔥 NEW: Track Remote Attendance Flag in Dashboard
        if (data['remote_attendance_enabled'] != null) {
          bool remoteVal = false;
          final rawVal = data['remote_attendance_enabled'];
          if (rawVal is bool) {
            remoteVal = rawVal;
          } else if (rawVal is num) {
            remoteVal = rawVal.toInt() == 1;
          } else if (rawVal is String) {
            remoteVal = (rawVal == "1" || rawVal == "true");
          }

          if (mounted && remoteVal != _isRemoteEnabled) {
            setState(() {
              _isRemoteEnabled = remoteVal;
            });
            // Update cache
            SecureStorageService.writeString(
                'remote_attendance_enabled_$_salesmanId', remoteVal.toString());
          }
        }

        // 🔥 Lunch status is tracked via PHP API (in syncImmediately & lunch screen)
        // NOT from Firebase listener — Firebase has stale data without date reset

        if (isSuspended) {
          if (_isSuspendedDialogShowing) return; // 🔥 Prevent duplicate alerts
          _isSuspendedDialogShowing = true;

          debugPrint("🛑 ACCOUNT SUSPENDED: Forcing Logout from Dashboard...");
          if (mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => PopScope(
                canPop: false,
                child: AlertDialog(
                  title: const Row(
                    children: [
                      Icon(Icons.block, color: Colors.red),
                      SizedBox(width: 8),
                      Text("Account Suspended"),
                    ],
                  ),
                  content: const Text(
                      "Your account has been suspended by the administrator. You will be logged out."),
                  actions: [
                    TextButton(
                      child:
                          const Text("OK", style: TextStyle(color: Colors.red)),
                      onPressed: () async {
                        try {
                          FlutterBackgroundService().invoke("stopService");
                          await SecureStorageService.clearSession();
                        } catch (e) {
                          debugPrint("Logout cleanup error: $e");
                        }
                        if (context.mounted) {
                          Navigator.pushNamedAndRemoveUntil(
                              context, '/login-screen', (route) => false);
                        }
                      },
                    )
                  ],
                ),
              ),
            );
          }
        } else {
          // 🔥 If admin changes it back to active while dialog is showing, dismiss it
          if (_isSuspendedDialogShowing && mounted) {
            Navigator.of(context, rootNavigator: true).pop();
            _isSuspendedDialogShowing = false;
          }
        }
      } catch (e) {
        debugPrint("Error processing RTDB salesman snapshot: $e");
      }
    }, onError: (error) {
      // 🔥 SILENTLY CATCH PERMISSION ERRORS (common on emulators/App Check issues)
      debugPrint("🛑 Firebase Status Listener Error: $error");
    });
  }

  Future<void> _triggerAbsentCheck() async {
    // Intentionally left empty to prevent auto marking.
  }

  Future<void> _fetchWalkingLeaderboard() async {
    try {
      final response = await http
          .post(
            Uri.parse(ApiUrl.walkingCustomer),
            body: jsonEncode({"action": "get_walking_leaderboard"}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // 🔥 NEW: Extract Reward Limits
        if (data['rewards_config'] != null &&
            data['rewards_config']['scarface_limit'] != null) {
          _scarfaceLimit = int.tryParse(
                  data['rewards_config']['scarface_limit'].toString()) ??
              1000;
        }

        if (data['status'] == 'success' && data['data'] != null) {
          final List rawList = data['data'];

          final List fullList = rawList;

          // 🚀 Update global static cache
          _cachedAllSalesmen = fullList;

          if (mounted) {
            setState(() {
              _allSalesmen = List.from(_cachedAllSalesmen);
              _isLoadingLeaderboard = false;
            });
          }
          return;
        }
      }
    } catch (e) {
      debugPrint("🛑 Top 3 Leaderboard Fetch Error: $e");
    }
    if (mounted) setState(() => _isLoadingLeaderboard = false);
  }

  DateTime? _lastFetchTime; // 🔥 THROTTLE: Prevents "chumma chumma reload"

  Future<void> _fetchServerData({bool force = false}) async {
    if (_salesmanId.isEmpty) {
      if (mounted) setState(() => _isInitialLoading = false);
      return;
    }

    // 🔥 THROTTLE: Don't refresh more than once every 30 seconds unless forced (manual pull-to-refresh)
    if (!force && _lastFetchTime != null) {
      final diff = DateTime.now().difference(_lastFetchTime!);
      if (diff.inSeconds < 30) {
        debugPrint("⏳ Refresh skipped (Throttle): ${diff.inSeconds}s ago");
        return;
      }
    }
    _lastFetchTime = DateTime.now();

    try {
      _updateSyncTime();
      await _triggerAbsentCheck();

      // 🔥 FAST START: Stop skeleton IMMEDIATELY using cached data.
      // Do not wait for slow internet to remove the skeleton loader!
      if (mounted) {
        setState(() => _isInitialLoading = false);
      }

      // 1. Fetch Attendance Summary from PHP API
      try {
        final response = await http
            .post(
              Uri.parse(ApiUrl.attendance),
              body: jsonEncode({
                "action": "get_summary",
                "salesman_id": _salesmanId,
              }),
            )
            .timeout(const Duration(seconds: 15));

        String newStatus = "Not Marked";
        String newTime = "--:--";
        bool leaveAlert = false;

        if (response.statusCode == 200) {
          final respData = jsonDecode(response.body);
          if (respData['status'] == 'success' && respData['data'] != null) {
            final data = respData['data'];
            final dbStatus = data['attendance_status'] ?? 'Not Marked';
            newStatus = dbStatus;

            // Robust Time Parsing
            DateTime? parseTime(dynamic t) {
              if (t == null || t.toString().isEmpty || t.toString() == 'null') {
                return null;
              }
              String s = t.toString();
              // 1. Try ISO 8601
              DateTime? dt = DateTime.tryParse(s);
              if (dt != null) return dt;
              // 2. Try HH:mm:ss (New standard)
              try {
                return DateFormat('HH:mm:ss').parse(s);
              } catch (_) {}
              // 3. Try hh:mm:ss a (Legacy)
              try {
                return DateFormat('hh:mm:ss a').parse(s);
              } catch (_) {}
              try {
                return DateFormat('hh:mm a').parse(s);
              } catch (_) {}
              return null;
            }

            if (dbStatus == 'Absent') {
              newTime = "Marked Today";
              leaveAlert = true;
            } else if (dbStatus.toString().contains('Leave')) {
              newTime = "Approved";
            } else if (dbStatus.toString().contains('Holiday')) {
              newTime = "🎉 Holiday";
            } else {
              // Default to server status
              newStatus = dbStatus;

              if (data['clock_in'] != null) {
                final inTime = parseTime(data['clock_in']);
                if (inTime != null) {
                  newTime = DateFormat('hh:mm a').format(inTime);
                }

                // If server says "Present" but we have no clock out, it's effectively "In" (or Resume)
                if (newStatus == "Not Marked" || newStatus == "Absent") {
                  newStatus = "In";
                }

                if (data['clock_out'] != null) {
                  newStatus = "Out";
                  final outTime = parseTime(data['clock_out']);
                  if (outTime != null) {
                    newTime = DateFormat('hh:mm a').format(outTime);
                  }
                }
              }
            }
          }
        }

        // 1.5 🔥 Robustness Fix: Fetch History to get LATEST today record (Server summary picks first one)
        try {
          final histResponse = await http
              .post(
                Uri.parse(ApiUrl.attendance),
                body: jsonEncode({
                  "action": "get_history",
                  "salesman_id": _salesmanId,
                }),
              )
              .timeout(const Duration(seconds: 15));

          if (histResponse.statusCode == 200) {
            final histData = jsonDecode(histResponse.body);
            if (histData['status'] == 'success' && histData['data'] != null) {
              final List historyList = histData['data'];
              final String todayDate = DateTime.now().toString().split(' ')[0];

              // Find the first record for today (ordered by DESC in API)
              final todayRecord = historyList.where((rec) {
                final recDate = rec['date'].toString().trim();
                return recDate.contains(todayDate);
              }).toList();

              if (todayRecord.isNotEmpty) {
                final latest = todayRecord.first;
                // 🔥 FIX: Check both 'status' AND handle case-sensitivity/mismatch
                newStatus = latest['status']?.toString() ?? newStatus;

                final String? modReason = latest['modified_reason']?.toString();
                bool hasModReason = modReason != null &&
                    modReason.isNotEmpty &&
                    modReason != 'null';
                final s = newStatus.toLowerCase();

                if (hasModReason &&
                    (s.contains('miss') ||
                        s.contains('absent') ||
                        s.contains('auto'))) {
                  newTime = modReason;
                  if (s == "present" ||
                      s == "in" ||
                      s == "late" ||
                      s == "half day") {
                    newStatus = "Out";
                  }
                } else {
                  // 🕑 FIX: API uses 'clockIn'/'clockOut' for history but 'clock_in_time'/'clock_out_time' for summary.
                  String rawTime = "";
                  final cOut = latest['clockOut'] ?? latest['clock_out_time'];
                  if (cOut != null &&
                      cOut.toString().trim().isNotEmpty &&
                      cOut.toString() != "--:--" &&
                      cOut.toString() != "null") {
                    rawTime = cOut.toString();

                    // 🔥 NEW: If clock-out exists, UI should show "Out" status (Orange color)
                    // even if daily status is "Present".
                    if (s == "present" ||
                        s == "in" ||
                        s == "late" ||
                        s == "half day") {
                      newStatus = "Out";
                    }
                  } else {
                    rawTime = (latest['clockIn'] ??
                            latest['clock_in_time'] ??
                            newTime)
                        .toString();
                  }

                  if (rawTime.contains(':')) {
                    try {
                      // 🔥 FIX: Check if time is already in 12-hour AM/PM format (e.g. "07:47:38 PM")
                      // Server sends clockIn/clockOut in "hh:mm:ss A" format from PHP's date('h:i:s A')
                      if (rawTime.toUpperCase().contains('AM') ||
                          rawTime.toUpperCase().contains('PM')) {
                        // Already in 12-hour format, parse it correctly (Force en_US for AM/PM consistency)
                        try {
                          final DateTime parsedTime =
                              DateFormat('hh:mm:ss a', 'en_US').parse(rawTime);
                          newTime =
                              DateFormat('hh:mm a', 'en_US').format(parsedTime);
                        } catch (_) {
                          try {
                            final DateTime parsedTime =
                                DateFormat('hh:mm a', 'en_US').parse(rawTime);
                            newTime = DateFormat('hh:mm a', 'en_US')
                                .format(parsedTime);
                          } catch (_) {
                            newTime = rawTime;
                          }
                        }
                      } else {
                        // 24-hour format (e.g. "2026-04-20 19:47:38" or "19:47:38")
                        String timeOnly = rawTime;
                        if (rawTime.contains('-')) {
                          // Full datetime like "2026-04-20 19:47:38"
                          final dtParsed = DateTime.tryParse(rawTime);
                          if (dtParsed != null) {
                            newTime =
                                DateFormat('hh:mm a', 'en_US').format(dtParsed);
                          } else {
                            timeOnly = rawTime.split(' ').last;
                            final DateTime parsedTime =
                                DateFormat('HH:mm:ss').parse(timeOnly);
                            newTime = DateFormat('hh:mm a', 'en_US')
                                .format(parsedTime);
                          }
                        } else {
                          final DateTime parsedTime =
                              DateFormat('HH:mm:ss').parse(timeOnly);
                          newTime =
                              DateFormat('hh:mm a', 'en_US').format(parsedTime);
                        }
                      }
                    } catch (e) {
                      newTime = rawTime;
                    }
                  }
                }
                if (newStatus == "Not Marked" && latest['status'] != null) {
                  newStatus = latest['status'].toString();
                }

                debugPrint(
                    "✅ Dashboard Sync: Found update in history: $newStatus - $newTime");
              }

              // Yesterday logic
              final DateTime yesterdayDateObj =
                  DateTime.now().subtract(const Duration(days: 1));
              final String yesterdayDate1 =
                  yesterdayDateObj.toString().split(' ')[0];
              final String yesterdayDate2 =
                  DateFormat('dd MMM yyyy').format(yesterdayDateObj);
              final String yesterdayDate3 =
                  DateFormat('dd MMM, yyyy').format(yesterdayDateObj);
              final String yesterdayDate4 =
                  DateFormat('d MMM, yyyy').format(yesterdayDateObj);
              final String yesterdayDate5 =
                  DateFormat('d MMM yyyy').format(yesterdayDateObj);

              final yesterdayRecord = historyList.where((rec) {
                final recDate = rec['date'].toString().trim();
                return recDate.contains(yesterdayDate1) ||
                    recDate.contains(yesterdayDate2) ||
                    recDate.contains(yesterdayDate3) ||
                    recDate.contains(yesterdayDate4) ||
                    recDate.contains(yesterdayDate5);
              }).toList();

              // 🔥 Default to Missout if the server didn't return a record for yesterday at all.
              bool showYest = true;
              String yestStatus = "Missout";
              String yestReason =
                  "நேற்று வருகை பதிவு செய்யப்படவில்லை (Attendance Missed)";

              if (yesterdayRecord.isNotEmpty) {
                final yesterday = yesterdayRecord.first;
                final modReason = yesterday['modified_reason']?.toString();
                final yStatus = yesterday['status']?.toString() ?? 'Missout';

                yestStatus = yStatus;

                if (modReason != null &&
                    modReason.isNotEmpty &&
                    modReason != 'null') {
                  yestReason = modReason;
                } else if (yStatus.toLowerCase() == 'missed' ||
                    yStatus.toLowerCase() == 'missout' ||
                    yStatus.toLowerCase() == 'absent') {
                  yestReason =
                      'நேற்று வருகை பதிவு செய்யப்படவில்லை (Attendance Missed).';
                } else if (yStatus.toLowerCase() == 'half day') {
                  yestReason = 'நேற்று அரை நாள் (Half Day) என பதிவாகியுள்ளது.';
                } else if (yStatus.toLowerCase() == 'leave') {
                  yestReason =
                      'நேற்று நீங்கள் விடுப்பு (Leave) எடுத்திருந்தீர்கள்.';
                } else if (yStatus.toLowerCase() == 'holiday') {
                  yestReason = yesterday['holiday_reason']?.toString() ??
                      'நேற்று விடுமுறை நாள் (Holiday).';
                } else {
                  yestReason = 'நேற்றைய வருகை வெற்றிகரமாக பதிவாகியுள்ளது.';
                }
              }

              if (mounted) {
                setState(() {
                  _showYesterdayAlert = showYest;
                  _yesterdayStatus = yestStatus;
                  _yesterdayReason = yestReason;
                });
              }
            }
          }
        } catch (e) {
          debugPrint("History Fetch (Dashboard Sync) Error: $e");
        }

        if (mounted) {
          setState(() {
            _attendanceStatus = newStatus;
            _lastAttendanceTime = newTime;
            _hasLeaveAlert = leaveAlert;
          });
          await SecureStorageService.writeString(
              'attendance_status_$_salesmanId', newStatus);
          await SecureStorageService.writeString(
              'clock_in_time_$_salesmanId', newTime);

          // 🔥 PERSIST: Write to saved_in_time for background service
          // Dashboard summary usually only has one time, so we update the primary notification one
          if (newStatus.toLowerCase().contains("in")) {
            await SecureStorageService.writeString(
                'saved_in_time_$_salesmanId', newTime);
          } else if (newStatus.toLowerCase().contains("out")) {
            await SecureStorageService.writeString(
                'saved_out_time_$_salesmanId', newTime);
          }

          // 🔥 SYNC: Inform background service immediately
          FlutterBackgroundService().invoke('update_notification_times', {
            'in_time': await SecureStorageService.readString(
                    'saved_in_time_$_salesmanId') ??
                '--:--',
            'out_time': await SecureStorageService.readString(
                    'saved_out_time_$_salesmanId') ??
                '--:--',
          });
        }
      } catch (e) {
        debugPrint("PHP Attendance Fetch Error: $e");
      }

      // 2. 🔥 WALKING STATS: Local DB First (FAST), then Sync from Firebase (SLOW)
      // Step A: Load instantly from local SQLite
      try {
        final localStats =
            await LocalDbHelper.instance.getWalkingStats(_salesmanId);
        if (mounted) {
          setState(() {
            _pendingWalkingCount = localStats['pending'] ?? 0;
            _billedWalkingCount = localStats['billed'] ?? 0;
          });
        }
      } catch (e) {
        debugPrint("Local Walking Stats Error: $e");
      }

      // Skeleton already stopped at the start of this function.

      // 3. 🔥 FETCH LEADERBOARD PODIUM
      await _fetchWalkingLeaderboard();

      // Step B: Background sync from Firebase Cloud Function (runs silently)
      try {
        final walkingResponse = await http
            .post(
              Uri.parse(_walkingApiUrl),
              headers: {"Content-Type": "application/json"},
              body: jsonEncode({
                "action": "get_my_walkings",
                "salesman_id": _salesmanId,
                "filename":
                    "dashboard_sync" // 🔥 FIX: Backend requires this field
              }),
            )
            .timeout(const Duration(
                seconds:
                    10)); // 🔥 REDUCED: 10s is better for 2G/3G/4G/5G responsiveness

        if (walkingResponse.statusCode == 200) {
          final wData = jsonDecode(walkingResponse.body);
          if (wData['status'] == 'success' && wData['data'] != null) {
            final List<Map<String, dynamic>> records =
                List<Map<String, dynamic>>.from(wData['data']);

            // Save to local DB for future instant access
            await LocalDbHelper.instance
                .syncWalkingCustomers(_salesmanId, records);

            // Get fresh stats from local DB
            final freshStats =
                await LocalDbHelper.instance.getWalkingStats(_salesmanId);
            if (mounted) {
              setState(() {
                _pendingWalkingCount = freshStats['pending'] ?? 0;
                _billedWalkingCount = freshStats['billed'] ?? 0;
              });
            }
          }
        }
      } catch (e) {
        debugPrint("Walking Sync Error: $e");
        // Local data already shown, so no problem
      }

      // 4. 🔥 FETCH SERVICE REPORTS (If Enabled & Role is Service)
      if (_isServiceEnabled && _userRole.toLowerCase() == 'service') {
        try {
          final serviceRes = await http
              .post(
                Uri.parse(ApiUrl.getServiceReports),
                headers: {"Content-Type": "application/json"},
                body: jsonEncode({
                  "showroom_name": _showroomName,
                }),
              )
              .timeout(const Duration(seconds: 10));

          if (serviceRes.statusCode == 200) {
            final sData = jsonDecode(serviceRes.body);
            if (sData['status'] == 'success' && sData['data'] != null) {
              final List records = sData['data'];
              int pending = 0;
              int finished = 0;
              for (var rec in records) {
                if (rec['status'] == 'Pending') {
                  pending++;
                } else if (rec['status'] == 'Finished') {
                  finished++;
                }
              }
              if (mounted) {
                setState(() {
                  _servicePendingCount = pending;
                  _serviceFinishedCount = finished;
                });
              }
            }
          }
        } catch (e) {
          debugPrint("Service Fetch Error: $e");
        }
      }
    } catch (e) {
      debugPrint("Dashboard Sync Error: $e");
      // 🔥 Even if everything fails, stop skeleton
      if (mounted) {
        setState(() {
          _isInitialLoading = false;
        });
      }
    }
  }

  bool _isInitialLoading = true; // 🔥 NEW: Track first load

  Future<void> _updateSyncTime() async {
    if (_salesmanId.isEmpty) {
      return;
    }
    try {
      debugPrint("🔄 Syncing: Writing presence to RTDB for $_salesmanId");
      final rtdb =
          FirebaseDatabase.instance.ref('tracking_status/$_salesmanId');
      await rtdb.update({
        'is_online': true,
        'last_online': ServerValue.timestamp,
      });
      // 🔥 Register onDisconnect handler
      await rtdb.onDisconnect().update({
        'is_online': false,
        'last_online': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint("❌ Sync Activity Error: $e");
    }
  }

  Future<void> _handleRefresh() async {
    HapticFeedback.mediumImpact();
    // Load both user profile info AND server stats
    await Future.wait([
      _loadUserData(),
      _fetchServerData(force: true),
    ]);
    await FeatureControlService().init(); // 🔥 Refresh listener on manual sync
    if (mounted) {
      ScaffoldMessenger.of(context)
          .clearSnackBars(); // 🔥 Clear previous before showing new
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Dashboard synced successfully'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _showComingSoon(String feature) {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context)
        .clearSnackBars(); // 🔥 Clear previous before showing new
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature - Coming Soon...'),
        duration: const Duration(milliseconds: 800),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _openWalkingNotes() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const WalkingNotesScreen()),
    ).then((_) => _fetchServerData(force: true)); // Refresh on return
  }

  void _openDamageReport() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const DamageScreen()),
    );
  }

  Future<void> _handleAttendanceTap() async {
    if (_currentMaintenanceMode == 1) {
      return;
    }

    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).clearSnackBars(); // 🔥 Clean transition
    await Navigator.pushNamed(
      context,
      '/attendance-screen',
      arguments: {'remote_enabled': _isRemoteEnabled},
    );
    _fetchServerData(force: true);
  }

  void _showMaintenanceDialog({bool blockApp = false}) {
    if (!mounted) {
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: !blockApp,
      builder: (context) => PopScope(
        canPop: !blockApp,
        child: AlertDialog(
          title: const Text("⚠️ Maintenance"),
          content: Text(_maintenanceMessage),
          actions: [
            if (blockApp)
              TextButton(
                  onPressed: () => SystemNavigator.pop(),
                  child: const Text("Close App"))
            else
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("OK"))
          ],
        ),
      ),
    );
  }

  void _handleStockCheckingTap() {
    if (_isMaintenanceMode) {
      _showMaintenanceDialog();
      return;
    }
    _showComingSoon('Stock Checking');
  }

  void _handleOrderBookTap() {
    if (_isMaintenanceMode) {
      _showMaintenanceDialog();
      return;
    }
    _showComingSoon('Billing');
  }

  void _handleAttendanceLongPress() => _showWeeklySummary();
  void _handleStockCheckingLongPress() => _showComingSoon('Recent Scans');
  void _handleOrderBookLongPress() => _showComingSoon('Filter Options');

  void _showWeeklySummary() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final theme = Theme.of(context);
        return Container(
          padding: EdgeInsets.all(4.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Weekly Attendance Summary',
                style: theme.textTheme.titleLarge,
              ),
              SizedBox(height: 2.h),
              _buildSummaryRow(theme, 'Present Days', '0', Colors.green),
              _buildSummaryRow(theme, 'Absent Days', '0', Colors.red),
              _buildSummaryRow(theme, 'Half Days', '0', Colors.orange),
              SizedBox(height: 2.h),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryRow(
      ThemeData theme, String label, String value, Color color) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 1.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyLarge),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 3.w, vertical: 0.5.h),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(value,
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: color, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewItem(
      ThemeData theme, String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 1.w),
        padding: EdgeInsets.all(3.w),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            SizedBox(height: 1.h),
            Text(value,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700, color: color)),
            Text(label,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 8, color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    Widget? floatingActionButtons;
    List<Widget> fabList = [];

    // Only Damage Report FAB needed now (Walking moved to Tile)
    if (_isDamageEnabled) {
      fabList.add(FloatingActionButton(
        heroTag: "damage_fab",
        onPressed: _openDamageReport,
        backgroundColor: Colors.redAccent,
        tooltip: "Report Damage",
        child: const Icon(Icons.broken_image_outlined, color: Colors.white),
      ));
    }

    if (fabList.isNotEmpty) {
      floatingActionButtons = Column(
        mainAxisSize: MainAxisSize.min,
        children: fabList,
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      floatingActionButton: floatingActionButtons,
      body: SafeArea(
        child: Stack(
          children: [
            _isInitialLoading
                ? _buildSkeletonLoading(theme)
                : Column(
                    children: [
                      // 🔥 MAINTENANCE BANNER AT TOP
                      MaintenanceBanner(
                        isVisible: _isMaintenanceMode,
                        message: _maintenanceMessage,
                      ),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _handleRefresh,
                          child: CustomScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            slivers: [
                              // --- TOP WELCOME HEADER ---
                              SliverToBoxAdapter(
                                child: Container(
                                  padding: EdgeInsets.all(4.w),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surface,
                                    boxShadow: [
                                      BoxShadow(
                                        color: theme.colorScheme.shadow
                                            .withValues(alpha: 0.05),
                                        offset: const Offset(0, 2),
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Welcome back,',
                                                  style: theme
                                                      .textTheme.bodyMedium
                                                      ?.copyWith(
                                                    color: theme.colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                ),
                                                SizedBox(height: 0.5.h),
                                                FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: Row(
                                                    children: [
                                                      Text(
                                                        _salesmanName,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        maxLines: 1,
                                                        style: theme.textTheme
                                                            .titleLarge
                                                            ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                      if (!_isOnline) ...[
                                                        const SizedBox(
                                                            width: 8),
                                                        Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal: 6,
                                                                  vertical: 2),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: Colors.red
                                                                .withValues(
                                                                    alpha: 0.1),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        4),
                                                            border: Border.all(
                                                                color:
                                                                    Colors.red,
                                                                width: 0.5),
                                                          ),
                                                          child: const Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              Icon(
                                                                  Icons
                                                                      .wifi_off,
                                                                  size: 10,
                                                                  color: Colors
                                                                      .red),
                                                              SizedBox(
                                                                  width: 4),
                                                              Text("OFFLINE",
                                                                  style: TextStyle(
                                                                      color: Colors
                                                                          .red,
                                                                      fontSize:
                                                                          8,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold)),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ),
                                                SizedBox(height: 0.5.h),
                                                Text(
                                                  'ID: $_salesmanId',
                                                  style: theme
                                                      .textTheme.bodySmall
                                                      ?.copyWith(
                                                    color: theme.colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                ),
                                                SizedBox(height: 0.5.h),
                                                Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Container(
                                                      width: 6,
                                                      height: 6,
                                                      decoration: BoxDecoration(
                                                        color:
                                                            _statusIndicatorColor,
                                                        shape: BoxShape.circle,
                                                        boxShadow: [
                                                          BoxShadow(
                                                            color:
                                                                _statusIndicatorColor
                                                                    .withValues(
                                                                        alpha:
                                                                            0.4),
                                                            blurRadius: 4,
                                                            spreadRadius: 1,
                                                          )
                                                        ],
                                                      ),
                                                    ),
                                                    SizedBox(width: 2.w),
                                                    Flexible(
                                                      child: Text(
                                                        _isOnline
                                                            ? "Active"
                                                            : "Offline",
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: theme
                                                            .textTheme.bodySmall
                                                            ?.copyWith(
                                                          color:
                                                              _statusIndicatorColor,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 9,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          Material(
                                            color: Colors.transparent,
                                            child: InkWell(
                                              // 🔥 TASK 2 FIX: Replaced custom timer with Native onLongPress
                                              // This eliminates multi-fires and weird 1-4 vibrations!
                                              onLongPress: () {
                                                HapticFeedback.heavyImpact();
                                                _showAccountSwitcher();
                                              },
                                              onTap: () {
                                                Navigator.pushNamed(
                                                    context, AppRoutes.setting);
                                              },
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: Container(
                                                padding: EdgeInsets.all(2.w),
                                                decoration: BoxDecoration(
                                                  color: theme.colorScheme
                                                      .surfaceContainerHighest
                                                      .withValues(alpha: 0.3),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Stack(
                                                      children: [
                                                        IconButton(
                                                          padding:
                                                              EdgeInsets.zero,
                                                          constraints:
                                                              const BoxConstraints(),
                                                          icon: Icon(
                                                              Icons
                                                                  .notifications_none_rounded,
                                                              color: theme
                                                                  .colorScheme
                                                                  .onSurfaceVariant,
                                                              size: 22),
                                                          onPressed:
                                                              _openNotifications,
                                                        ),
                                                        if (_activeAnnouncements
                                                            .isNotEmpty)
                                                          Positioned(
                                                            right: 0,
                                                            top: 0,
                                                            child: Container(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .all(2),
                                                              decoration:
                                                                  const BoxDecoration(
                                                                color:
                                                                    Colors.red,
                                                                shape: BoxShape
                                                                    .circle,
                                                              ),
                                                              constraints:
                                                                  const BoxConstraints(
                                                                minWidth: 12,
                                                                minHeight: 12,
                                                              ),
                                                              child: Text(
                                                                '${_activeAnnouncements.length}',
                                                                style:
                                                                    const TextStyle(
                                                                  color: Colors
                                                                      .white,
                                                                  fontSize: 7,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                ),
                                                                textAlign:
                                                                    TextAlign
                                                                        .center,
                                                              ),
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                    SizedBox(width: 3.w),
                                                    CustomIconWidget(
                                                      iconName: 'settings',
                                                      color: theme.colorScheme
                                                          .onSurfaceVariant,
                                                      size: 22,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                          SizedBox(width: 3.w),
                                          GestureDetector(
                                            // 🔥 TASK 2 FIX: Native onLongPress here too
                                            onLongPress: () {
                                              HapticFeedback.heavyImpact();
                                              _showAccountSwitcher();
                                            },
                                            onTap: () {
                                              Navigator.pushNamed(
                                                  context, AppRoutes.setting);
                                            },
                                            child: Container(
                                              padding: EdgeInsets.all(2.w),
                                              decoration: BoxDecoration(
                                                color: theme.colorScheme
                                                    .primaryContainer
                                                    .withValues(alpha: 0.1),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: ProfileImageWidget(
                                                name: _salesmanName,
                                                profilePhoto: _profilePhoto,
                                                avatarAnimal: (_avatarAnimal
                                                                .toLowerCase() ==
                                                            'scarface lion' &&
                                                        _billedWalkingCount <
                                                            _scarfaceLimit)
                                                    ? "Lion"
                                                    : _avatarAnimal,
                                                size: 32,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 1.h),
                                    ],
                                  ),
                                ),
                              ),

                              // --- MAIN LIST ---
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: EdgeInsets.all(4.w),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // 🔥 STICKY ANNOUNCEMENT 🔥
                                      _buildStickyAnnouncements(),

                                      // 0. 🔥 TOP 3 PODIUM LEADERBOARD 🔥
                                      if (_isPodiumVisible) ...[
                                        Top3PodiumWidget(
                                          salesmen: _allSalesmen,
                                          isLoading: _isLoadingLeaderboard,
                                          initialShowroom: _showroomName,
                                          scarfaceLimit:
                                              _scarfaceLimit, // 🔥 PASSING LIMIT
                                          onRefresh: () {
                                            setState(() =>
                                                _isLoadingLeaderboard = true);
                                            _fetchWalkingLeaderboard();
                                          },
                                        ),
                                        SizedBox(height: 3.h),
                                      ],

                                      if (_showYesterdayAlert) ...[
                                        YesterdayStatusWidget(
                                          status: _yesterdayStatus,
                                          reason: _yesterdayReason,
                                          onDismiss: () {
                                            setState(() {
                                              _showYesterdayAlert = false;
                                            });
                                          },
                                        ),
                                      ],

                                      // 1. Attendance Tile
                                      AttendanceTileWidget(
                                        status: _attendanceStatus,
                                        lastTime: _lastAttendanceTime,
                                        hasLeaveAlert: _hasLeaveAlert,
                                        onTap: _handleAttendanceTap,
                                        onLongPress: _handleAttendanceLongPress,
                                      ),
                                      SizedBox(height: 3.h),

                                      // 2. 🔥 NEW: CUSTOMER FOLLOW-UP TILE 🔥
                                      if (_isWalkingEnabled) ...[
                                        CustomerFollowupTileWidget(
                                          pendingCount: _pendingWalkingCount,
                                          billedCount: _billedWalkingCount,
                                          onTap: _openWalkingNotes,
                                        ),
                                        SizedBox(height: 3.h),
                                      ],

                                      // 🔥 NEW: SERVICE REPORT TILE 🔥
                                      if (_isServiceEnabled &&
                                          _userRole.toLowerCase() ==
                                              'service') ...[
                                        ServiceReportTileWidget(
                                          pendingCount: _servicePendingCount,
                                          finishedCount: _serviceFinishedCount,
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                  builder: (context) =>
                                                      const ServiceScreen()),
                                            ).then((_) =>
                                                _fetchServerData(force: true));
                                          },
                                        ),
                                        SizedBox(height: 3.h),
                                      ],

                                      // 3. Stock Checking (Locked)
                                      StockCheckingTileWidget(
                                        lastScanCount: _lastStockCount,
                                        onTap: _handleStockCheckingTap,
                                        onLongPress:
                                            _handleStockCheckingLongPress,
                                      ),
                                      SizedBox(height: 3.h),

                                      // 4. Order Book (Locked)
                                      OrderBookTileWidget(
                                        pendingOrdersCount: _pendingOrdersCount,
                                        onTap: _handleOrderBookTap,
                                        onLongPress: _handleOrderBookLongPress,
                                      ),
                                      SizedBox(height: 3.h),

                                      // 5. Today's Overview (Stack - Locked)
                                      Stack(
                                        children: [
                                          Container(
                                            padding: EdgeInsets.all(4.w),
                                            decoration: BoxDecoration(
                                              color: theme.colorScheme.surface,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: theme
                                                      .colorScheme.shadow
                                                      .withValues(alpha: 0.05),
                                                  offset: const Offset(0, 2),
                                                  blurRadius: 8,
                                                ),
                                              ],
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Today\'s Overview',
                                                  style: theme
                                                      .textTheme.titleMedium
                                                      ?.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                SizedBox(height: 2.h),
                                                Row(
                                                  children: [
                                                    _buildOverviewItem(
                                                      theme,
                                                      'Total Calls',
                                                      '0',
                                                      Icons.phone_in_talk,
                                                      theme.colorScheme.primary
                                                          .withValues(
                                                              alpha: 0.5),
                                                    ),
                                                    _buildOverviewItem(
                                                      theme,
                                                      'Orders',
                                                      '0',
                                                      Icons
                                                          .shopping_bag_outlined,
                                                      theme.colorScheme.primary
                                                          .withValues(
                                                              alpha: 0.5),
                                                    ),
                                                    _buildOverviewItem(
                                                      theme,
                                                      'Collections',
                                                      '0',
                                                      Icons
                                                          .monetization_on_outlined,
                                                      theme.colorScheme.primary
                                                          .withValues(
                                                              alpha: 0.5),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          Positioned.fill(
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: theme.colorScheme.surface
                                                    .withValues(alpha: 0.6),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: const Center(
                                                child: Text(
                                                  'Coming Soon',
                                                  style: TextStyle(
                                                    color: Colors.grey,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 3.h),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

            // 🔥 MANDATORY PROFILE SETUP OVERLAY 🔥
            if (_showProfileSetup)
              ProfileSetupOverlay(
                onComplete: () async {
                  // 🔥 FIX: Set permanent flag FIRST, then dismiss overlay
                  await SecureStorageService.setProfileSetupDone(true);

                  // 🔥 SYNC: Reload local state strings immediately to show in header/UI
                  final photo =
                      await SecureStorageService.readString('profile_photo');
                  final animal =
                      await SecureStorageService.readString('avatar_animal');

                  setState(() {
                    _showProfileSetup = false;
                    if (photo != null && photo.isNotEmpty) {
                      _profilePhoto = photo;
                    }
                    if (animal != null && animal.isNotEmpty) {
                      _avatarAnimal = animal;
                    }
                  });

                  // Refresh business data
                  _fetchServerData(force: true);
                },
              ),
          ],
        ),
      ),
      bottomNavigationBar: CustomBottomBar(
        currentRoute: '/dashboard',
      ),
    );
  }

  Widget _buildSkeletonLoading(ThemeData theme) {
    bool isDark = theme.brightness == Brightness.dark;
    Color surfaceColor = isDark ? const Color(0xFF15222B) : Colors.white;

    return SingleChildScrollView(
      child: Column(
        children: [
          // Simulated top header
          Container(
            padding: EdgeInsets.all(4.w),
            color: surfaceColor,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SkeletonBox(width: 30.w, height: 1.5.h),
                    SizedBox(height: 1.h),
                    _SkeletonBox(width: 50.w, height: 2.5.h),
                    SizedBox(height: 1.h),
                    _SkeletonBox(width: 20.w, height: 1.5.h),
                  ],
                ),
                _SkeletonBox(width: 12.w, height: 12.w, shape: BoxShape.circle),
              ],
            ),
          ),
          // Body padding
          Padding(
            padding: EdgeInsets.all(4.w),
            child: Column(
              children: [
                _SkeletonBox(width: double.infinity, height: 12.h),
                SizedBox(height: 3.h),
                _SkeletonBox(width: double.infinity, height: 12.h),
                SizedBox(height: 3.h),
                _SkeletonBox(width: double.infinity, height: 12.h),
                SizedBox(height: 3.h),
                _SkeletonBox(width: double.infinity, height: 12.h),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAccountSwitcher() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const AccountSwitcherOverlay(),
    );
  }
}

class _SkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final BoxShape shape;
  const _SkeletonBox(
      {required this.width,
      required this.height,
      this.shape = BoxShape.rectangle});

  @override
  _SkeletonBoxState createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<_SkeletonBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color baseColor = isDark ? Colors.grey.shade800 : Colors.grey.shade300;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: baseColor.withValues(alpha: 0.4 + (_controller.value * 0.4)),
            shape: widget.shape,
            borderRadius: widget.shape == BoxShape.circle
                ? null
                : BorderRadius.circular(8),
          ),
        );
      },
    );
  }
}
