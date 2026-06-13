import 'package:dio/dio.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'secure_storage_service.dart';
import '../core/app_export.dart';
import '../core/services/notification_service.dart';

/// Secure API Client
/// Replaces the default `http` package to provide built-in JWT injection,
/// automatic token expiration handling, and request timeouts.
class ApiService {
  // Singleton Pattern
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  late Dio _dio;

  ApiService._internal() {
    _dio = Dio(BaseOptions(
      // IMPORTANT: Firebase Functions Base URL
      baseUrl: ApiUrl.firebaseBaseUrl, 
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      contentType: 'application/json',
    ));

    // Add Security Interceptors
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // 1. Firebase App Check Token
          try {
            final appCheckToken = await FirebaseAppCheck.instance.getToken();
            if (appCheckToken != null) {
              options.headers['X-Firebase-AppCheck'] = appCheckToken;
            }
          } catch (e) {
            debugPrint("App Check Error: $e");
          }

          // 2. Firebase Auth ID Token
          try {
            final user = FirebaseAuth.instance.currentUser;
            if (user != null) {
              final idToken = await user.getIdToken();
              if (idToken != null) {
                options.headers['Authorization'] = 'Bearer $idToken';
              }
            } else {
              // Fallback to locally stored Custom Token (JWT)
              final token = await SecureStorageService.getToken();
              if (token != null && token.isNotEmpty) {
                options.headers['Authorization'] = 'Bearer $token';
              }
            }
          } catch (e) {
             debugPrint("Auth token fetch failed: $e");
          }
          
          return handler.next(options);
        },
        onError: (DioException e, handler) async {
          // 2. Token Expiration Handling (HTTP 401 Unauthorized)
          if (e.response?.statusCode == 401) {
            debugPrint("🚨 Token Expired! Logging out user safely.");
            
            // Clear the local session securely
            await SecureStorageService.clearSession();
            
            // Navigate the user back to the login screen using the global navigator key
            if (navigatorKey.currentState != null) {
              navigatorKey.currentState!.pushNamedAndRemoveUntil(
                AppRoutes.login, 
                (route) => false,
              );
            }
          }
          return handler.next(e);
        },
      ),
    );
  }

  /// Expose the Dio instance for making requests
  Dio get client => _dio;
}
