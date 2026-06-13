import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart'; // ⚠️ Add image_picker to pubspec.yaml
import 'package:sizer/sizer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import '../../../core/utils/permission_guard.dart';
import '../../../core/utils/image_picker_guard.dart';

import '../../../core/app_export.dart';
import '../../../widgets/custom_icon_widget.dart';

class DamageImagePickerWidget extends StatefulWidget {
  final Function(List<XFile>) onImagesSelected;

  const DamageImagePickerWidget({super.key, required this.onImagesSelected});

  @override
  State<DamageImagePickerWidget> createState() =>
      _DamageImagePickerWidgetState();
}

class _DamageImagePickerWidgetState extends State<DamageImagePickerWidget> {
  final List<XFile?> _images = [null, null, null]; // 3 Slots
  final ImagePicker _picker = ImagePicker();
  bool _isPickingImage = false; // 🛡️ Guard

  Future<void> _pickImage(int index) async {
    if (_isPickingImage) return; // 🛑 Already picking, ignore
    _isPickingImage = true;

    try {
      // 🛡️ Guard: Request Camera Permission before opening picker
      final granted =
          await PermissionGuard.run(() => Permission.camera.request());
      if (granted != PermissionStatus.granted) {
        debugPrint("Camera Permission Denied");
        _isPickingImage = false;
        return;
      }

      final XFile? image = await ImagePickerGuard.run(() => _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024, // Resize large 108MP photos
        maxHeight: 1024,
        imageQuality: 30, // Compress further for speed
      ));

      if (image != null) {
        setState(() {
          _images[index] = image;
        });
        // Send valid images back to parent
        widget.onImagesSelected(_images.whereType<XFile>().toList());
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
    } catch (e) {
      debugPrint("Error picking image: $e");
    } finally {
      _isPickingImage = false; // 🔓 Release flag
    }
  }

  void _removeImage(int index) {
    setState(() {
      _images[index] = null;
    });
    widget.onImagesSelected(_images.whereType<XFile>().toList());
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(3, (index) {
        return _buildImageSlot(index);
      }),
    );
  }

  Widget _buildImageSlot(int index) {
    final theme = Theme.of(context);
    bool hasImage = _images[index] != null;

    return GestureDetector(
      onTap: () => hasImage ? null : _pickImage(index),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 28.w,
            height: 28.w,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasImage
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: hasImage
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(
                      File(_images[index]!.path),
                      fit: BoxFit.cover,
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CustomIconWidget(
                        iconName: 'add_a_photo',
                        color: theme.colorScheme.onSurfaceVariant,
                        size: 24,
                      ),
                      SizedBox(height: 0.5.h),
                      Text(
                        "Photo ${index + 1}",
                        style: theme.textTheme.bodySmall,
                      )
                    ],
                  ),
          ),

          // Remove Button (Only if image exists)
          if (hasImage)
            Positioned(
              top: -8,
              right: -8,
              child: GestureDetector(
                onTap: () => _removeImage(index),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
