import 'dart:convert';
import 'package:slfm_salesman_app/services/activity_logger.dart';
import 'dart:io';
import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:slfm_salesman_app/core/services/secure_http_client.dart'
    as http;
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import '../../services/secure_storage_service.dart';
import 'package:sizer/sizer.dart';

import '../../core/app_export.dart';
import '../../widgets/custom_app_bar.dart';
import './widgets/damage_form_widget.dart';
import './widgets/damage_image_picker_widget.dart';

class DamageScreen extends StatefulWidget {
  const DamageScreen({super.key});

  @override
  State<DamageScreen> createState() => _DamageScreenState();
}

class _DamageScreenState extends State<DamageScreen> {
  final _osCodeController = TextEditingController();
  final _brandController = TextEditingController();
  final _modelController = TextEditingController();
  final _rateController = TextEditingController();
  final _descController = TextEditingController();

  List<XFile> _selectedImages = [];
  bool _isLoading = false;
  bool _isInitialLoading = true; // 🔥 NEW: Track initial load
  String _salesmanId = "";
  String _showroomName = "";
  bool _isDamageReportVisible = true;
  StreamSubscription<DatabaseEvent>? _visibilitySubscription;

  // ⚠️ Create this file: damage_report.php
  final String _apiUrl = "${ApiUrl.baseUrl}/damage_report.php";

  @override
  void initState() {
    super.initState();
    _loadSalesmanData();
  }

  void _listenToVisibility() {
    if (_showroomName.isEmpty) {
      return;
    }
    _visibilitySubscription?.cancel();

    final showroom = _showroomName.toLowerCase();
    _visibilitySubscription = FirebaseDatabase.instance
        .ref('features/$showroom/damage_report_visible')
        .onValue
        .listen((event) {
      if (event.snapshot.value != null && mounted) {
        bool visible = true;
        final val = event.snapshot.value;
        if (val is bool) {
          visible = val;
        } else if (val is num) {
          visible = val == 1;
        } else if (val is String) {
          visible = (val == "1" || val == "true");
        }

        setState(() {
          _isDamageReportVisible = visible;
        });
      }
    });
  }

  Future<void> _loadSalesmanData() async {
    final id = await SecureStorageService.getSalesmanId();
    final showroom =
        await SecureStorageService.readString('showroom_name') ?? '';
    setState(() {
      _salesmanId = id ?? "";
      _showroomName = showroom;
      _isInitialLoading = false; // 🔥 Stop loading when data is ready
    });
    _listenToVisibility();
  }

  @override
  void dispose() {
    _osCodeController.dispose();
    _brandController.dispose();
    _modelController.dispose();
    _rateController.dispose();
    _descController.dispose();
    _visibilitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _submitReport() async {
    if (_osCodeController.text.isEmpty || _descController.text.isEmpty) {
      try { ActivityLogger.instance.logError('UI', 'Snackbar error shown'); } catch(_) {}
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("OS Code and Description are mandatory!"),
            backgroundColor: Colors.red),
      );
      return;
    }

    if (_selectedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Please upload at least 1 photo"),
            backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 🔥 FIX: Compress images in a background isolate to prevent UI freeze
      // Without this, 3 raw 8MP photos = 24MB decoded in UI thread = OOM crash
      final Map<String, dynamic> compressedFiles = {};
      for (int i = 0; i < _selectedImages.length; i++) {
        final originalBytes = await File(_selectedImages[i].path).readAsBytes();
        final compressed = await compute(_compressImageIsolate, originalBytes);
        compressedFiles['image_$i'] = compressed;
        debugPrint(
            "📸 Image $i: ${originalBytes.length ~/ 1024}KB → ${compressed.length ~/ 1024}KB");
      }

      // 🔥 FIX: Use centralized retry helper for 2G/3G resilience
      final response = await http.postMultipartWithRetry(
        Uri.parse(_apiUrl),
        fields: {
          'action': 'report_damage',
          'salesman_id': _salesmanId,
          'os_code': _osCodeController.text.trim(),
          'brand': _brandController.text.trim(),
          'model': _modelController.text.trim(),
          'rate': _rateController.text.trim(),
          'description': _descController.text.trim(),
        },
        files: compressedFiles,
        maxRetries: 2,
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['status'] == 'success') {
        _showSuccessDialog();
      } else {
        _showError(data['message'] ?? "Upload Failed");
      }
    } catch (e) {
      _showError("Connection Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Report Sent"),
        content: const Text(
            "Damage report submitted successfully. It will be visible to your showroom admin."),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx); // Close Dialog
              Navigator.pop(context); // Close Screen
            },
            child: const Text("OK"),
          )
        ],
      ),
    );
  }

  void _showError(String msg) {
    try { ActivityLogger.instance.logError('UI', 'Snackbar error shown'); } catch(_) {}
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: CustomAppBar(
        title: 'Report Damage',
        showBackButton: true,
        onBackPressed: () => Navigator.pop(context),
      ),
      body: SafeArea(
        child: _isInitialLoading
            ? Container(
                color: Colors.white,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                          color: theme.colorScheme.primary),
                      SizedBox(height: 2.h),
                      Text(
                        "Updating Report Status...",
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12.sp,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : SingleChildScrollView(
                padding: EdgeInsets.all(4.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Image Picker Section
                    Text("Upload Photos (Max 3)",
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    SizedBox(height: 1.5.h),
                    DamageImagePickerWidget(
                      onImagesSelected: (images) {
                        _selectedImages = images;
                      },
                    ),

                    SizedBox(height: 3.h),

                    // 2. Details Form
                    Text("Product Details",
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    SizedBox(height: 1.5.h),
                    DamageFormWidget(
                      osCodeController: _osCodeController,
                      brandController: _brandController,
                      modelController: _modelController,
                      rateController: _rateController,
                      descController: _descController,
                    ),

                    SizedBox(height: 4.h),

                    // 3. Submit Button
                    if (_isDamageReportVisible)
                      SizedBox(
                        width: double.infinity,
                        height: 6.h,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _submitReport,
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Colors.redAccent, // Red for Damage Alert
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2),
                                )
                              : const Text("Submit Report",
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold)),
                        ),
                      )
                    else
                      Container(
                        padding: EdgeInsets.all(4.w),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.red.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, color: Colors.red),
                            SizedBox(width: 3.w),
                            const Expanded(
                              child: Text(
                                "Damage reporting is currently disabled for your showroom.",
                                style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// 🔥 Top-level isolate function for image compression
/// Must be top-level (not inside a class) to work with compute()
List<int> _compressImageIsolate(Uint8List originalBytes) {
  try {
    final image = img.decodeImage(originalBytes);
    if (image != null) {
      img.Image resized = image;
      if (image.width > 800) {
        final targetH = (image.height * (800 / image.width)).round();
        resized = img.copyResize(image, width: 800, height: targetH);
      }
      return img.encodeJpg(resized, quality: 75);
    }
  } catch (_) {}
  // Fallback: return original if compression fails
  return originalBytes;
}
