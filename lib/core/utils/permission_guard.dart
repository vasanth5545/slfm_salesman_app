import 'package:flutter/foundation.dart';
import 'dart:async';

/// A global guard to prevent concurrent permission requests which cause crashes on Android.
/// 🚀 UPGRADED: Now uses a serialized queue to ensure requests never overlap.
class PermissionGuard {
  static Future<void>? _pending;

  /// Executes a permission request action, waiting for any existing request to finish.
  ///
  /// Returns the result of the [requestAction].
  /// Includes a safety delay after completion to ensure native stability.
  static Future<T?> run<T>(Future<T> Function() requestAction) async {
    // 1. Capture the previous task (if any) and set up our lock
    final previous = _pending;
    final completer = Completer<void>();
    _pending = completer.future;

    // 2. Wait for previous request to FULLY finish (including its delay)
    if (previous != null) {
      debugPrint("⏳ PermissionGuard: Waiting for active request to finish...");
      await previous;
    }

    debugPrint("🔐 PermissionGuard: Lock acquired.");

    try {
      final result = await requestAction();
      return result;
    } catch (e) {
      debugPrint("❌ PermissionGuard: Error during request: $e");
      // If it's the "already running" error, it means something bypassed the guard.
      // We still return null to prevent crashing the app.
      return null;
    } finally {
      // 💡 Crucial: Small delay after the native dialog closes.
      // This prevents the "request already running" error if a second request
      // follows immediately after the first one's animation finishes.
      await Future.delayed(const Duration(milliseconds: 1200));

      // Release lock
      completer.complete();
      debugPrint("🔓 PermissionGuard: Lock released.");
    }
  }
}
