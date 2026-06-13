import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import '../constants/api_urls.dart';
import '../../services/secure_storage_service.dart';

class VersionCheckService {
  /// Checks if an update is available and shows a dialog if true.
  Future<void> checkVersion(BuildContext context,
      {bool isManual = false}) async {
    try {
      // 1. Get Current App Version
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String currentVersion = packageInfo.version;
      String currentBuildNumber = packageInfo.buildNumber;

      // 🔥 Get Salesman ID for server-side showroom analysis
      final salesmanId = await SecureStorageService.readString('salesman_id');

      debugPrint("Current Version: $currentVersion+$currentBuildNumber");

      // 🔥 NEW: Detect Architecture (ABI)
      DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      String abi = 'universal';
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        abi = androidInfo.supportedAbis.isNotEmpty
            ? androidInfo.supportedAbis[0]
            : 'universal';
      }

      // 2. Fetch Server Version (PHP handles showroom analysis)
      Dio dio = Dio();
      Response response = await dio.get(
        ApiUrl.versionJsonUrl,
        options: Options(headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        }),
        queryParameters: {
          'salesman_id': salesmanId,
          'current_version': currentVersion,
          'abi': abi, // 🔥 NEW: Send ABI to server
        },
      );

      if (response.statusCode == 200) {
        Map<String, dynamic> serverData = response.data;
        String serverVersion = serverData['version'];
        String serverBuildCode = serverData['build_number'].toString();
        bool isMandatory = serverData['mandatory'] == true ||
            serverData['mandatory'] == 1; // Robust bool check

        String updateMessage = serverData['message'] ??
            "A new version ($serverVersion) of the app is available.\nPlease update to continue using the latest features.";

        // 3. Client-side Showroom Filtering
        bool isGlobal = serverData['is_global'] == true;
        List<dynamic> targetShowrooms = serverData['target_showrooms'] ?? [];
        String? userShowroom = await SecureStorageService.getShowroomName();

        bool shouldShowUpdate = false;

        if (isGlobal || targetShowrooms.isEmpty) {
          // If global or no specific showrooms listed, everyone gets it
          shouldShowUpdate = true;
        } else if (userShowroom != null) {
          // Check if current user's showroom is in the target list (Case-insensitive)
          shouldShowUpdate = targetShowrooms.any((s) =>
              s.toString().toLowerCase().trim() ==
              userShowroom.toLowerCase().trim());
        }

        // 4. Compare Build Numbers if allowed
        if (shouldShowUpdate) {
          // 🔥 FIX: Normalize build numbers to handle split-per-abi offsets (+1000, +2000)
          // This ensures that version 30 (Local) and 2030 (v8a) are treated as the same base version.
          int currentBuildBase = (int.tryParse(currentBuildNumber) ?? 0) % 1000;
          int serverBuildBase = (int.tryParse(serverBuildCode) ?? 0) % 1000;

          debugPrint("📡 Version Check Logic (Normalized):");
          debugPrint(
              "   - Server Build: $serverBuildBase (Original: $serverBuildCode)");
          debugPrint(
              "   - Local Build: $currentBuildBase (Original: $currentBuildNumber)");

          if (serverBuildBase > currentBuildBase && context.mounted) {
            debugPrint("🚀 UPDATE REQUIRED: Showing Dialog...");
            _showUpdateDialog(
                context, serverVersion, isMandatory, updateMessage);
          } else {
            debugPrint(
                "❌ UPDATE NOT REQUIRED: Server ($serverBuildBase) <= Local ($currentBuildBase)");
            if (isManual && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("You are up to date! ✅"),
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(seconds: 2),
                ),
              );
            }
          }
        } else {
          debugPrint(
              "🚫 SHOWROOM MISMATCH: This update is not for $userShowroom");
        }
      } else {
        debugPrint("Server Response Error: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Version Check Exception: $e");
    }
  }

  void _showUpdateDialog(BuildContext context, String newVersion,
      bool isMandatory, String message) {
    showDialog(
      context: context,
      barrierDismissible: !isMandatory, // 🔒 Lock if mandatory
      builder: (context) {
        return PopScope(
          canPop: !isMandatory, // 🔒 Disable back button if mandatory
          child: AlertDialog(
            title: const Text("New Update Available!"),
            content: Text(message),
            actions: [
              if (!isMandatory) // 🛡️ Hide Later if mandatory
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Later"),
                ),
              ElevatedButton(
                onPressed: () async {
                  final Uri playStoreUri = Uri.parse(ApiUrl.playStoreUrl);
                  if (await canLaunchUrl(playStoreUri)) {
                    await launchUrl(playStoreUri,
                        mode: LaunchMode.externalApplication);
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text("Could not open Play Store ❌")),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                child: const Text("Update Now",
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      },
    );
  }
}
