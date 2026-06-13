import 'dart:convert';
import 'package:image/image.dart' as img; // 🔥 TASK 1: Image compression
import 'package:slfm_salesman_app/services/activity_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:slfm_salesman_app/core/services/secure_http_client.dart'
    as http;
import 'package:image_picker/image_picker.dart';
import '../../services/secure_storage_service.dart';
import 'package:sizer/sizer.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/offline_sync_service.dart';
import '../../core/app_export.dart';
import '../../core/database/local_db_helper.dart';
import '../../widgets/custom_app_bar.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/utils/permission_guard.dart';
import '../../core/utils/image_picker_guard.dart';

class WalkingNotesScreen extends StatefulWidget {
  const WalkingNotesScreen({super.key});

  @override
  State<WalkingNotesScreen> createState() => _WalkingNotesScreenState();
}

class _WalkingNotesScreenState extends State<WalkingNotesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _productController = TextEditingController();
  final _feedbackController = TextEditingController();

  bool _isLoading = false;
  bool _isInitialLoading = true;
  bool _isPickingImage = false; // 🛡️ Guard
  String? _editingId;

  List<Map<String, dynamic>> _pendingList = [];
  List<Map<String, dynamic>> _billedList = [];

  String _currentSalesmanId = "";
  String _currentSalesmanName = "Me";

  final String _apiUrl =
      ApiUrl.walkingCustomer; // 🔥 Points to api/walking_customers.php
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadUserData();
    _initSyncListener();

    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && _tabController.index != 0) {
        _fetchMyData();
      }
    });
  }

  void _initSyncListener() async {
    await OfflineSyncService().init();
    OfflineSyncService().queueListenable?.addListener(_onSyncChange);
  }

  void _onSyncChange() {
    if (mounted) {
      debugPrint("🔄 Sync Queue Changed. Refreshing UI...");
      _fetchMyData();
    }
  }

  @override
  void dispose() {
    OfflineSyncService().queueListenable?.removeListener(_onSyncChange);
    _tabController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _productController.dispose();
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final name = await SecureStorageService.getSalesmanName();
    final id = await SecureStorageService.getSalesmanId();
    setState(() {
      _currentSalesmanId = id ?? "";
      _currentSalesmanName = name ?? "Salesman";
    });
    _fetchMyData();
  }

  Future<void> _fetchMyData() async {
    setState(() => _isLoading = true);

    // 🔥 Step 1: Load instantly from local SQLite
    try {
      final localData =
          await LocalDbHelper.instance.getWalkingCustomers(_currentSalesmanId);
      debugPrint(
          "📦 Local Walking DB: Found ${localData.length} records for $_currentSalesmanId");
      if (localData.isNotEmpty && mounted) {
        final localPending = <Map<String, dynamic>>[];
        final localBilled = <Map<String, dynamic>>[];
        for (var item in localData) {
          final mapItem = _toDisplayMap(item);
          if (mapItem['status'] == 'Billed') {
            localBilled.add(mapItem);
          } else {
            localPending.add(mapItem);
          }
        }
        final offlineItems = OfflineSyncService().getPendingWalkingCustomers();
        setState(() {
          _pendingList = [...offlineItems, ...localPending];
          _billedList = localBilled;
          _isLoading = false;
          _isInitialLoading = false;
        });
      }
    } catch (e) {
      debugPrint("❌ Local Walking Load Error: $e");
    }

    // 🔥 Step 2: Background sync from Firebase Cloud Function
    List<Map<String, dynamic>> serverPending = [];
    List<Map<String, dynamic>> serverBilled = [];

    try {
      debugPrint(
          "🌐 Walking API Call: $_apiUrl | SalesmanID: $_currentSalesmanId");
      final response = await http
          .post(
            Uri.parse(_apiUrl),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "action": "get_my_walkings",
              "salesman_id": _currentSalesmanId
            }),
          )
          .timeout(const Duration(seconds: 15));

      debugPrint("🌐 Walking API Response: StatusCode=${response.statusCode}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint(
            "🌐 Walking API Data: status=${data['status']}, records=${(data['data'] as List?)?.length ?? 0}");
        if (data['status'] == 'success') {
          final List<dynamic> rawList = data['data'] ?? [];
          final List<Map<String, dynamic>> allRecords = [];

          for (var item in rawList) {
            final mapItem = _toDisplayMap(item);
            allRecords.add(mapItem);
            if (mapItem['status'] == 'Billed') {
              serverBilled.add(mapItem);
            } else {
              serverPending.add(mapItem);
            }
          }

          // 🔥 Save to local DB for future instant access
          await LocalDbHelper.instance
              .syncWalkingCustomers(_currentSalesmanId, allRecords);
        } else {
          debugPrint(
              "❌ Walking API Error: ${data['message'] ?? 'Unknown error'}");
        }
      } else {
        debugPrint(
            "❌ Walking API HTTP Error: ${response.statusCode} | Body: ${response.body}");
      }
    } catch (e) {
      debugPrint("❌ Walking API Exception: $e");
    }

    if (mounted) {
      final localItems = OfflineSyncService().getPendingWalkingCustomers();

      setState(() {
        if (serverPending.isNotEmpty || serverBilled.isNotEmpty) {
          _pendingList = [...localItems, ...serverPending];
          _billedList = serverBilled;
        }
        _isLoading = false;
        _isInitialLoading = false; // 🔥 ALWAYS stop loading spinner
      });
    }
  }

  /// Helper: Convert raw API data to display map
  Map<String, dynamic> _toDisplayMap(dynamic item) {
    return {
      "id": item['id'].toString(),
      "customer_name": item['customer_name']?.toString() ?? "",
      "phone": item['phone']?.toString() ?? "",
      "product_interest": item['product_interest']?.toString() ?? "",
      "status": item['status']?.toString() ?? "Pending",
      "feedback_text": item['feedback_text'],
      "bill_photo": item['bill_photo'],
      "created_date_fmt": item['created_date_fmt'] ?? "",
      "billed_date_fmt": item['billed_date_fmt'] ?? "",
      "salesman_id": item['salesman_id']?.toString() ?? "",
      "salesman_real_name": item['salesman_real_name']?.toString() ?? "Unknown",
    };
  }

  // 🔥 NEW LOGIC: Upload Photo to PHP, Update Data to Firebase
  Future<void> _pickAndUploadBill(String customerId) async {
    if (_isPickingImage) return; // 🛑 Already picking, ignore
    _isPickingImage = true;

    try {
      // 🛡️ Guard: Request Camera Permission before opening picker
      final granted =
          await PermissionGuard.run(() => Permission.camera.request());
      if (granted != PermissionStatus.granted) {
        debugPrint("Camera Permission Denied");
        return;
      }

      final XFile? photo = await ImagePickerGuard.run(
          () => _picker.pickImage(source: ImageSource.camera, imageQuality: 50));
      if (photo == null) {
        return;
      }

      setState(() => _isLoading = true);
      _showSnack("Uploading Bill Photo...");

      // 🔥 TASK 1: Compress image to KB-level before sending
      final originalBytes = await photo.readAsBytes();
      List<int> compressedBytes = originalBytes;

      try {
        final image = img.decodeImage(originalBytes);
        if (image != null) {
          img.Image resized = image;
          // Resize to max 480px width for fast transmission
          if (image.width > 480) {
            final targetH = (image.height * (480 / image.width)).round();
            resized = img.copyResize(image, width: 480, height: targetH);
          }
          // JPEG quality 40 = ~30-80KB per image (good enough for bill photos)
          compressedBytes = img.encodeJpg(resized, quality: 40);
          debugPrint(
              "📸 Bill Image: ${originalBytes.length ~/ 1024}KB → ${compressedBytes.length ~/ 1024}KB");
        }
      } catch (compressErr) {
        debugPrint("⚠️ Bill compression failed, using original: $compressErr");
      }

      final base64Image = base64Encode(compressedBytes);

      final response = await http
          .post(
            Uri.parse(_apiUrl),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "action": "upload_bill",
              "id": customerId,
              "bill_image": base64Image
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final res = jsonDecode(response.body);
        if (res['status'] == 'success') {
          _showSnack("Bill uploaded successfully!");
          _fetchMyData(); // Refresh the list
        } else {
          _showSnack("Error: ${res['message']}", isError: true);
        }
      } else {
        _showSnack("Server Error: ${response.statusCode}", isError: true);
      }
    } on PlatformException catch (e) {
      debugPrint("Platform Error: ${e.code} - ${e.message}");
      if (e.code == 'no_available_camera') {
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text("Camera Not Found"),
              content: const Text(
                  "It seems your device doesn't have a camera available or it is being restricted."),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("OK"),
                ),
              ],
            ),
          );
        }
      } else {
        _showSnack("Camera Error: ${e.message}", isError: true);
      }
    } catch (e) {
      debugPrint("Upload Error: $e");
      _showSnack("Upload failed: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
      _isPickingImage = false; // 🔓 Release flag
    }
  }

  Future<void> _submitFeedback(String customerId) async {
    if (_feedbackController.text.trim().isEmpty) {
      return;
    }

    final body = {
      "action": "add_feedback",
      "id": customerId,
      "feedback_text": _feedbackController.text.trim(),
      "salesman_name": _currentSalesmanName,
      "sync_type": "walking"
    };

    await OfflineSyncService().saveWalkingCustomer(body);

    _showSnack("Feedback Saved in Background!");
    _feedbackController.clear();
    if (!mounted) {
      return;
    }
    Navigator.pop(context);

    final index =
        _pendingList.indexWhere((element) => element['id'] == customerId);
    if (index != -1) {
      setState(() {
        _pendingList[index]['feedback_text'] = body['feedback_text'];
      });
    }
  }

  void _showFeedbackDialog(Map<String, dynamic> item) {
    _feedbackController.clear();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Call Feedback"),
        content: TextField(
          controller: _feedbackController,
          decoration: const InputDecoration(
              hintText: "What happened?", border: OutlineInputBorder()),
          maxLines: 2,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          ElevatedButton(
              onPressed: () => _submitFeedback(item['id']),
              child: const Text("Save")),
        ],
      ),
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    try { ActivityLogger.instance.logError('UI', 'Snackbar error shown'); } catch(_) {}
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(msg),
          backgroundColor: isError ? Colors.red : Colors.green),
    );
  }

  Future<void> _saveOrUpdateCustomer() async {
    if (_nameController.text.isEmpty) {
      return;
    }

    final now = DateTime.now();

    final body = {
      "action": _editingId == null ? "add_walking" : "update_walking",
      "salesman_id": _currentSalesmanId,
      "customer_name": _nameController.text.trim(),
      "phone": _phoneController.text.trim(),
      "product_interest": _productController.text.trim(),
    };
    if (_editingId != null) {
      body['id'] = _editingId!;
    }

    setState(() {
      _isLoading = true;
    });

    final connectivityResult = await Connectivity().checkConnectivity();
    bool isOnline = !connectivityResult.contains(ConnectivityResult.none);

    bool saveSuccess = false;

    if (isOnline) {
      // 🚀 Direct Server API Call
      try {
        final response = await http
            .post(
              Uri.parse(ApiUrl.walkingCustomer),
              headers: {"Content-Type": "application/json"},
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final res = jsonDecode(response.body);
          if (res['status'] == 'success') {
            _showSnack("Saved to Database!");
            saveSuccess = true;
          } else {
            _showSnack("Error: ${res['message']}", isError: true);
          }
        } else {
          _showSnack("Server Error. Saved offline.", isError: true);
        }
      } catch (e) {
        debugPrint("Direct Upload Failed: $e");
        _showSnack("Network Issue. Saved offline.", isError: true);
      }
    } else {
      _showSnack("No Internet. Saved offline.");
    }

    // Attempt Local / Hive fallback if API failed or offline
    if (!saveSuccess) {
      await OfflineSyncService()
          .saveWalkingCustomer(Map<String, dynamic>.from(body));

      // Manually add to UI list for immediate reflection
      final newItem = {
        "id": _editingId ?? "temp_${now.millisecondsSinceEpoch}",
        "customer_name": body['customer_name'],
        "phone": body['phone'],
        "product_interest": body['product_interest'],
        "status": "Pending (Offline)",
        "created_date_fmt": "Waiting to Sync...",
        "salesman_id": _currentSalesmanId,
        "salesman_real_name": _currentSalesmanName,
        "is_local": true,
      };

      setState(() {
        if (_editingId == null) {
          _pendingList.insert(0, newItem);
        } else {
          final index = _pendingList.indexWhere((e) => e['id'] == _editingId);
          if (index != -1) {
            _pendingList[index] = newItem;
          }
        }
      });
    }

    _nameController.clear();
    _phoneController.clear();
    _productController.clear();
    _editingId = null;

    setState(() {
      _isLoading = false;
    });

    _tabController.animateTo(1);

    if (saveSuccess) {
      // Re-fetch data from server and refresh UI/LocalDB instantly
      await _fetchMyData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 85.h,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: CustomAppBar(
          title: 'Walking Customers',
          showBackButton: false,
          leading: IconButton(
              icon: const Icon(Icons.refresh), onPressed: _fetchMyData),
          actions: [
            IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context))
          ],
        ),
        body: SafeArea(
          child: _isInitialLoading
              ? Container(
                  color: theme.scaffoldBackgroundColor,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                            color: theme.colorScheme.primary),
                        SizedBox(height: 2.h),
                        Text(
                          "Loading Customers...",
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12.sp,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Container(
                      color: theme.colorScheme.surface,
                      child: TabBar(
                        controller: _tabController,
                        labelColor: theme.colorScheme.primary,
                        unselectedLabelColor: Colors.grey,
                        indicatorColor: theme.colorScheme.primary,
                        tabs: const [
                          Tab(text: "Add New"),
                          Tab(text: "Pending"),
                          Tab(text: "History"),
                        ],
                      ),
                    ),
                    if (_isLoading) const LinearProgressIndicator(),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildAddForm(theme),
                          _buildPendingList(theme),
                          _buildBilledList(theme),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildAddForm(ThemeData theme) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(4.w),
      child: Column(
        children: [
          SizedBox(height: 2.h),
          Text(_editingId == null ? "New Customer Entry" : "Edit Customer",
              style: theme.textTheme.titleMedium),
          SizedBox(height: 3.h),
          _buildTextField("Customer Name", Icons.person, _nameController),
          SizedBox(height: 2.h),
          _buildTextField("Phone", Icons.phone, _phoneController,
              isNumber: true),
          SizedBox(height: 2.h),
          _buildTextField("Product Interest", Icons.chair, _productController),
          SizedBox(height: 4.h),
          SizedBox(
            width: double.infinity,
            height: 6.h,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _saveOrUpdateCustomer,
              style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary),
              child: Text(
                  _editingId == null ? "Save Details" : "Update Details",
                  style: const TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingList(ThemeData theme) {
    if (_pendingList.isEmpty) {
      return const Center(child: Text("No pending follow-ups"));
    }

    return ListView.builder(
      padding: EdgeInsets.all(4.w),
      itemCount: _pendingList.length,
      itemBuilder: (context, index) {
        final item = _pendingList[index];
        final bool hasFeedback = item['feedback_text'] != null &&
            item['feedback_text'].toString().isNotEmpty;

        final isDark = theme.brightness == Brightness.dark;

        return Card(
          elevation: 2,
          color: isDark ? const Color(0xFF15222B) : theme.cardTheme.color,
          margin: EdgeInsets.only(bottom: 1.5.h),
          child: Padding(
            padding: EdgeInsets.all(3.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(item['customer_name'],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12.sp)),
                    ),
                    SizedBox(width: 2.w),
                    Text(item['created_date_fmt'],
                        style: TextStyle(
                            fontSize: 9.sp,
                            color: Colors.grey,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
                SizedBox(height: 1.h),
                InkWell(
                  onTap: () =>
                      launchUrl(Uri(scheme: 'tel', path: item['phone'])),
                    child: Row(
                      children: [
                        const Icon(Icons.phone, size: 16, color: Colors.blue),
                        SizedBox(width: 2.w),
                        Flexible(
                          child: Text(
                            item['phone'],
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.blue,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline),
                          ),
                        ),
                      ],
                    ),
                ),
                SizedBox(height: 0.5.h),
                Text("Needs: ${item['product_interest']}",
                    style: TextStyle(color: Colors.orange[800])),
                SizedBox(height: 1.5.h),
                if (hasFeedback)
                  Container(
                    padding: EdgeInsets.all(2.w),
                    color: theme.brightness == Brightness.dark
                        ? const Color(0xFF1C2E3A)
                        : Colors.grey.shade200,
                    width: double.infinity,
                    child: Text("Feedback: ${item['feedback_text']}",
                        style: TextStyle(
                            fontSize: 10.sp, fontStyle: FontStyle.italic)),
                  ),
                SizedBox(height: 2.h),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showFeedbackDialog(item),
                        icon: const Icon(Icons.chat_bubble_outline, size: 16),
                        label: const Text("Feedback"),
                      ),
                    ),
                    SizedBox(width: 2.w),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _pickAndUploadBill(item['id']),
                        icon: const Icon(Icons.camera_alt, size: 16),
                        label: const Text("Upload Bill"),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBilledList(ThemeData theme) {
    if (_billedList.isEmpty) {
      return const Center(child: Text("No billed customers yet"));
    }

    return ListView.builder(
      padding: EdgeInsets.all(4.w),
      itemCount: _billedList.length,
      itemBuilder: (context, index) {
        final item = _billedList[index];

        // 🔥 Handle both Old ('api/uploads/bills/') and New ('firebase_photo_uploads/bills/date/') paths
        String? billUrl;
        final rawPhoto = item['bill_photo']?.toString();

        if (rawPhoto != null && rawPhoto.isNotEmpty && rawPhoto != "null") {
          if (rawPhoto.startsWith('http')) {
            billUrl = rawPhoto;
          } else {
            // Correctly attach base url for local server paths
            final base = ApiUrl.baseUrl.endsWith('/')
                ? ApiUrl.baseUrl.substring(0, ApiUrl.baseUrl.length - 1)
                : ApiUrl.baseUrl;
            final path =
                rawPhoto.startsWith('/') ? rawPhoto.substring(1) : rawPhoto;
            billUrl = "$base/$path";
          }
        }

        final isDark = theme.brightness == Brightness.dark;

        return Card(
          elevation: 2,
          color: isDark ? const Color(0xFF15222B) : theme.cardTheme.color,
          margin: EdgeInsets.only(bottom: 1.5.h),
          child: Padding(
            padding: EdgeInsets.all(3.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle,
                        color: Colors.green[400], size: 28),
                    SizedBox(width: 3.w),
                    Expanded(
                      child: Text(item['customer_name'],
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13.sp)),
                    ),
                  ],
                ),
                SizedBox(height: 1.h),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 14, color: Colors.green[400]),
                    SizedBox(width: 2.w),
                    Text("Billed on: ${item['billed_date_fmt']}",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green[300],
                            fontSize: 10.sp)),
                  ],
                ),
                SizedBox(height: 0.5.h),
                Row(
                  children: [
                    Icon(Icons.badge_outlined,
                        size: 14,
                        color: isDark ? Colors.grey[400] : Colors.grey[700]),
                    SizedBox(width: 2.w),
                    Text(
                        "Salesman: ${item['salesman_real_name']} (${item['salesman_id']})",
                        style: TextStyle(
                            color: isDark ? Colors.grey[300] : Colors.grey[700],
                            fontSize: 10.sp)),
                  ],
                ),
                SizedBox(height: 1.h),
                const Divider(),
                Text("Phone: ${item['phone']}"),
                Text("Item: ${item['product_interest']}"),
                if (billUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: InkWell(
                      onTap: () => launchUrl(Uri.parse(billUrl!)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          const Icon(Icons.image, size: 16, color: Colors.blue),
                          SizedBox(width: 1.w),
                          const Text("View Bill Photo",
                              style: TextStyle(
                                  color: Colors.blue,
                                  decoration: TextDecoration.underline,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTextField(
      String hint, IconData icon, TextEditingController controller,
      {bool isNumber = false}) {
    return TextField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.phone : TextInputType.text,
      inputFormatters: isNumber
          ? [
              LengthLimitingTextInputFormatter(10),
              FilteringTextInputFormatter.digitsOnly
            ]
          : [],
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: Colors.grey[500]),
        labelText: hint,
        filled: true,
        fillColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF15222B)
            : Colors.grey.shade100,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
