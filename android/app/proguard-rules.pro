# ============================================
# SLFM Attendance App - ProGuard Rules
# Fixes MissingPluginException in Release Builds
# ============================================

# --- Flutter Core ---
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }

# --- Firebase Realtime Database (ROOT CAUSE of MissingPluginException) ---
-keep class com.google.firebase.database.** { *; }
-keep class com.google.android.gms.internal.firebase_database.** { *; }
-keep class io.flutter.plugins.firebase.database.** { *; }

# --- Firebase Core ---
-keep class com.google.firebase.** { *; }
-keep class io.flutter.plugins.firebase.core.** { *; }

# --- Firebase Auth ---
-keep class com.google.firebase.auth.** { *; }
-keep class io.flutter.plugins.firebase.auth.** { *; }

# --- Cloud Firestore ---
-keep class com.google.firebase.firestore.** { *; }
-keep class io.flutter.plugins.firebase.firestore.** { *; }

# --- Firebase Crashlytics ---
-keep class com.google.firebase.crashlytics.** { *; }
-keep class io.flutter.plugins.firebase.crashlytics.** { *; }

# --- Firebase App Check ---
-keep class com.google.firebase.appcheck.** { *; }

# --- Firebase Remote Config ---
-keep class com.google.firebase.remoteconfig.** { *; }

# --- Google Play Services ---
-keep class com.google.android.gms.** { *; }

# --- Flutter Background Service ---
-keep class id.flutter.flutter_background_service.** { *; }

# --- Geolocator ---
-keep class com.baseflow.geolocator.** { *; }

# --- Flutter Secure Storage ---
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# --- Prevent stripping of method channels ---
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# --- Keep native methods ---
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# --- Suppress warnings for Firebase ---
-dontwarn com.google.firebase.**
-dontwarn io.flutter.plugins.firebase.**

# --- Google Play Services Auth (Fixes OnePlus SignInHubActivity crash) ---
-keep class com.google.android.gms.auth.** { *; }
-keep class com.google.android.gms.auth.api.signin.** { *; }
-keep class com.google.android.gms.auth.api.signin.internal.** { *; }
-keep class com.google.android.gms.common.** { *; }
-dontwarn com.google.android.gms.**

# --- Google Play Core (Fixes R8 "Missing class" build error) ---
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**

