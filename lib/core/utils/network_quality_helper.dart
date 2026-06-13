import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Helper to determine network quality and suggest appropriate timeouts.
/// Helps the app remain resilient on 2G/3G while staying fast on 5G/WiFi.
class NetworkQualityHelper {
  /// 🔥 FIX 3: Real internet reachability check via DNS lookup.
  /// Works even when SIM + WiFi are both connected but one has no internet.
  /// Returns true only if actual internet access is verified.
  static Future<bool> hasRealInternet() async {
    // 1. Quick check using connectivity_plus to immediately fail if no interfaces are active
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.isEmpty ||
          (connectivityResult.length == 1 &&
              connectivityResult.first == ConnectivityResult.none)) {
        return false;
      }
    } catch (_) {}

    try {
      // 2. Try standard DNS lookup first (Fastest and standard way)
      // Increased timeout to 5s because some WiFi networks take longer to resolve initially.
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        return true;
      }
    } catch (_) {}

    try {
      // 3. Fallback: Connect to Google's IP on port 443 (HTTPS)
      // We use 443 instead of 53 because some ISPs block/intercept port 53 TCP.
      final socket = await Socket.connect('8.8.8.8', 443,
          timeout: const Duration(seconds: 5));
      socket.destroy();
      return true;
    } catch (_) {}

    try {
      // 4. Fallback 2: Cloudflare DNS
      final socket = await Socket.connect('1.1.1.1', 443,
          timeout: const Duration(seconds: 5));
      socket.destroy();
      return true;
    } catch (_) {}

    return false;
  }

  /// Returns a suggested timeout Duration based on the current connection.
  static Future<Duration> getRecommendedTimeout({
    Duration fastTimeout = const Duration(seconds: 15),
    Duration slowTimeout = const Duration(seconds: 45),
  }) async {
    final connectivityResult = await Connectivity().checkConnectivity();

    // If on mobile data, we check if it's likely to be slow (though connectivity_plus doesn't
    // give us the exact 2G/3G/4G/5G subtype on all platforms easily, we can assume
    // mobile is generally more variable than WiFi).
    if (connectivityResult.contains(ConnectivityResult.mobile)) {
      // In a real-world scenario, we could use another plugin to get 2G/3G/4G specifics.
      // For now, we'll provide a slightly more generous timeout for mobile.
      return const Duration(seconds: 25);
    }

    if (connectivityResult.contains(ConnectivityResult.none)) {
      return slowTimeout;
    }

    return fastTimeout;
  }

  /// Special case for heavy uploads (images/sync)
  static Future<Duration> getUploadTimeout() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.wifi)) {
      return const Duration(seconds: 30);
    }
    // Mobile or other: give it 60s to handle slow 2G/3G uploads
    return const Duration(seconds: 60);
  }
}
