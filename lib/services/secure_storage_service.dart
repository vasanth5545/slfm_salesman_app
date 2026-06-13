import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Service for managing securely encrypted local storage.
/// Replaces `shared_preferences` for sensitive items.
class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  // --- Session Management ---

  static Future<void> saveUserSession({
    required String id,
    required String name,
    required String showroom,
    String profilePhoto = '',
    String avatarAnimal = '',
    String role = 'salesman',
    String customLateCutoff = '10:00:59',
  }) async {
    await _storage.write(key: 'salesman_id', value: id);
    await _storage.write(key: 'salesman_name', value: name);
    await _storage.write(key: 'showroom_name', value: showroom);
    await _storage.write(key: 'profile_photo', value: profilePhoto);
    await _storage.write(key: 'avatar_animal', value: avatarAnimal);
    await _storage.write(key: 'user_role', value: role);
    await _storage.write(key: 'custom_late_cutoff', value: customLateCutoff);
    await _storage.write(key: 'is_logged_in', value: 'true');
  }

  static Future<void> clearSession() async {
    // Read all keys, and delete everything EXCEPT critical global keys
    final allKeys = await _storage.readAll();
    final List<String> preserveKeys = [
      'hive_encryption_key',
      'saved_accounts',
      'last_run_version',
      'has_clicked_auto_start', // 🔥 Prevent annoying Auto-Start prompt on re-login
      'has_clicked_battery_opt', // 🔥 Prevent repeated battery prompts
    ];

    for (var key in allKeys.keys) {
      if (!preserveKeys.contains(key)) {
        await _storage.delete(key: key);
      }
    }
  }

  /// Logouts the current user but PRESERVES them in the switcher registry.
  /// Modified as per user request: "don't delete accounts on logout"
  static Future<void> logoutCurrentAccount() async {
    await clearSession();
  }

  // --- Generic Storage Methods ---

  static Future<void> writeString(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  static Future<String?> readString(String key) async {
    return await _storage.read(key: key);
  }

  static Future<void> writeInt(String key, int value) async {
    await _storage.write(key: key, value: value.toString());
  }

  static Future<int?> readInt(String key) async {
    final val = await _storage.read(key: key);
    return val != null ? int.tryParse(val) : null;
  }

  static Future<void> writeBool(String key, bool value) async {
    await _storage.write(key: key, value: value.toString());
  }

  static Future<bool?> readBool(String key) async {
    final val = await _storage.read(key: key);
    if (val == 'true') return true;
    if (val == 'false') return false;
    return null;
  }

  static Future<void> deleteKey(String key) async {
    await _storage.delete(key: key);
  }

  // --- Getters ---

  static Future<bool> isLoggedIn() async {
    final val = await _storage.read(key: 'is_logged_in');
    return val == 'true';
  }

  static Future<String?> getSalesmanId() async {
    return await _storage.read(key: 'salesman_id');
  }

  static Future<String?> getSalesmanName() async {
    return await _storage.read(key: 'salesman_name');
  }

  static Future<String?> getShowroomName() async {
    return await _storage.read(key: 'showroom_name');
  }

  static Future<String> getUserRole() async {
    return await _storage.read(key: 'user_role') ?? 'salesman';
  }

  static Future<String> getCustomLateCutoff() async {
    return await _storage.read(key: 'custom_late_cutoff') ?? '10:00:59';
  }

  static Future<void> saveCustomLateCutoff(String cutoff) async {
    await _storage.write(key: 'custom_late_cutoff', value: cutoff);
  }

  // --- App Settings ---

  static Future<String> getTickSound() async {
    return await _storage.read(key: 'attendance_tick_sound') ?? 'sound1.mp3';
  }

  static Future<void> saveTickSound(String soundFile) async {
    await _storage.write(key: 'attendance_tick_sound', value: soundFile);
  }

  // --- Profile Setup Flags ---

  static Future<void> setProfileSetupDone(bool done) async {
    await _storage.write(key: 'is_profile_setup_done', value: done.toString());
  }

  static Future<bool> isProfileSetupDone() async {
    final val = await _storage.read(key: 'is_profile_setup_done');
    // If it's explicitly 'true', we return true.
    // Otherwise, we return false (including if it's null/never set).
    return val == 'true';
  }

  // --- JWT Management (for upcoming implementation) ---

  static Future<void> saveToken(String token) async {
    await _storage.write(key: 'jwt_token', value: token);
  }

  static Future<String?> getToken() async {
    return await _storage.read(key: 'jwt_token');
  }

  // --- Account Switcher Management ---

  /// Adds an account to the list of saved accounts for quick switching.
  static Future<void> addAccountToSwitcher({
    required String id,
    required String name,
    required String showroom,
    String profilePhoto = '',
    String avatarAnimal = '',
    String role = 'salesman',
    String? token,
  }) async {
    final existingAccountsStr = await _storage.read(key: 'saved_accounts');
    List<dynamic> accounts = [];
    if (existingAccountsStr != null) {
      try {
        accounts = jsonDecode(existingAccountsStr);
      } catch (e) {
        accounts = [];
      }
    }

    final Map<String, dynamic> accountData = {
      'salesman_id': id,
      'salesman_name': name,
      'showroom_name': showroom,
      'profile_photo': profilePhoto,
      'avatar_animal': avatarAnimal,
      'user_role': role,
      'jwt_token': token,
      'last_used': DateTime.now().toIso8601String(),
    };

    // Check if account already exists
    final index = accounts.indexWhere((a) => a['salesman_id'] == id);
    if (index != -1) {
      accounts[index] = accountData; // Update existing
    } else {
      accounts.add(accountData); // Add new
    }

    await _storage.write(key: 'saved_accounts', value: jsonEncode(accounts));
  }

  /// Retrieves all saved accounts for the account switcher.
  static Future<List<Map<String, dynamic>>> getSavedAccounts() async {
    final accountsStr = await _storage.read(key: 'saved_accounts');
    if (accountsStr == null) return [];
    try {
      final List<dynamic> decoded = jsonDecode(accountsStr);
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }

  /// Clears specifically the saved accounts list.
  static Future<void> clearSavedAccounts() async {
    await _storage.delete(key: 'saved_accounts');
  }

  /// Removes a specific account from the switcher by salesman ID.
  static Future<void> removeAccountFromSwitcher(String salesmanId) async {
    final accounts = await getSavedAccounts();
    final updated = accounts
        .where((a) => a['salesman_id'].toString() != salesmanId)
        .toList();
    await _storage.write(key: 'saved_accounts', value: jsonEncode(updated));
  }

  /// Switches the active session to the provided saved account data.
  static Future<void> switchActiveAccount(Map<String, dynamic> account) async {
    // 🔥 Before switching, ensure the current session is registered in the switcher
    await syncCurrentSessionToSwitcher();

    await saveUserSession(
      id: account['salesman_id'].toString(),
      name: account['salesman_name'].toString(),
      showroom: account['showroom_name'].toString(),
      profilePhoto: (account['profile_photo'] ?? '').toString(),
      avatarAnimal: (account['avatar_animal'] ?? '').toString(),
      role: (account['user_role'] ?? 'salesman').toString(),
    );
    if (account['jwt_token'] != null) {
      await saveToken(account['jwt_token'].toString());
    }
  }

  /// Ensures the currently logged in session is saved in the switcher registry.
  /// Useful for mid-session updates or when transition occurs.
  static Future<void> syncCurrentSessionToSwitcher() async {
    final loggedIn = await isLoggedIn();
    if (!loggedIn) return;

    final id = await getSalesmanId();
    final name = await getSalesmanName();
    final showroom = await getShowroomName();
    final photo = await _storage.read(key: 'profile_photo') ?? '';
    final animal = await _storage.read(key: 'avatar_animal') ?? '';
    final role = await getUserRole();
    final token = await getToken();

    if (id != null && name != null && showroom != null) {
      await addAccountToSwitcher(
        id: id,
        name: name,
        showroom: showroom,
        profilePhoto: photo,
        avatarAnimal: animal,
        role: role,
        token: token,
      );
    }
  }

  // --- Local DB Encryption ---

  /// Generates or retrieves an encryption key for Hive databases.
  static Future<List<int>> getHiveEncryptionKey() async {
    final containsEncryptionKey =
        await _storage.containsKey(key: 'hive_encryption_key');
    if (!containsEncryptionKey) {
      final key = Hive.generateSecureKey();
      await _storage.write(
        key: 'hive_encryption_key',
        value: base64UrlEncode(key),
      );
      return key;
    }

    final encodedKey = await _storage.read(key: 'hive_encryption_key');
    return base64Url.decode(encodedKey!);
  }

  // --- Announcement Acknowledgement ---

  static Future<void> saveAcknowledgedAnnouncements(List<String> ids) async {
    await _storage.write(
        key: 'acknowledged_announcements', value: jsonEncode(ids));
  }

  static Future<List<String>> getAcknowledgedAnnouncements() async {
    final idsStr = await _storage.read(key: 'acknowledged_announcements');
    if (idsStr == null) return [];
    try {
      final List<dynamic> decoded = jsonDecode(idsStr);
      return decoded.cast<String>();
    } catch (e) {
      return [];
    }
  }

  // --- Announcement Notifications ---

  static Future<void> saveNotifiedAnnouncements(List<String> ids) async {
    await _storage.write(
        key: 'notified_announcements', value: jsonEncode(ids));
  }

  static Future<List<String>> getNotifiedAnnouncements() async {
    final idsStr = await _storage.read(key: 'notified_announcements');
    if (idsStr == null) return [];
    try {
      final List<dynamic> decoded = jsonDecode(idsStr);
      return decoded.cast<String>();
    } catch (e) {
      return [];
    }
  }
}
