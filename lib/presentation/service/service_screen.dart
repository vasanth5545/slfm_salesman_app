import 'dart:convert';
import 'package:slfm_salesman_app/services/activity_logger.dart';
import 'package:flutter/material.dart';

import 'package:shimmer/shimmer.dart';
import 'package:slfm_salesman_app/core/services/secure_http_client.dart'
    as http;
import '../../services/secure_storage_service.dart';
import 'package:sizer/sizer.dart';
import 'package:intl/intl.dart';

import '../../core/app_export.dart';
import '../../widgets/custom_app_bar.dart';
import './widgets/service_form_dialog.dart';

class ServiceScreen extends StatefulWidget {
  const ServiceScreen({super.key});

  @override
  State<ServiceScreen> createState() => _ServiceScreenState();
}

class _ServiceScreenState extends State<ServiceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _isLoading = false;
  bool _isInitialLoading = true;

  List<Map<String, dynamic>> _pendingList = [];
  List<Map<String, dynamic>> _finishedList = [];

  String _showroomName = "";
  String _showroomShortCode = "AB"; // Default short code

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted && !_tabController.indexIsChanging) {
        setState(() {}); // Rebuild to update FAB visibility when tab changes
      }
    });
    _loadUserData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final showroom = await SecureStorageService.getShowroomName() ?? '';
    setState(() {
      _showroomName = showroom;
      // Generate short code from showroom name (first 2 letters uppercase)
      if (showroom.length >= 2) {
        _showroomShortCode = showroom.substring(0, 2).toUpperCase();
      }
    });
    _fetchServiceReports();
  }

  Future<void> _fetchServiceReports() async {
    if (_showroomName.isEmpty) return;
    setState(() => _isLoading = true);

    try {
      final response = await http
          .post(
            Uri.parse(ApiUrl.getServiceReports),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "showroom_name": _showroomName,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success' && data['data'] != null) {
          final List rawList = data['data'];
          final List<Map<String, dynamic>> pending = [];
          final List<Map<String, dynamic>> finished = [];

          for (var item in rawList) {
            final map = Map<String, dynamic>.from(item);
            if (map['status'] == 'Finished') {
              finished.add(map);
            } else {
              pending.add(map);
            }
          }

          if (mounted) {
            setState(() {
              _pendingList = pending;
              _finishedList = finished;
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Service Fetch Error: $e");
      if (mounted) {
        _showSnack("Failed to load reports: $e", isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isInitialLoading = false;
        });
      }
    }
  }

  /// Generate next service ID: YYYY-MM-DD-ABXXX
  String _generateServiceId() {
    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(now);

    // Find the max number for today
    int maxNum = 0;
    for (var report in [..._pendingList, ..._finishedList]) {
      final sid = (report['service_id'] ?? '').toString();
      if (sid.startsWith(dateStr) && sid.length >= 3) {
        // Extract the number part (last 3 digits)
        final numPart = sid.substring(sid.length - 3);
        final num = int.tryParse(numPart) ?? 0;
        if (num > maxNum) maxNum = num;
      }
    }

    final nextNum = (maxNum + 1).toString().padLeft(3, '0');
    return '$dateStr-$_showroomShortCode$nextNum';
  }

  Future<void> _saveServiceReport(Map<String, dynamic> reportData) async {
    setState(() => _isLoading = true);

    try {
      final response = await http
          .post(
            Uri.parse(ApiUrl.saveServiceReport),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode(reportData),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final res = jsonDecode(response.body);
        if (res['status'] == 'success') {
          _showSnack("Service report saved successfully!");
          await _fetchServiceReports();
        } else {
          _showSnack("Error: ${res['message']}", isError: true);
        }
      } else {
        _showSnack("Server Error: ${response.statusCode}", isError: true);
      }
    } catch (e) {
      _showSnack("Connection Error: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openAddDialog() {
    final newId = _generateServiceId();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ServiceFormDialog(
        serviceId: newId,
        showroomName: _showroomName,
        onSave: (data) {
          Navigator.pop(ctx);
          _saveServiceReport(data);
        },
      ),
    );
  }

  void _openEditDialog(Map<String, dynamic> report) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ServiceFormDialog(
        serviceId: report['service_id'] ?? '',
        showroomName: _showroomName,
        existingData: report,
        onSave: (data) {
          Navigator.pop(ctx);
          _saveServiceReport(data);
        },
      ),
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    try { ActivityLogger.instance.logError('UI', 'Snackbar error shown'); } catch(_) {}
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildSkeletonLoading() {
    return ListView.builder(
      itemCount: 5,
      padding: EdgeInsets.all(4.w),
      itemBuilder: (_, __) => _buildSkeletonCard(),
    );
  }

  Widget _buildSkeletonCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white10 : Colors.grey[300]!;
    final highlightColor = isDark ? Colors.white24 : Colors.grey[100]!;

    return Container(
      margin: EdgeInsets.only(bottom: 2.h),
      padding: EdgeInsets.all(4.w),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF15222B) : Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: Shimmer.fromColors(
        baseColor: baseColor,
        highlightColor: highlightColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 120,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Container(
                  width: 70,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ],
            ),
            SizedBox(height: 2.h),
            Container(
              width: 180,
              height: 14,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            SizedBox(height: 1.5.h),
            Container(
              width: 140,
              height: 14,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            SizedBox(height: 2.h),
            Container(
              width: double.infinity,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            SizedBox(height: 2.h),
            const Divider(height: 1),
            SizedBox(height: 1.5.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 80,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Container(
                  width: 80,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: CustomAppBar(
        title: 'Service Reports',
        showBackButton: true,
        onBackPressed: () => Navigator.pop(context),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchServiceReports,
          ),
        ],
      ),
      floatingActionButton: _shouldShowFab(theme)
          ? FloatingActionButton.extended(
              onPressed: _openAddDialog,
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text("New Report"),
            )
          : null,
      body: SafeArea(
        child: _isInitialLoading
            ? _buildSkeletonLoading()
            : Column(
                children: [
                  // Tab Bar
                  Container(
                    color: theme.colorScheme.surface,
                    child: TabBar(
                      controller: _tabController,
                      labelColor: theme.colorScheme.primary,
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: theme.colorScheme.primary,
                      tabs: [
                        Tab(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.pending_actions, size: 18),
                              SizedBox(width: 1.5.w),
                              Text("Pending (${_pendingList.length})"),
                            ],
                          ),
                        ),
                        Tab(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.check_circle_outline, size: 18),
                              SizedBox(width: 1.5.w),
                              Text("Finished (${_finishedList.length})"),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isLoading) const LinearProgressIndicator(),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildSafeTab(_pendingList, isPending: true),
                        _buildSafeTab(_finishedList, isPending: false),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  /// Wraps report list in a safety net so build errors in a card
  /// never trigger the global FlutterError.onError / ErrorWidget.builder
  Widget _buildSafeTab(List<Map<String, dynamic>> reports,
      {required bool isPending}) {
    try {
      return _buildReportList(reports, isPending: isPending);
    } catch (e, stack) {
      debugPrint(
          "Error building ${isPending ? 'Pending' : 'Finished'} tab: $e\n$stack");
      return Center(
        child: Padding(
          padding: EdgeInsets.all(6.w),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
              SizedBox(height: 2.h),
              Text(
                "Unable to display reports",
                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 1.h),
              Text(
                "Error: $e",
                style: TextStyle(fontSize: 9.sp, color: Colors.grey[500]),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 2.h),
              ElevatedButton.icon(
                onPressed: _fetchServiceReports,
                icon: const Icon(Icons.refresh),
                label: const Text("Retry"),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildReportList(List<Map<String, dynamic>> reports,
      {required bool isPending}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (reports.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isPending ? Icons.pending_actions : Icons.check_circle_outline,
              size: 48,
              color: Colors.grey[400],
            ),
            SizedBox(height: 2.h),
            Text(
              isPending
                  ? "No pending service reports"
                  : "No finished service reports",
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12.sp,
              ),
            ),
            SizedBox(height: 2.h),
            ElevatedButton.icon(
              onPressed: _openAddDialog,
              icon: const Icon(Icons.add),
              label: const Text("Create First Report"),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchServiceReports,
      child: ListView.builder(
        padding: EdgeInsets.all(4.w),
        itemCount: reports.length,
        itemBuilder: (context, index) {
          try {
            final report = reports[index];
            return _buildReportCard(report,
                isPending: isPending, theme: theme, isDark: isDark);
          } catch (e, stack) {
            debugPrint("Error building report card #$index: $e\n$stack");
            return Card(
              color: Colors.red.withValues(alpha: 0.1),
              margin: EdgeInsets.only(bottom: 1.5.h),
              child: Padding(
                padding: EdgeInsets.all(4.w),
                child: Text(
                  "Error rendering report #${index + 1}",
                  style: TextStyle(color: Colors.red, fontSize: 10.sp),
                ),
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildReportCard(Map<String, dynamic> report,
      {required bool isPending,
      required ThemeData theme,
      required bool isDark}) {
    final statusColor = isPending ? Colors.orange : Colors.green;
    final createdAt = report['created_at']?.toString() ?? '';
    final updatedAt = report['updated_at']?.toString() ?? '';

    return Card(
      elevation: 2,
      color: isDark ? const Color(0xFF15222B) : theme.cardTheme.color,
      margin: EdgeInsets.only(bottom: 1.5.h),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: statusColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: () => _openEditDialog(report),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(4.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row: Service ID + Status Badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(Icons.confirmation_number,
                            size: 16, color: theme.colorScheme.primary),
                        SizedBox(width: 2.w),
                        Expanded(
                          child: Text(
                            (report['service_id'] ?? 'N/A').toString(),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12.sp,
                              color: theme.colorScheme.primary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border:
                          Border.all(color: statusColor.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      (report['status'] ?? 'Pending').toString(),
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 9.sp,
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: 1.5.h),

              // Toll Free ID
              if ((report['toll_free_id'] ?? '').toString().isNotEmpty) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.support_agent,
                        size: 14,
                        color: isDark ? Colors.cyan[300] : Colors.cyan[700]),
                    SizedBox(width: 2.w),
                    Expanded(
                      child: Text(
                        "Toll Free ID: ${report['toll_free_id']}",
                        style: TextStyle(
                          fontSize: 10.sp,
                          color: isDark ? Colors.cyan[300] : Colors.cyan[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 0.8.h),
              ],

              // Customer Details
              if ((report['customer_details'] ?? '').toString().isNotEmpty) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.person,
                        size: 14,
                        color: isDark ? Colors.grey[400] : Colors.grey[700]),
                    SizedBox(width: 2.w),
                    Expanded(
                      child: Text(
                        report['customer_details']?.toString() ?? '',
                        style: TextStyle(
                          fontSize: 10.sp,
                          color: isDark ? Colors.grey[300] : Colors.grey[800],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 0.8.h),
              ],

              // Fault Details
              if ((report['fault_details'] ?? '').toString().isNotEmpty) ...[
                Container(
                  padding: EdgeInsets.all(2.5.w),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.red.withValues(alpha: 0.1)
                        : Colors.red.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: Colors.red.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber,
                          size: 14, color: Colors.red[400]),
                      SizedBox(width: 2.w),
                      Expanded(
                        child: Text(
                          report['fault_details']?.toString() ?? '',
                          style: TextStyle(
                            fontSize: 10.sp,
                            color: isDark ? Colors.red[300] : Colors.red[800],
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 0.8.h),
              ],

              // Remark
              if ((report['remark'] ?? '').toString().isNotEmpty) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.notes,
                        size: 14,
                        color: isDark ? Colors.amber[300] : Colors.amber[800]),
                    SizedBox(width: 2.w),
                    Expanded(
                      child: Text(
                        "Remark: ${report['remark']}",
                        style: TextStyle(
                          fontSize: 10.sp,
                          fontStyle: FontStyle.italic,
                          color: isDark ? Colors.amber[200] : Colors.amber[900],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],

              SizedBox(height: 1.5.h),
              const Divider(height: 1),
              SizedBox(height: 1.h),

              // Footer: Created / Updated timestamps
              Wrap(
                spacing: 4.w,
                runSpacing: 0.5.h,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  if (createdAt.isNotEmpty)
                    Text(
                      "Created: ${_formatDate(createdAt)}",
                      style: TextStyle(fontSize: 8.sp, color: Colors.grey[500]),
                    ),
                  if (updatedAt.isNotEmpty && updatedAt != createdAt)
                    Text(
                      "Updated: ${_formatDate(updatedAt)}",
                      style: TextStyle(fontSize: 8.sp, color: Colors.grey[500]),
                    ),
                ],
              ),

              // Action button: Edit for pending, Undo/Revert for finished
              SizedBox(height: 1.h),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _openEditDialog(report),
                  icon: Icon(isPending ? Icons.edit : Icons.history_rounded,
                      size: 16),
                  label: Text(
                      isPending ? "Edit Report" : "Undo / Revert to Pending"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor:
                        isPending ? theme.colorScheme.primary : Colors.orange,
                    side: BorderSide(
                        color: (isPending
                                ? theme.colorScheme.primary
                                : Colors.orange)
                            .withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr);
      return DateFormat('dd MMM yyyy, hh:mm a').format(dt);
    } catch (_) {
      return dateStr;
    }
  }

  bool _shouldShowFab(ThemeData theme) {
    if (_isInitialLoading || _isLoading || _tabController.indexIsChanging) {
      return false;
    }

    // Hide FAB if the current tab is empty, as the empty state already provides a "Create" button
    try {
      if (_tabController.index == 0 && _pendingList.isEmpty) {
        return false;
      }
      if (_tabController.index == 1 && _finishedList.isEmpty) {
        return false;
      }
    } catch (_) {
      return false;
    }

    return true;
  }
}
