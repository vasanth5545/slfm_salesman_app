import 'package:flutter/material.dart';
import '../presentation/stock_checking_screen/stock_checking_screen.dart';
import '../presentation/attendance_screen/attendance_screen.dart';
import '../presentation/login_screen/login_screen.dart';
import '../presentation/dashboard/dashboard.dart';
import '../presentation/customer_billing_screen/customer_billing_screen.dart';
import '../presentation/os_code_entry_screen/os_code_entry_screen.dart';
import '../presentation/setting/setting.dart';
// Removed Privacy Policy Import
// Add Splash Screen Import
import '../presentation/splash_screen/splash_screen.dart';
import '../presentation/leaderboard/leaderboard_screen.dart'; // 🔥 NEW: Leaderboard
import '../presentation/lunch_screen/lunch_screen.dart'; // 🔥 NEW: Lunch
import '../presentation/permission_screen/permission_screen.dart'; // 🔥 NEW: Permission
import '../presentation/setting/activity_logs_screen.dart'; // 🔥 Admin Logs

class AppRoutes {
  static const String initial = '/'; // Points to Splash Screen
  static const String splashScreen = '/splash-screen';
  static const String stockChecking = '/stock-checking-screen';
  static const String attendance = '/attendance-screen';
  static const String login = '/login-screen';
  static const String dashboard = '/dashboard';
  static const String customerBilling = '/customer-billing-screen';
  static const String osCodeEntry = '/os-code-entry-screen';
  static const String setting = '/setting-screen';

  static const String leaderboard = '/leaderboard'; // 🔥 NEW: Leaderboard
  static const String lunch = '/lunch-screen'; // 🔥 NEW: Lunch
  static const String permission = '/permission-screen'; // 🔥 NEW: Permission
  static const String activityLogs = '/activity-logs-screen'; // 🔥 Admin Logs

  static Map<String, WidgetBuilder> routes = {
    // Change initial route to SplashScreen
    initial: (context) => const SplashScreen(),
    splashScreen: (context) => const SplashScreen(),
    stockChecking: (context) => const StockCheckingScreen(),
    attendance: (context) => const AttendanceScreen(),
    login: (context) => const LoginScreen(),
    dashboard: (context) => const Dashboard(),
    customerBilling: (context) => const CustomerBillingScreen(),
    osCodeEntry: (context) => const OsCodeEntryScreen(),
    setting: (context) => const SettingScreen(),

    leaderboard: (context) => const LeaderboardScreen(), // 🔥 NEW: Leaderboard
    lunch: (context) => const LunchScreen(), // 🔥 NEW: Lunch
    permission: (context) => const PermissionScreen(), // 🔥 NEW: Permission
    activityLogs: (context) => const ActivityLogsScreen(), // 🔥 Admin Logs
  };
}
