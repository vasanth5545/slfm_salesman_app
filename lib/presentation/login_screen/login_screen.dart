import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart'; // 🔥 Import url_launcher
import 'package:slfm_salesman_app/core/services/secure_http_client.dart'
    as http;
import '../../services/secure_storage_service.dart';
import 'package:sizer/sizer.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import '../../core/app_export.dart';
import '../../core/utils/device_utils.dart';
import '../../main.dart'; // Import for globalSecurityGuardState
import '../../services/activity_logger.dart'; // 🔥 Admin Logger

/// Login Screen for SLFM Attendance app
///
/// Features included:
/// 1. Real Database Login (via PHP API) - COMPATIBLE WITH YOUR PHP FILES
/// 2. Demo Login Button (for testing without server)
/// 3. Input Validation (Regex for Salesman ID)
/// 4. Focus Management (Auto-focus next field)
/// 5. Loading States & Error Handling
/// 6. Secure Password Entry with Toggle
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Controllers
  final TextEditingController _salesmanIdController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // Focus Nodes for keyboard navigation
  final FocusNode _salesmanIdFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();

  // State Variables
  bool _isLoading = false;
  bool _isPasswordVisible = false;
  String? _errorMessage;
  String _appVersion = '';

  // ⚠️ API CONFIGURATION
  // Use '10.0.2.2' for Android Emulator to reach localhost XAMPP
  // Use your PC's IP (e.g., 192.168.1.x) for Real Device testing
  final String _apiUrl = ApiUrl.login;

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    // 🔥 Ensure the current session is saved in the switcher before we potentially overwrite it
    SecureStorageService.syncCurrentSessionToSwitcher();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _appVersion = 'v${info.version}');
      }
    } catch (_) {
      // Silently fail — footer will just show empty version
    }
  }

  @override
  void dispose() {
    _salesmanIdController.dispose();
    _passwordController.dispose();
    _salesmanIdFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  // --- LOGIN LOGIC HANDLERS ---

  /// Handles the Real Login Process connecting to PHP API
  Future<void> _handleRealLogin() async {
    // 1. Reset State
    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });
    FocusScope.of(context).unfocus(); // Hide keyboard

    final salesmanId = _salesmanIdController.text.trim();
    final password = _passwordController.text.trim();

    // 2. Local Validation
    if (salesmanId.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = "Please enter both Salesman ID and Password";
        _isLoading = false;
      });
      return;
    }

    try {
      // Restored Device info fetch for login
      final deviceInfo = await DeviceUtils.getDeviceDetails()
          .catchError((_) => <String, String>{}) as Map<String, dynamic>;

      // Maintenance check via Firestore
      try {
        final settingsRef =
            FirebaseFirestore.instance.collection('app_settings');
        final query =
            await settingsRef.get().timeout(const Duration(seconds: 8));

        int mode = 0;
        String msg = "Maintenance in progress";

        for (var doc in query.docs) {
          if (doc.id == 'maintenance_mode') {
            final val = doc.data()['setting_value'];
            mode = (val == true || val == 1) ? 1 : 0;
          } else if (doc.id == 'maintenance_message') {
            msg = doc.data()['setting_value']?.toString() ?? msg;
          }
        }

        if (mode == 1) {
          setState(() {
            _isLoading = false;
            _errorMessage = "⚠️ MAINTENANCE MODE\n$msg";
          });
          _showMaintenanceDialog(msg);
          return; // STOP LOGIN
        }
      } catch (e) {
        debugPrint(
            "⚠️ Maintenance check skipped (Firestore error/timeout) — proceeding");
      }

      debugPrint("Attempting connection to: $_apiUrl");
      debugPrint("Device Info: $deviceInfo");

      // 3. Network Request — with retry for 2G/3G resilience
      final response = await http.postWithRetry(
        Uri.parse(_apiUrl),
        body: {
          'salesman_id': salesmanId,
          'password': password,
          'device_id': deviceInfo['device_id']?.toString() ?? '',
          'device_model': deviceInfo['device_model']?.toString() ?? '',
        },
        baseTimeoutSeconds: 20,
        maxRetries: 1,
      );

      debugPrint("API Response: ${response.statusCode} - ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['status'] == 'success') {
          // 4. Success Case
          final userData = data['data'];

          // SAFETY CHECK: Ensure we handle missing/null values from API
          // Using explicit casts and fallbacks to prevent 'Null' errors
          final id =
              (userData['salesman_id'] ?? userData['id'] ?? '').toString();
          final name = (userData['name'] ?? '').toString();
          // Fallback if showroom_name is missing/null in API response
          final showroom =
              (userData['showroom_name'] ?? 'SLFM Main Branch').toString();

          final profilePhoto = (userData['profile_photo'] ?? '').toString();
          final avatarAnimal = (userData['avatar_animal'] ?? '').toString();
          final role = (userData['role'] ?? 'salesman').toString();
          final customCutoff =
              (userData['custom_late_cutoff'] ?? '10:00:59').toString();

          // 🔥 JWT / Firebase Custom Token Integration
          final String? token = data['token']?.toString();
          if (token != null && token.isNotEmpty) {
            try {
              await FirebaseAuth.instance.signInWithCustomToken(token);
              // Also securely save the token locally for custom Dio interceptors
              await SecureStorageService.writeString('jwt_token', token);
            } on PlatformException catch (e) {
              // 🛡️ OnePlus devices: SignInHubActivity NullPointerException workaround
              debugPrint(
                  "🔥 Firebase Auth PlatformException (device-specific): $e");
              // Still save token locally so API calls work
              await SecureStorageService.writeString('jwt_token', token);
            } catch (e) {
              debugPrint("🔥 Firebase Auth Error: $e");
              setState(() => _errorMessage = 'Firebase Auth Failed: $e');
              HapticFeedback.lightImpact();
              return;
            }
          }

          // 🔥 FIX: Pass the token directly to prevent Race Conditions
          await _saveSessionAndNavigate(
            id: id,
            name: name,
            showroom: showroom,
            profilePhoto: profilePhoto,
            avatarAnimal: avatarAnimal,
            role: role,
            customCutoff: customCutoff,
            token: token,
          );
        } else {
          // 5. API Logic Error (Wrong password, etc.)
          final errorMsg = data['message'] ?? 'Login failed';
          ActivityLogger.instance.logLogin('failed',
              salesmanId: salesmanId, success: false, reason: errorMsg);
          setState(() => _errorMessage = errorMsg);
          HapticFeedback.lightImpact(); // Feedback for error
        }
      } else {
        // 🔥 SECURE: Hide Details (Don't show raw response body or weird codes if possible)
        ActivityLogger.instance.logLogin('failed',
            salesmanId: salesmanId,
            success: false,
            reason: 'Server Error: ${response.statusCode}');
        setState(() => _errorMessage =
            'Server Error (Code: ${response.statusCode}). Please contact manager.');
      }
    } catch (e) {
      // 6. Network/Connection Error
      debugPrint("Login Exception: $e");
      ActivityLogger.instance.logLogin('failed',
          salesmanId: salesmanId, success: false, reason: 'Connection Error');
      ActivityLogger.instance.logError('Login', e.toString());
      setState(() => _errorMessage =
          'Unable to connect. Please check your internet and try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Shared method to save session and navigate to Dashboard
  Future<void> _saveSessionAndNavigate({
    required String id,
    required String name,
    required String showroom,
    required String profilePhoto,
    required String avatarAnimal,
    String role = 'salesman',
    String customCutoff = '10:00:59',
    String? token, // 🔥 ADDED TOKEN PARAMETER
  }) async {
    await SecureStorageService.saveUserSession(
      id: id,
      name: name,
      showroom: showroom,
      profilePhoto: profilePhoto,
      avatarAnimal: avatarAnimal,
      role: role,
      customLateCutoff: customCutoff,
    );

    // 🔥 FIX: Use the directly passed token instead of reading from storage immediately
    final finalToken = token ?? await SecureStorageService.getToken();
    await SecureStorageService.addAccountToSwitcher(
      id: id,
      name: name,
      showroom: showroom,
      profilePhoto: profilePhoto,
      avatarAnimal: avatarAnimal,
      role: role,
      token: finalToken,
    );

    // 🔥 NOTIFY BACKGROUND SERVICE
    FlutterBackgroundService().invoke("updateSalesmanId", {"id": id});

    // 🔥 INIT ACTIVITY LOGGER
    ActivityLogger.instance.init(id);
    ActivityLogger.instance.logLogin('success', salesmanId: id);

    // 🔥 RE-INITIALIZE GLOBAL SUSPENSION LISTENER
    globalSecurityGuardState?.setupGlobalSuspensionAndPresence();

    if (mounted) {
      HapticFeedback.mediumImpact(); // Success haptic

      // 🛡️ Permanent Flag Check: If we see data on login, mark setup as done permanently
      if (profilePhoto.isNotEmpty || avatarAnimal.isNotEmpty) {
        await SecureStorageService.setProfileSetupDone(true);
      }

      // 🔥 FIX: Route to SPLASH SCREEN instead of Dashboard.
      // This ensures all Singletons, Memory, and Feature Flags are cleanly wiped
      // and re-initialized for the newly logged-in account, preventing data collapse!
      final isSetupDone = await SecureStorageService.isProfileSetupDone();

      if (!mounted) return;

      if (!isSetupDone) {
        debugPrint("🚀 Mandatory Profile Setup Required on Login!");
        Navigator.pushNamedAndRemoveUntil(
            context, AppRoutes.splashScreen, (route) => false);
      } else {
        debugPrint("✅ Profile setup found. Skipping overlay.");
        Navigator.pushNamedAndRemoveUntil(
            context, AppRoutes.splashScreen, (route) => false);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.greenAccent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Welcome, $name!",
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1E2643),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: EdgeInsets.all(4.w),
        ),
      );
    }
  }

  void _showMaintenanceDialog(String msg) {
    if (!mounted) {
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("⚠️ Under Maintenance"),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => SystemNavigator.pop(), // Closes App
            child: const Text("Close App"),
          ),
        ],
      ),
    );
  }

  // --- UI BUILDER ---

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: GestureDetector(
          // Dismiss keyboard when tapping outside
          onTap: () => FocusScope.of(context).unfocus(),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: ConstrainedBox(
                  // Ensures content fills screen height correctly
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                  ),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6.w),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 40), // Top spacing

                          // 1. Logo Section
                          _buildLogo(theme),

                          const SizedBox(height: 40),

                          // 2. Header Text
                          _buildWelcomeText(theme),

                          const SizedBox(height: 32),

                          // 3. ID Input Field
                          _buildSalesmanIdField(theme),

                          const SizedBox(height: 20),

                          // 4. Password Input Field
                          _buildPasswordField(theme),

                          // 5. Error Message Display
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 16),
                            _buildErrorMessage(theme),
                          ],

                          const SizedBox(height: 32),

                          // 6. Main Login Button
                          _buildLoginButton(theme),

                          const SizedBox(height: 16),

                          // 8. Help Text
                          _buildHelpText(theme),

                          const Spacer(),
                          const SizedBox(height: 24), // Buffer before footer

                          // 9. Footer
                          _buildFooter(theme),

                          const SizedBox(height: 24), // Bottom spacing
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // --- WIDGET COMPONENTS ---

  Widget _buildLogo(ThemeData theme) {
    return Center(
      child: Container(
        width: 32.w,
        height: 32.w,
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withValues(alpha: 0.2),
              offset: const Offset(0, 8),
              blurRadius: 20,
              spreadRadius: 0,
            ),
          ],
        ),
        child: ClipOval(
          child: Image.asset(
            'assets/images/logo.jpg',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: theme.colorScheme.primary, // Fallback background
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.broken_image_outlined,
                        color: theme.colorScheme.onPrimary,
                        size: 30.sp,
                      ),
                      SizedBox(height: 0.5.h),
                      Text(
                        "No Image",
                        style: TextStyle(
                          color: theme.colorScheme.onPrimary,
                          fontSize: 10.sp,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeText(ThemeData theme) {
    return Column(
      children: [
        Text(
          'Welcome Back',
          style: theme.textTheme.headlineMedium?.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'Sign in to access your dashboard\nand manage sales.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildSalesmanIdField(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 1.w),
          child: Text(
            'Salesman ID',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _errorMessage != null && _salesmanIdController.text.isEmpty
                  ? theme.colorScheme.error
                  : theme.colorScheme.outline.withValues(alpha: 0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.shadow.withValues(alpha: 0.05),
                offset: const Offset(0, 4),
                blurRadius: 12,
              ),
            ],
          ),
          child: TextField(
            controller: _salesmanIdController,
            focusNode: _salesmanIdFocusNode,
            enabled: !_isLoading,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) =>
                FocusScope.of(context).requestFocus(_passwordFocusNode),
            keyboardType: TextInputType.text,
            textCapitalization: TextCapitalization.characters,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: 'e.g., SM000',
              hintStyle: TextStyle(
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              prefixIcon: Icon(
                Icons.badge_outlined,
                color: theme.colorScheme.primary,
              ),
              border: InputBorder.none,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 4.w, vertical: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 1.w),
          child: Text(
            'Password',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _errorMessage != null && _passwordController.text.isEmpty
                  ? theme.colorScheme.error
                  : theme.colorScheme.outline.withValues(alpha: 0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.shadow.withValues(alpha: 0.05),
                offset: const Offset(0, 4),
                blurRadius: 12,
              ),
            ],
          ),
          child: TextField(
            controller: _passwordController,
            focusNode: _passwordFocusNode,
            enabled: !_isLoading,
            obscureText: !_isPasswordVisible,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _handleRealLogin(),
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: 'Enter your password',
              hintStyle: TextStyle(
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              prefixIcon: Icon(
                Icons.lock_outline,
                color: theme.colorScheme.primary,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                onPressed: () =>
                    setState(() => _isPasswordVisible = !_isPasswordVisible),
              ),
              border: InputBorder.none,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 4.w, vertical: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorMessage(ThemeData theme) {
    return Container(
      padding: EdgeInsets.all(3.w),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.error_rounded, color: theme.colorScheme.error, size: 22),
          SizedBox(width: 3.w),
          Expanded(
            child: Text(
              _errorMessage!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginButton(ThemeData theme) {
    return SizedBox(
      height: 55,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleRealLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: _isLoading ? 0 : 4,
          shadowColor: theme.colorScheme.primary.withValues(alpha: 0.4),
        ),
        child: _isLoading
            ? SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'SECURE LOGIN',
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  SizedBox(width: 2.w),
                  const Icon(Icons.arrow_forward_rounded, size: 20),
                ],
              ),
      ),
    );
  }

  Widget _buildHelpText(ThemeData theme) {
    return TextButton(
      onPressed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1E2643),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: const Text(
              "Please contact the Store Manager for password reset.",
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        );
      },
      child: Text(
        'Forgot ID or Password?',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          decoration: TextDecoration.underline,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildFooter(ThemeData theme) {
    return Column(
      children: [
        Divider(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
          indent: 20.w,
          endIndent: 20.w,
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.security,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            SizedBox(width: 1.w),
            Text(
              'SLFM Furniture Showroom',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'SLFM Universe 4.5.1 $_appVersion',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            fontSize: 9.sp,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            final url =
                Uri.parse('https://vasanth5545.github.io/slfm-privacy/');
            if (await canLaunchUrl(url)) {
              await launchUrl(url, mode: LaunchMode.externalApplication);
            }
          },
          child: Text(
            'Privacy Policy',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary.withValues(alpha: 0.8),
              decoration: TextDecoration.underline,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
