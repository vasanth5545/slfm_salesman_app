import 'dart:async';
import 'dart:convert';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/constants/api_urls.dart';
import 'secure_storage_service.dart';

class FeatureControlService {
  static final FeatureControlService _instance =
      FeatureControlService._internal();
  factory FeatureControlService() => _instance;
  FeatureControlService._internal();

  // ValueNotifiers for real-time UI updates
  final ValueNotifier<bool> podiumVisible = ValueNotifier<bool>(false);
  final ValueNotifier<bool> leaderboardVisible = ValueNotifier<bool>(false);
  final ValueNotifier<bool> damageVisible = ValueNotifier<bool>(false);
  final ValueNotifier<bool> walkingVisible = ValueNotifier<bool>(false);
  final ValueNotifier<bool> serviceWidgetVisible =
      ValueNotifier<bool>(false); // NEW

  // Real-time lunch window status
  final ValueNotifier<bool> lunchWindowOpen = ValueNotifier<bool>(false);
  final ValueNotifier<bool> lunchIsManual = ValueNotifier<bool>(false);
  final ValueNotifier<String> lunchStartTime = ValueNotifier<String>('13:00');
  final ValueNotifier<String> lunchEndTime = ValueNotifier<String>('16:00');

  // 🍽️ Lunch In-Progress flag: true when salesman did Lunch In but not Lunch Out yet
  final ValueNotifier<bool> lunchInProgress = ValueNotifier<bool>(false);
  final ValueNotifier<bool> lunchCompleted = ValueNotifier<bool>(false);

  // 🔥 Track the DATE of the lunch status — only today's in-progress should allow access
  final ValueNotifier<String> lunchStatusDate = ValueNotifier<String>('');

  StreamSubscription<DatabaseEvent>? _subscription;
  StreamSubscription<DatabaseEvent>? _lunchSubscription;

  // 🔥 Track which showroom we're currently subscribed to
  String _currentShowroom = '';

  /// Initialize the service, load from cache, and start Firebase listener
  Future<void> init() async {
    // 1. Get showroom name FIRST — we need it for cache keys
    final showroom =
        await SecureStorageService.readString('showroom_name') ?? '';

    // 2. 🔥 FIX: Reset all values to safe defaults BEFORE loading cache
    // This prevents stale flags from a different showroom flashing
    if (_currentShowroom != showroom.toLowerCase()) {
      podiumVisible.value = false;
      leaderboardVisible.value = false;
      damageVisible.value = false;
      walkingVisible.value = false;
      serviceWidgetVisible.value = false;
      debugPrint(
          "📡 FeatureControl: Showroom changed ($_currentShowroom → ${showroom.toLowerCase()}), reset all flags");
    }
    _currentShowroom = showroom.toLowerCase();

    // 3. Load from showroom-specific cache
    await _loadFromCache(showroom);

    if (showroom.isEmpty) {
      debugPrint("📡 FeatureControl: No showroom yet, listener pending...");
      return;
    }

    final path = 'features';
    debugPrint("📡 FeatureControl: Subscribing to $path (parent node to catch both global and local showroom updates)");

    // Start Showroom Feature Listener
    _subscription?.cancel();
    _subscription = FirebaseDatabase.instance.ref(path).onValue.listen((event) async {
      // 🔥 Trigger API fetch whenever Firebase data changes
      // This ensures we get the role-filtered flags from PHP instead of raw Firebase flags
      await _fetchFeaturesFromAPI(showroom);
    }, onError: (err) {
      debugPrint("❌ FeatureControl: Firebase Error: $err");
    });

    // Start Lunch Window Listener (Global Priority for Admin Panel)
    _lunchSubscription?.cancel();
    _lunchSubscription = FirebaseDatabase.instance
        .ref('settings/lunch_window')
        .onValue
        .listen((event) {
      if (event.snapshot.value != null && event.snapshot.value is Map) {
        final data = event.snapshot.value as Map;
        final isOpen = _toBool(data['is_open']);
        // Admin panel writes `mode: 'manual'` or `mode: 'auto'` (NOT `is_manual`)
        final isManual = data['mode']?.toString() == 'manual';
        final st = data['start_time']?.toString() ?? '13:00';
        final et = data['end_time']?.toString() ?? '16:00';

        debugPrint(
            "🍽️ LunchControl Global: open=$isOpen, mode=${data['mode']}, manual=$isManual, range=$st-$et");

        // 🔥 Cloud cron job handles open/close — just use is_open directly
        // Manual override: always open
        bool finalOpen = isManual ? true : isOpen;

        lunchWindowOpen.value = finalOpen;
        lunchIsManual.value = isManual;
        lunchStartTime.value = st;
        lunchEndTime.value = et;

        SecureStorageService.writeString(
            'fc_lunch_window', finalOpen.toString());
      }
    }, onError: (err) {
      debugPrint("❌ FeatureControl: Firebase Lunch Window Error: $err");
    });
  }

  Future<void> _fetchFeaturesFromAPI(String showroom) async {
    try {
      final role = await SecureStorageService.getUserRole();
      final url = "${ApiUrl.getFeatureStatus}?showroom=${Uri.encodeComponent(showroom)}&role=${Uri.encodeComponent(role)}";
      
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success' && data['data'] != null) {
          final p = _toBool(data['data']['podium_visible']);
          final l = _toBool(data['data']['leaderboard_visible']);
          final d = _toBool(data['data']['damage_report_visible']);
          final w = _toBool(data['data']['walking_customer_visible']);
          final s = _toBool(data['data']['service_widget_visible']);

          debugPrint("📡 FeatureControl PHP UPDATE: podium=$p, leaderboard=$l, damage=$d, walking=$w, service=$s");
          _updateStates(p, l, d, w, s, showroom);
        }
      }
    } catch (e) {
      debugPrint("❌ FeatureControl: PHP API Error: $e");
    }
  }

  /// 🔥 FIX: Showroom-specific cache keys to prevent cross-account feature leaks
  Future<void> _loadFromCache(String showroom) async {
    final key = showroom.toLowerCase();
    final p = await SecureStorageService.readString('fc_podium_$key');
    final l = await SecureStorageService.readString('fc_leaderboard_$key');
    final d = await SecureStorageService.readString('fc_damage_$key');
    final w = await SecureStorageService.readString('fc_walking_$key');
    final s = await SecureStorageService.readString('fc_service_$key');
    final lw = await SecureStorageService.readString('fc_lunch_window');
    final lm = await SecureStorageService.readString('fc_lunch_manual');
    final lst = await SecureStorageService.readString('fc_lunch_start');
    final let = await SecureStorageService.readString('fc_lunch_end');

    if (p != null) podiumVisible.value = p == 'true';
    if (l != null) leaderboardVisible.value = l == 'true';
    if (d != null) damageVisible.value = d == 'true';
    if (w != null) walkingVisible.value = w == 'true';
    if (s != null) serviceWidgetVisible.value = s == 'true';
    if (lw != null) lunchWindowOpen.value = lw == 'true';
    if (lm != null) lunchIsManual.value = lm == 'true';
    if (lst != null) lunchStartTime.value = lst;
    if (let != null) lunchEndTime.value = let;
  }

  Future<void> syncImmediately() async {
    try {
      final showroom =
          await SecureStorageService.readString('showroom_name') ?? '';

      // Run both Firebase calls in parallel
      await Future.wait([
        // 1. Feature Toggles (via PHP API to respect role-based rules)
        () async {
          if (showroom.isNotEmpty) {
            await _fetchFeaturesFromAPI(showroom);
          }
        }(),

        // 2. Lunch Window Settings
        () async {
          final lunchSnap = await FirebaseDatabase.instance
              .ref('settings/lunch_window')
              .get()
              .timeout(const Duration(seconds: 2));
          if (lunchSnap.value != null && lunchSnap.value is Map) {
            final data = lunchSnap.value as Map;
            // Admin panel writes `mode: 'manual'` or `mode: 'auto'` (NOT `is_manual`)
            final isManual = data['mode']?.toString() == 'manual';
            final st = data['start_time']?.toString() ?? '13:00';
            final et = data['end_time']?.toString() ?? '16:00';

            // ✅ Same logic as real-time listener:
            //   Admin ON (manual) → always open
            //   Admin OFF → check time range
            final bool finalOpen = isManual ? true : _isWithinTimeRange(st, et);

            if (lunchWindowOpen.value != finalOpen) {
              lunchWindowOpen.value = finalOpen;
              SecureStorageService.writeString(
                  'fc_lunch_window', finalOpen.toString());
            }
            if (lunchIsManual.value != isManual) {
              lunchIsManual.value = isManual;
              SecureStorageService.writeString(
                  'fc_lunch_manual', isManual.toString());
            }
            if (lunchStartTime.value != st) {
              lunchStartTime.value = st;
              SecureStorageService.writeString('fc_lunch_start', st);
            }
            if (lunchEndTime.value != et) {
              lunchEndTime.value = et;
              SecureStorageService.writeString('fc_lunch_end', et);
            }
          }
        }(),

        // 3. Lunch In-Progress Status (from PHP API — Firebase has stale data)
        () async {
          final salesmanId = await SecureStorageService.getSalesmanId();
          if (salesmanId != null && salesmanId.isNotEmpty) {
            try {
              final res = await http
                  .post(
                    Uri.parse(ApiUrl.lunch),
                    body: jsonEncode({
                      "action": "get_lunch_status",
                      "salesman_id": salesmanId,
                    }),
                  )
                  .timeout(const Duration(seconds: 3));
              if (res.statusCode == 200) {
                final body = jsonDecode(res.body);
                if (body['status'] == 'success' && body['data'] != null) {
                  final lStatus =
                      body['data']['lunch_status']?.toString() ?? 'not_started';
                  lunchInProgress.value = (lStatus == 'in_progress');
                  lunchCompleted.value = (lStatus == 'completed');
                  if (lStatus == 'in_progress' || lStatus == 'completed') {
                    final now = DateTime.now();
                    lunchStatusDate.value =
                        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
                  }
                  debugPrint(
                      "🍽️ SyncImmediate: PHP API lunch_status=$lStatus");
                }
              }
            } catch (e) {
              debugPrint("🍽️ SyncImmediate: Lunch status API error: $e");
            }
          }
        }()
      ]);
    } catch (e) {
      debugPrint(
          "📡 FeatureControl: syncImmediately failed (timeout or offline): $e");
    }
  }

  void _updateStates(bool p, bool l, bool d, bool w, bool s, String showroom) {
    final key = showroom.toLowerCase();
    // Only update and cache if values actually changed to prevent redundant UI rebuilds
    if (podiumVisible.value != p) {
      podiumVisible.value = p;
      SecureStorageService.writeString('fc_podium_$key', p.toString());
    }
    if (leaderboardVisible.value != l) {
      leaderboardVisible.value = l;
      SecureStorageService.writeString('fc_leaderboard_$key', l.toString());
    }
    if (damageVisible.value != d) {
      damageVisible.value = d;
      SecureStorageService.writeString('fc_damage_$key', d.toString());
    }
    if (walkingVisible.value != w) {
      walkingVisible.value = w;
      SecureStorageService.writeString('fc_walking_$key', w.toString());
    }
    if (serviceWidgetVisible.value != s) {
      serviceWidgetVisible.value = s;
      SecureStorageService.writeString('fc_service_$key', s.toString());
    }
  }

  bool _toBool(dynamic val) {
    if (val == null) return false; // Default to disabled if not set
    if (val is bool) return val;
    if (val is num) return val == 1;
    if (val is String) {
      final s = val.toLowerCase().trim();
      return s == '1' || s == 'true' || s == 'yes';
    }
    return false;
  }

  void dispose() {
    _subscription?.cancel();
    _lunchSubscription?.cancel();
  }

  /// Helper to check if current time is within a 24h range string (e.g. "13:00")
  bool _isWithinTimeRange(String startStr, String endStr) {
    try {
      final now = DateTime.now();

      final startParts = startStr.split(':');
      final endParts = endStr.split(':');

      if (startParts.length != 2 || endParts.length != 2) return false;

      final start = DateTime(now.year, now.month, now.day,
          int.parse(startParts[0]), int.parse(startParts[1]));
      final end = DateTime(now.year, now.month, now.day, int.parse(endParts[0]),
          int.parse(endParts[1]));

      // 🔥 >= start (inclusive at 1 PM) AND < end (closes AT 4 PM)
      return !now.isBefore(start) && now.isBefore(end);
    } catch (e) {
      debugPrint("❌ Error parsing lunch time range: $e");
      return false;
    }
  }
}
