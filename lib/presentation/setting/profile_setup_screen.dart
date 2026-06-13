import 'package:flutter/material.dart';
import 'package:slfm_salesman_app/services/activity_logger.dart';
import 'package:lottie/lottie.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:fluentui_emoji_icon/fluentui_emoji_icon.dart';
import 'package:sizer/sizer.dart';
import '../../services/secure_storage_service.dart';
import '../../core/constants/api_urls.dart';
import '../../core/services/secure_http_client.dart' as http;
import '../leaderboard/leaderboard_screen.dart';
import '../../core/constants/animal_data.dart';
import '../../widgets/profile_image_widget.dart';
import 'package:slfm_salesman_app/core/theme/app_colors.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../../routes/app_routes.dart';
import '../../core/utils/permission_guard.dart';
import '../../core/utils/image_picker_guard.dart';

class ProfileSetupScreen extends StatefulWidget {
  final UserModel currentUser;
  final Function(AvatarConfig) onSave;

  const ProfileSetupScreen({
    super.key,
    required this.currentUser,
    required this.onSave,
  });

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  late String selectedAnimal;
  String? photoUrl;
  File? _imageFile;
  bool _isUploading = false;
  Set<String> _takenAnimals = {}; // 🔥 Track taken animals
  int _scarfaceLimit = 1000; // 🔥 Dynamic from DB
  String? _previewAnimal; // 🔥 For Scarface Preview
  final double _crownOffset = -150.0; // 🔥 ADJUST CROWN TOP/BOTTOM HERE
  final double _lionOffset = 0.0; // 🔥 ADJUST LION TOP/BOTTOM HERE
  final double _crownSize = 220.0; // 🔥 ADJUST CROWN SIZE HERE
  bool _isPickingImage =
      false; // 🛡️ Flag to prevent concurrent image picker calls

  @override
  void initState() {
    super.initState();
    selectedAnimal = widget.currentUser.avatarConfig.animal ?? 'Monkey';
    photoUrl = widget.currentUser.avatarConfig.photoUrl;
    _fetchTakenAnimals();
  }

  Future<void> _fetchTakenAnimals() async {
    try {
      final response = await http.get(Uri.parse(ApiUrl.getLeaderboard));
      final result = jsonDecode(response.body);
      if (result['status'] == 'success') {
        // Extract Dynamic Config
        if (result['rewards_config'] != null) {
          _scarfaceLimit = result['rewards_config']['scarface_limit'] ?? 1000;
        }

        Set<String> taken = {};
        for (var user in result['data']) {
          // Identify animals used by OTHERS
          if (user['empId'] != widget.currentUser.empId &&
              user['avatar_animal'] != null &&
              user['avatar_animal'].toString().isNotEmpty &&
              user['avatar_animal'].toString() != "0") {
            taken.add(user['avatar_animal']);
          }
        }
        if (mounted) {
          setState(() {
            _takenAnimals = taken;
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching taken animals: $e");
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_isPickingImage) return; // 🛑 Already picking, ignore
    _isPickingImage = true;

    // 🛡️ Guard: Request Camera Permission before opening picker
    if (source == ImageSource.camera) {
      final granted =
          await PermissionGuard.run(() => Permission.camera.request());
      if (granted != PermissionStatus.granted) {
        debugPrint("Camera Permission Denied");
        _isPickingImage = false;
        return;
      }
    }

    final picker = ImagePicker();
    try {
      final pickedFile = await ImagePickerGuard.run(() => picker.pickImage(
            source: source,
            maxWidth: 800,
            maxHeight: 800,
            imageQuality: 70,
          ));

      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
          photoUrl = null; // Clear existing network photo if any
        });
      }
    } on PlatformException catch (e) {
      debugPrint("Platform Error: ${e.code} - ${e.message}");
      if (e.code == 'no_available_camera') {
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text("Camera Not Found"),
              content: const Text(
                  "It seems your device doesn't have a camera available or it is being restricted."),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("OK"),
                ),
              ],
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Camera Error: ${e.message}")),
          );
        }
      }
    } finally {
      _isPickingImage = false; // 🔓 Release flag
    }
  }

  void _removePhoto() {
    setState(() {
      _imageFile = null;
      photoUrl = null;
    });
  }

  Future<void> _saveProfile() async {
    setState(() => _isUploading = true);

    try {
      String? uploadedPath;

      // 1. Upload Photo if selected
      if (_imageFile != null) {
        final bytes = await _imageFile!.readAsBytes();
        final base64Image = base64Encode(bytes);

        final response = await http.post(
          Uri.parse(ApiUrl.uploadProfile),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'salesman_id': widget.currentUser.empId,
            'avatar_animal': selectedAnimal,
            'showroom': widget.currentUser.showroomName,
            'image': base64Image,
          }),
        );

        final result = jsonDecode(response.body);
        if (result['status'] == 'success') {
          uploadedPath = result['profile_photo'];
        } else {
          throw Exception(result['message'] ?? "Upload failed");
        }
      } else if (photoUrl == null) {
        // Explicitly clear photo on server if removed
        await http.post(
          Uri.parse(ApiUrl.uploadProfile),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'salesman_id': widget.currentUser.empId,
            'avatar_animal': selectedAnimal,
            'clear_photo': true,
          }),
        );
      } else {
        // Just update animal if photo is unchanged
        await http.post(
          Uri.parse(ApiUrl.uploadProfile),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'salesman_id': widget.currentUser.empId,
            'avatar_animal': selectedAnimal,
          }),
        );
      }

      // 2. Update Local Storage
      await SecureStorageService.writeString('avatar_animal', selectedAnimal);
      if (uploadedPath != null) {
        await SecureStorageService.writeString('profile_photo', uploadedPath);
      } else if (_imageFile == null && photoUrl == null) {
        await SecureStorageService.writeString('profile_photo', '');
      }

      // 3. Callback to refresh UI
      final newConfig = AvatarConfig(
        emoji: '',
        animal: selectedAnimal,
        photoUrl: uploadedPath ?? photoUrl,
      );
      widget.onSave(newConfig);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.white,
            content: Text("Profile updated successfully! ✅",
                style: TextStyle(
                    color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        );
      }
    } catch (e) {
      debugPrint("Save Error: $e");
      if (mounted) {
        try { ActivityLogger.instance.logError('UI', 'Snackbar error shown'); } catch(_) {}
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.white,
            content: Text("Error: ${e.toString()}",
                style: const TextStyle(
                    color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _logout() async {
    final colors = AppColors.of(context);
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text("Logout?", style: TextStyle(color: colors.textPrimary)),
        content: Text(
          "Are you sure you want to logout? You can quickly switch back to this account later from the switcher.",
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("CANCEL"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text("LOGOUT"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (mounted) setState(() => _isUploading = true);
      try {
        await SecureStorageService.logoutCurrentAccount();

        // Stop background services if any
        try {
          final service = FlutterBackgroundService();
          if (await service.isRunning()) {
            service.invoke("stopService");
          }
        } catch (e) {
          debugPrint("Error stopping service: $e");
        }

        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            AppRoutes.login,
            (route) => false,
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Logout error: $e")),
          );
        }
      } finally {
        if (mounted) setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        title: Text('Profile Customization',
            style: TextStyle(color: colors.textPrimary)),
        backgroundColor: colors.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: _logout,
            tooltip: "Logout Account",
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Column(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(vertical: 4.h),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        colors.bg,
                        colors.surface,
                      ],
                    ),
                  ),
                  child: Column(
                    children: [
                      Center(
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(
                                  bottom: 15, right: 15, left: 15),
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: colors.neonBlue, width: 3),
                              ),
                              child: _imageFile != null
                                  ? CircleAvatar(
                                      radius: 57,
                                      backgroundImage: FileImage(_imageFile!),
                                    )
                                  : ProfileImageWidget(
                                      profilePhoto: photoUrl,
                                      avatarAnimal:
                                          _previewAnimal ?? selectedAnimal,
                                      name: widget.currentUser.name,
                                      size: 114,
                                    ),
                            ),
                            Positioned(
                              bottom: 15,
                              child: GestureDetector(
                                onTap: () => _pickImage(ImageSource.camera),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: colors.neonBlue,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.camera_alt,
                                      color: Colors.white, size: 20),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 10,
                              right: 15,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: colors.surface,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: colors.textPrimary, width: 1.5),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.5),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    )
                                  ],
                                ),
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: AnimalData.getAssetPath(
                                              _previewAnimal ??
                                                  selectedAnimal) !=
                                          null
                                      ? Image.asset(
                                          AnimalData.getAssetPath(
                                              _previewAnimal ??
                                                  selectedAnimal)!,
                                          fit: BoxFit.contain,
                                        )
                                      : FluentUiEmojiIcon(
                                          fl: AnimalData.getIcon(
                                                  _previewAnimal ??
                                                      selectedAnimal) ??
                                              Fluents.flMonkey,
                                          w: 24,
                                          h: 24,
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        widget.currentUser.name,
                        style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 18.sp,
                            fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 1.h),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_imageFile != null || photoUrl != null) ...[
                            TextButton.icon(
                              onPressed: () => _pickImage(ImageSource.camera),
                              icon: Icon(Icons.refresh, color: colors.neonBlue),
                              label: Text("RE-TAKE",
                                  style: TextStyle(color: colors.neonBlue)),
                            ),
                            const SizedBox(width: 10),
                            TextButton.icon(
                              onPressed: _removePhoto,
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.redAccent),
                              label: const Text("REMOVE",
                                  style: TextStyle(color: Colors.redAccent)),
                            ),
                          ] else
                            Text(
                              "Add a real photo for a premium look!",
                              style: TextStyle(
                                  color: colors.textSecondary, fontSize: 10),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 5.w, vertical: 2.h),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(30),
                        topRight: Radius.circular(30),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Choose Your Avatar Animal",
                          style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 1.h),
                        Expanded(
                          child: GridView.builder(
                            itemCount: AnimalData.animals.length,
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              childAspectRatio: 1,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                            ),
                            itemBuilder: (context, index) {
                              final animalMap = AnimalData.animals[index];
                              final animalName = animalMap['name'] as String;
                              final isSelected = selectedAnimal == animalName;
                              final bool isTaken =
                                  _takenAnimals.contains(animalName);
                              bool isLocked = false;
                              String lockMsg = "";

                              if (animalName.toLowerCase() == 'scarface lion' &&
                                  widget.currentUser.score < _scarfaceLimit) {
                                isLocked = true;
                                lockMsg = "Reach $_scarfaceLimit billed!";
                              } else if (animalName == 'Lion' &&
                                  widget.currentUser.currentRank != 1) {
                                isLocked = true;
                                lockMsg = "Only for Rank #1";
                              } else if (animalName == 'Tiger' &&
                                  widget.currentUser.currentRank != 2) {
                                isLocked = true;
                                lockMsg = "Only for Rank #2";
                              } else if (animalName == 'Elephant' &&
                                  widget.currentUser.currentRank != 3) {
                                isLocked = true;
                                lockMsg = "Only for Rank #3";
                              }

                              final String? assetPath =
                                  AnimalData.getAssetPath(animalName);

                              return GestureDetector(
                                onTap: (isLocked || isTaken)
                                    ? () {
                                        if (animalName.toLowerCase() ==
                                            'scarface lion') {
                                          _triggerScarfacePreview();
                                          return;
                                        }
                                        ScaffoldMessenger.of(context)
                                            .clearSnackBars();
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            backgroundColor: colors.surface,
                                            content: Text(
                                              isTaken
                                                  ? "👤 Already taken by another salesman!"
                                                  : "🔒 $lockMsg",
                                              style: TextStyle(
                                                  color: colors.textPrimary,
                                                  fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        );
                                      }
                                    : () {
                                        setState(
                                            () => selectedAnimal = animalName);
                                      },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? colors.neonBlue.withValues(alpha: 0.1)
                                        : colors.bg,
                                    borderRadius: BorderRadius.circular(15),
                                    border: Border.all(
                                      color: isSelected
                                          ? colors.neonBlue
                                          : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Opacity(
                                        opacity:
                                            (isLocked || isTaken) ? 0.2 : 1.0,
                                        child: assetPath != null
                                            ? Image.asset(assetPath,
                                                width: 32, height: 32)
                                            : FluentUiEmojiIcon(
                                                fl: AnimalData.getIcon(
                                                        animalName) ??
                                                    Fluents.flMonkey,
                                                w: 32,
                                                h: 32,
                                              ),
                                      ),
                                      if (isLocked)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 4, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: colors.surface
                                                .withValues(alpha: 0.7),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            "RANKED",
                                            style: GoogleFonts.inter(
                                              fontSize: 7,
                                              color: colors.textPrimary,
                                              letterSpacing: 0.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      if (isTaken && !isLocked)
                                        Icon(Icons.person,
                                            color: Colors.red
                                                .withValues(alpha: 0.8),
                                            size: 22),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.fromLTRB(5.w, 1.h, 5.w, 3.h),
                  color: colors.surface,
                  child: SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _isUploading ? null : _saveProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.neonBlue,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15)),
                        elevation: 0,
                      ),
                      child: _isUploading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              "SAVE PROFILE",
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ),
                Text(
                  "Account Switcher",
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          if (_previewAnimal != null) _buildScarfacePreview(context),
        ],
      ),
    );
  }

  void _triggerScarfacePreview() {
    setState(() {
      _previewAnimal = 'Scarface Lion';
    });
  }

  Widget _buildScarfacePreview(BuildContext context) {
    final colors = AppColors(Theme.of(context).brightness == Brightness.dark);
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => _previewAnimal = null),
        onPanStart: (_) {},
        onPanUpdate: (_) {},
        onPanEnd: (_) {},
        onPanCancel: () {},
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: Colors.black.withValues(alpha: 0.85),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 500),
            curve: Curves.elasticOut,
            builder: (context, value, child) {
              return Transform.scale(
                scale: value,
                child: Opacity(
                  opacity: value.clamp(0.0, 1.0),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 250,
                          height: 250,
                          decoration: const BoxDecoration(
                              // 🔥 REMOVED CIRCLE SHAPE TO PREVENT CROWNS FROM BEING CUT OFF
                              ),
                          child: Stack(
                            alignment: Alignment.center,
                            clipBehavior:
                                Clip.none, // 🔥 Allow crown to breakout
                            children: [
                              // 🔥 1. BLACK CIRCLE BACKGROUND (REQUIRED)
                              Container(
                                width: 180,
                                height: 180,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0D1025),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white54,
                                    width: 3,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: colors.gold
                                          .withValues(alpha: 0.2 * value),
                                      blurRadius: 40,
                                      spreadRadius: 10,
                                    ),
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.8),
                                      blurRadius: 30,
                                      spreadRadius: 5,
                                    )
                                  ],
                                ),
                              ),
                              Transform.translate(
                                offset: Offset(0, _lionOffset),
                                child: Image.asset(
                                  'assets/leaderboard/SCARFACE_LION.png',
                                  width: 230,
                                  height: 230,
                                  fit: BoxFit.contain,
                                ),
                              ),
                              // 🔥 2. CROWN POSITIONED ABOVE THE HEAD
                              Transform.translate(
                                offset: Offset(0, _crownOffset),
                                child: Lottie.asset(
                                  'assets/leaderboard/Crown.json',
                                  width: _crownSize,
                                  height: _crownSize,
                                  fit: BoxFit.contain,
                                  repeat: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          "SCARFACE LION",
                          style: GoogleFonts.orbitron(
                            color: Colors.amber,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                            shadows: [
                              Shadow(
                                  color: Colors.amber.withValues(alpha: 0.5),
                                  blurRadius: 10),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "REACH $_scarfaceLimit BILLED TO UNLOCK!",
                          style: GoogleFonts.orbitron(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 40),
                        Text(
                          "STRIKE FAST. RULE THE PACK.",
                          style: GoogleFonts.inter(
                            color: Colors.white24,
                            fontSize: 10,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
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
}
