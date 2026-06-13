import 'dart:convert';
import 'package:slfm_salesman_app/services/activity_logger.dart';
import 'package:flutter/material.dart';
import 'package:slfm_salesman_app/core/services/secure_http_client.dart'
    as http;
import 'package:intl/intl.dart';
import '../../../services/secure_storage_service.dart';
import '../../../core/database/local_db_helper.dart';
import 'package:sizer/sizer.dart';

import '../../../core/app_export.dart';
import '../../../widgets/custom_app_bar.dart';

class LeaveRequestScreen extends StatefulWidget {
  const LeaveRequestScreen({super.key});

  @override
  State<LeaveRequestScreen> createState() => _LeaveRequestScreenState();
}

class _LeaveRequestScreenState extends State<LeaveRequestScreen> {
  final TextEditingController _reasonController = TextEditingController();

  String _selectedType = 'Full Day';
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  String _salesmanId = "";

  List<Map<String, dynamic>> _leaveHistory = [];
  bool _isHistoryLoading = false;

  final String _apiUrl = ApiUrl.leave;

  @override
  void initState() {
    super.initState();
    _loadSalesmanId();
  }

  Future<void> _loadSalesmanId() async {
    final id = await SecureStorageService.getSalesmanId();
    setState(() {
      _salesmanId = id ?? "";
    });
    if (_salesmanId.isNotEmpty) {
      _fetchLeaveHistory();
    }
  }

  // --- 1. FETCH LEAVE HISTORY (PHP API) ---
  Future<void> _fetchLeaveHistory() async {
    if (!mounted) return;
    setState(() => _isHistoryLoading = true);

    try {
      // Fetch from PHP API
      final response = await http
          .post(
            Uri.parse(_apiUrl),
            body: jsonEncode({
              "action": "get_history",
              "salesman_id": _salesmanId,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success' && data['data'] != null) {
          final List<dynamic> rawList = data['data'];
          final List<Map<String, dynamic>> serverLeaves = rawList.map((item) {
            return {
              "id": item['id']?.toString() ?? '',
              "leave_date": item['leave_date']?.toString() ?? '',
              "leave_type": item['leave_type']?.toString() ?? 'Unknown',
              "reason": item['reason']?.toString() ?? '',
              "status": item['status']?.toString() ?? 'Pending',
            };
          }).toList();

          await LocalDbHelper.instance
              .clearAndInsertLeaveHistory(_salesmanId, serverLeaves);
        }
      }
    } catch (e) {
      debugPrint("Error fetching leave history from PHP: $e");
    }

    // Always load from local DB (offline-first)
    final fullHistory =
        await LocalDbHelper.instance.getLeaveHistory(_salesmanId);

    if (mounted) {
      setState(() {
        _leaveHistory = fullHistory;
      });
    }
    if (mounted) setState(() => _isHistoryLoading = false);
  }

  // --- 2. SEND CANCEL REQUEST API ---
  Future<void> _sendCancelRequestApi(String leaveId, String message) async {
    // Show Loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        body: jsonEncode({
          "action": "request_cancellation",
          "salesman_id": _salesmanId,
          "leave_id": leaveId,
          "message": message,
        }),
      );

      if (!mounted) return;
      Navigator.pop(context); // Close Loader

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['status'] == 'success') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message']),
            backgroundColor: AppTheme.successDark,
          ),
        );
        _fetchLeaveHistory(); // Refresh list after cancel request
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message'] ?? "Failed to send request"),
            backgroundColor: AppTheme.errorDark,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      try { ActivityLogger.instance.logError('UI', 'Snackbar error shown'); } catch(_) {}
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
    }
  }

  // --- 3. SHOW CANCEL DIALOG ---
  void _showCancelRequestDialog(Map<String, dynamic> item) {
    final TextEditingController cancelMsgController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Request Cancellation"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Leave Date: ${_formatDate(item['leave_date'])}",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 1.h),
            const Text(
              "Please mention why you want to cancel (e.g., 'I am present today').",
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            SizedBox(height: 2.h),
            TextField(
              controller: cancelMsgController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: "Reason for cancellation...",
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
          ElevatedButton(
            onPressed: () {
              if (cancelMsgController.text.trim().isEmpty) {
                try { ActivityLogger.instance.logError('UI', 'Snackbar error shown'); } catch(_) {}
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text("Message required."),
                      backgroundColor: Colors.red),
                );
                return;
              }
              Navigator.pop(context);
              _sendCancelRequestApi(
                  item['id'], cancelMsgController.text.trim());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryDark,
              foregroundColor: Colors.black,
            ),
            child: const Text("Send Request"),
          ),
        ],
      ),
    );
  }

  // --- 4. SUBMIT LEAVE ---
  Future<void> _submitLeave() async {
    if (_reasonController.text.trim().isEmpty) {
      try { ActivityLogger.instance.logError('UI', 'Snackbar error shown'); } catch(_) {}
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Reason is required (Custom Message)"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_salesmanId.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final formattedDate = DateFormat('yyyy-MM-dd').format(_selectedDate);

      final response = await http.post(
        Uri.parse(_apiUrl),
        body: jsonEncode({
          "action": "apply_leave",
          "salesman_id": _salesmanId,
          "date": formattedDate,
          "type": _selectedType,
          "reason": _reasonController.text.trim(),
        }),
      );

      final data = jsonDecode(response.body);

      if (mounted) {
        if (response.statusCode == 200 && data['status'] == 'success') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['message']),
              backgroundColor: AppTheme.successDark,
            ),
          );
          _reasonController.clear();
          _fetchLeaveHistory();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['message'] ?? "Failed to submit"),
              backgroundColor: AppTheme.errorDark,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        try { ActivityLogger.instance.logError('UI', 'Snackbar error shown'); } catch(_) {}
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Connection Error: $e"),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    // Collect dates that already have leave applied (except rejected ones)
    final Set<String> leaveDates = _leaveHistory
        .where((item) => item['status'] != 'Rejected')
        .map((item) => item['leave_date'] as String)
        .toSet();

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      selectableDayPredicate: (DateTime day) {
        // Disable days where leave is already applied
        final formattedDay = DateFormat('yyyy-MM-dd').format(day);
        return !leaveDates.contains(formattedDay);
      },
      builder: (context, child) {
        final dTheme = Theme.of(context);
        return Theme(
          data: dTheme.copyWith(
            colorScheme: dTheme.colorScheme.copyWith(
              primary: AppTheme.primaryDark,
              onPrimary: Colors.black,
              onSurface: dTheme.colorScheme.onSurface,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  // --- HELPER: SAFE DATE FORMATTING ---
  String _formatDate(String dateStr) {
    try {
      return DateFormat('dd MMM yyyy').format(DateTime.parse(dateStr));
    } catch (e) {
      return dateStr; // Return original string if parsing fails
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Apply Leave',
        showBackButton: true,
        onBackPressed: () => Navigator.pop(context),
        actions: [
          IconButton(
            icon: const Icon(Icons.assignment_return_outlined),
            tooltip: "My Cancel Requests",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) =>
                        CancelRequestsHistoryScreen(salesmanId: _salesmanId)),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchLeaveHistory,
        color: theme.colorScheme.primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(4.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Select Date",
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              SizedBox(height: 1.h),
              InkWell(
                onTap: () => _selectDate(context),
                child: Container(
                  padding: EdgeInsets.all(4.w),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outline),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                          DateFormat('EEE, dd MMM yyyy').format(_selectedDate)),
                      const Icon(Icons.calendar_today),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 3.h),
              Text("Leave Type",
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              SizedBox(height: 1.h),
              Row(
                children: [
                  _buildTypeChip("Full Day"),
                  SizedBox(width: 3.w),
                  _buildTypeChip("Half Day"),
                ],
              ),
              SizedBox(height: 3.h),
              Text("Reason (Required)",
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              SizedBox(height: 1.h),
              TextField(
                controller: _reasonController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: "Enter the reason...",
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
              SizedBox(height: 3.h),
              SizedBox(
                width: double.infinity,
                height: 6.h,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitLeave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("Submit Request",
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              SizedBox(height: 2.h),
              Center(
                  child: Text("Monthly Limit: 4 Leaves",
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.grey))),
              SizedBox(height: 3.h),
              Divider(color: theme.colorScheme.outline.withValues(alpha: 0.3)),
              SizedBox(height: 2.h),
              Text("Request History (Tap to Cancel)",
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
              SizedBox(height: 2.h),
              if (_isHistoryLoading && _leaveHistory.isEmpty)
                const Center(child: CircularProgressIndicator())
              else if (_leaveHistory.isEmpty)
                SizedBox(
                  height: 20.h,
                  child: Center(
                    child: Text(
                      "No history found.\nPull down to refresh.",
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.grey),
                    ),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _leaveHistory.length,
                  itemBuilder: (context, index) {
                    final item = _leaveHistory[index];
                    return _buildHistoryItem(theme, item);
                  },
                ),
              SizedBox(height: 2.h),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryItem(ThemeData theme, Map<String, dynamic> item) {
    String status = item['status'] ?? 'Pending';
    Color statusColor;
    switch (status.toLowerCase()) {
      case 'approved':
        statusColor = Colors.green;
        break;
      case 'rejected':
        statusColor = Colors.red;
        break;
      case 'cancelled':
        statusColor = Colors.red;
        break;
      default:
        statusColor = Colors.orange;
    }

    return GestureDetector(
      onTap: () => _showCancelRequestDialog(item),
      child: Container(
        margin: EdgeInsets.only(bottom: 1.5.h),
        padding: EdgeInsets.all(3.w),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.2)),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDate(item['leave_date']),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 2.w, vertical: 0.5.h),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    status,
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: statusColor, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            SizedBox(height: 1.h),
            Row(
              children: [
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 2.w, vertical: 0.2.h),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    item['leave_type'],
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.primary),
                  ),
                ),
                const Spacer(),
                const Icon(Icons.cancel_outlined, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Text("Request Cancel",
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: Colors.grey)),
              ],
            ),
            SizedBox(height: 1.h),
            Text(
              "Reason: ${item['reason']}",
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeChip(String type) {
    final isSelected = _selectedType == type;
    final theme = Theme.of(context);
    return ChoiceChip(
      label: Text(type),
      selected: isSelected,
      onSelected: (val) => setState(() => _selectedType = type),
      selectedColor: AppTheme.primaryDark,
      labelStyle: TextStyle(
          color: isSelected ? Colors.black : theme.colorScheme.onSurface),
    );
  }
}

// --- NEW PAGE: Cancel Requests History ---
class CancelRequestsHistoryScreen extends StatefulWidget {
  final String salesmanId;
  const CancelRequestsHistoryScreen({super.key, required this.salesmanId});

  @override
  State<CancelRequestsHistoryScreen> createState() =>
      _CancelRequestsHistoryScreenState();
}

class _CancelRequestsHistoryScreenState
    extends State<CancelRequestsHistoryScreen> {
  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;
  @override
  void initState() {
    super.initState();
    _fetchRequests();
  }

  Future<void> _fetchRequests() async {
    try {
      final response = await http
          .post(
            Uri.parse(ApiUrl.leave),
            body: jsonEncode({
              "action": "get_cancel_requests",
              "salesman_id": widget.salesmanId,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success' && data['data'] != null) {
          final List<dynamic> rawList = data['data'];
          final List<Map<String, dynamic>> loadedRequests = rawList.map((item) {
            return {
              "id": item['id']?.toString() ?? '',
              "request_message": item['request_message']?.toString() ??
                  item['cancel_reason']?.toString() ??
                  '',
              "leave_date": item['leave_date']?.toString() ?? '',
              "leave_type": item['leave_type']?.toString() ?? '',
              "created_at": item['created_at']?.toString() ??
                  DateTime.now().toIso8601String(),
              "status": item['status']?.toString() ?? '',
            };
          }).toList();

          loadedRequests
              .sort((a, b) => b['created_at'].compareTo(a['created_at']));

          if (mounted) {
            setState(() {
              _requests = loadedRequests;
              _isLoading = false;
            });
          }
        } else {
          if (mounted) setState(() => _isLoading = false);
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("Error fetching cancel requests: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: "Cancel Requests Log",
        showBackButton: true,
        onBackPressed: () => Navigator.pop(context),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _requests.isEmpty
              ? const Center(child: Text("No cancel requests sent."))
              : ListView.builder(
                  padding: EdgeInsets.all(4.w),
                  itemCount: _requests.length,
                  itemBuilder: (context, index) {
                    final req = _requests[index];
                    return Card(
                      margin: EdgeInsets.only(bottom: 1.5.h),
                      elevation: 2,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue.withValues(alpha: 0.1),
                          child: const Icon(Icons.mark_email_read,
                              color: Colors.blue),
                        ),
                        title: Text(
                          req['request_message'],
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                                "Leave Date: ${req['leave_date']} (${req['leave_type']})"),
                            Text(
                              "Sent: ${DateFormat('dd MMM hh:mm a').format(DateTime.parse(req['created_at']))}",
                              style: TextStyle(
                                  fontSize: 10.sp, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
