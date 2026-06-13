import 'dart:async';
import 'package:slfm_salesman_app/services/activity_logger.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../services/secure_storage_service.dart';
import 'package:sizer/sizer.dart';
import '../../core/app_export.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../core/services/secure_http_client.dart' as http;
import '../../services/feature_control_service.dart'; // Add this import
import '../../services/security_service.dart';
import '../../core/utils/network_quality_helper.dart';

class SplashScreen extends StatefulWidget {
  static bool isSplashScreenActive = true;

  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _isOffline = false;
  bool _isInitializing = false;
  bool _forceOfflineProceed =
      false; // Add flag to bypass UI but keep offline state

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  /// 🚀 NEW: Sequential initialization to prevent concurrent permission crashes
  Future<void> _initializeApp({bool skipNetworkCheck = false}) async {
    if (_isInitializing) return;
    _isInitializing = true;

    if (!skipNetworkCheck) {
      // 🌐 STEP 0: Check Internet Connectivity with Timeout (Prevents hanging on boot)
      bool hasInternet = false;
      try {
        hasInternet = await NetworkQualityHelper.hasRealInternet().timeout(
          const Duration(seconds: 3),
          onTimeout: () => false, 
        );
      } catch (e) {
        hasInternet = false;
      }
      
      if (!hasInternet) {
        setState(() {
          _isOffline = true;
          _isInitializing = false;
        });
        return;
      } else {
        if (_isOffline) {
          setState(() => _isOffline = false);
        }
      }
    } else {
      // User clicked 'Continue to Offline'
      setState(() {
        _forceOfflineProceed = true;
      });
      // Keep _isOffline true so we don't attempt network calls that will timeout
    }

    // 🚀 ULTRA-OPTIMIZED: Run ALL initialization tasks in parallel with Timeouts
    // We wait for a minimum of 500ms for branding, while performing all logic.
    try {
      await Future.wait([
        Future.delayed(const Duration(milliseconds: 500)),
        _checkVersionAndReset().timeout(const Duration(seconds: 3)),
        _checkLoginStatus().timeout(const Duration(seconds: 5)),
      ]);
    } catch (e) {
      debugPrint("Splash Init Error/Timeout: $e");
      // If it times out, try to force navigation to login
      if (mounted) {
        if (!SecurityService.threatDetected) {
          // Prevent navigation if RASP caught something
          SplashScreen.isSplashScreenActive = false;
          Navigator.pushReplacementNamed(context, AppRoutes.login);
        }
      }
    }

    _isInitializing = false;
  }

  /// 🔄 FORCE LOGOUT ON VERSION CHANGE
  /// This ensures that when we update the app (e.g., v2.2.0),
  /// all users are logged out so they MUST re-login.
  /// This is critical for the new "Device Integrity" check to register the device.
  Future<void> _checkVersionAndReset() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final String currentVersion = packageInfo.version;

      final String? lastRunVersion =
          await SecureStorageService.readString('last_run_version');

      // If version changed (or first run), FORCE CLEANUP
      // We check for "2.2.0" specifically or just any change.
      // Let's force it if it's NOT the current version.
      if (lastRunVersion != currentVersion) {
        debugPrint(
            "📱 App Updated ($lastRunVersion -> $currentVersion). Updating local version record.");

        // 🟢 FIXED: REMOVED FORCE LOGOUT
        // Based on user request: Version change should not "close" the user's session.
        // await SecureStorageService.clearSession();

        // Save New Version to prevent repeated checks
        await SecureStorageService.writeString(
            'last_run_version', currentVersion);
      }
    } catch (e) {
      debugPrint("Error checking version reset: $e");
    }
  }

  // Location permission checks moved to Dashboard

  Future<void> _checkLoginStatus() async {
    final bool isLoggedIn = await SecureStorageService.isLoggedIn();

    if (isLoggedIn) {
      // Account Suspension Check (Moved from Dashboard to Splash Screen)
      final String? salesmanId =
          await SecureStorageService.readString('salesman_id');
      if (salesmanId != null && salesmanId.isNotEmpty) {
        bool isSuspended = await _checkSalesmanStatusFromServer(salesmanId);
        if (isSuspended) {
          await SecureStorageService.clearSession();
          if (!mounted) return;
          if (SecurityService.threatDetected) {
            return; // Prevent navigation if RASP caught something
          }
          try { ActivityLogger.instance.logError('Splash', 'Account suspended - session cleared'); } catch(_) {}
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  "Your account has been suspended. Please login again or contact admin.",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              backgroundColor: Colors.red,
            ),
          );
          SplashScreen.isSplashScreenActive = false;
          Navigator.pushReplacementNamed(context, AppRoutes.login);
          return;
        }
      }

      // 🔥 Showroom / Lunch On-Off: Load features for current showroom BEFORE Dashboard
      await FeatureControlService().init();

      if (!mounted) return;
      if (SecurityService.threatDetected) {
        return; // Prevent navigation if RASP caught something
      }
      SplashScreen.isSplashScreenActive = false;
      Navigator.pushReplacementNamed(context, AppRoutes.dashboard);
    } else {
      if (!mounted) return;
      if (SecurityService.threatDetected) {
        return; // Prevent navigation if RASP caught something
      }
      SplashScreen.isSplashScreenActive = false;
      Navigator.pushReplacementNamed(context, AppRoutes.login);
    }
  }

  /// 🔥 Check salesman status from MySQL via PHP API
  Future<bool> _checkSalesmanStatusFromServer(String salesmanId) async {
    if (_isOffline) {
      debugPrint(
          "Offline: Skipping salesman status check to avoid timeout delay.");
      return false; // ✅ ALLOWED (Bypass network delay)
    }
    try {
      final url = Uri.parse(ApiUrl.salesmanCheck);
      // Wait a max of 3s so we don't hold the user in suspense if network is bad
      final response = await http.SecureHttpClient.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'salesman_id': salesmanId}),
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          final salesmanData = data['data'];
          final accountStatus = salesmanData?['account_status'] ?? 'Active';

          if (salesmanData != null) {
            final serverPhoto = salesmanData['profile_photo']?.toString() ?? '';
            final serverAnimal =
                salesmanData['avatar_animal']?.toString() ?? '';
            if (serverPhoto.isNotEmpty) {
              await SecureStorageService.writeString(
                  'profile_photo', serverPhoto);
            }
            if (serverAnimal.isNotEmpty) {
              await SecureStorageService.writeString(
                  'avatar_animal', serverAnimal);
            }
            if (serverPhoto.isNotEmpty && serverAnimal.isNotEmpty) {
              await SecureStorageService.setProfileSetupDone(true);
            }
          }

          if (accountStatus == 'Suspended') {
            return true; // ⛔ BLOCKED
          }
        } else if (data['data']?['account_status'] == 'NotFound') {
          return true; // Deleted from DB
        }
      }
    } catch (e) {
      debugPrint("Status check failed (proceeding): $e");
    }
    return false; // ✅ ALLOWED
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.primary, // Brand Color Background
      body: (_isOffline && !_forceOfflineProceed)
          ? _buildNoInternetUI(theme)
          : _buildSplashUI(theme),
    );
  }

  Widget _buildSplashUI(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Logo Container
          Container(
            width: 40.w,
            height: 40.w,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            padding: EdgeInsets.all(4.w),
            child: ClipOval(
              child: Image.asset(
                'assets/images/logo.jpg',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    Icons.storefront,
                    size: 40.sp,
                    color: theme.colorScheme.primary,
                  );
                },
              ),
            ),
          ),
          SizedBox(height: 3.h),

          // App Name
          Text(
            "SLFM Attendance app",
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),

          SizedBox(height: 6.h),

          // Loader
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
          SizedBox(height: 2.h),
          Text(
            "Securing your workspace...",
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 10.sp,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoInternetUI(ThemeData theme) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 10.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(6.w),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.wifi_off_rounded,
                size: 50.sp,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              "Mobile Data Off",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 1.5.h),
            Text(
              "Please turn on your internet connection to use the app.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 11.sp,
              ),
            ),
            SizedBox(height: 5.h),
            ElevatedButton(
              onPressed: () => _initializeApp(skipNetworkCheck: true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: theme.colorScheme.primary,
                padding:
                    EdgeInsets.symmetric(horizontal: 12.w, vertical: 1.5.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                elevation: 5,
              ),
              child: Text(
                "Continue to Offline",
                style: TextStyle(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
