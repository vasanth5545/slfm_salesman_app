import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:slfm_salesman_app/core/app_export.dart';
import 'package:slfm_salesman_app/services/secure_storage_service.dart';
import 'package:sizer/sizer.dart';
import 'package:slfm_salesman_app/core/services/secure_http_client.dart'
    as http;
import 'package:fluentui_emoji_icon/fluentui_emoji_icon.dart';
import '../../../../core/constants/animal_data.dart';
import '../../../../core/theme/app_colors.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../../../../core/utils/permission_guard.dart';
import '../../../../core/utils/image_picker_guard.dart';

class ProfileSetupOverlay extends StatefulWidget {
  final VoidCallback onComplete;

  const ProfileSetupOverlay({super.key, required this.onComplete});

  @override
  State<ProfileSetupOverlay> createState() => _ProfileSetupOverlayState();
}

class _ProfileSetupOverlayState extends State<ProfileSetupOverlay> {
  File? _imageFile;
  String? _selectedAnimal;
  bool _isUploading = false;
  List<String> _takenAnimals = [];
  bool _isPickingImage = false; // 🛡️ Guard
  bool _isLoadingAvailability = true;

  final List<Map<String, dynamic>> _animals = AnimalData.animals;

  int _billedCount = 0;
  int _userRank = 999;

  Map<String, dynamic>? get _selectedAnimalData =>
      _animals.firstWhere((a) => a['name'] == _selectedAnimal,
          orElse: () => _animals[0]);

  @override
  void initState() {
    super.initState();
    _fetchAvailability();
  }

  Future<void> _fetchAvailability() async {
    try {
      final salesmanId = await SecureStorageService.getSalesmanId();

      // 1. Fetch Taken Animals
      final response = await http.SecureHttpClient.get(
          Uri.parse(ApiUrl.getAvatarAvailability));

      // 2. Fetch User Stats for Locking (Simulated or via API if available)
      // Assuming we can fetch stats or it's provided.
      // For now, let's fetch leaderboard data to find rank/billed
      final lbResponse =
          await http.SecureHttpClient.get(Uri.parse(ApiUrl.getLeaderboard));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted && data['status'] == 'success') {
          setState(() {
            _takenAnimals = List<String>.from(data['taken_animals'] ?? []);
            _isLoadingAvailability = false;
          });
        }
      }

      if (lbResponse.statusCode == 200) {
        final lbData = json.decode(lbResponse.body);
        if (mounted && lbData['status'] == 'success') {
          final list = lbData['leaderboard'] as List;
          final myIndex =
              list.indexWhere((s) => s['salesman_id'] == salesmanId);
          if (myIndex != -1) {
            setState(() {
              _userRank = myIndex + 1;
              _billedCount =
                  int.tryParse(list[myIndex]['billed_count'].toString()) ?? 0;
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Error fetching profile setup data: $e");
      if (mounted) setState(() => _isLoadingAvailability = false);
    }
  }

  Future<void> _pickImage() async {
    if (_isPickingImage) return; // 🛑 Already picking, ignore
    _isPickingImage = true;

    // 🛡️ Guard: Request Camera Permission before opening picker
    final granted =
        await PermissionGuard.run(() => Permission.camera.request());
    if (granted != PermissionStatus.granted) {
      debugPrint("Camera Permission Denied");
      _isPickingImage = false;
      return;
    }

    final picker = ImagePicker();
    try {
      final pickedFile = await ImagePickerGuard.run(() => picker.pickImage(
            source: ImageSource.camera,
            preferredCameraDevice: CameraDevice.front,
            imageQuality: 50,
            maxWidth: 800,
          ));

      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
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

  Future<void> _submitProfile() async {
    if (_imageFile == null || _selectedAnimal == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Please upload a photo and pick an animal!")),
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      final salesmanId = await SecureStorageService.getSalesmanId();
      final showroom = await SecureStorageService.getShowroomName();
      final bytes = await _imageFile!.readAsBytes();
      final base64Image = base64Encode(bytes);

      final response = await http.SecureHttpClient.post(
        Uri.parse(ApiUrl.uploadProfile),
        body: jsonEncode({
          'salesman_id': salesmanId,
          'showroom': showroom,
          'image': base64Image,
          'avatar_animal': _selectedAnimal,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          // Update local storage with fallback protection
          final photoPath = data['profile_photo'] ?? data['path'];
          final animalPath = data['avatar_animal'] ?? _selectedAnimal;

          if (photoPath != null) {
            await SecureStorageService.writeString('profile_photo', photoPath);
          }
          if (animalPath != null) {
            await SecureStorageService.writeString('avatar_animal', animalPath);
          }

          if (mounted) {
            widget.onComplete();
          }
        } else {
          throw Exception(data['message'] ?? 'Upload failed');
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _logout() async {
    final colors = AppColors(Theme.of(context).brightness == Brightness.dark);
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text("Logout?", style: TextStyle(color: colors.textPrimary)),
        content: Text(
          "Are you sure you want to logout? You can quickly switch back to this account later.",
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
    final colors = AppColors(Theme.of(context).brightness == Brightness.dark);
    return Material(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: Container(
          width: 90.w,
          constraints: BoxConstraints(maxHeight: 85.h),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: colors.textPrimary.withValues(alpha: 0.2),
                blurRadius: 40,
                spreadRadius: 5,
              )
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.fromLTRB(6.w, 4.h, 6.w, 2.h),
                  decoration: BoxDecoration(
                    border: Border(
                        bottom: BorderSide(
                            color: colors.divider.withValues(alpha: 0.1))),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Column(
                        children: [
                          Text(
                            "INITIAL SETUP",
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 16.sp,
                              letterSpacing: 2,
                            ),
                          ),
                          SizedBox(height: 1.h),
                          Text(
                            "Complete your profile to join the legends",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 10.sp,
                            ),
                          ),
                        ],
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: IconButton(
                          icon: Icon(Icons.logout,
                              color: Colors.redAccent, size: 22),
                          onPressed: _logout,
                          tooltip: "Logout",
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 4.h),

                // Photo & Avatar Preview
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 40.w,
                      height: 40.w,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: colors.neonBlue.withValues(alpha: 0.2),
                            blurRadius: 20,
                            spreadRadius: 2,
                          )
                        ],
                      ),
                    ),
                    Container(
                      width: 35.w,
                      height: 35.w,
                      decoration: BoxDecoration(
                        color: colors.bg,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _imageFile != null || _selectedAnimal != null
                              ? colors.neonBlue
                              : colors.divider,
                          width: 3,
                        ),
                      ),
                      child: _imageFile != null
                          ? ClipOval(
                              child: Image.file(_imageFile!, fit: BoxFit.cover))
                          : (_selectedAnimal != null
                              ? Center(
                                  child: FluentUiEmojiIcon(
                                    fl: _selectedAnimalData!['icon'],
                                    w: 22.w,
                                    h: 22.w,
                                  ),
                                )
                              : Icon(Icons.person_outline,
                                  color: colors.textSecondary, size: 50)),
                    ),
                    // Badge Overlay - Bottom Right
                    if (_imageFile != null && _selectedAnimal != null)
                      Positioned(
                        bottom: 0,
                        right: 2.w,
                        child: Container(
                          padding: EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: colors.surface,
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: colors.neonBlue, width: 2),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black45,
                                  blurRadius: 4,
                                  offset: Offset(2, 2))
                            ],
                          ),
                          child: FluentUiEmojiIcon(
                            fl: _selectedAnimalData!['icon'],
                            w: 12.w,
                            h: 12.w,
                          ),
                        ),
                      ),
                  ],
                ),

                SizedBox(height: 2.h),

                // Explicit Upload Button
                OutlinedButton.icon(
                  onPressed: _pickImage,
                  icon: Icon(Icons.camera_alt_rounded, size: 18),
                  label: Text(_imageFile == null ? "UPLOAD PHOTO" : "RE-TAKE"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.neonBlue,
                    side: BorderSide(color: colors.neonBlue),
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),

                SizedBox(height: 3.h),

                // Info Box
                Container(
                  margin: EdgeInsets.symmetric(horizontal: 6.w),
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.neonBlue.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: colors.neonBlue.withValues(alpha: 0.1)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "* Top 3 Animals are locked.",
                        style: TextStyle(
                            color: colors.neonBlue,
                            fontSize: 10.sp,
                            fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              "* Scarface Lion unlocks at 1000 Billed Customers!",
                              style: TextStyle(
                                  color: colors.textSecondary, fontSize: 9.sp),
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(Icons.lock, color: colors.neonBlue, size: 12),
                        ],
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 3.h),

                // Animal Picker
                Text(
                  "SELECT YOUR CHAMPION",
                  style: TextStyle(
                    color: colors.textPrimary.withValues(alpha: 0.8),
                    fontWeight: FontWeight.bold,
                    fontSize: 10.sp,
                    letterSpacing: 1.2,
                  ),
                ),
                SizedBox(height: 2.h),
                if (_isLoadingAvailability)
                  CircularProgressIndicator(color: colors.neonBlue)
                else
                  Container(
                    height: 25.h,
                    padding: EdgeInsets.symmetric(horizontal: 6.w),
                    child: GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                      ),
                      itemCount: _animals.length,
                      itemBuilder: (context, index) {
                        final animal = _animals[index];
                        final isTaken = _takenAnimals.contains(animal['name']);
                        final isSelected = _selectedAnimal == animal['name'];

                        // Locking Logic
                        bool isLockedByRank = false;
                        if (animal['isTop3'] == true) {
                          if (animal['name'] == 'Lion' && _userRank != 1) {
                            isLockedByRank = true;
                          }
                          if (animal['name'] == 'Tiger' && _userRank != 2) {
                            isLockedByRank = true;
                          }
                          if (animal['name'] == 'Elephant' && _userRank != 3) {
                            isLockedByRank = true;
                          }
                        }

                        bool isLockedByAchievement = false;
                        if (animal['isScarface'] == true &&
                            _billedCount < 1000) {
                          isLockedByAchievement = true;
                        }

                        final isLocked =
                            isLockedByRank || isLockedByAchievement;

                        return GestureDetector(
                          onTap: (isTaken || isLocked)
                              ? null
                              : () => setState(
                                  () => _selectedAnimal = animal['name']),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? colors.neonBlue.withValues(alpha: 0.1)
                                  : colors.textPrimary.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected
                                    ? colors.neonBlue
                                    : (isLocked || isTaken
                                        ? Colors.transparent
                                        : colors.divider
                                            .withValues(alpha: 0.2)),
                                width: 1.5,
                              ),
                            ),
                            child: Stack(
                              children: [
                                Center(
                                  child: Opacity(
                                    opacity: (isTaken || isLocked) ? 0.3 : 1.0,
                                    child: FluentUiEmojiIcon(
                                      fl: animal['icon'],
                                      w: 30,
                                      h: 30,
                                    ),
                                  ),
                                ),
                                if (isTaken || isLocked)
                                  Positioned(
                                    top: 2,
                                    right: 2,
                                    child: Icon(
                                        isTaken ? Icons.person_off : Icons.lock,
                                        color: Colors.red,
                                        size: 14),
                                  ),
                                Positioned(
                                  bottom: 2,
                                  left: 0,
                                  right: 0,
                                  child: Text(
                                    animal['name'],
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: (isTaken || isLocked)
                                          ? colors.textSecondary
                                              .withValues(alpha: 0.5)
                                          : colors.textPrimary,
                                      fontSize: 8.sp,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                SizedBox(height: 4.h),

                // Save Button
                Padding(
                  padding: EdgeInsets.all(6.w),
                  child: SizedBox(
                    width: double.infinity,
                    height: 6.h,
                    child: ElevatedButton(
                      onPressed: _isUploading ? null : _submitProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.neonBlue,
                        foregroundColor: colors.surface,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 5,
                      ),
                      child: _isUploading
                          ? CircularProgressIndicator(color: colors.surface)
                          : Text(
                              "SAVE PROFILE",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.1),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
