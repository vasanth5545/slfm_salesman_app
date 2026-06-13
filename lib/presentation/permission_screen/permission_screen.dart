import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sizer/sizer.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_export.dart';
import '../../main.dart';
import 'package:auto_start_flutter/auto_start_flutter.dart';
import 'package:flutter/services.dart';
import '../../services/secure_storage_service.dart';
import 'package:disable_battery_optimization/disable_battery_optimization.dart';

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen>
    with WidgetsBindingObserver {
  bool _isLocationAlways = false;
  bool _isCameraGranted = false;
  bool _isNotificationGranted = false;
  bool _isBatteryOptimizationIgnored = false;
  bool _isAutoStartAvailable = false;
  bool _hasClickedAutoStart =
      false; // Cannot verify programmatically, so we track click
  bool _isLoading = true;
  bool _isRequesting =
      false; // 🔥 Prevents lifecycle observer from double-firing during request

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isRequesting) {
      // Only re-check if we're NOT in the middle of a permission request
      // This prevents double setState and ANR when returning from system dialog
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    setState(() => _isLoading = true);

    // 🔥 Check if user already clicked Auto-Start in a previous session
    final hasClicked =
        await SecureStorageService.readBool('has_clicked_auto_start');
    if (hasClicked == true) {
      _hasClickedAutoStart = true;
    }

    // Check Location Always
    final locationStatus = await Permission.locationAlways.status;
    _isLocationAlways = locationStatus.isGranted;

    // Check Camera
    final cameraStatus = await Permission.camera.status;
    _isCameraGranted = cameraStatus.isGranted;

    // Check Notification
    final notificationStatus = await Permission.notification.status;
    _isNotificationGranted = notificationStatus.isGranted;

    // Check Battery Optimization
    bool? isBatteryOptDisabled =
        await DisableBatteryOptimization.isBatteryOptimizationDisabled;

    // 🔥 NEW: Fallback for devices that incorrectly report battery optimization status
    final hasClickedBattery =
        await SecureStorageService.readBool('has_clicked_battery_opt');
    _isBatteryOptimizationIgnored =
        (isBatteryOptDisabled == true) || (hasClickedBattery == true);

    // Check Auto-Start Availability (Only available on certain OEMs)
    try {
      final isAvailable = await isAutoStartAvailable;
      if (isAvailable != null) {
        _isAutoStartAvailable = isAvailable;
      }
    } on PlatformException catch (_) {
      _isAutoStartAvailable = false;
    }

    setState(() => _isLoading = false);

    // If all granted, notify SecurityGuard to refresh and move on
    if (_isLocationAlways && _isCameraGranted && _isNotificationGranted) {
      if (mounted) {
        globalSecurityGuardState?.refreshPermissions();
        // Redirect will happen via SecurityGuard's build logic
      }
    }
  }

  // 🔥 Track permanently denied permissions for inline guidance (no dialogs = no crashes)
  final Set<Permission> _permanentlyDenied = {};

  Future<void> _requestPermission(Permission permission) async {
    _isRequesting = true; // 🔥 Block lifecycle observer while requesting
    try {
      if (permission == Permission.locationAlways) {
        // Step 1: Check if "Allow all the time" is already granted
        final alwaysCheck = await Permission.locationAlways.status;
        if (alwaysCheck.isGranted) {
          _permanentlyDenied.remove(Permission.locationAlways);
        } else {
          // Step 2: Ensure foreground location is granted first
          var fgStatus = await Permission.location.status;
          if (!fgStatus.isGranted) {
            fgStatus = await Permission.location.request();
          }

          if (fgStatus.isGranted) {
            // Foreground granted but NOT "all the time"
            // Don't call locationAlways.request() — it crashes on Realme/Oppo.
            // Instead, show "Open Settings" red box so user can manually set it.
            _permanentlyDenied.add(Permission.locationAlways);
          } else {
            // User denied even foreground location
            _permanentlyDenied.add(Permission.locationAlways);
          }
        }
      } else if (permission == Permission.ignoreBatteryOptimizations) {
        // 🔋 Battery Optimization using disable_battery_optimization
        bool? isBatteryOptDisabled =
            await DisableBatteryOptimization.isBatteryOptimizationDisabled;
        if (isBatteryOptDisabled != true) {
          await DisableBatteryOptimization
              .showDisableBatteryOptimizationSettings();

          // 🔥 NEW: Record that the user visited settings, to bypass OEM API bugs
          await SecureStorageService.writeBool('has_clicked_battery_opt', true);

          // After returning from settings, assume it's manually checked by user
          // (Since it might still return false on OEM settings, we just clear permanently denied if they went there)
          _permanentlyDenied.remove(permission);
        } // Don't mark as permanently denied — Android always allows re-requesting battery
      } else {
        // Handle Camera and Notifications
        var status = await permission.status;

        if (!status.isGranted) {
          status = await permission.request();

          if (status.isGranted) {
            _permanentlyDenied.remove(permission);
          } else {
            // Denied standard permission, show "Open Settings" Red Box
            _permanentlyDenied.add(permission);
          }
        }
      }
    } finally {
      _isRequesting = false; // 🔥 Unblock lifecycle observer
      _checkPermissions(); // Refresh UI state
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blue.shade50,
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 6.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 5.h),
                _buildHeader(),
                SizedBox(height: 4.h),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : ListView(
                          physics: const BouncingScrollPhysics(),
                          children: [
                            _buildPermissionTile(
                              title: "Location Access",
                              subtitle:
                                  "This app collects location data to enable attendance tracking and background route monitoring even when the app is closed or not in use.\n(வருகைப்பதிவு மற்றும் இருப்பிடத்தை கணக்கிட 'Allow all the time' அனுமதி அவசியம்.)",
                              icon: Icons.location_on_rounded,
                              isGranted: _isLocationAlways,
                              permission: Permission.locationAlways,
                              onTap: () =>
                                  _requestPermission(Permission.locationAlways),
                            ),
                            _buildPermissionTile(
                              title: "Camera Access",
                              subtitle:
                                  "This app collects photos to verify your identity during attendance clock-in and clock-out.\n(வருகைப்பதிவின் போது உங்களை உறுதி செய்ய புகைப்படம் எடுக்க கேமரா அனுமதி அவசியம்.)",
                              icon: Icons.camera_alt_rounded,
                              isGranted: _isCameraGranted,
                              permission: Permission.camera,
                              onTap: () =>
                                  _requestPermission(Permission.camera),
                            ),
                            _buildPermissionTile(
                              title: "Notifications",
                              subtitle:
                                  "முக்கிய அறிவிப்புகள் மற்றும் தகவல்களை உடனுக்குடன் பெற நோட்டிபிகேஷன் அனுமதி அவசியம்.",
                              icon: Icons.notifications_active_rounded,
                              isGranted: _isNotificationGranted,
                              permission: Permission.notification,
                              onTap: () =>
                                  _requestPermission(Permission.notification),
                            ),
                            _buildPermissionTile(
                              title: "Battery Optimization",
                              subtitle:
                                  "பின்னணியில் இருப்பிடத்தை கண்காணிக்க 'Unrestricted' பேட்டரி அனுமதி அவசியம். மேலும் 'Pause app activity if unused' என்பதை OFF செய்யவும்.",
                              icon: Icons.battery_charging_full_rounded,
                              isGranted: _isBatteryOptimizationIgnored,
                              permission: Permission.ignoreBatteryOptimizations,
                              onTap: () => _requestPermission(
                                  Permission.ignoreBatteryOptimizations),
                            ),
                            if (_isAutoStartAvailable)
                              _buildPermissionTile(
                                title: "Auto-Start / Background Run",
                                subtitle:
                                    "உங்கள் போன் பின்னணி செயலிகளை தானாக நிறுத்துவதை தவிர்க்க 'Auto-Start' அல்லது 'Allow background activity'-ஐ ON செய்யவும்.",
                                icon: Icons.rocket_launch_rounded,
                                isGranted: _hasClickedAutoStart,
                                permission: Permission
                                    .unknown, // Dummy permission for logic
                                onTap: () async {
                                  _isRequesting = true;
                                  try {
                                    await getAutoStartPermission();
                                    await SecureStorageService.writeBool(
                                        'has_clicked_auto_start', true);
                                    setState(() {
                                      _hasClickedAutoStart = true;
                                    });
                                  } catch (e) {
                                    debugPrint(e.toString());
                                  } finally {
                                    _isRequesting = false;
                                    _checkPermissions();
                                  }
                                },
                              ),
                          ],
                        ),
                ),
                _buildFooter(),
                SizedBox(height: 2.h),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade100,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.security_rounded,
              color: Colors.blue.shade800, size: 32),
        ),
        SizedBox(height: 2.h),
        Text(
          "Permissions Required",
          style: GoogleFonts.inter(
            fontSize: 22.sp,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        SizedBox(height: 1.h),
        Text(
          "To provide a seamless tracking experience, please grant the following permissions.",
          style: GoogleFonts.inter(
            fontSize: 12.sp,
            color: Colors.black54,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isGranted,
    required Permission permission,
    required VoidCallback onTap,
  }) {
    final bool isPermanent = _permanentlyDenied.contains(permission);

    // Inline guidance text for permanently denied permissions (Tamil + English)
    // Same detailed content as before — just shown inline instead of dialog (dialog caused crashes)
    String? guidanceText;
    if (isPermanent && !isGranted) {
      if (permission == Permission.locationAlways) {
        guidanceText = "அனுமதி மறுக்கப்பட்டுள்ளது. 'Open Settings' சென்று:\n"
            "Permissions ➔ Location ➔ 'Allow all the time'";
      } else if (permission == Permission.camera) {
        guidanceText = "அனுமதி மறுக்கப்பட்டுள்ளது. 'Open Settings' சென்று:\n"
            "Permissions ➔ Camera ➔ 'Allow'";
      } else if (permission == Permission.ignoreBatteryOptimizations) {
        guidanceText = "அனுமதி மறுக்கப்பட்டுள்ளது. 'Open Settings' சென்று:\n"
            "Battery ➔ 'Unrestricted' என மாற்றவும்.\n"
            "மேலும் 'Pause app activity if unused' என்பதை OFF செய்யவும்.";
      } else if (permission == Permission.unknown) {
        // Auto-start guidance
        guidanceText =
            "இந்த செட்டிங்ஸ் உங்கள் போன் மாடலை பொறுத்தது.\n'Manage Manually' என மாற்றி அனைத்தையும் ON செய்யவும்.";
      } else {
        guidanceText = "அனுமதி மறுக்கப்பட்டுள்ளது. 'Open Settings' சென்று:\n"
            "Permissions ➔ Notifications ➔ 'Allow'";
      }
    }

    return Container(
      margin: EdgeInsets.only(bottom: 2.h),
      padding: EdgeInsets.all(2.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isGranted
              ? Colors.green.shade200
              : (isPermanent ? Colors.red.shade200 : Colors.blue.shade100),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isGranted
                      ? Colors.green.shade50
                      : (isPermanent
                          ? Colors.red.shade50
                          : Colors.blue.shade50),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: isGranted
                      ? Colors.green.shade700
                      : (isPermanent
                          ? Colors.red.shade700
                          : Colors.blue.shade700),
                  size: 24,
                ),
              ),
              SizedBox(width: 4.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: 0.5.h),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 10.sp,
                        color: Colors.black45,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 2.w),
              InkWell(
                onTap: isGranted
                    ? null
                    : (isPermanent ? () => openAppSettings() : onTap),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 1.h),
                  decoration: BoxDecoration(
                    color: isGranted
                        ? Colors.green.shade500
                        : (isPermanent
                            ? Colors.orange.shade600
                            : Colors.blue.shade600),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: isGranted
                      ? const Icon(Icons.check_rounded,
                          color: Colors.white, size: 18)
                      : Text(
                          isPermanent ? "Open Settings" : "Allow",
                          style: GoogleFonts.inter(
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
          // 🔥 Inline guidance when permanently denied (no dialog = no crash)
          if (guidanceText != null) ...[
            SizedBox(height: 1.5.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 3.w, vertical: 1.2.h),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200, width: 1),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.warning_rounded,
                      color: Colors.red.shade600, size: 22),
                  SizedBox(width: 3.w),
                  Expanded(
                    child: Text(
                      guidanceText,
                      style: GoogleFonts.inter(
                        fontSize: 10.5.sp,
                        color: Colors.red.shade900,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final allGranted =
        _isLocationAlways && _isCameraGranted && _isNotificationGranted;

    return Column(
      children: [
        if (!allGranted)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    color: Colors.orange.shade800, size: 20),
                SizedBox(width: 3.w),
                Expanded(
                  child: Text(
                    "You must grant all permissions to continue using the app.",
                    style: GoogleFonts.inter(
                      fontSize: 10.sp,
                      color: Colors.orange.shade900,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        SizedBox(height: 2.h),
        SizedBox(
          width: double.infinity,
          height: 7.h,
          child: ElevatedButton(
            onPressed: allGranted
                ? () {
                    globalSecurityGuardState?.refreshPermissions();
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade800,
              disabledBackgroundColor: Colors.grey.shade300,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              elevation: 0,
            ),
            child: Text(
              allGranted ? "Continue to App" : "Grant All Required Access",
              style: GoogleFonts.inter(
                fontSize: 14.sp,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
