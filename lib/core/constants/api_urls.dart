import 'dart:convert';

class ApiUrl {
  /// Simple obfuscation logic to prevent raw strings in compiled binary
  static String _decode(String encoded) {
    try {
      // Logic fix: Base64 strings should not be reversed as it breaks padding
      // Reverting to direct base64 decode if it starts with valid base64 or just use the string.
      return utf8.decode(base64Decode(encoded));
    } catch (_) {
      return '';
    }
  }

  // 🔒 BASE URL
  static String get baseUrl {
    // Default is a dummy URL (https://dummy-company.com/api)
    const String url = String.fromEnvironment('BASE_URL', defaultValue: 'aHR0cHM6Ly9kdW1teS1jb21wYW55LmNvbS9hcGk=');
    return _decode(url);
  }

  // 🔥 FIREBASE CLOUD FUNCTIONS BASE URL
  static String get firebaseBaseUrl {
    // Default is a dummy URL (https://dummy-firebase.com/api)
    const String url = String.fromEnvironment('FIREBASE_URL', defaultValue: 'aHR0cHM6Ly9kdW1teS1maXJlYmFzZS5jb20vYXBp');
    return _decode(url);
  }

  // --- SLFM Attendance App URLs (ALL PHP+MySQL) ---
  static String get login => "$baseUrl/login.php";
  static String get attendance => "$baseUrl/attendance.php";
  static String get locationTracker => "$baseUrl/location_update.php";
  static String get billing => "$baseUrl/billing.php";

  static String get leave => "$baseUrl/leave.php";
  static String get messages => "$baseUrl/messages.php";
  static String get productLookup => "$baseUrl/product_lookup.php";
  static String get stockCheck => "$baseUrl/stock_check.php";
  static String get syncActivity => "$baseUrl/sync_activity.php";
  static String get registerSalesman => "$baseUrl/register_salesman.php";
  static String get markAbsent => "$baseUrl/mark_absent.php";
  static String get getFeatureStatus => "$baseUrl/get_feature_status.php";
  static String get updateSalesmanSummary =>
      "$baseUrl/update_salesman_summary.php";
  static String get walkingCustomer => "$baseUrl/walking_customer.php";
  static String get damageReport => "$baseUrl/damage_report.php";

  // --- SERVICE REPORT APIs ---
  static String get saveServiceReport => "$baseUrl/save_service_report.php";
  static String get getServiceReports => "$baseUrl/get_service_reports.php";

  // 🍽️ Lunch Time Module
  static String get lunch => "$baseUrl/lunch.php";

  // 🔥 NEW: Splash Screen Status Check
  static String get salesmanCheck => "$baseUrl/salesman_check.php";
  static String get getAvatarAvailability =>
      "$baseUrl/get_avatar_availability.php";
  static String get uploadProfile => "$baseUrl/upload_profile.php";
  static String get getLeaderboard => "$baseUrl/get_leaderboard.php";

  // --- Update Check URLs ---
  static String get updateServerBaseUrl => baseUrl;

  static String get versionJsonUrl => "$updateServerBaseUrl/check_version.php";
  static String get apkDownloadUrl =>
      "$updateServerBaseUrl/apps/salesman/app-release.apk";

  // 🔥 NEW: Play Store URL for official updates
  static String get playStoreUrl =>
      "https://play.google.com/store/apps/details?id=com.slfm.salesman";
}
