import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart'; // NEW: Firebase Core
import 'package:firebase_app_check/firebase_app_check.dart'; // NEW: Firebase App Check
import 'package:firebase_crashlytics/firebase_crashlytics.dart'; // NEW: Firebase Crashlytics
import 'package:firebase_database/firebase_database.dart'; // 🔥 RTDB for global suspension + presence
import 'package:disable_battery_optimization/disable_battery_optimization.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // 🔥 NEW: Maintenance Mode Listener
import 'package:permission_handler/permission_handler.dart' hide ServiceStatus;
import 'package:geolocator/geolocator.dart';
import 'package:sizer/sizer.dart';
import 'package:slfm_salesman_app/core/app_export.dart';
//  IMPORT BACKGROUND SERVICE
import 'package:slfm_salesman_app/services/security_service.dart'; // NEW: RASP Security
import 'package:slfm_salesman_app/services/secure_storage_service.dart'; // 🔥 For global suspension check
import 'package:slfm_salesman_app/presentation/walking_notes/walking_notes_screen.dart';
import 'package:slfm_salesman_app/presentation/splash_screen/splash_screen.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:slfm_salesman_app/core/services/offline_sync_service.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'core/services/notification_service.dart';
import 'services/theme_service.dart';
import 'services/theme_notifier.dart';
import 'package:slfm_salesman_app/firebase_options.dart';
import 'services/feature_control_service.dart';
import 'presentation/permission_screen/permission_screen.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // 🔥 FCM: WhatsApp-style wake-up
import 'package:slfm_salesman_app/core/database/local_db_helper.dart'; // 🔥 SQLite for offline location history

// Global key moved to notification_service.dart

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

// 🔥 FCM BACKGROUND HANDLER — MUST be top-level (outside any class)
// This runs in a SEPARATE ISOLATE when a silent push arrives while the app is killed/locked.
// WhatsApp-style: OS wakes up this isolate → we fetch location → update RTDB → isolate dies.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // 1. Initialize Firebase in this background isolate
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e) {
    // Already initialized or Hot Restart — safe to ignore
  }

  // 2. Read salesman ID from secure storage
  String salesmanId = '';
  try {
    salesmanId = await SecureStorageService.getSalesmanId() ?? '';
  } catch (e) {
    // KeyStore locked or unavailable — abort silently
    return;
  }

  if (salesmanId.isEmpty) return; // No user logged in — nothing to do

  // 3. Check if GPS/Location service is enabled
  bool isGpsOn = false;
  try {
    isGpsOn = await Geolocator.isLocationServiceEnabled();
  } catch (e) {
    // Cannot determine GPS state — treat as OFF
  }

  final rtdb = FirebaseDatabase.instance.ref('locations/$salesmanId');

  if (!isGpsOn) {
    // 🚨 GPS is OFF — Alert admin immediately
    try {
      await rtdb.update({
        'gps_status': 'OFF',
        'updated_at': ServerValue.timestamp,
      }).timeout(const Duration(seconds: 15));
    } catch (_) {}
    return;
  }

  // 4. Check location permission
  try {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return; // No permission — can't fetch location
    }
  } catch (e) {
    return;
  }

  // 5. Get current position
  Position? position;
  try {
    position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
  } catch (e) {
    // Timeout or error — try cached location
    try {
      Position? lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        final age = DateTime.now().difference(lastKnown.timestamp);
        if (age.inMinutes <= 5) {
          position = lastKnown;
        }
      }
    } catch (_) {}
  }

  if (position == null || (position.latitude == 0 && position.longitude == 0)) {
    return; // No valid position available
  }

  // 🚨 Anti-Spoofing: Reject mock/fake GPS
  if (position.isMocked) return;

  // 6. Update RTDB with fresh location
  try {
    await rtdb.set({
      'lat': position.latitude,
      'lng': position.longitude,
      'updated_at': ServerValue.timestamp,
      'gps_status': 'ON',
    }).timeout(const Duration(seconds: 15));
  } catch (_) {}

  // 7. Also update tracking_status to show the app responded
  try {
    await FirebaseDatabase.instance.ref('tracking_status/$salesmanId').update({
      'last_fcm_response': ServerValue.timestamp,
      'is_online': true,
    }).timeout(const Duration(seconds: 10));
  } catch (_) {}

  // 8. Record to offline location history and sync to RTDB if enabled
  try {
    final trackingSnapshot = await FirebaseDatabase.instance
        .ref('tracking_requests/$salesmanId/record_history')
        .get()
        .timeout(const Duration(seconds: 8));

    if (trackingSnapshot.exists && trackingSnapshot.value == true) {
      // Save to local database
      await LocalDbHelper.instance.insertOfflineLocation(
        salesmanId,
        position.latitude,
        position.longitude,
        DateTime.now().millisecondsSinceEpoch,
        'ON',
      );

      // Sync pending locations to RTDB
      final pendingLocations =
          await LocalDbHelper.instance.getPendingLocations(salesmanId);
      if (pendingLocations.isNotEmpty) {
        // Group records by date (YYYY-MM-DD)
        Map<String, List<Map<String, dynamic>>> grouped = {};
        for (var loc in pendingLocations) {
          int ts = loc['timestamp'];
          DateTime dt = DateTime.fromMillisecondsSinceEpoch(ts);
          String dateStr =
              '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
          if (!grouped.containsKey(dateStr)) {
            grouped[dateStr] = [];
          }
          grouped[dateStr]!.add(loc);
        }

        final dbRef = FirebaseDatabase.instance.ref('location_history');
        List<int> syncedIds = [];

        for (String dateStr in grouped.keys) {
          for (var loc in grouped[dateStr]!) {
            String pushId = dbRef.push().key ??
                DateTime.now().millisecondsSinceEpoch.toString();
            await dbRef.child(dateStr).child(salesmanId).child(pushId).set({
              'lat': loc['latitude'],
              'lng': loc['longitude'],
              'timestamp': loc['timestamp'],
              'status': loc['status'],
            }).timeout(const Duration(seconds: 10));
            syncedIds.add(loc['id']);
          }
        }

        // Delete synced ones from local database
        if (syncedIds.isNotEmpty) {
          await LocalDbHelper.instance.deletePendingLocations(syncedIds);
          debugPrint(
              "✅ FCM Isolate: Synced ${syncedIds.length} location history points.");
        }
      }
    }
  } catch (e) {
    debugPrint("Error in FCM history recording/syncing: $e");
  }
}

Future<void> main() async {
  // 🚀 PERFORMANCE OPTIMIZATION: Disable all debug prints in Release Mode
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  WidgetsFlutterBinding.ensureInitialized();

  // 🛡️ SSL HANDSHAKE FIX: Prevents "Connection terminated during handshake" crash on Realme/older devices
  HttpOverrides.global = GlobalHttpOverrides();

  // 🛡️ BUNDLED FONTS: Set to false to force using local assets and prevent offline crashes.
  GoogleFonts.config.allowRuntimeFetching = false;

  // 🔥 Initialize Firebase with safety guards for Hot Restarts
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e) {
    debugPrint(
        "⚠️ Firebase already initialized or encountered Hot Restart issue: $e");
  }

  // 🔐 EARLY AUTH: Sign in anonymously BEFORE any RTDB reads (rules require auth != null)
  if (FirebaseAuth.instance.currentUser == null) {
    try {
      await FirebaseAuth.instance.signInAnonymously();
      debugPrint("🔐 Early anonymous auth succeeded");
    } on PlatformException catch (e) {
      // 🛡️ OnePlus devices: SignInHubActivity NullPointerException workaround
      debugPrint(
          "⚠️ Early anonymous auth PlatformException (device-specific): $e");
    } catch (e) {
      debugPrint("⚠️ Early anonymous auth failed: $e");
    }
  }

  // 🔥 Initialize Firebase App Check
  try {
    await FirebaseAppCheck.instance.activate(
      providerAndroid:
          kDebugMode ? AndroidDebugProvider() : AndroidPlayIntegrityProvider(),
    );
  } catch (e) {
    debugPrint("⚠️ Firebase App Check activation failed: $e");
  }

  // 🔥 FCM: Register background handler BEFORE any other messaging code
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // 🔥 FCM: Get device token and save to RTDB (for Cloud Function to target)
  try {
    final fcmToken = await FirebaseMessaging.instance.getToken();
    if (fcmToken != null) {
      debugPrint("🔥 FCM Token obtained: ${fcmToken.substring(0, 20)}...");
      // Save immediately if a salesman is already logged in
      final salesmanId = await SecureStorageService.getSalesmanId();
      if (salesmanId != null && salesmanId.isNotEmpty) {
        await FirebaseDatabase.instance
            .ref('salesmen/$salesmanId/fcmToken')
            .set(fcmToken)
            .timeout(const Duration(seconds: 10));
        debugPrint("✅ FCM Token saved to RTDB for salesman: $salesmanId");
      }
    }
  } catch (e) {
    debugPrint("⚠️ FCM token fetch/save error: $e");
  }

  // 🔥 FCM: Listen for token refresh (tokens change periodically)
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
    try {
      final salesmanId = await SecureStorageService.getSalesmanId();
      if (salesmanId != null && salesmanId.isNotEmpty) {
        await FirebaseDatabase.instance
            .ref('salesmen/$salesmanId/fcmToken')
            .set(newToken)
            .timeout(const Duration(seconds: 10));
        debugPrint("🔄 FCM Token REFRESHED and saved for $salesmanId");
      }
    } catch (e) {
      debugPrint("⚠️ FCM token refresh save error: $e");
    }
  });

  // 🔥 FCM: Handle foreground messages (silent — just trigger location update)
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    debugPrint("📩 FCM foreground message received: ${message.data}");
    // App is already in foreground — trigger a force sync
    try {
      FlutterBackgroundService().invoke('force_sync');
    } catch (e) {
      debugPrint("FCM foreground sync trigger error: $e");
    }
  });

  // 🔥 STEP 2: Initialize Unified Notification Service
  await NotificationService().init();

  // 1.1 Initialize Hive & Sync Service
  await Hive.initFlutter();
  await ThemeService.init(); // 🔥 Initialize Theme Service
  await OfflineSyncService().init();
  await FeatureControlService().init(); // 🔥 Start Global Feature Listener

  // 🔥 NEW: Crashlytics Error Handling
  // Only log to Crashlytics — do NOT call runApp() here.
  // runApp() destroys the entire widget tree, so even a minor render
  // glitch (e.g., layout overflow during tab animation) would nuke
  // the whole app and show "Something went wrong".
  FlutterError.onError = (errorDetails) {
    FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
    debugPrint("FlutterError caught: ${errorDetails.exceptionAsString()}");
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  // ErrorWidget.builder replaces only the broken widget in the tree,
  // so it must be lightweight — no Scaffold, no navigation, just a
  // small inline error indicator.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    debugPrint("ErrorWidget triggered: ${details.exceptionAsString()}");
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
            const SizedBox(height: 8),
            Text(
              "Something went wrong",
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF262626),
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  };

  Future.wait([
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
  ]).then((value) {
    runApp(const MyApp());
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Sizer(
      builder: (context, orientation, deviceType) {
        return ListenableBuilder(
          listenable: themeNotifier,
          builder: (context, child) {
            return MaterialApp(
              navigatorKey: navigatorKey, // 🔥 Attach Global Key
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: themeNotifier.themeMode,
              title: 'SLFM Attendance app',
              debugShowCheckedModeBanner: false,
              initialRoute: AppRoutes.initial, // Points to Splash Screen
              routes: AppRoutes.routes,
              // Global Location Guard applied to all screens
              builder: (context, child) {
                return SecurityGuard(child: child);
              },
            );
          },
        );
      },
    );
  }
}

class SecurityGuard extends StatefulWidget {
  final Widget? child;
  const SecurityGuard({super.key, required this.child});

  @override
  State<SecurityGuard> createState() => SecurityGuardState();
}

SecurityGuardState? globalSecurityGuardState;

class SecurityGuardState extends State<SecurityGuard>
    with WidgetsBindingObserver {
  bool _isLocationEnabled = true;
  bool _hasLocationPermission = true;
  bool _hasCameraPermission = true;
  bool _hasNotificationPermission = true;
  bool _hasBatteryOptimization = true; // 🔋 Track battery optimization
  bool _isTimeCorrect = true;
  bool _isVpnActive = false; // 🔥 NEW: Track VPN State
  bool _isLoggedIn = false; // 🔥 NEW: Track login state
  bool _isInitialCheckDone = false; // 📍 NEW: Prevent flicker on first start
  Timer? _locationCheckTimer; // 📍 Only checking location periodically now
  Timer? _splashCheckTimer; // 🔥 NEW: Instantly update UI when splash finishes

  // 🔥 Stable key for PermissionScreen's Navigator wrapper
  // Prevents Navigator from being destroyed/recreated on SecurityGuard rebuilds
  final GlobalKey<NavigatorState> _permissionNavKey =
      GlobalKey<NavigatorState>();

  // 🔥 GLOBAL SUSPENSION & PRESENCE
  StreamSubscription<DatabaseEvent>? _suspensionSubscription;
  StreamSubscription<DatabaseEvent>?
      _timeOffsetSubscription; // 🔥 NEW: Global Time Listener
  StreamSubscription?
      _maintenanceSubscription; // 🔥 Maintenance Listener (Dynamic to handle different snapshot types)
  StreamSubscription<List<ConnectivityResult>>?
      _connectivitySubscription; // 🔥 Global Offline Listener
  DatabaseReference? _presenceRef;
  bool _isSuspendedDialogShowing = false;
  bool _isMaintenanceMode = false; // 🔥 NEW
  bool _isOffline = false; // 🔥 Global Offline State
  bool _showBackOnline = false; // 🔥 Show green back online banner briefly
  Timer? _backOnlineTimer;
  String _maintenanceMsg =
      "System is currently under maintenance. Please try again later."; // 🔥 NEW

  @override
  void initState() {
    super.initState();
    globalSecurityGuardState = this; // Export state globally
    WidgetsBinding.instance.addObserver(this);
    _checkLocationOnly();
    _checkVpn(); // 🔥 Check VPN on startup
    _setupGlobalTimeListener(); // 🔥 Start listening to time offset immediately

    // 🔥 FIX FOR LATE OFFLINE BANNER:
    // Constantly monitor if Splash Screen has finished. Once it finishes,
    // trigger a setState immediately so the banner pops up without delay!
    _splashCheckTimer =
        Timer.periodic(const Duration(milliseconds: 300), (timer) {
      if (!SplashScreen.isSplashScreenActive) {
        if (mounted) {
          setState(() {}); // Force rebuild immediately to show banner!
        }
        timer.cancel(); // Stop checking once we know splash is done
      }
    });

    // 🔥 Check Initial Notification Payload (Cold Start)
    _checkInitialPayload();

    // 🔥 Start RASP Protection (freerasp)
    SecurityService.initialize();

    // 🔥 INITIAL PERMISSION CHECK
    refreshPermissions();

    // 🔥 GLOBAL: Setup suspension listener + online presence
    setupGlobalSuspensionAndPresence();

    // 🔥 NEW: Setup real-time Maintenance Mode Listener
    _setupMaintenanceListener();

    // 🔥 NEW: Setup Global Internet Listener
    _setupConnectivityListener();
  }

  void _setupConnectivityListener() async {
    try {
      List<ConnectivityResult> initialResult =
          await Connectivity().checkConnectivity();
      if (mounted) {
        setState(() {
          _isOffline = initialResult.contains(ConnectivityResult.none);
        });
      }
    } catch (e) {
      debugPrint("Initial connectivity check error: $e");
    }

    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> result) {
      bool isOffline = result.contains(ConnectivityResult.none);
      
      // 🔥 NEW: Check VPN immediately when any network change happens!
      // This helps if user toggles VPN from the Quick Settings dropdown without minimizing the app.
      _checkVpn();
      
      if (_isOffline != isOffline) {
        debugPrint("🌐 Global Network Change: Offline=$isOffline");
        if (mounted) {
          setState(() {
            if (_isOffline && !isOffline) {
              // Came back online
              _showBackOnline = true;
              _backOnlineTimer?.cancel();
              _backOnlineTimer = Timer(const Duration(seconds: 3), () {
                if (mounted) setState(() => _showBackOnline = false);
              });
            } else if (isOffline) {
              _showBackOnline = false;
            }
            _isOffline = isOffline;
          });
        }
      }
    });
  }

  // 🔥 NEW: Public method to trigger a full permission re-check
  Future<void> refreshPermissions() async {
    await _checkAllPermissions();
  }

  // 🔥 NEW: Public method to force UI rebuild (can be called from anywhere)
  void forceRebuild() {
    if (mounted) setState(() {});
  }

  void _setupMaintenanceListener() {
    _maintenanceSubscription?.cancel();
    _maintenanceSubscription = FirebaseFirestore.instance
        .collection('app_settings')
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          for (var doc in snapshot.docs) {
            final data = doc.data();
            final val = data['setting_value'];
            if (doc.id == 'maintenance_mode') {
              _isMaintenanceMode = (val == 1 || val == true);
            } else if (doc.id == 'maintenance_message') {
              _maintenanceMsg = val?.toString() ??
                  "System under maintenance. Please try again later.";
            }
          }
        });
      }
    });
  }

  Future<void> _checkInitialPayload() async {
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    final NotificationAppLaunchDetails? details =
        await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();

    if (details != null &&
        details.didNotificationLaunchApp &&
        details.notificationResponse?.payload == 'navigate_walking') {
      debugPrint("🚀 Cold Start Notification Click: Navigating...");
      // Delay slightly to allow App to build
      Future.delayed(const Duration(seconds: 2), () {
        navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (context) => const WalkingNotesScreen()),
        );
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _splashCheckTimer?.cancel(); // 🔥 Cleanup Splash Timer
    _locationCheckTimer?.cancel();
    _backOnlineTimer?.cancel(); //online and offline
    _suspensionSubscription?.cancel();
    _timeOffsetSubscription?.cancel(); // 🔥 Cleanup
    _maintenanceSubscription?.cancel(); // 🔥 Use Null Safety
    _connectivitySubscription?.cancel(); // 🔥 Global network cleanup
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint("🔄 App Resumed: Checking Security (Location & Time)...");

      // 🔥 ALWAYS refresh location state when returning to the app!
      // (This fixes the bug where turning on location in settings doesn't dismiss the warning screen)
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _checkAllPermissions();
          _checkVpn(); // 🔥 Check VPN again on resume
        }
      });

      // 🔥 Check if permissions are all granted BEFORE doing heavy work
      bool allGranted = _isLocationEnabled &&
          _hasLocationPermission &&
          _hasCameraPermission &&
          _hasNotificationPermission &&
          _hasBatteryOptimization;

      if (!allGranted) {
        // 🔥 PermissionScreen has its own lifecycle observer — do NOTHING here
        // Calling refreshPermissions() here destroys the Navigator wrapper,
        // causing black screen + crash when returning from permission dialogs
        debugPrint(
            "🔄 Permissions not granted yet, skipping heavy resume work");
        return;
      }

      // 🔥 Delay heavy work to prevent ANR
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return;

        // 🔥 FORCE Firebase Reconnect: This forces Firebase to do a new WebSocket handshake,
        // which recalculates `.info/serverTimeOffset` against the current device time!
        try {
          FirebaseDatabase.instance.goOffline();
          FirebaseDatabase.instance.goOnline();
        } catch (e) {
          debugPrint("Firebase reconnect error: $e");
        }

        FlutterBackgroundService().invoke('force_sync');
        _updateOnlinePresence(true);
      });
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _updateOnlinePresence(false);
    }
  }

  // ─── GLOBAL SUSPENSION & ONLINE PRESENCE ───

  Future<void> setupGlobalSuspensionAndPresence() async {
    try {
      final salesmanId = await SecureStorageService.readString('salesman_id');

      // 🔥 CRITICAL: If no one is logged in, CLEAR everything and exit
      if (salesmanId == null || salesmanId.isEmpty) {
        debugPrint(
            "🔸 SecurityGuard: No salesmanId found. Clearing listeners...");
        if (mounted) setState(() => _isLoggedIn = false);
        await _clearAllListeners();
        return;
      }

      if (mounted) setState(() => _isLoggedIn = true);

      // 🔥 AUTH FALLBACK: If not signed in, sign in anonymously to satisfy 'auth != null'
      if (FirebaseAuth.instance.currentUser == null) {
        debugPrint("🔐 FirebaseAuth: No user found, signing in anonymously...");
        await FirebaseAuth.instance.signInAnonymously();
      }

      // 1. CLEAR OLD STATE BEFORE NEW USER
      await _clearAllListeners();

      // 2. Setup online presence with onDisconnect()
      _presenceRef =
          FirebaseDatabase.instance.ref('tracking_status/$salesmanId');

      // Shadow variable for null safety
      final ref = _presenceRef;
      if (ref != null) {
        await ref.update({
          'is_online': true,
          'last_online': ServerValue.timestamp,
        });

        // 🔥 CRITICAL: onDisconnect marks offline if app is killed or loses connection
        await ref.onDisconnect().update({
          'is_online': false,
          'last_online': ServerValue.timestamp,
        });
      }

      debugPrint(
          "✅ Global presence set: is_online=true, onDisconnect registered");

      // 🔥 FCM: Save device token to RTDB (ensures token is saved after login)
      try {
        final fcmToken = await FirebaseMessaging.instance.getToken();
        if (fcmToken != null) {
          await FirebaseDatabase.instance
              .ref('salesmen/$salesmanId/fcmToken')
              .set(fcmToken)
              .timeout(const Duration(seconds: 10));
          debugPrint("✅ FCM Token saved on login for salesman: $salesmanId");
        }
      } catch (e) {
        debugPrint("⚠️ FCM token save on login error: $e");
      }

      // 3. Setup global suspension listener
      _suspensionSubscription = FirebaseDatabase.instance
          .ref('salesmen_status/$salesmanId/status')
          .onValue
          .listen((DatabaseEvent event) async {
        if (event.snapshot.value == null) {
          debugPrint("🔸 Suspension Listener: No data for $salesmanId");
          return;
        }
        final status = event.snapshot.value.toString().toLowerCase();
        debugPrint("🔸 Suspension Status Update: $status (ID: $salesmanId)");

        if (status == 'suspended') {
          if (_isSuspendedDialogShowing) {
            return;
          }
          _isSuspendedDialogShowing = true;
          debugPrint("🛑 GLOBAL SUSPENSION DETECTED: Forcing logout...");

          // Force background service to stop FIRST
          try {
            FlutterBackgroundService().invoke("stopService");
          } catch (e) {
            debugPrint("Suspension BG stop error: $e");
          }

          // Show dialog and wait for OK to clean session and redirect
          // Use mounted check right before showing dialog
          if (mounted) {
            final ctx = navigatorKey.currentContext;
            if (ctx != null && ctx.mounted) {
              showDialog(
                context: ctx,
                barrierDismissible: false,
                builder: (dialogCtx) => PopScope(
                  canPop: false,
                  child: AlertDialog(
                    title: const Row(children: [
                      Icon(Icons.block, color: Colors.red),
                      SizedBox(width: 8),
                      Text("Account Suspended"),
                    ]),
                    content: const Text(
                        "Your account is suspended. Please logout by clicking OK."),
                    actions: [
                      TextButton(
                        child: const Text("OK",
                            style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          _isSuspendedDialogShowing =
                              false; // Mark closed before navigating
                          try {
                            await SecureStorageService.clearSession();
                          } catch (e) {
                            debugPrint("Clear session error: $e");
                          }
                          navigatorKey.currentState?.pushNamedAndRemoveUntil(
                              '/login-screen', (route) => false);
                        },
                      )
                    ],
                  ),
                ),
              ).then((_) {
                // Safety: Ensure flag is reset if dialog closes for any other reason
                _isSuspendedDialogShowing = false;
              });
            } else {
              _isSuspendedDialogShowing = false;
            }
          }
        } else {
          // If admin reactivates while dialog is showing, close it safely
          if (_isSuspendedDialogShowing) {
            _isSuspendedDialogShowing = false;
            // Use maybePop and check canPop to ensure we never pop the root screen (black screen fix)
            if (navigatorKey.currentState?.canPop() ?? false) {
              navigatorKey.currentState?.maybePop();
            }
          }
        }
      }, onError: (error) {
        // 🔥 SILENTLY CATCH PERMISSION ERRORS (common on emulators/App Check issues)
        debugPrint("🛑 Global Firebase Suspension Listener Error: $error");
      });
    } catch (e) {
      debugPrint("⚠️ Global suspension/presence setup error: $e");
    }
  }

  /// 🔥 NEW: Robust listener cleanup to prevent MissingPluginException and memory leaks
  Future<void> _clearAllListeners() async {
    try {
      // 1. Mark offline manually before clearing reference (if we still have one)
      if (_presenceRef != null) {
        await _presenceRef!.update({
          'is_online': false,
          'last_online': ServerValue.timestamp,
        });
        _presenceRef = null;
      }

      // 2. Cancel subscriptions with try-catch
      if (_suspensionSubscription != null) {
        try {
          await _suspensionSubscription!.cancel();
        } catch (e) {
          debugPrint("🔸 Silent ignore: suspension cancel error: $e");
        }
        _suspensionSubscription = null;
      }
    } catch (e) {
      debugPrint("🔸 Error in _clearAllListeners: $e");
    }
  }

  Future<void> _updateOnlinePresence(bool isOnline) async {
    try {
      final ref = _presenceRef;
      if (ref != null) {
        await ref.update({
          'is_online': isOnline,
          'last_online': ServerValue.timestamp,
        });
      }
    } catch (e) {
      debugPrint("Presence update error: $e");
    }
  }

  Future<void> _checkAllPermissions() async {
    try {
      // 1. Check Location Service & Permission
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      LocationPermission locPerm = await Geolocator.checkPermission();

      // 2. Check Camera
      final cameraStatus = await Permission.camera.status;

      // 3. Check Notification
      final notificationStatus = await Permission.notification.status;

      // 4. Check Battery Optimization using disable_battery_optimization plugin
      bool? isBatteryOptDisabled =
          await DisableBatteryOptimization.isBatteryOptimizationDisabled;

      // 🔥 FIX: Check fallback from SecureStorage because some OEMs always return false
      final hasClickedBattery =
          await SecureStorageService.readBool('has_clicked_battery_opt');

      final batteryStatusGranted =
          (isBatteryOptDisabled == true) || (hasClickedBattery == true);

      if (mounted) {
        setState(() {
          _isLocationEnabled = serviceEnabled;
          _hasLocationPermission = (locPerm == LocationPermission.always);
          _hasCameraPermission = cameraStatus.isGranted;
          _hasNotificationPermission = notificationStatus.isGranted;
          _hasBatteryOptimization = batteryStatusGranted;
          _isInitialCheckDone = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitialCheckDone = true;
        });
      }
    }
  }

  // Keep for backward compatibility if any other code calls it
  Future<void> _checkLocationOnly() async {
    await _checkAllPermissions();
  }

  // --- 🔥 NEW: VPN CHECKER ---
  Future<void> _checkVpn() async {
    bool vpnActive = false;
    try {
      List<NetworkInterface> interfaces = await NetworkInterface.list(
          includeLoopback: false, type: InternetAddressType.any);
      if (interfaces.isNotEmpty) {
        for (NetworkInterface interface in interfaces) {
          final name = interface.name.toLowerCase();
          if (name.contains("tun") ||
              name.contains("ppp") ||
              name.contains("pptp") ||
              name.contains("tap")) {
            vpnActive = true;
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking VPN: $e');
    }

    if (mounted && _isVpnActive != vpnActive) {
      setState(() {
        _isVpnActive = vpnActive;
      });
    }
  }

  // --- 🔥 NEW: FIREBASE GLOBAL TIME LISTENER ---
  void _setupGlobalTimeListener() {
    _timeOffsetSubscription?.cancel();
    _timeOffsetSubscription = FirebaseDatabase.instance
        .ref('.info/serverTimeOffset')
        .onValue
        .listen((DatabaseEvent event) {
      if (event.snapshot.value != null) {
        // offset = serverTime - localTime
        int offset = (event.snapshot.value as num).toInt();

        // Tolerance: 3 minutes (180,000 milliseconds)
        bool isCorrect = offset.abs() <= 180000;

        if (_isTimeCorrect != isCorrect) {
          debugPrint(
              "⏰ Firebase Time Check: Offset=$offset. Time is ${isCorrect ? 'CORRECT' : 'WRONG'}!");
          if (mounted) {
            setState(() {
              _isTimeCorrect = isCorrect;
            });
          }
        }
      }
    }, onError: (error) {
      debugPrint("⚠️ Firebase Time Listener Error: $error");
      // If error, assume true to not block app incorrectly
      if (mounted && !_isTimeCorrect) {
        setState(() => _isTimeCorrect = true);
      }
    });
  }

  void _onUserInteraction(PointerEvent event) {
    if (!_isTimeCorrect) {
      return; // Already blocked
    }
    // We no longer manually verify time here because the Firebase listener is Real-Time!
  }

  @override
  Widget build(BuildContext context) {
    if (widget.child == null) {
      return const SizedBox.shrink();
    }

    // (Removed global blocking UI for offline, we use a banner instead)

    // 0. 🔥 Check Maintenance Mode (Real-time Blocking)
    if (_isMaintenanceMode) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 30),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF0F172A).withValues(alpha: 0.95),
                const Color(0xFF1E293B),
              ],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Rotating/Glowing Icon
              TweenAnimationBuilder(
                tween: Tween<double>(begin: 0, end: 2 * 3.14159),
                duration: const Duration(seconds: 10),
                builder: (context, double rotation, child) {
                  return Transform.rotate(
                    angle: rotation,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.amber.withValues(alpha: 0.2),
                            blurRadius: 40,
                            spreadRadius: 10,
                          )
                        ],
                      ),
                      child: const Icon(Icons.settings_suggest_rounded,
                          size: 100, color: Colors.amber),
                    ),
                  );
                },
                onEnd: () {}, // Restart loop
              ),
              const SizedBox(height: 40),
              Text(
                "Maintenance Active",
                style: GoogleFonts.orbitron(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.white10),
                ),
                child: Text(
                  _maintenanceMsg,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    color: Colors.white70,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 40),
              const Text(
                "Our team is upgrading the system.\nWe'll be back shortly!",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white30, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    // 0.5 Check VPN Active (Block immediately if VPN is ON)
    if (_isVpnActive) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.vpn_key_off, size: 80, color: Colors.red),
              const SizedBox(height: 20),
              const Text(
                "VPN Detected!",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 15),
              const Text(
                "தயவுசெய்து உங்கள் மொபைலில் உள்ள VPN-ஐ OFF செய்துவிட்டு, மீண்டும் App-ஐ திறக்கவும்.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.black87),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () {
                  _checkVpn();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                ),
                child: const Text("Check Again"),
              ),
            ],
          ),
        ),
      );
    }

    // 1. Check Time First (Security)
    if (!_isTimeCorrect) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.timer_off_outlined, size: 80, color: Colors.red),
              const SizedBox(height: 20),
              const Text(
                "உங்கள் மொபைல் நேரம் தவறாக உள்ளது!", // "Incorrect Device Time!"
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 15),
              const Text(
                "உங்கள் மொபைல் நேரம் சர்வர் நேரத்துடன் பொருந்தவில்லை.\n\nதயவுசெய்து உங்கள் மொபைல் Settings-ல் 'Automatic Date & Time'-ஐ ஆன் செய்யவும்.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.black87),
              ),
              const SizedBox(height: 30),
              // We don't need a retry button because Firebase updates automatically
              // when the user corrects the time in Settings!
              const Text(
                "Time check is automatic. Fix the time to proceed.",
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    // 1.5. Check if GPS Hardware (Location Service) is turned on
    if (!_isLocationEnabled && _isLoggedIn) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_off_rounded,
                  size: 80, color: Colors.orange),
              const SizedBox(height: 20),
              const Text(
                "GPS / Location is Disabled",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(height: 15),
              const Text(
                "Your device's Location service is turned off. Please pull down the notification panel and turn on Location/GPS to continue.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.black87),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () async {
                  await Geolocator.openLocationSettings();
                  // Force re-check
                  globalSecurityGuardState?.refreshPermissions();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                ),
                child: const Text("Open Location Settings"),
              ),
            ],
          ),
        ),
      );
    }

    // 2. Check Permissions (Location Always, Camera, Notification)
    // 🔥 NEW: If initial check is not done, show the app content (Splash) to avoid red flicker
    // Also, don't block if they are on the Login screen (they need to login first)
    // 🔥 NEW: Enforce Permissions ONLY AFTER Login.
    bool allPermissionsGranted = _isLocationEnabled &&
        _hasLocationPermission &&
        _hasCameraPermission &&
        _hasNotificationPermission;

    if (!_isInitialCheckDone || !_isLoggedIn || allPermissionsGranted) {
      final bool showBanner =
          (_isOffline || _showBackOnline) && !SplashScreen.isSplashScreenActive;

      return Listener(
        onPointerDown: _onUserInteraction,
        behavior: HitTestBehavior.translucent,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: showBanner ? 1.0 : 0.0),
            duration: const Duration(milliseconds: 300),
            builder: (context, value, child) {
              final double topPadding = MediaQuery.of(context).padding.top;
              final double maxBannerHeight = 24.0 + topPadding;
              final double currentBannerHeight = maxBannerHeight * value;

              // We want to remove the top padding from the child proportionally
              // as the banner takes over the status bar space.
              final double remainingTopPadding = topPadding * (1.0 - value);

              return Column(
                children: [
                  Container(
                    height: currentBannerHeight,
                    color: _isOffline ? Colors.red : Colors.green,
                    width: double.infinity,
                    alignment: Alignment.bottomCenter,
                    padding: const EdgeInsets.only(bottom: 2),
                    child: value > 0.1
                        ? Text(
                            _isOffline
                                ? "No Internet Connection"
                                : "Back Online",
                            style: TextStyle(
                              color: Colors.white
                                  .withValues(alpha: value.clamp(0.0, 1.0)),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.none,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  Expanded(
                    child: MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        padding: EdgeInsets.only(top: remainingTopPadding),
                      ),
                      child: widget.child!,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    }

    // 3. Mandatory Permission Onboarding Page
    // We only force this AFTER login.
    // 🔥 Wrap in Navigator so showDialog/openAppSettings works
    // Use _permissionNavKey so Navigator survives SecurityGuard rebuilds (no black screen)
    return Navigator(
      key: _permissionNavKey,
      onGenerateRoute: (_) => MaterialPageRoute(
        builder: (_) => const PermissionScreen(),
      ),
    );
  }
}

/// 🛡️ SSL HANDSHAKE FIX: Global HTTP Overrides to handle "Connection terminated during handshake" errors.
/// This is specifically helpful for Realme devices and older Android versions that might reject valid certificates.
class GlobalHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}
