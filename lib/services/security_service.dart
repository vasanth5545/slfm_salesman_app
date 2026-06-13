import 'package:flutter/material.dart';
import 'package:freerasp/freerasp.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:slfm_salesman_app/core/services/notification_service.dart'; // To access navigatorKey

/// Service for handling Runtime Application Self-Protection (RASP)
/// using the freerasp package.
class SecurityService {
  /// Initializes freerasp and starts listening for device/app threats.
  static void initialize() {
    // 🛡️ BYPASS: Skip ALL freeRASP in debug/emulator builds
    if (kDebugMode) {
      debugPrint(
          '⚠️ DEBUG MODE: freeRASP security BYPASSED for emulator testing');
      return;
    }

    // 1. Configure the checks needed for your app
    final config = TalsecConfig(
      androidConfig: AndroidConfig(
        packageName: 'com.slfm.salesman',
        // ⚠️ ACTION REQUIRED: Replace with your real SHA-256 Base64 hash from Google Play Console
        // Play Console → App Integrity → App signing key certificate → SHA-256 certificate fingerprint
        // Convert to Base64: echo -n 'XX:XX:...' | xxd -r -p | base64
        signingCertHashes: [
          'ZMW6uN/KpGT0zWu+0wiYppDig4fNHa9DUiPwhACYhDs=', // Debug Hash
          '8EfluWc1OqCGQehhjUoXxoEmks+DZEK5GMGQNdBtQx0=', // Release Hash from upload-keystore.jks
          'gH3Wb+BZBoCjpRgP8ABP/TOuL8CeKfzSKNz+ruhyo/U=' // Google Play App Signing Key Hash
        ],
        supportedStores: [
          'com.android.vending', // Google Play Store
          'com.sec.android.app.samsungapps', // Samsung Galaxy Store
          'com.google.android.packageinstaller', // Android Package Installer
          'com.android.packageinstaller', // Generic Package Installer
          'com.android.chrome', // Chrome
          'org.mozilla.firefox', // Firefox
          'com.opera.browser', // Opera
          'com.UCMobile.intl', // UC Browser
          'com.mi.android.globalFileexplorer', // Mi File Manager
          'com.coloros.filemanager', // Oppo/Realme File Manager
          'com.android.shell', // ADB / Side-load
        ],
      ),
      iosConfig: IOSConfig(
        bundleIds: ['com.slfm.salesman'],
        teamId: 'SLFM-WHITE-FIRE',
      ),
      watcherMail: 'vasanthvarman0@gmail.com', // Success! Real email added
      isProd:
          kReleaseMode, // true enforce strict checks natively, disabled in debug mode for emulator testing
    );

    // 2. Setup Threat Handlers
    final callback = ThreatCallback(
      onAppIntegrity: () =>
          _handleThreat("App Integrity Compromised (Modded APK)"),
      onObfuscationIssues: () => _handleThreat("Obfuscation missing"),
      onDebug: () => debugPrint(
          "⚠️ Debug detection (non-blocking)"), // Log only, don't block
      onDeviceBinding: () => _handleThreat("Device Binding failed"),
      onDeviceID: () => _handleThreat("Device ID spoofed"),
      onHooks: () => _handleThreat("Hooking framework detected (Frida/Xposed)"),
      onPrivilegedAccess: () => _handleThreat("Root / Jailbreak detected"),
      onSecureHardwareNotAvailable: () => _handleThreat("Insecure hardware"),
      onSimulator: () => _handleThreat("Emulator detected"),
    );

    // 3. Attach and Start
    Talsec.instance.attachListener(callback);
    Talsec.instance.start(config);
  }

  static bool threatDetected = false;

  /// Triggered whenever freerasp detects a threat.
  static void _handleThreat(String reason) {
    debugPrint("🚨 SECURITY THREAT DETECTED: $reason 🚨");

    // Disable blocking UI for Emulators during development
    if (!kReleaseMode) {
      debugPrint("⚠️ Ignoring Security Threat in Debug Mode to allow testing.");
      return;
    }

    threatDetected = true;

    // We must use a delayed future to ensure the widget tree is ready if this
    // fires immediately at startup.
    Future.microtask(() {
      final navContext = navigatorKey.currentContext;
      if (navContext == null || !navContext.mounted) return;

      showDialog(
        context: navContext,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false, // Prevent back button dismissal
          child: AlertDialog(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.gpp_bad, color: Colors.red, size: 30),
                SizedBox(width: 10),
                Expanded(
                    child: Text("Security Alert",
                        style: TextStyle(color: Colors.red))),
              ],
            ),
            content: Text(
              "Security Violation Detected!\n\nReason: $reason\n\nPlease ensure you are using the official version of the app.",
              style: const TextStyle(fontSize: 16),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  // Force kill the application
                  SystemNavigator.pop();
                },
                child: const Text("CLOSE APP",
                    style: TextStyle(
                        color: Colors.red, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      );
    });
  }
}
