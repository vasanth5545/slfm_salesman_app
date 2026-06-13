import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import '../../presentation/walking_notes/walking_notes_screen.dart';
import '../../services/announcement_service.dart';
import 'dart:async';

// Import global key from main if possible, or just define a way to access it.
// Since it's defined in main.dart, we might have circular dependency.
// I'll use a safer approach.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: DarwinInitializationSettings(),
    );

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint("🚀 Notification Clicked with payload: ${response.payload}");

        if (response.payload == 'navigate_walking') {
          navigatorKey.currentState?.push(
            MaterialPageRoute(builder: (context) => const WalkingNotesScreen()),
          );
        } else if (response.payload != null &&
            response.payload!.startsWith('announcement_')) {
          // Future: Navigate to specific announcement detail if needed
          debugPrint("Announcement notification clicked: ${response.payload}");
        }
      },
    );
  }

  Future<void> showAnnouncementNotification({
    required String id,
    required String message,
  }) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'announcements_channel',
      'Announcements',
      channelDescription: 'Notifications for new announcements',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await _notificationsPlugin.show(
      id.hashCode,
      'New Announcement',
      message.length > 50 ? '${message.substring(0, 50)}...' : message,
      platformChannelSpecifics,
      payload: 'announcement_$id',
    );
  }

  // 🔥 GLOBAL LISTENER: Formerly used for snackbars
  StreamSubscription? _announcementSubscription;

  void startAnnouncementListener(String showroomName, String salesmanId) {
    _announcementSubscription?.cancel();
    _announcementSubscription = AnnouncementService()
        .getAnnouncements(showroomName, salesmanId)
        .listen((announcements) {
      // In-app snackbar removed as per user request. 
      // Announcements are handled directly in the Dashboard UI.
    });
  }

  void stopAnnouncementListener() {
    _announcementSubscription?.cancel();
    _announcementSubscription = null;
  }
}
