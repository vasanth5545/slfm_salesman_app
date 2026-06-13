import 'package:http_certificate_pinning/http_certificate_pinning.dart';
import 'package:flutter/foundation.dart';

/// Service to handle SSL Certificate Pinning
/// Prevents Man-in-the-Middle (MITM) attacks by ensuring the app only
/// communicates with the server if the SSL fingerprint matches.
class SSLPinningService {
  // 🔒 Domain Fingerprints Map
  static const Map<String, List<String>> _domainFingerprints = {
    'us-central1-admin-decd9.cloudfunctions.net': [
      "29:B3:5A:3D:30:BE:5C:6D:2C:11:2C:67:A4:1D:8A:A2:AA:27:E6:D6:A1:FB:6B:86:4C:50:C8:4E:6E:FA:C4:A0", // Firebase ECDSA
      "83:6E:0D:C0:54:3D:3E:AF:D5:57:B2:C3:51:EE:98:AE:8E:CF:37:73:9D:69:E3:06:C7:D9:AD:DE:1B:F3:0D:EF", // Firebase RSA
    ],
    'skyblue-raven-196549.hostingersite.com': [
      "6E:B5:73:11:43:F1:AE:81:0E:04:A8:39:D4:C0:27:61:6C:54:0E:5E:58:0D:78:AA:E3:6B:6F:1B:98:6F:37:28", // Hostinger Leaf
    ],
  };

  /// Verifies the SSL connection for a specific URL before proceeding.
  /// 🛡️ FIX: Now checks the actual target host, preventing redundant checks and slow performance.
  static Future<bool> verifyConnection(Uri url) async {
    if (kDebugMode) return true;

    try {
      final host = url.host;
      if (host.isEmpty) return true;

      // Check if we have fingerprints for this domain
      final fingerprints = _domainFingerprints[host];
      if (fingerprints == null) {
        debugPrint("ℹ️ SSL Pinning: Skipping check for unknown domain: $host");
        return true; 
      }

      final secure = await HttpCertificatePinning.check(
        serverURL: host, // 🛡️ CRITICAL: Use ONLY the hostname (no https://)
        headerHttp: {},
        sha: SHA.SHA256,
        allowedSHAFingerprints: fingerprints,
        timeout: 20, // Reduced timeout for better UX
      );

      return secure.contains("CONNECTION_SECURE");
    } catch (e) {
      debugPrint("🚨 SSL PINNING FAILED for ${url.host}: $e");
      return false;
    }
  }
}
