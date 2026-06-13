import 'dart:async';
import 'dart:convert';
import 'dart:io';
// 🔥 NEW: For Uint8List
import 'package:flutter/foundation.dart'; // For ValueListenable
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image/image.dart' as img; // 🔥 NEW: For compression
import 'package:slfm_salesman_app/core/services/secure_http_client.dart'
    as http;
import '../app_export.dart';
import '../utils/device_utils.dart';
import 'package:slfm_salesman_app/core/database/local_db_helper.dart';
import '../../services/secure_storage_service.dart';
import '../utils/sync_event_bus.dart';

class OfflineSyncService {
  static const String _boxName = 'attendance_queue';
  final String _apiUrl = ApiUrl.attendance;

  // Singleton pattern
  static final OfflineSyncService _instance = OfflineSyncService._internal();
  factory OfflineSyncService() => _instance;
  OfflineSyncService._internal();

  Box? _box;
  StreamSubscription? _connectivitySubscription;
  Future<void>? _syncFuture;

  /// Initialize Hive and the Sync Service
  Future<void> init() async {
    // Hive.initFlutter() is usually called in main.dart, but we ensure box is open here
    if (!Hive.isBoxOpen(_boxName)) {
      try {
        final encryptionKey = await SecureStorageService.getHiveEncryptionKey();
        _box = await Hive.openBox(
          _boxName,
          encryptionCipher: HiveAesCipher(encryptionKey),
        );
      } catch (e) {
        debugPrint("🚨 Error opening encrypted Hive box: $e. Recreating...");
        await Hive.deleteBoxFromDisk(_boxName);
        final encryptionKey = await SecureStorageService.getHiveEncryptionKey();
        _box = await Hive.openBox(
          _boxName,
          encryptionCipher: HiveAesCipher(encryptionKey),
        );
      }
    } else {
      _box = Hive.box(_boxName);
    }

    // Start listening to connectivity changes
    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      if (!results.contains(ConnectivityResult.none)) {
        syncPendingData();
      }
    }, onError: (e) {
      debugPrint("Connectivity Stream Error: $e");
    });

    // Initial check on app start
    _checkAndSync();
  }

  Future<void> _checkAndSync() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (!connectivityResult.contains(ConnectivityResult.none)) {
      syncPendingData();
    }
  }

  /// Stop listening (e.g., on app dispose)
  void dispose() {
    _connectivitySubscription?.cancel();
  }

  /// Get pending count for UI badge
  int get pendingCount => _box?.length ?? 0;

  /// Listen to queue changes for UI updates
  ValueListenable<Box>? get queueListenable => _box?.listenable();

  /// 1. Main Entry Point: Mark Attendance (Online or Offline)
  /// Returns a status message to display to the user.
  Future<Map<String, dynamic>> markAttendance({
    required String action,
    required String salesmanId,
    required double lat,
    required double lng,
    String? imagePath,
  }) async {
    final now = DateTime.now();
    final String sqlTimestamp =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";

    final Map<String, dynamic> data = {
      "action": action,
      "salesman_id": salesmanId,
      "lat": lat.toString(),
      "lng": lng.toString(),
      "timestamp": sqlTimestamp, // SQL Format (IST)
      "image_path": imagePath, // Store path locally
    };

    // 📱 FETCH DEVICE INFO (Integrity Check)
    try {
      final deviceInfo = await DeviceUtils.getDeviceDetails();
      data['device_id'] = deviceInfo['device_id'] ?? '';
      data['device_model'] = deviceInfo['device_model'] ?? '';
    } catch (e) {
      debugPrint("Device Info Error: $e");
    }

    // Check Connectivity
    final connectivityResult = await Connectivity().checkConnectivity();
    bool isOnline = !connectivityResult.contains(ConnectivityResult.none);

    if (isOnline) {
      // PROPOSE: Try uploading immediately
      try {
        bool success = await _uploadData(data);
        if (success) {
          return {
            "success": true,
            "message": "Attendance Marked Successfully (Online)"
          };
        } else {
          // 🔥 FIX: We already showed the error in _uploadData (if it was a logical error)
          // Only fallback to offline if it was a network timeout/failure.
          // For now, let's assume if it reached here and failed, we don't auto-queue 
          // logical rejections to avoid infinite error loops.
          return {
            "success": false,
            "message": "Submission Failed. Please check your status."
          };
        }
      } catch (e) {
        // Network error during call
        await _saveToHive(data);
        return {
          "success": true,
          "message": "Network Issue. Saved Offline & will retry."
        };
      }
    } else {
      // OFFLINE: Save directly
      await _saveToHive(data);
      return {
        "success": true,
        "message": "No Internet. Saved to Queue (Will upload auto)."
      };
    }
  }

  /// Helper: Save data to Hive
  Future<void> _saveToHive(Map<String, dynamic> data) async {
    if (_box == null) await init();
    await _box!.add(data);
    debugPrint("Saved to Hive: ${data['action']} at ${data['timestamp']}");
  }

  // Helper to determine URL based on data type
  String _getEndpoint(String? type) {
    if (type == 'walking') {
      return ApiUrl.walkingCustomer; // 🔥 Firebase Cloud Function
    }
    return _apiUrl; // Default to attendance
  }

  /// Helper: Upload Single Record
  Future<bool> _uploadData(Map<String, dynamic> dataMap) async {
    try {
      Map<String, dynamic> bodyData = Map.from(dataMap);
      String endpoint = _getEndpoint(bodyData['sync_type']);

      bodyData.remove('sync_type');

      if (bodyData['image_path'] != null && bodyData['image_path'].isNotEmpty) {
        // 🔥 FIX 7: Compress image before encoding (KB vs MB)
        String? base64img = _convertImageToBase64(bodyData['image_path']);
        if (base64img != null) {
          if (endpoint.contains('walking')) {
            bodyData['bill_image'] = base64img;
          } else {
            bodyData['selfie_url'] = base64img;
          }
        }
        bodyData.remove('image_path');
      }

      if (bodyData.containsKey('timestamp')) {
        bodyData['created_at'] = bodyData['timestamp'];
      }

      debugPrint("🚀 Syncing to $endpoint: ${bodyData['action']}");

      // 🔥 FIX 6: Use postWithRetry for better resilience on 2G/3G
      final response = await http.postWithRetry(
        Uri.parse(endpoint),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(bodyData),
        baseTimeoutSeconds: 30, // Higher base for sync
        maxRetries: 2,
      );

      if (response.statusCode == 200) {
        final respData = jsonDecode(response.body);
        if (respData['status'] == 'success') {
          return true;
        } else {
          debugPrint("❌ Server Error: ${respData['message']}");
        }
      }
      return false;
    } catch (e) {
      debugPrint("Upload Failed: $e");
      return false;
    }
  }

  // --- NEW: WALKING CUSTOMER METHODS ---
  Future<void> saveWalkingCustomer(Map<String, dynamic> customerData) async {
    customerData['sync_type'] = 'walking';
    customerData['timestamp'] = DateTime.now().toIso8601String();
    await _saveToHive(customerData);
    syncPendingData();
  }

  Future<void> uploadWalkingBill(String id, String imagePath) async {
    final data = {
      "action": "upload_bill",
      "id": id,
      "image_path": imagePath,
      "sync_type": "walking",
      "timestamp": DateTime.now().toIso8601String(),
    };
    await _saveToHive(data);
    syncPendingData();
  }

  List<Map<String, dynamic>> getPendingWalkingCustomers() {
    if (_box == null || _box!.isEmpty) return [];

    List<Map<String, dynamic>> localItems = [];
    for (var key in _box!.keys) {
      final item = _box!.get(key);
      if (item != null) {
        final Map<String, dynamic> data = Map<String, dynamic>.from(item);
        if (data['sync_type'] == 'walking' &&
            (data['action'] == 'add_walking' ||
                data['action'] == 'update_walking')) {
          localItems.add({
            "id": data['id'] ?? "local_$key",
            "customer_name": data['customer_name'] ?? "Unknown",
            "phone": data['phone'] ?? "",
            "product_interest": data['product_interest'] ?? "",
            "status": "Pending (Offline)",
            "created_date_fmt": "Waiting to Sync...",
            "salesman_id": data['salesman_id'],
            "is_local": true,
          });
        }
      }
    }
    return localItems.reversed.toList();
  }

  String? _convertImageToBase64(String? imagePath) {
    if (imagePath == null) return null;
    try {
      final File file = File(imagePath);
      if (!file.existsSync()) return null;

      final Uint8List originalBytes = file.readAsBytesSync();
      
      // Attempt Image Compression (Targeting ~100KB for slow networks)
      try {
        final img.Image? image = img.decodeImage(originalBytes);
        if (image != null) {
          // Maintaining Aspect Ratio (Max Width 600px)
          int targetWidth = 600;
          img.Image resized = image;
          
          if (image.width > targetWidth) {
            int targetHeight = (image.height * (targetWidth / image.width)).round();
            resized = img.copyResize(image, width: targetWidth, height: targetHeight, interpolation: img.Interpolation.linear);
          }
          
          // Encode to JPG with 80% Quality
          final List<int> compressedBytes = img.encodeJpg(resized, quality: 80);
          debugPrint("📸 Sync Compression: ${originalBytes.length ~/ 1024}KB -> ${compressedBytes.length ~/ 1024}KB");
          return base64Encode(compressedBytes);
        }
      } catch (e) {
        debugPrint("Image Compression Failed, using original: $e");
      }
      
      return base64Encode(originalBytes);
    } catch (e) {
      debugPrint("Image Load Error: $e");
      return null;
    }
  }

  // 🔥 CRITICAL FIX: Offline Sync also uses JSON POST to match PHP backend
  Future<bool> _syncPendingAttendance() async {
    bool didUpdate = false;
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) return false;

    final db = await LocalDbHelper.instance.database;
    // 🔥 FIX: Also retry 'failed' records — these are offline clock-outs that
    // failed the initial upload attempt and must be retried when internet returns.
    final pendingRecords = await db.query('pending_attendance',
        where: "status IN ('pending', 'failed', 'retry_needed')",
        orderBy: 'capture_time ASC');

    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    for (var record in pendingRecords) {
      try {
        // 🔥 SAME-DAY CHECK: Only sync records from today's date
        final captureTime = record['capture_time']?.toString() ?? '';
        if (captureTime.isNotEmpty) {
          final captureDate = captureTime.substring(0, 10); // YYYY-MM-DD
          if (captureDate != todayStr) {
            debugPrint(
                "⏭️ OfflineSync: Skipping record ${record['local_id']} — capture_date $captureDate != today $todayStr");
            continue;
          }

          // 🔥 5-MINUTE AUTO-SYNC CHECK: Stop auto-retrying if older than 5 minutes
          try {
            final recordTime = DateTime.parse(captureTime);
            if (now.difference(recordTime).inMinutes >= 5) {
              debugPrint(
                  "⏭️ OfflineSync: Skipping record ${record['local_id']} — older than 5 mins. Auto-retry stopped.");
              final currentStatus = record['status']?.toString() ?? '';
              if (currentStatus != 'retry_needed') {
                await db.update('pending_attendance', {'status': 'retry_needed'},
                    where: 'local_id = ?', whereArgs: [record['local_id']]);
              }
              continue;
            }
          } catch (e) {
            debugPrint("⚠️ OfflineSync: Could not parse capture_time: $captureTime, $e");
          }
        }

        final uri = Uri.parse(ApiUrl.attendance);

        // Convert Offline Image to Base64 (with compression)
        String base64Image = "";
        final imagePath = record['image_path']?.toString();
        File imageFile = File(imagePath ?? '');
        if (imagePath != null && imagePath.isNotEmpty && await imageFile.exists()) {
          // 🔥 Reuse compression helper — same 600px/80% as Hive sync
          base64Image = _convertImageToBase64(imagePath) ?? "";
        }

        // Create exactly the same JSON payload format
        final Map<String, dynamic> payload = {
          'attendance_uid': record['attendance_uid'].toString(),
          'action': record['action'].toString(),
          'salesman_id': record['salesman_id'].toString(),
          'lat': record['latitude'].toString(),
          'lng': record['longitude'].toString(),
          'capture_time': record['capture_time'].toString(),
          'timestamp': record['capture_time'].toString(),
          'created_at': record['capture_time'].toString(),
          'selfie_url': base64Image, // Matched with PHP!
        };

        var response = await http
            .postWithRetry(
              uri,
              headers: {"Content-Type": "application/json"},
              body: jsonEncode(payload),
              baseTimeoutSeconds: 30, // Higher timeout for sync
            );

        if (response.statusCode == 200) {
          final result = jsonDecode(response.body);
          // 🔥 FIX: Only delete on SUCCESS or DUPLICATE — NOT on generic 'error'.
          // An 'error' could be a transient server issue; deleting would lose the record permanently.
          if (result['status'] == 'success') {
            await db.delete('pending_attendance',
                where: 'local_id = ?', whereArgs: [record['local_id']]);
            debugPrint(
                "✅ OfflineSync: Record ${record['local_id']} synced & removed (${result['status']}).");
            didUpdate = true;
          } else if (result['status'] == 'duplicate') {
            await db.update('pending_attendance', {'status': 'duplicate'},
                where: 'local_id = ?', whereArgs: [record['local_id']]);
            debugPrint(
                "⚠️ OfflineSync: Record ${record['local_id']} was Duplicate/Already Done.");
            didUpdate = true;
          } else if (result['status'] == 'error') {
            // Server processed but rejected — mark as failed for manual retry
            final errMsg = result['message']?.toString() ?? '';
            // Never auto-delete. Mark as retry_needed or failed. Let user decide.
            final isPermanentRejection = errMsg.contains('already') ||
                errMsg.contains('ஏற்கனவே');
            if (isPermanentRejection) {
              await db.update('pending_attendance', {'status': 'retry_needed'},
                  where: 'local_id = ?', whereArgs: [record['local_id']]);
              debugPrint(
                  "⚠️ OfflineSync: Permanent rejection for ${record['local_id']}: $errMsg — marked as retry_needed.");
              didUpdate = true;
            } else {
              await db.update('pending_attendance', {'status': 'failed'},
                  where: 'local_id = ?', whereArgs: [record['local_id']]);
              debugPrint(
                  "⚠️ OfflineSync: Server error for ${record['local_id']}: $errMsg — marked as failed.");
              didUpdate = true;
            }

            // 🔥 IMPORTANT: DO NOT delete photo file! It must remain visible in UI.
          }
        }
        
        // 🔥 FIX: Small delay between items to prevent hammering on slow nets
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        debugPrint(
            "Sync failed for record ${record['local_id']}, will retry later.");
        // 🔥 FIX: Longer delay on error before next record
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    return didUpdate;
  }

  /// Process the Queue from Hive
  Future<void> syncPendingData() {
    if (_syncFuture != null) {
      return _syncFuture!;
    }

    _syncFuture = _doSyncPendingData().whenComplete(() {
      _syncFuture = null;
    });

    return _syncFuture!;
  }

  Future<void> _doSyncPendingData() async {
    // --- Sync Attendance SQLite ---
    bool attendanceUpdated = await _syncPendingAttendance();

    // --- Existing Hive Logic for Walking ---
    bool hiveUpdated = false;
    if (_box == null) await init();
    if (_box!.isNotEmpty) {
      debugPrint("Starting Sync... ${_box!.length} items pending.");
      final keys = _box!.keys.toList();
      for (var key in keys) {
        final item = _box!.get(key);
        if (item != null) {
          final Map<String, dynamic> data = Map<String, dynamic>.from(item);
          bool success = await _uploadData(data);
          if (success) {
            await _box!.delete(key);
            debugPrint("Synced Item $key successfully.");
            hiveUpdated = true;
          }
        }
      }
    }

    if (attendanceUpdated || hiveUpdated) {
      SyncEventBus.broadcastSyncCompleted();
    }

    debugPrint("Sync Finished.");
  }
}
