import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as inner_http;
import '../../services/secure_storage_service.dart';
import '../../services/ssl_pinning_service.dart';
import '../utils/network_quality_helper.dart';

/// Secure HTTP Client Wrapper
/// Automatically intercepts all requests to inject authorization headers
/// using the local JWT token from SecureStorageService.
///
/// 🔥 NEW: Includes retry-with-backoff methods for slow network resilience (2G/3G).
class SecureHttpClient {
  static Future<Map<String, String>> _getSecurityHeaders(
      Map<String, String>? existingHeaders) async {
    final headers = Map<String, String>.from(existingHeaders ?? {});

    // 🔥 Anti-Bot / ModSecurity bypass headers to prevent HTTP 403 Forbidden
    headers['User-Agent'] =
        'Mozilla/5.0 (Linux; Android 10; SM-G981B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/80.0.3987.162 Mobile Safari/537.36';
    headers['Accept'] = 'application/json, text/plain, */*';

    // Local JWT Token from SecureStorage
    try {
      final token = await SecureStorageService.getToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    } catch (e) {
      debugPrint("Auth token fetch failed: $e");
    }

    return headers;
  }

  static Future<inner_http.Response> get(Uri url,
      {Map<String, String>? headers}) async {
    // 🛡️ SSL Pinning Enforcement
    if (kReleaseMode) {
      await SSLPinningService.verifyConnection(url);
    }
    final secureHeaders = await _getSecurityHeaders(headers);
    return inner_http.get(url, headers: secureHeaders);
  }

  static Future<inner_http.Response> post(Uri url,
      {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
    // 🛡️ SSL Pinning Enforcement
    if (kReleaseMode) {
      await SSLPinningService.verifyConnection(url);
    }
    final secureHeaders = await _getSecurityHeaders(headers);
    return inner_http.post(url,
        headers: secureHeaders, body: body, encoding: encoding);
  }

  // =========================================================================
  // 🔥 RETRY WITH EXPONENTIAL BACKOFF — For Slow Network Resilience (2G/3G)
  // =========================================================================

  /// POST with automatic retry + exponential backoff.
  /// On 2G/3G, the first attempt may fail due to slow DNS/TLS handshake.
  /// Retrying 1-2 times with increasing timeout drastically reduces
  /// false "saved offline" errors.
  ///
  /// - [maxRetries]: Number of retry attempts (default: 2)
  /// - [baseTimeoutSeconds]: Timeout for first attempt; increases per retry
  static Future<inner_http.Response> postWithRetry(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    int maxRetries = 2,
    int baseTimeoutSeconds = 15,
  }) async {
    Object? lastError;
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        // Exponential backoff delay before retry (0s, 2s, 4s)
        if (attempt > 0) {
          final delay = Duration(seconds: 2 * attempt);
          debugPrint("🔄 Retry $attempt after ${delay.inSeconds}s...");
          await Future.delayed(delay);
        }
        // Increase timeout for each retry: 15s → 25s → 35s
        final timeout = Duration(seconds: baseTimeoutSeconds + (attempt * 10));
        return await post(url, headers: headers, body: body, encoding: encoding)
            .timeout(timeout);
      } on TimeoutException catch (e) {
        lastError = e;
        debugPrint("⏱️ Attempt $attempt timed out");
      } catch (e) {
        lastError = e;
        debugPrint("❌ Attempt $attempt failed: $e");
        // We SHOULD retry on ClientException because it wraps SocketException (Network errors)
      }
    }
    throw lastError ?? TimeoutException("All $maxRetries retries exhausted");
  }

  /// GET with automatic retry + exponential backoff.
  static Future<inner_http.Response> getWithRetry(
    Uri url, {
    Map<String, String>? headers,
    int maxRetries = 2,
    int baseTimeoutSeconds = 15,
  }) async {
    Object? lastError;
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        if (attempt > 0) {
          final delay = Duration(seconds: 2 * attempt);
          debugPrint("🔄 Retry GET $attempt after ${delay.inSeconds}s...");
          await Future.delayed(delay);
        }
        final timeout = Duration(seconds: baseTimeoutSeconds + (attempt * 10));
        return await get(url, headers: headers).timeout(timeout);
      } on TimeoutException catch (e) {
        lastError = e;
        debugPrint("⏱️ GET Attempt $attempt timed out");
      } catch (e) {
        lastError = e;
        debugPrint("❌ GET Attempt $attempt failed: $e");
        // We SHOULD retry on ClientException (Network errors)
      }
    }
    throw lastError ?? TimeoutException("All $maxRetries retries exhausted");
  }

  /// MULTIPART POST with automatic retry + exponential backoff.
  /// Standard MultipartRequest can only be sent once. This helper
  /// recreates the request for each retry.
  ///
  /// - [files]: Map of field names to file paths or bytes.
  static Future<inner_http.Response> postMultipartWithRetry(
    Uri url, {
    Map<String, String>? headers,
    Map<String, String>? fields,
    Map<String, dynamic>? files, // path (String) or bytes (List<int>)
    int maxRetries = 2,
  }) async {
    Object? lastError;

    // Suggest a generous timeout for heavy uploads
    final uploadTimeout = await NetworkQualityHelper.getUploadTimeout();

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        if (attempt > 0) {
          final delay = Duration(seconds: 3 * attempt);
          debugPrint(
              "🔄 Multipart Retry $attempt after ${delay.inSeconds}s...");
          await Future.delayed(delay);
        }

        final request = MultipartRequest('POST', url);
        if (headers != null) request.headers.addAll(headers);
        if (fields != null) request.fields.addAll(fields);

        if (files != null) {
          for (var entry in files.entries) {
            if (entry.value is String) {
              request.files.add(await inner_http.MultipartFile.fromPath(
                  entry.key, entry.value));
            } else if (entry.value is List<int>) {
              request.files.add(inner_http.MultipartFile.fromBytes(
                  entry.key, entry.value,
                  filename: '${entry.key}.jpg'));
            }
          }
        }

        final streamedResponse = await request.send().timeout(uploadTimeout);
        final response = await inner_http.Response.fromStream(streamedResponse);

        // Only return if success or logic error (4xx/5xx).
        // We retry on connection/timeout issues.
        return response;
      } on TimeoutException catch (e) {
        lastError = e;
        debugPrint("⏱️ Multipart Attempt $attempt timed out");
      } catch (e) {
        lastError = e;
        debugPrint("❌ Multipart Attempt $attempt failed: $e");
        // We SHOULD retry on ClientException (Network errors)
      }
    }
    throw lastError ??
        TimeoutException("All $maxRetries multipart retries exhausted");
  }
}

/// Secure Multipart Request Wrapper
class MultipartRequest extends inner_http.MultipartRequest {
  MultipartRequest(super.method, super.url);

  @override
  Future<inner_http.StreamedResponse> send() async {
    // Inject local JWT token before sending
    try {
      final token = await SecureStorageService.getToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    } catch (_) {}

    return super.send();
  }
}

/// Expose commonly used inner_http classes
typedef Response = inner_http.Response;
typedef StreamedResponse = inner_http.StreamedResponse;
typedef MultipartFile = inner_http.MultipartFile;

// ============================================================================
// TOP-LEVEL DROP-IN REPLACEMENTS FOR http.post AND http.get
// ============================================================================

Future<inner_http.Response> post(Uri url,
    {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
  return SecureHttpClient.post(url,
      headers: headers, body: body, encoding: encoding);
}

Future<inner_http.Response> get(Uri url, {Map<String, String>? headers}) async {
  return SecureHttpClient.get(url, headers: headers);
}

/// 🔥 NEW: Top-level retry functions for slow network resilience
Future<inner_http.Response> postWithRetry(Uri url,
    {Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    int maxRetries = 2,
    int baseTimeoutSeconds = 15}) async {
  return SecureHttpClient.postWithRetry(url,
      headers: headers,
      body: body,
      encoding: encoding,
      maxRetries: maxRetries,
      baseTimeoutSeconds: baseTimeoutSeconds);
}

Future<inner_http.Response> getWithRetry(Uri url,
    {Map<String, String>? headers,
    int maxRetries = 2,
    int baseTimeoutSeconds = 15}) async {
  return SecureHttpClient.getWithRetry(url,
      headers: headers,
      maxRetries: maxRetries,
      baseTimeoutSeconds: baseTimeoutSeconds);
}

/// 🔥 NEW: Multipart retry function
Future<inner_http.Response> postMultipartWithRetry(Uri url,
    {Map<String, String>? headers,
    Map<String, String>? fields,
    Map<String, dynamic>? files,
    int maxRetries = 2}) async {
  return SecureHttpClient.postMultipartWithRetry(url,
      headers: headers, fields: fields, files: files, maxRetries: maxRetries);
}
