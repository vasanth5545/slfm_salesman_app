import 'package:flutter/material.dart';
import 'package:slfm_salesman_app/main.dart'; // 🔥 Resolves globalSecurityGuardState
import '../../services/secure_storage_service.dart';
import 'package:sizer/sizer.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../services/theme_notifier.dart'; // 🔥 Import Notifier
import '../../core/database/local_db_helper.dart'; // 🔥 Fetch Stats
import '../../core/services/version_check_service.dart'; // 🔥 NEW: Update Check
import 'package:url_launcher/url_launcher.dart'; // 🔥 Launch URL
import 'package:audioplayers/audioplayers.dart'; // 🔥 Sound Preview
import '../../core/app_export.dart';
import '../../widgets/custom_app_bar.dart';
import '../leaderboard/leaderboard_screen.dart'; // 🔥 NEW: UserModel & AvatarConfig
import './profile_setup_screen.dart'; // 🔥 NEW: Navigation
import '../../widgets/profile_image_widget.dart';
import './activity_logs_screen.dart'; // 🔥 Admin audit trail

class SettingScreen extends StatefulWidget {
  const SettingScreen({super.key});

  @override
  State<SettingScreen> createState() => _SettingScreenState();
}

class _SettingScreenState extends State<SettingScreen>
    with TickerProviderStateMixin {
  late AnimationController _skeletonController;
  String _salesmanName = "Loading...";
  String _salesmanId = "";
  String _showroomName = "";
  String _profilePhoto = ""; // 🔥 New
  String _avatarAnimal = ""; // 🔥 New
  int _billedCount = 0; // 🔥 For locking special animals
  String _appVersion = "Loading..."; // 🔥 Dynamic Version
  String _userRole = "salesman"; // 🔥 Role-based filtering
  String _selectedTickSound = "sound1.mp3"; // 🔥 Tick Sound Selection
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _skeletonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _loadUserData();
    _loadAppVersion(); // 🔥 Fetch Version
  }

  @override
  void dispose() {
    _skeletonController.dispose();
    super.dispose();
  }

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = "Universe 4.5.1 v${info.version}";
      });
    }
  }

  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);
    final name = await SecureStorageService.getSalesmanName();
    final id = await SecureStorageService.getSalesmanId();
    final showroom = await SecureStorageService.getShowroomName();
    final photo = await SecureStorageService.readString('profile_photo');
    final animal = await SecureStorageService.readString('avatar_animal');
    final role = await SecureStorageService.getUserRole();
    final tickSound = await SecureStorageService.getTickSound();

    // Fetch stats for profile locking logic
    if (id != null) {
      final stats = await LocalDbHelper.instance.getWalkingStats(id);
      _billedCount = stats['billed'] ?? 0;
    }

    if (mounted) {
      setState(() {
        _salesmanName = name ?? "Salesman";
        _salesmanId = id ?? "";
        _showroomName = showroom ?? "Main Branch";
        _profilePhoto = photo ?? "";
        _avatarAnimal = animal ?? "";
        _userRole = role;
        _selectedTickSound = tickSound;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleLogout() async {
    await SecureStorageService.logoutCurrentAccount();

    // 🔥 STOP/RESET TRACKING & LISTENERS
    FlutterBackgroundService().invoke("updateSalesmanId", {"id": ""});
    globalSecurityGuardState
        ?.setupGlobalSuspensionAndPresence(); // Effectively clears listeners

    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.login,
        (route) => false,
      );
    }
  }

  void _showContactAdminMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.white),
            SizedBox(width: 8),
            Text("Contact Admin to change password"),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showSoundSelectionDialog() async {
    final List<Map<String, String>> sounds = [
      {'name': 'Default Tick 1', 'file': 'sound1.mp3'},
      {'name': 'Default Tick 2', 'file': 'sound2.mp3'},
      {'name': 'Default Tick 3', 'file': 'sound3.mp3'},
    ];

    final previewPlayer = AudioPlayer();

    await showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.symmetric(vertical: 2.h),
              child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Select Tick Sound',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              SizedBox(height: 1.h),
              ...sounds.map((sound) {
                return ListTile(
                  leading: Icon(
                    Icons.audiotrack,
                    color: _selectedTickSound == sound['file']
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  title: Text(
                    sound['name']!,
                    style: TextStyle(
                      fontWeight: _selectedTickSound == sound['file']
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  trailing: _selectedTickSound == sound['file']
                      ? Icon(Icons.check_circle,
                          color: Theme.of(context).colorScheme.primary)
                      : null,
                  onTap: () async {
                    // Save the choice
                    await SecureStorageService.saveTickSound(sound['file']!);
                    
                    // Update Main UI State
                    setState(() {
                      _selectedTickSound = sound['file']!;
                    });
                    // Update Modal UI State
                    setModalState(() {});
                    
                    // Preview Sound
                    await previewPlayer.setAudioContext(AudioContext(
                      android: const AudioContextAndroid(
                        isSpeakerphoneOn: false,
                        stayAwake: false,
                        contentType: AndroidContentType.sonification,
                        usageType: AndroidUsageType.notificationEvent,
                        audioFocus: AndroidAudioFocus.gainTransientMayDuck,
                      ),
                      iOS: AudioContextIOS(
                        category: AVAudioSessionCategory.ambient,
                      ),
                    ));
                    await previewPlayer.play(AssetSource('sounds/${sound['file']}'));
                  },
                );
              }),
              SizedBox(height: 2.h),
            ],
          ),
            );
          },
        );
      },
    );

    // Dispose player when modal closes
    previewPlayer.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: CustomAppBar(
        title: 'Settings',
        showBackButton: true,
        onBackPressed: () => Navigator.pop(context),
      ),
      body: _isLoading
          ? _buildSkeletonLoadingView(theme)
          : SingleChildScrollView(
              padding: EdgeInsets.all(4.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Profile Section
                  _buildSectionHeader(theme, 'Profile'),
                  SizedBox(height: 1.h),
                  _buildProfileCard(theme),
                  SizedBox(height: 1.h),
                  if (_userRole.toLowerCase() == 'salesman' ||
                      _userRole.toLowerCase() == 'promoter')
                    _buildSettingTile(
                      theme,
                      icon: 'person',
                      title: 'Leaderboard Profile Setup',
                      subtitle: 'Customize your avatar & photo',
                      onTap: () {
                        // Pass real data for the profile setup
                        final currentUser = UserModel(
                          id: int.tryParse(_salesmanId) ?? 0,
                          empId: _salesmanId,
                          name: _salesmanName,
                          score: _billedCount, // 🔥 REAL BILL COUNT
                          showroomName: _showroomName, // 🔥 PASS SHOWROOM
                          isLocal: true,
                          isCurrentUser: true,
                          avatarConfig: AvatarConfig(
                            emoji: '',
                            animal:
                                _avatarAnimal.isEmpty ? null : _avatarAnimal,
                            photoUrl:
                                _profilePhoto.isEmpty ? null : _profilePhoto,
                          ),
                        );

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ProfileSetupScreen(
                              currentUser: currentUser,
                              onSave: (newConfig) async {
                                debugPrint(
                                    "🎯 Saved New Profile: ${newConfig.animal}");
                                // Refresh user data to show new photo/animal immediately
                                await _loadUserData();
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  SizedBox(height: 3.h),

                  // General Settings (Modified - Removed Notifications)
                  _buildSectionHeader(theme, 'General'),
                  SizedBox(height: 1.h),
                  _buildSettingTile(
                    theme,
                    icon: 'language',
                    title: 'Language',
                    subtitle: 'English (Default)',
                    onTap: () {},
                  ),
                  _buildSettingTile(
                    theme,
                    icon: 'notifications_active',
                    title: 'Tick Sound',
                    subtitle: 'Selected: ${_selectedTickSound.replaceAll('.mp3', '')}',
                    onTap: _showSoundSelectionDialog,
                  ),
                  SizedBox(height: 3.h),

                  // Appearance Section (New)
                  _buildSectionHeader(theme, 'Appearance'),
                  SizedBox(height: 1.h),
                  _buildThemeSwitcher(theme),

                  SizedBox(height: 3.h),

                  // Security Section (Modified - Removed Biometric)
                  _buildSectionHeader(theme, 'Security'),
                  SizedBox(height: 1.h),
                  _buildSettingTile(
                    theme,
                    icon: 'lock_outline',
                    title: 'Change Password',
                    onTap: _showContactAdminMessage, // Shows "Contact Admin"
                  ),

                  SizedBox(height: 3.h),

                  // Admin Section
                  _buildSectionHeader(theme, 'Admin'),
                  SizedBox(height: 1.h),
                  _buildSettingTile(
                    theme,
                    icon: 'admin_panel_settings',
                    title: 'Activity Logs',
                    subtitle: 'View 3-day app activity',
                    onTap: () {
                      ActivityLogsGate.showPasswordDialog(context);
                    },
                  ),
                  SizedBox(height: 3.h),

                  // App Info
                  _buildSectionHeader(theme, 'About'),
                  SizedBox(height: 1.h),
                  _buildSettingTile(
                    theme,
                    icon: 'info_outline',
                    title: 'App Version',
                    subtitle: _appVersion,
                    showArrow: false,
                  ),
                  _buildSettingTile(
                    theme,
                    icon: 'system_update_outlined',
                    title: 'Check for Updates',
                    subtitle: 'Tap to check for new versions',
                    onTap: () {
                      // 🔥 TRIGGER MANUAL UPDATE CHECK
                      VersionCheckService()
                          .checkVersion(context, isManual: true);
                    },
                  ),
                  _buildSettingTile(
                    theme,
                    icon: 'privacy_tip_outlined',
                    title: 'Privacy Policy',
                    onTap: () async {
                      final Uri url = Uri.parse(
                          'https://vasanth5545.github.io/slfm-privacy/');
                      if (!await launchUrl(url,
                          mode: LaunchMode.externalApplication)) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                    Text('Could not launch privacy policy')),
                          );
                        }
                      }
                    },
                  ),

                  SizedBox(height: 4.h),

                  // Logout Button (Fixed Text Visibility)
                  SizedBox(
                    width: double.infinity,
                    height: 6.h,
                    child: ElevatedButton(
                      onPressed: _handleLogout,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD32F2F), // Red Color
                        foregroundColor: Colors.white, // White Text
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.logout, color: Colors.white),
                          SizedBox(width: 2.w),
                          const Text(
                            'Log Out',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 2.h),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: EdgeInsets.only(left: 2.w),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildProfileCard(ThemeData theme) {
    return Container(
      padding: EdgeInsets.all(4.w),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          ProfileImageWidget(
            name: _salesmanName,
            profilePhoto: _profilePhoto,
            avatarAnimal: _avatarAnimal,
            size: 60,
            fontSize: 24,
          ),
          SizedBox(width: 4.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _salesmanName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 0.5.h),
                Text(
                  'ID: $_salesmanId',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: 0.5.h),
                Text(
                  _showroomName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingTile(
    ThemeData theme, {
    required String icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    bool showArrow = true,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: 1.5.h),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: CustomIconWidget(
            iconName: icon,
            color: theme.colorScheme.onSurface,
            size: 20,
          ),
        ),
        title: Text(
          title,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            : null,
        trailing: showArrow
            ? Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
                size: 20,
              )
            : null,
      ),
    );
  }

  Widget _buildThemeSwitcher(ThemeData theme) {
    return ListenableBuilder(
      listenable: themeNotifier,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.1),
            ),
          ),
          child: Column(
            children: [
              _buildThemeOption(
                theme,
                mode: ThemeMode.light,
                title: 'Light Mode',
                icon: Icons.light_mode_outlined,
              ),
              Divider(
                height: 1,
                indent: 12.w,
                color: theme.colorScheme.outline.withValues(alpha: 0.05),
              ),
              _buildThemeOption(
                theme,
                mode: ThemeMode.dark,
                title: 'Dark Mode',
                icon: Icons.dark_mode_outlined,
              ),
              Divider(
                height: 1,
                indent: 12.w,
                color: theme.colorScheme.outline.withValues(alpha: 0.05),
              ),
              _buildThemeOption(
                theme,
                mode: ThemeMode.system,
                title: 'System Default',
                icon: Icons.settings_suggest_outlined,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildThemeOption(
    ThemeData theme, {
    required ThemeMode mode,
    required String title,
    required IconData icon,
  }) {
    final isSelected = themeNotifier.themeMode == mode;
    return InkWell(
      onTap: () => themeNotifier.setThemeMode(mode),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 1.8.h),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            SizedBox(width: 4.w),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w400,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                size: 20,
                color: theme.colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonLoadingView(ThemeData theme) {
    final baseColor =
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3);
    return SingleChildScrollView(
      padding: EdgeInsets.all(4.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(theme, 'Profile'),
          SizedBox(height: 1.h),
          FadeTransition(
            opacity: Tween<double>(begin: 0.4, end: 0.8)
                .animate(_skeletonController),
            child: Container(
              padding: EdgeInsets.all(4.w),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: baseColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: 4.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                            width: 150,
                            height: 20,
                            decoration: BoxDecoration(
                                color: baseColor,
                                borderRadius: BorderRadius.circular(4))),
                        SizedBox(height: 1.h),
                        Container(
                            width: 100,
                            height: 15,
                            decoration: BoxDecoration(
                                color: baseColor,
                                borderRadius: BorderRadius.circular(4))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 3.h),
          _buildSectionHeader(theme, 'General'),
          SizedBox(height: 1.h),
          _buildSkeletonTile(theme),
          SizedBox(height: 3.h),
          _buildSectionHeader(theme, 'Appearance'),
          SizedBox(height: 1.h),
          _buildSkeletonTile(theme),
          _buildSkeletonTile(theme),
          _buildSkeletonTile(theme),
        ],
      ),
    );
  }

  Widget _buildSkeletonTile(ThemeData theme) {
    final baseColor =
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3);
    return FadeTransition(
      opacity: Tween<double>(begin: 0.4, end: 0.8).animate(_skeletonController),
      child: Container(
        margin: EdgeInsets.only(bottom: 1.5.h),
        height: 70,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListTile(
          leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  color: baseColor, borderRadius: BorderRadius.circular(8))),
          title: Container(
              width: 120,
              height: 16,
              decoration: BoxDecoration(
                  color: baseColor, borderRadius: BorderRadius.circular(4))),
          subtitle: Container(
              width: 80,
              height: 12,
              decoration: BoxDecoration(
                  color: baseColor, borderRadius: BorderRadius.circular(4))),
        ),
      ),
    );
  }
}
