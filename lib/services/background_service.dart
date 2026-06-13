import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart'; // 🔥 ADDED: For Time Formatting
import 'package:slfm_salesman_app/core/services/secure_http_client.dart'
    as http;
import 'package:image/image.dart' as img;
import 'secure_storage_service.dart';
import 'package:slfm_salesman_app/core/constants/api_urls.dart';
import 'package:slfm_salesman_app/core/database/local_db_helper.dart';
import 'package:slfm_salesman_app/core/utils/network_quality_helper.dart';
import 'package:slfm_salesman_app/firebase_options.dart';

// Flag to prevent overlapping tasks
bool _isProcessing = false;
bool _isServiceStopping = false; // 🔥 NEW: Flag to signal shutdown
Timer? _periodicTimer; // 🔥 NEW: Track timer for disposal
Timer?
    _aggressiveRetryTimer; // 🔥 NEW: Track aggressive retry timer for disposal
StreamSubscription? _stopSubscription; // 🔥 NEW: Track subscriptions
StreamSubscription<DatabaseEvent>?
    _trackingSubscription; // 🔥 Moved to global for cleanup
StreamSubscription<Position>?
    _liveTrackingStream; // 🔥 NEW: Live Tracking stream
StreamSubscription<Position>? _historyTrackingStream; // 🔥 Route History stream
bool _isHistoryRecordingEnabled = false;

Future<void> initializeService() async {
  // 🔥 CRASH FIX: On Android 14+ (SDK 34+), a foreground service with
  // foregroundServiceType="location" REQUIRES location permissions to be granted
  // BEFORE startForeground() is called. If not granted, Android throws
  // ForegroundServiceDidNotStartInTimeException and kills the entire app.
  if (Platform.isAndroid) {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      debugPrint(
          "⚠️ Location permission not granted. Skipping foreground service start.");
      debugPrint(
          "   Service will be started after permissions are granted (splash screen).");
      return;
    }
  }

  final service = FlutterBackgroundService();

  // 🔥 NEW: Don't re-initialize if already running
  if (await service.isRunning()) {
    debugPrint("✅ Background service is already running. Skipping init.");
    return;
  }

  // 🔥 CHANGED CHANNEL ID: Forces Android to reset Importance settings
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'my_foreground_silent_v2', // Changed ID to invalidate old cache
    'SLFM Attendance Service', // Removed Tracking text
    description:
        'This channel is used for Attendance tasks', // Removed location tracking text
    importance: Importance.low, // Silent
    playSound: false, // 🔥 ABSOLUTELY NO SOUND
    enableVibration: false, // 🔥 ABSOLUTELY NO VIBRATION
  );

  // 🔥 NEW: High-priority channel ONLY for Announcements
  const AndroidNotificationChannel announcementChannel =
      AndroidNotificationChannel(
    'announcements_channel_v1',
    'Announcements',
    description: 'Important announcements from the company',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  final androidPlugin =
      flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(channel);
  await androidPlugin?.createNotificationChannel(announcementChannel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart:
          true, // 🔥 CHANGED TO TRUE: Will start on boot (Allowed because we have ignoreBatteryOptimizations)
      isForegroundMode: true,
      notificationChannelId: 'my_foreground_silent_v2', // Must match above
      initialNotificationTitle: 'SLFM App',
      initialNotificationContent: 'Active',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
    ),
  );

  await service.startService();
}

// Helper to update notification safely (Anti-Spam)
void _updateNotification(ServiceInstance service, String title, String content,
    {String? inTime, String? outTime, String? announcement}) async {
  if (service is AndroidServiceInstance) {
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    String displayTitle;
    String displayBody;

    // 🔥 ALWAYS show In/Out times in the Title if available
    if (inTime != null && outTime != null) {
      displayTitle = '🟢 In: $inTime   🔴 Out: $outTime';
    } else {
      displayTitle = 'SLFM Shortcuts';
    }

    // 🔥 If announcement is active, show it in the Body
    if (announcement != null && announcement.isNotEmpty) {
      displayBody = '📢 $announcement';
    } else {
      displayBody = '👆 Tap to add walking customer';
    }

    await flutterLocalNotificationsPlugin.show(
      888, // 🔥 SAME ID as Foreground Service
      displayTitle,
      displayBody,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'my_foreground_silent_v2',
          'SLFM Background Service',
          icon: 'ic_launcher', // 🔥 FIXED: Using ic_launcher as fallback
          ongoing: true,
          autoCancel: false,
          showWhen: true,
          importance: Importance.low,
          priority: Priority.low,
          playSound: false,
          enableVibration: false,
          largeIcon: const DrawableResourceAndroidBitmap('walking_customer'),
        ),
      ),
      payload: 'navigate_walking',
    );

    debugPrint(
        "🔔 Notification Updated: $displayBody (Ann: ${announcement != null})");
  }
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // 🛡️ SECURITY: Disable all debug prints in Background Release Mode
  if (const bool.fromEnvironment('dart.vm.product')) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // Reset shutdown flag for new start
  _isServiceStopping = false;

  // 🔥 NEW: Wrap everything in a zone to suppress print() calls from packages
  runZoned(() async {
    // 🔥 Internal logic starts here

    // 🔥 CRITICAL FIX: On Android 12+ (especially Oppo/Vivo), setAsForegroundService()
    // MUST be called immediately before any asynchronous work (like Firebase init).
    // If not, the system will kill the app with ForegroundServiceDidNotStartInTimeException.
    if (service is AndroidServiceInstance) {
      await service.setAsForegroundService();

      // Bind Notification Immediately with initial info
      service.setForegroundNotificationInfo(
        title: "SLFM Shortcuts",
        content: "walking customer",
      );
    }

    // 🔥 SAFE FIREBASE INIT FOR BACKGROUND ISOLATE (With Retry)
    for (int i = 0; i < 3; i++) {
      if (Firebase.apps.isNotEmpty) {
        break;
      }
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        break;
      } catch (e) {
        debugPrint("Firebase background init attempt ${i + 1} failed: $e");
        if (i < 2) await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    // 🔥 CRITICAL: Enable Firebase RTDB persistence + force online
    // Without this, RTDB listeners may not fire when app is closed
    try {
      FirebaseDatabase.instance.setPersistenceEnabled(true);
      FirebaseDatabase.instance.goOnline();
      debugPrint("✅ Firebase RTDB: Persistence ON + goOnline()");
    } catch (e) {
      debugPrint("Firebase persistence/goOnline warning: $e");
    }

    // 🔥 Initialize notifications in this isolate
    try {
      final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
          FlutterLocalNotificationsPlugin();
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('ic_launcher');
      const InitializationSettings initializationSettings =
          InitializationSettings(android: initializationSettingsAndroid);
      await flutterLocalNotificationsPlugin.initialize(
        initializationSettings,
      );
    } catch (e) {
      debugPrint("Background notification init warning: $e");
    }

    // Mutable variables
    String salesmanId = '';
    bool manualStop = false;
    int lastRequestTimestamp = 0;
    String? currentAnnouncement;

    // --- NEW: ON-DEMAND TRACKING LISTENER ---
    void setupOnDemandTrackingListener(String id) {
      if (id.isEmpty) return;

      try {
        _trackingSubscription?.cancel();
      } catch (e) {
        debugPrint("⚠️ Tracking subscription cancel error: $e");
      }

      // Safety check: ensure firebase is ready
      if (Firebase.apps.isEmpty) {
        debugPrint("❌ Cannot setup listener: Firebase not initialized");
        return;
      }

      final trackingRequestsRef =
          FirebaseDatabase.instance.ref('tracking_requests/$id');

      // 🔥 CRITICAL: Force Firebase to keep this path always synced
      // Without this, Android may deprioritize the listener when app is closed
      trackingRequestsRef.keepSynced(true);

      try {
        _trackingSubscription =
            trackingRequestsRef.onValue.listen((DatabaseEvent event) async {
          if (event.snapshot.value != null) {
            try {
              final data =
                  Map<String, dynamic>.from(event.snapshot.value as Map);
              if (data.containsKey('request_timestamp')) {
                final int currentTimestamp =
                    int.parse(data['request_timestamp'].toString());

                if (currentTimestamp > lastRequestTimestamp) {
                  lastRequestTimestamp = currentTimestamp;

                  // Process requests made in the last 2 minutes
                  final now = DateTime.now().millisecondsSinceEpoch;
                  if (now - currentTimestamp < 120000) {
                    debugPrint("🎯 Ethical On-Demand Tracking Triggered!");
                    if (!manualStop) {
                      await _getCurrentLocationAndSend(id);
                    }
                  }
                }
              }

              // --- NEW: Live Tracking Stream Logic ---
              if (data.containsKey('is_live')) {
                final bool isLive = data['is_live'] == true;
                if (isLive && !manualStop) {
                  if (_liveTrackingStream == null) {
                    debugPrint("📡 STARTING LIVE TRACKING STREAM for $id");

                    // 🔥 Send current location IMMEDIATELY before stream starts
                    await _getCurrentLocationAndSend(id);

                    late LocationSettings locationSettings;
                    if (Platform.isAndroid) {
                      locationSettings = AndroidSettings(
                        accuracy: LocationAccuracy.best,
                        distanceFilter: 2, // Every 2 meters
                        forceLocationManager:
                            true, // Improves background reliability on some OEMs
                        intervalDuration: const Duration(
                            seconds: 10), // Ensures it doesn't freeze
                      );
                    } else if (Platform.isIOS || Platform.isMacOS) {
                      locationSettings = AppleSettings(
                        accuracy: LocationAccuracy.best,
                        activityType: ActivityType.fitness,
                        distanceFilter: 2,
                        pauseLocationUpdatesAutomatically: false,
                        showBackgroundLocationIndicator: true,
                      );
                    } else {
                      locationSettings = const LocationSettings(
                        accuracy: LocationAccuracy.best,
                        distanceFilter: 2,
                      );
                    }

                    _liveTrackingStream = Geolocator.getPositionStream(
                      locationSettings: locationSettings,
                    ).listen((Position position) {
                      if (position.isMocked) return;
                      try {
                        final rtdb =
                            FirebaseDatabase.instance.ref('locations/$id');
                        rtdb.update({
                          'lat': position.latitude,
                          'lng': position.longitude,
                          'updated_at': ServerValue.timestamp,
                          'gps_status': 'LIVE',
                        });
                      } catch (e) {
                        debugPrint("Live tracking update error: $e");
                      }
                    });
                  }
                } else {
                  if (_liveTrackingStream != null) {
                    debugPrint("📡 STOPPING LIVE TRACKING STREAM");
                    _liveTrackingStream?.cancel();
                    _liveTrackingStream = null;
                  }
                }
              }

              // --- NEW: Route History Logic ---
              if (data.containsKey('record_history')) {
                _isHistoryRecordingEnabled = data['record_history'] == true;
                if (_isHistoryRecordingEnabled && !manualStop) {
                  if (_historyTrackingStream == null) {
                    debugPrint("📡 STARTING ROUTE HISTORY STREAM for $id");

                    late LocationSettings historyLocationSettings;
                    if (Platform.isAndroid) {
                      historyLocationSettings = AndroidSettings(
                        accuracy: LocationAccuracy.high,
                        distanceFilter: 30, // Every 30 meters
                        forceLocationManager: true,
                        intervalDuration: const Duration(seconds: 30),
                      );
                    } else if (Platform.isIOS || Platform.isMacOS) {
                      historyLocationSettings = AppleSettings(
                        accuracy: LocationAccuracy.high,
                        activityType: ActivityType.fitness,
                        distanceFilter: 30,
                        pauseLocationUpdatesAutomatically: false,
                      );
                    } else {
                      historyLocationSettings = const LocationSettings(
                        accuracy: LocationAccuracy.high,
                        distanceFilter: 30,
                      );
                    }

                    _historyTrackingStream = Geolocator.getPositionStream(
                      locationSettings: historyLocationSettings,
                    ).listen((Position position) {
                      if (position.isMocked) return;
                      try {
                        LocalDbHelper.instance.insertOfflineLocation(
                          id,
                          position.latitude,
                          position.longitude,
                          position.timestamp.millisecondsSinceEpoch,
                          'ON',
                        );
                      } catch (e) {
                        debugPrint("History tracking SQLite error: $e");
                      }
                    });
                  }
                } else {
                  if (_historyTrackingStream != null) {
                    debugPrint("📡 STOPPING ROUTE HISTORY STREAM");
                    _historyTrackingStream?.cancel();
                    _historyTrackingStream = null;
                  }
                }
              }
            } catch (e) {
              debugPrint("On-Demand Listener Data Error: $e");
            }
          }
        }, onError: (Object error) {
          if (error is FirebaseException && error.code == 'permission-denied') {
            debugPrint(
                "🚫 RTDB Permission Denied for tracking_requests/$id. Check Security Rules.");
          } else {
            debugPrint("Tracking Requests Listener Error: $error");
          }
        });
      } catch (e) {
        debugPrint("❌ Failed to initialize tracking listener: $e");
      }
    }

    if (service is AndroidServiceInstance) {
      service.on('setAsForeground').listen((event) {
        service.setAsForegroundService();
      });

      _stopSubscription = service.on('stopService').listen((event) {
        _isServiceStopping = true;
        try {
          _periodicTimer?.cancel();
          _aggressiveRetryTimer?.cancel();
          _trackingSubscription?.cancel();
          _liveTrackingStream?.cancel();
          _historyTrackingStream?.cancel();
          _stopSubscription?.cancel();
        } catch (e) {
          debugPrint("⚠️ Service cleanup error: $e");
        }
        service.stopSelf();
      });

      // Event listener as a backup/instant trigger
      service.on('updateSalesmanId').listen((event) {
        if (event != null && event['id'] != null) {
          salesmanId = event['id'] as String;
          debugPrint("✅ Service EVENT update: $salesmanId");

          try {
            setupOnDemandTrackingListener(salesmanId);
          } catch (e) {
            debugPrint('Tracking listener setup error: $e');
          }

          // Force update notification to keep it alive
          _updateNotification(service, "SLFM Shortcuts", "Walking customer",
              announcement: currentAnnouncement);
        }
      });

      // 🔥 NEW: Remote Tracking Control Listener
      service.on('setTrackingStatus').listen((event) {
        if (event != null && event['status'] != null) {
          String status = event['status'] as String;
          debugPrint("📡 Remote Command Received: $status");

          if (status == 'red') {
            manualStop = true; // STOP TRACKING
            debugPrint("🛑 TRACKING PAUSED BY ADMIN (RED)");
          } else {
            manualStop = false; // RESUME TRACKING (Green/Yellow)
            debugPrint("🟢 TRACKING ACTIVE (GREEN/YELLOW)");
          }
        }
      });
    }

    // Initial Load
    // Initial Load with Timeout (Prevents hang if KeyStore is locked)
    salesmanId = await SecureStorageService.getSalesmanId().timeout(
          const Duration(seconds: 5),
          onTimeout: () => null,
        ) ??
        '';

    // Force initial update if ID exists
    if (salesmanId.isNotEmpty) {
      setupOnDemandTrackingListener(salesmanId);
    }

    Future<void> performTracking() async {
      // 🔥 CRITICAL FIX: Secure Storage always reads fresh from disk
      try {
        final freshId = await SecureStorageService.getSalesmanId() ?? '';

        // Update local variable if changed on disk
        if (freshId != salesmanId) {
          salesmanId = freshId;
          debugPrint("🔄 Service DISK SYNC update: $salesmanId");
          try {
            setupOnDemandTrackingListener(salesmanId);
          } catch (e) {
            debugPrint('Disk-sync listener error: $e');
          }
        }
      } catch (e) {
        debugPrint("Storage Sync Error: $e");
      }

      // 🛑 ABORT if service is stopping
      if (_isServiceStopping) return;

      // 🔥 FIX 1: Notification Time Source of Truth -> Secure Storage (Written by UI)
      String inTime = '--:--';
      String outTime = '--:--';
      try {
        if (salesmanId.isNotEmpty) {
          final now = DateTime.now();
          final todayDate = DateFormat('yyyy-MM-dd').format(now);

          bool readFromSqlite = true;
          final savedDate = await SecureStorageService.readString(
              'saved_notification_date_$salesmanId');

          if (savedDate == todayDate) {
            // 🔥 PERFECT SYNC: Trust UI's Secure Storage unconditionally for today
            inTime = await SecureStorageService.readString(
                    'saved_in_time_$salesmanId') ??
                '--:--';
            outTime = await SecureStorageService.readString(
                    'saved_out_time_$salesmanId') ??
                '--:--';
            readFromSqlite = false;
          } else {
            // Day rolled over, app UI hasn't opened yet. Reset cache.
            await SecureStorageService.writeString(
                'saved_notification_date_$salesmanId', todayDate);
            await SecureStorageService.writeString(
                'saved_in_time_$salesmanId', '--:--');
            await SecureStorageService.writeString(
                'saved_out_time_$salesmanId', '--:--');
          }

          // Fallback to SQLite ONLY IF Secure Storage wasn't matching today (e.g. background service running but UI closed)
          if (readFromSqlite) {
            final history = await LocalDbHelper.instance
                .getAttendanceHistoryPage(salesmanId, limit: 1);
            if (history.isNotEmpty) {
              final lastRecord = history.first;
              if (lastRecord['date'] == todayDate) {
                String formatTimeStr(String t) {
                  if (t == '--:--' || t.isEmpty || t == 'null') {
                    return '--:--';
                  }
                  if (t.toUpperCase().contains('AM') ||
                      t.toUpperCase().contains('PM')) {
                    return t;
                  }
                  try {
                    final parts = t.split(':');
                    if (parts.length >= 2) {
                      final dt = DateTime(
                          2020, 1, 1, int.parse(parts[0]), int.parse(parts[1]));
                      return DateFormat('hh:mm a').format(dt);
                    }
                  } catch (_) {}
                  return t;
                }

                String rawIn = (lastRecord['clock_in_time'] ??
                        lastRecord['clock_in'] ??
                        '')
                    .toString();
                String rawOut = (lastRecord['clock_out_time'] ??
                        lastRecord['clock_out'] ??
                        '')
                    .toString();

                if (rawIn.isNotEmpty) inTime = formatTimeStr(rawIn);
                if (rawOut.isNotEmpty) outTime = formatTimeStr(rawOut);

                if (inTime == '--:--') {
                  String status =
                      (lastRecord['status']?.toString() ?? '').toLowerCase();
                  if (status == 'absent') {
                    inTime = 'Absent';
                  } else if (status.contains('leave')) {
                    inTime = 'Leave';
                  } else if (status.contains('holiday')) {
                    inTime = 'Holiday';
                  }
                }
              }
            }

            if (inTime == '--:--') {
              try {
                final leaveHistory =
                    await LocalDbHelper.instance.getLeaveHistory(salesmanId);
                for (var leave in leaveHistory) {
                  if (leave['leave_date'] == todayDate &&
                      leave['status']?.toString().toLowerCase() == 'approved') {
                    inTime = 'Leave';
                    break;
                  }
                }
              } catch (_) {}
            }
          }
        }
      } catch (e) {
        debugPrint("SQLite notification time check error: $e");
      }

      // Stop if no user logged in (Empty ID = Logout state)
      if (salesmanId.isEmpty) {
        // Ensure notification is generic even if logged out
        _updateNotification(service, "SLFM App", "Active",
            announcement: currentAnnouncement);
        return;
      }

      // 🔥 Always update notification to show the latest In/Out times
      _updateNotification(
        service,
        "SLFM Shortcuts",
        "👆 Tap to add walking customer",
        inTime: inTime,
        outTime: outTime,
        announcement: currentAnnouncement, // 🔥 Pass announcement state
      );

      // 🔥 CHECK REMOTE STOP
      if (manualStop) {
        // Just update notification to show running, but DO NOT track
        // Or keeping silent is better.
        // User asked "naa on/off pannala nu soldrathu".
        // So we keep the service running, but we SKIP the location update call.
        return;
      }

      // Avoid running if previous task is still running
      if (_isProcessing) return;
      _isProcessing = true;

      try {
        // 🔥 UPDATE ONLINE PRESENCE (Every 3-5 mins)
        try {
          if (Firebase.apps.isNotEmpty && salesmanId.isNotEmpty) {
            final trackingRtdb =
                FirebaseDatabase.instance.ref('tracking_status/$salesmanId');
            await trackingRtdb.update({
              'is_online': true,
              'last_online': ServerValue.timestamp,
            }).catchError((e) {
              if (e is FirebaseException && e.code == 'permission-denied') {
                debugPrint("🚫 RTDB Presence Permission Denied");
              } else {
                debugPrint("RTDB Update Error: $e");
              }
            });
            // 🔥 Ensure onDisconnect is always registered
            await trackingRtdb.onDisconnect().update({
              'is_online': false,
              'last_online': ServerValue.timestamp,
            }).catchError((e) => debugPrint("OnDisconnect Error: $e"));
            debugPrint("⏱️ Online presence updated in RTDB for $salesmanId");
          }
        } catch (e) {
          debugPrint("Presence Update Block Error: $e");
        }

        // 🔥 PERIODIC LOCATION PUSH TO RTDB (Every cycle — keeps admin tracking fresh)
        try {
          await _getCurrentLocationAndSend(salesmanId).timeout(
            const Duration(seconds: 45),
            onTimeout: () => debugPrint("⏳ Location sync timed out"),
          );
        } catch (e) {
          debugPrint("Periodic Location Push Error: $e");
        }

        if (service is AndroidServiceInstance) {
          if (await service.isForegroundService()) {
            // 🔥 CRITICAL FIX: Only sync if we have a real internet connection
            final hasInternet = await NetworkQualityHelper.hasRealInternet();
            if (hasInternet) {
              // 🔥 NEW: Sync offline attendance & messages queue
              await _syncOfflineAttendance(salesmanId).timeout(
                const Duration(minutes: 2),
                onTimeout: () => debugPrint("⏳ Attendance sync timed out"),
              );
              await _syncOfflineMessages(salesmanId).timeout(
                const Duration(minutes: 1),
                onTimeout: () => debugPrint("⏳ Messages sync timed out"),
              );
              // 🔥 NEW: Reconcile leave data with server (handles deletions)
              await _syncLeaveRequests(salesmanId).timeout(
                const Duration(seconds: 45), // 🔥 Reduced from 1m
                onTimeout: () => debugPrint("⏳ Leave sync timed out"),
              );
              await _syncOfflineLocationHistory(salesmanId).timeout(
                const Duration(seconds: 45),
                onTimeout: () =>
                    debugPrint("⏳ Location History sync timed out"),
              );
            } else {
              debugPrint(
                  "🚫 Offline or poor network. Skipping background data sync loops.");
            }
          }
        }
      } catch (e) {
        debugPrint("Service Loop Error: $e");
      } finally {
        // ✅ Release lock
        _isProcessing = false;
      }
    }

    // Helper to run performTracking with stop-check
    Future<void> safePerformTracking() async {
      if (_isServiceStopping) return;
      await performTracking();
    }

    // 🔥 DIRECT TIME UPDATE: Times come straight from UI — no disk read
    service.on('update_notification_times').listen((event) {
      if (event != null) {
        final String inTime = event['in_time'] as String? ?? '--:--';
        final String outTime = event['out_time'] as String? ?? '--:--';
        debugPrint("🔔 Direct time update: In=$inTime Out=$outTime");
        _updateNotification(
          service,
          "SLFM Shortcuts",
          "👆 Tap to add walking customer",
          inTime: inTime,
          outTime: outTime,
          announcement:
              currentAnnouncement, // 🔥 Ensure announcement persistent
        );
      }
    });

    // 🔥 NEW: Announcement Display Control
    service.on('show_announcement_in_bg').listen((event) async {
      if (event != null && event['message'] != null) {
        currentAnnouncement = event['message'] as String;
        debugPrint("📢 Background Notification: Showing Announcement Overlay");

        // 🔥 Trigger ONE-TIME Heads-up Notification with Sound & Vibration
        final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
            FlutterLocalNotificationsPlugin();
        await flutterLocalNotificationsPlugin.show(
          999, // Separate ID so it doesn't mess with foreground sticky notification
          'Company Announcement',
          currentAnnouncement,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'announcements_channel_v1',
              'Announcements',
              importance: Importance.high,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
              icon: 'ic_launcher',
            ),
          ),
        );

        performTracking(); // Refresh UI immediately (Silent persistent notification)
      }
    });

    service.on('hide_announcement_in_bg').listen((event) {
      currentAnnouncement = null;
      debugPrint("📢 Background Notification: Restoring In/Out Times");
      performTracking(); // Refresh UI immediately
    });

    void startAggressiveRetryTimer() {
      if (_aggressiveRetryTimer != null && _aggressiveRetryTimer!.isActive) return;
      
      debugPrint("⚡ Starting Aggressive Retry Timer...");
      _aggressiveRetryTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
        if (_isServiceStopping || _isProcessing) return;
        if (salesmanId.isEmpty) return;

        try {
          final pendingRecords = await LocalDbHelper.instance.getPendingAttendance(salesmanId);
          if (pendingRecords.isEmpty) {
            timer.cancel(); // Nothing pending — no need to keep running
            return;
          }

          final now = DateTime.now();
          final anyWithinWindow = pendingRecords.any((r) {
            try {
              final t = DateTime.parse(r['capture_time'].toString());
              return now.difference(t).inMinutes < 5;
            } catch (_) {
              return false;
            }
          });

          if (!anyWithinWindow) {
            // All records are past the 5-minute window — stop background retry
            timer.cancel();
            debugPrint("⏹️ Aggressive retry stopped: all pending records past 5-min window.");
            return;
          }

          // Attempt immediate sync if internet is available
          final hasInternet = await NetworkQualityHelper.hasRealInternet();
          if (hasInternet) {
            debugPrint("⚡ Aggressive retry: Syncing ${pendingRecords.length} pending records...");
            await _syncOfflineAttendance(salesmanId).timeout(
              const Duration(minutes: 1),
              onTimeout: () => debugPrint("⏳ Aggressive attendance sync timed out"),
            );
          }
        } catch (e) {
          debugPrint("Aggressive attendance retry error: $e");
        }
      });
    }

    // 🔥 Global Force Sync Listener (reads from disk for periodic updates)
    service.on('force_sync').listen((event) {
      debugPrint("⚡ FORCE SYNC TRIGGERED (Touch/Resume)");
      performTracking(); // Run immediately
      startAggressiveRetryTimer();
    });

    // 🔥 CORE LOOP: Check every 5 minutes
    _periodicTimer =
        Timer.periodic(const Duration(seconds: 300), (timer) async {
      await safePerformTracking();
    });

    // 🔥 AGGRESSIVE SILENT RETRY: Check every 30 seconds for pending attendance/lunch.
    // Syncs immediately when online without showing any notification alerts.
    startAggressiveRetryTimer();

    // 🔥 SEPARATE GPS LISTENER
    // We keep this separate because it is a stream, not a loop.
    // We just need to check salesmanId inside it.
    Geolocator.getServiceStatusStream().listen((ServiceStatus status) {
      if (salesmanId.isEmpty) return;

      if (status == ServiceStatus.disabled) {
        _sendGpsAlert(salesmanId, "OFF");
        _updateNotification(
            service, "⚠️ Check Location", "Location required for attendance",
            announcement: currentAnnouncement);

        // Log Location OFF event to history
        if (_isHistoryRecordingEnabled) {
          LocalDbHelper.instance.insertOfflineLocation(salesmanId, 0.0, 0.0,
              DateTime.now().millisecondsSinceEpoch, 'OFF');
        }
      } else if (status == ServiceStatus.enabled) {
        _sendGpsAlert(salesmanId, "ON");
        _updateNotification(service, "SLFM App", "Active",
            announcement: currentAnnouncement);

        // Log Location ON event to history
        if (_isHistoryRecordingEnabled) {
          LocalDbHelper.instance.insertOfflineLocation(salesmanId, 0.0, 0.0,
              DateTime.now().millisecondsSinceEpoch, 'ON');
        }
      }
    }, onError: (Object error) {
      debugPrint("Geolocator Stream Error: $error");
    });
    // 🔥 CRITICAL: Periodically re-assert Firebase connection
    // Some OEMs (Oppo/Vivo/Xiaomi) may drop WebSocket after 10+ minutes
    Timer.periodic(const Duration(minutes: 2), (_) {
      if (_isServiceStopping) return;
      try {
        FirebaseDatabase.instance.goOnline();
      } catch (e) {
        debugPrint("Firebase goOnline refresh error: $e");
      }
    });
  }, zoneSpecification: ZoneSpecification(
    print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
      if (const bool.fromEnvironment('dart.vm.product')) {
        return;
      }
      parent.print(zone, line);
    },
  ));
}

// --- HELPER 1: Send GPS Alert (Direct RTDB — Zero Cloud Function Cost) ---
Future<void> _sendGpsAlert(String id, String status) async {
  try {
    if (Firebase.apps.isEmpty) return;

    final rtdb = FirebaseDatabase.instance.ref('locations/$id');
    await rtdb
        .update({
          'gps_status': status,
          'updated_at': ServerValue.timestamp,
        })
        .timeout(const Duration(seconds: 10))
        .catchError((e) {
          if (e is FirebaseException && e.code == 'permission-denied') {
            debugPrint("🚫 GPS Alert Permission Denied");
          }
        });
  } catch (e) {
    debugPrint("GPS Alert Error: $e");
  }
}

// --- HELPER 2: (Removed checkServerStatus) ---

// --- HELPER 3: Get & Send Location (🔥 DIRECT RTDB — Zero Cloud Function Cost) ---
Future<void> _getCurrentLocationAndSend(String id) async {
  try {
    // 🛑 CRITICAL FIX: Avoid crash if GPS is off
    bool isEnabled = await Geolocator.isLocationServiceEnabled();
    if (!isEnabled) {
      debugPrint(
          "GPS Service is DISABLED. Updating RTDB and skipping request.");
      await _sendGpsAlert(id, "OFF");
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      return;
    }

    Position? position;

    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } catch (e) {
      debugPrint("GPS Timeout/Error ($e), checking cached location.");
      try {
        Position? lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          final age = DateTime.now().difference(lastKnown.timestamp);
          if (age.inMinutes <= 5) {
            position = lastKnown;
          }
        }
      } catch (innerE) {
        debugPrint("Background LastKnownPosition error: $innerE");
      }
    }

    if (position == null ||
        (position.latitude == 0 && position.longitude == 0)) {
      return;
    }

    // 🚨 ANTI-SPOOFING: Reject Fake GPS
    if (position.isMocked) {
      debugPrint(
          "🚨 FAKE GPS DETECTED in Background Service! Ignoring location update.");
      return;
    }

    // 🔥 DIRECT RTDB WRITE — No Cloud Function, No Firestore Write
    if (Firebase.apps.isEmpty) return;

    final rtdb = FirebaseDatabase.instance.ref('locations/$id');
    await rtdb
        .set({
          'lat': position.latitude,
          'lng': position.longitude,
          'updated_at': ServerValue.timestamp,
          'gps_status': 'ON',
        })
        .timeout(const Duration(seconds: 20))
        .catchError((e) {
          if (e is FirebaseException && e.code == 'permission-denied') {
            debugPrint("🚫 Location Set Permission Denied");
          }
        });

    // Log successful location to history if enabled
    if (_isHistoryRecordingEnabled) {
      await LocalDbHelper.instance.insertOfflineLocation(id, position.latitude,
          position.longitude, DateTime.now().millisecondsSinceEpoch, 'ON');
    }
  } catch (e) {
    debugPrint("Location RTDB Error: $e");
  }
}

// --- HELPER 4: Sync Offline Location History ---
Future<void> _syncOfflineLocationHistory(String salesmanId) async {
  try {
    final pendingLocations =
        await LocalDbHelper.instance.getPendingLocations(salesmanId);
    if (pendingLocations.isEmpty) return;

    if (Firebase.apps.isEmpty) return;

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
        });
        syncedIds.add(loc['id']);
      }
    }

    // Delete synced ones from local
    if (syncedIds.isNotEmpty) {
      await LocalDbHelper.instance.deletePendingLocations(syncedIds);
      debugPrint(
          "✅ Synced ${syncedIds.length} offline location history points.");
    }
  } catch (e) {
    debugPrint("Offline Location Sync Error: $e");
  }
}

// --- Background Task Loops ---Offline Attendance ---
Future<void> _syncOfflineAttendance(String salesmanId) async {
  try {
    final pendingRecords =
        await LocalDbHelper.instance.getPendingAttendance(salesmanId);
    if (pendingRecords.isEmpty) return;

    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    for (var record in pendingRecords) {
      // 🛑 STOP IMMEDIATELY if service is shutting down
      if (_isServiceStopping) {
        debugPrint("🛑 BG Sync: Service stopping, breaking loop.");
        break;
      }

      try {
        // 🔥 TIME LIMIT CHECK: Only sync records from today's date AND within 5 minutes
        final captureTime = record['capture_time']?.toString() ?? '';
        if (captureTime.isNotEmpty) {
          try {
            // Validate it's a valid date string
            final recordTime = DateTime.parse(captureTime);

            // 1. Same-day check
            final captureDate = captureTime.substring(0, 10);
            if (captureDate != todayStr) {
              debugPrint(
                  "⏭️ BG Sync: Skipping record ${record['local_id']} — capture_date $captureDate != today $todayStr");
              continue;
            }

            // 2. 5-minute window check: Stop background retry if older than 5 minutes
            if (now.difference(recordTime).inMinutes >= 5) {
              final db = await LocalDbHelper.instance.database;
              // Only update if still 'pending' — don't overwrite 'failed' or 'duplicate'
              final currentStatus = record['status']?.toString() ?? '';
              if (currentStatus == 'pending') {
                await db.update(
                  'pending_attendance',
                  {'status': 'retry_needed'},
                  where: 'local_id = ?',
                  whereArgs: [record['local_id']],
                );
                debugPrint(
                    "⏹️ BG Sync: Record ${record['local_id']} — auto-retry window expired. Marked 'retry_needed'.");
              }
              continue;
            }
          } catch (e) {
            debugPrint("⚠️ Could not parse capture_time: $captureTime, $e");
          }
        }

        final uri =
            (record['action'] == 'lunch_in' || record['action'] == 'lunch_out')
                ? Uri.parse(ApiUrl.lunch)
                : Uri.parse(ApiUrl.attendance);
        String base64Image = "";

        if (record['image_path'] != null) {
          final imagePath = record['image_path'] as String;
          final file = File(imagePath);
          if (await file.exists()) {
            final originalBytes = await file.readAsBytes();
            List<int> compressedBytes = originalBytes;

            try {
              final image = img.decodeImage(originalBytes);
              if (image != null) {
                img.Image resized = image;
                if (image.width > 800) {
                  final targetH = (image.height * (800 / image.width)).round();
                  resized = img.copyResize(image, width: 800, height: targetH);
                }
                compressedBytes = img.encodeJpg(resized, quality: 70);
              }
            } catch (compressErr) {
              debugPrint("⚠️ Compression failed, using original: $compressErr");
            }

            base64Image = base64Encode(compressedBytes);
          }
        }

        final Map<String, dynamic> payload = {
          'attendance_uid': record['attendance_uid']?.toString() ?? '',
          'action': record['action']?.toString() ?? '',
          'salesman_id': salesmanId,
          'lat': record['latitude']?.toString() ?? '',
          'lng': record['longitude']?.toString() ?? '',
          'latitude': record['latitude']?.toString() ?? '',
          'longitude': record['longitude']?.toString() ?? '',
          'capture_time': record['capture_time']?.toString() ?? '',
          'timestamp': record['capture_time']?.toString() ?? '',
          'created_at': record['capture_time']?.toString() ?? '',
          'image_base64': base64Image,
          'selfie_url': base64Image,
        };

        var response = await http.postWithRetry(
          uri,
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(payload),
          baseTimeoutSeconds: 30,
        );

        if (response.statusCode == 200) {
          final result = jsonDecode(response.body);
          bool isSuccess = result['status'] == 'success';
          bool isAlreadyDone = result['status'] == 'error' &&
              result['message'].toString().toLowerCase().contains('already') &&
              !result['message']
                  .toString()
                  .contains('ஏற்கனவே பதிவு செய்துவிட்டீர்கள்');
          bool isDuplicate = result['status'] == 'duplicate';

          if (isSuccess) {
            await LocalDbHelper.instance
                .deletePendingAttendance(record['local_id']);
          } else if (isAlreadyDone || isDuplicate) {
            await LocalDbHelper.instance.database.then((db) {
              db.update('pending_attendance', {'status': 'duplicate'},
                  where: 'local_id = ?', whereArgs: [record['local_id']]);
            });
          } else {
            await LocalDbHelper.instance.database.then((db) {
              db.update('pending_attendance', {'status': 'failed'},
                  where: 'local_id = ?', whereArgs: [record['local_id']]);
            });
          }
        }
      } catch (e) {
        // 🔥 FIX: Handle per-record errors without stopping the entire sync
        debugPrint("Sync Error for record ${record['local_id']}: $e");
      }
    }
  } catch (e) {
    debugPrint("Offline Sync Error: $e");
  }
}

// --- HELPER 5: Sync Offline Messages & Leaves ---
Future<void> _syncOfflineMessages(String salesmanId) async {
  try {
    final pendingMessages =
        await LocalDbHelper.instance.getMessages(salesmanId);
    final toSync =
        pendingMessages.where((m) => m['status'] == 'pending_upload').toList();
    if (toSync.isEmpty) return;

    for (var msg in toSync) {
      // 🛑 STOP IMMEDIATELY if service is shutting down
      if (_isServiceStopping) break;

      if (msg['message_type'] == 'leave_request' && msg['payload'] != null) {
        // --- 1. SYNC OFFLINE LEAVE REQUESTS ---
        final response = await http.post(
          Uri.parse(ApiUrl.leave),
          body: msg['payload'], // The full JSON payload we saved
          headers: {"Content-Type": "application/json"},
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final result = jsonDecode(response.body);
          if (result['status'] == 'success') {
            // Delete from local queue; native _leaveHistory will handle it
            await LocalDbHelper.instance.database.then((db) => db.delete(
                'local_messages',
                where: 'local_id = ?',
                whereArgs: [msg['local_id']]));
          }
        }
      } else {
        // --- 2. SYNC NORMAL CHAT MESSAGES ---
        final String messagesUrl = ApiUrl.messages;
        final response = await http
            .post(
              Uri.parse(messagesUrl),
              body: jsonEncode({
                "action": "send_message",
                "salesman_id": salesmanId,
                "message_text": msg['message_text'],
                "message_type": msg['message_type'] ?? 'user',
                "created_at": msg['timestamp'],
              }),
            )
            .timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final result = jsonDecode(response.body);
          if (result['status'] == 'success') {
            await LocalDbHelper.instance.updateMessageSent(msg['local_id'],
                int.tryParse(result['id']?.toString() ?? '0') ?? 0);
          }
        }
      }
    }
  } catch (e) {
    debugPrint("Message Sync Error: $e");
  }
}

// --- HELPER 6: Sync Leave Requests (Background Reconciliation) ---
// Fetches leave data from server and reconciles local SQLite (leave_history + local_messages)
Future<void> _syncLeaveRequests(String salesmanId) async {
  try {
    final response = await http.post(
      Uri.parse(ApiUrl.leave),
      body: jsonEncode({
        "action": "get_history",
        "salesman_id": salesmanId,
      }),
      headers: {"Content-Type": "application/json"},
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode == 200 && response.body.isNotEmpty) {
      final responseData = jsonDecode(response.body);
      if (responseData['status'] == 'success' && responseData['data'] != null) {
        final List<dynamic> serverLeaves = responseData['data'];

        // Collect server doc IDs for reconciliation
        final List<String> serverDocIds = serverLeaves
            .map((item) => item['id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toList();

        // Sync leave_history table (full clear+insert)
        final List<Map<String, dynamic>> serverLeaveForHistory =
            serverLeaves.map((item) {
          return <String, dynamic>{
            'id': item['id']?.toString() ?? '',
            'salesman_id': salesmanId,
            'leave_date': item['leave_date']?.toString() ?? '',
            'leave_type': item['leave_type']?.toString() ?? 'Unknown',
            'reason': item['reason']?.toString() ?? '',
            'status': item['status']?.toString() ?? 'Pending',
            'created_at': item['created_at']?.toString() ?? '',
            'updated_at': item['updated_at']?.toString() ?? '',
          };
        }).toList();

        await LocalDbHelper.instance
            .clearAndInsertLeaveHistory(salesmanId, serverLeaveForHistory);

        // Reconcile deletions (leave_history + local_messages)
        final deletedCount = await LocalDbHelper.instance
            .reconcileLeaveHistory(salesmanId, serverDocIds);
        final cleanedCount = await LocalDbHelper.instance
            .reconcileLeaveMessages(salesmanId, serverDocIds);

        if (deletedCount > 0 || cleanedCount > 0) {
          debugPrint(
              "🔄 BG Sync: Reconciled $deletedCount leave records, $cleanedCount orphaned messages");
        }

        // 🔥 Purge old leave data beyond 2-month window
        await LocalDbHelper.instance.purgeOldLeaveData(salesmanId);
      }
    }
  } catch (e) {
    debugPrint("BG Leave Sync Error: $e");
  }
}
