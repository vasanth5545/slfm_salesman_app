import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// A global guard to prevent "Image picker is already active" crashes.
/// 🚀 Serializes all image picking requests across the app.
class ImagePickerGuard {
  static Future<void>? _pending;

  /// Executes an image picking action, waiting for any existing picker to close.
  /// 
  /// Returns the result of the [pickerAction].
  /// Includes a safety delay after completion to ensure native stability.
  static Future<XFile?> run(Future<XFile?> Function() pickerAction) async {
    // 1. Capture the previous task (if any) and set up our lock
    final previous = _pending;
    final completer = Completer<void>();
    _pending = completer.future;

    // 2. Wait for previous picker to FULLY finish (including its delay)
    if (previous != null) {
      debugPrint("⏳ ImagePickerGuard: Waiting for active picker to finish...");
      await previous;
    }

    debugPrint("🔐 ImagePickerGuard: Lock acquired.");
    
    try {
      final result = await pickerAction();
      return result;
    } on PlatformException catch (e) {
      debugPrint("❌ ImagePickerGuard: Platform Error: ${e.code}");
      
      // 🛡️ Handle "already_active" gracefully
      if (e.code == 'already_active') {
        debugPrint("⚠️ ImagePickerGuard: Caught 'already_active'. Returning null to prevent crash.");
        return null;
      }
      rethrow; // Rethrow other platform errors (like no_camera)
    } catch (e) {
      debugPrint("❌ ImagePickerGuard: Error during picking: $e");
      return null;
    } finally {
      // 💡 Crucial: Delay after the native picker closes.
      // Android 15 / Oppo devices need time to settle the activity state.
      await Future.delayed(const Duration(milliseconds: 1500));
      
      // Release lock
      completer.complete();
      debugPrint("🔓 ImagePickerGuard: Lock released.");
    }
  }
}
