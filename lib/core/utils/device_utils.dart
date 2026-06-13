import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

class DeviceUtils {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  /// Returns a map with 'device_id', 'model', and 'brand'.
  /// For Android, it uses 'id' (Release ID) or 'androidId' if available.
  /// Note: 'androidId' is the most unique, but 'id' is safer for general identification.
  static Future<Map<String, String>> getDeviceDetails() async {
    String deviceId = 'unknown_id';
    String model = 'Unknown Model';
    String brand = 'Unknown Brand';

    try {
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await _deviceInfo.androidInfo;
        // Use 'id' (e.g. TQ3A.230901.001) combined with model to ensure some uniqueness
        // OR better: use androidInfo.id for the unique build ID.
        // Best for tracking hardware: androidInfo.serialNumber (requires permission) or just use model + id.
        // Let's use 'model' and 'id'.

        deviceId = androidInfo.id; // Unique Build ID
        model = androidInfo.model; // e.g. Pixel 6
        brand = androidInfo.brand; // e.g. google
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await _deviceInfo.iosInfo;
        deviceId = iosInfo.identifierForVendor ?? 'unknown_ios_id';
        model = iosInfo.utsname.machine;
        brand = 'Apple';
      }
    } catch (e) {
      debugPrint("Error getting device info: $e");
    }

    return {
      'device_id': deviceId,
      'device_model': '$brand $model', // e.g. "Google Pixel 6"
      'device_brand': brand,
    };
  }
}
