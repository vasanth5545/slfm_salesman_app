import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';

/// Bottom sheet form dialog for creating/editing service reports.
///
/// Fields:
///  - Service ID (read-only, auto-generated)
///  - Toll Free / ID
///  - Customer Details (Name & Address)
///  - Fault Details (Nature of fault / Model / S.No)
///  - Remark
///  - Status toggle (Pending ↔ Finished) via checkbox
class ServiceFormDialog extends StatefulWidget {
  final String serviceId;
  final String showroomName;
  final Map<String, dynamic>? existingData;
  final Function(Map<String, dynamic>) onSave;

  const ServiceFormDialog({
    super.key,
    required this.serviceId,
    required this.showroomName,
    this.existingData,
    required this.onSave,
  });

  @override
  State<ServiceFormDialog> createState() => _ServiceFormDialogState();
}

class _ServiceFormDialogState extends State<ServiceFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _tollFreeController;
  late TextEditingController _customerController;
  late TextEditingController _faultController;
  late TextEditingController _remarkController;
  bool _isFinished = false;

  bool get _isEditing => widget.existingData != null;

  @override
  void initState() {
    super.initState();
    final data = widget.existingData;
    _tollFreeController =
        TextEditingController(text: data?['toll_free_id']?.toString() ?? '');
    _customerController = TextEditingController(
        text: data?['customer_details']?.toString() ?? '');
    _faultController =
        TextEditingController(text: data?['fault_details']?.toString() ?? '');
    _remarkController =
        TextEditingController(text: data?['remark']?.toString() ?? '');
    _isFinished = data?['status'] == 'Finished';
  }

  @override
  void dispose() {
    _tollFreeController.dispose();
    _customerController.dispose();
    _faultController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  void _handleSave() {
    if (!_formKey.currentState!.validate()) return;

    final payload = {
      'service_id': widget.serviceId,
      'showroom_name': widget.showroomName,
      'toll_free_id': _tollFreeController.text.trim(),
      'customer_details': _customerController.text.trim(),
      'fault_details': _faultController.text.trim(),
      'remark': _remarkController.text.trim(),
      'status': _isFinished ? 'Finished' : 'Pending',
    };

    widget.onSave(payload);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0B141A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 2.h),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: EdgeInsets.only(bottom: 2.h),
                      decoration: BoxDecoration(
                        color: Colors.grey[400],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Title
                  Row(
                    children: [
                      Icon(
                        _isEditing ? Icons.edit_note : Icons.add_circle,
                        color: theme.colorScheme.primary,
                        size: 28,
                      ),
                      SizedBox(width: 2.w),
                      Expanded(
                        child: Text(
                          _isEditing
                              ? "Edit Service Report"
                              : "New Service Report",
                          style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: 2.h),

                  // Service ID (read-only)
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 4.w, vertical: 1.5.h),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color:
                              theme.colorScheme.primary.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.confirmation_number,
                            size: 20, color: theme.colorScheme.primary),
                        SizedBox(width: 3.w),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Service ID",
                              style: TextStyle(
                                  fontSize: 9.sp, color: Colors.grey[500]),
                            ),
                            Text(
                              widget.serviceId,
                              style: TextStyle(
                                fontSize: 13.sp,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 2.5.h),

                  // Toll Free / ID
                  _buildField(
                    label: "Toll Free / ID",
                    hint: "Enter toll free or reference ID",
                    icon: Icons.support_agent,
                    controller: _tollFreeController,
                    isDark: isDark,
                  ),

                  SizedBox(height: 2.h),

                  // Customer Details
                  _buildField(
                    label: "Customer Details",
                    hint: "Customer name, address, phone...",
                    icon: Icons.person,
                    controller: _customerController,
                    maxLines: 3,
                    isRequired: true,
                    isDark: isDark,
                  ),

                  SizedBox(height: 2.h),

                  // Fault Details
                  _buildField(
                    label: "Fault Details",
                    hint: "Nature of fault, Model Name, S.No...",
                    icon: Icons.warning_amber,
                    controller: _faultController,
                    maxLines: 3,
                    isRequired: true,
                    isDark: isDark,
                  ),

                  SizedBox(height: 2.h),

                  // Remark
                  _buildField(
                    label: "Remark",
                    hint: "Any additional notes...",
                    icon: Icons.notes,
                    controller: _remarkController,
                    maxLines: 2,
                    isDark: isDark,
                  ),

                  SizedBox(height: 2.h),

                  // Status Toggle
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 4.w, vertical: 1.h),
                    decoration: BoxDecoration(
                      color: _isFinished
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isFinished
                            ? Colors.green.withValues(alpha: 0.4)
                            : Colors.orange.withValues(alpha: 0.4),
                      ),
                    ),
                    child: CheckboxListTile(
                      value: _isFinished,
                      onChanged: (val) {
                        setState(() => _isFinished = val ?? false);
                      },
                      title: Text(
                        _isFinished
                            ? "✅ Finished (Completed)"
                            : "⏳ Pending (In Progress)",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11.sp,
                          color: _isFinished ? Colors.green : Colors.orange,
                        ),
                      ),
                      subtitle: Text(
                        _isFinished
                            ? "This report is marked as completed"
                            : "Tick to mark this report as finished",
                        style:
                            TextStyle(fontSize: 9.sp, color: Colors.grey[500]),
                      ),
                      activeColor: Colors.green,
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),

                  SizedBox(height: 3.h),

                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 6.h,
                    child: ElevatedButton.icon(
                      onPressed: _handleSave,
                      icon: Icon(_isEditing ? Icons.save : Icons.add_circle),
                      label: Text(
                        _isEditing ? "Update Report" : "Save Report",
                        style: TextStyle(
                            fontSize: 12.sp, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),

                  SizedBox(height: 2.h),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required String label,
    required String hint,
    required IconData icon,
    required TextEditingController controller,
    required bool isDark,
    int maxLines = 1,
    bool isRequired = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: Colors.grey[500]),
            SizedBox(width: 1.5.w),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.sp,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
            if (isRequired)
              Text(" *", style: TextStyle(color: Colors.red, fontSize: 10.sp)),
          ],
        ),
        SizedBox(height: 0.8.h),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          validator: isRequired
              ? (val) {
                  if (val == null || val.trim().isEmpty) {
                    return '$label is required';
                  }
                  return null;
                }
              : null,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey[400], fontSize: 10.sp),
            filled: true,
            fillColor: isDark ? const Color(0xFF15222B) : Colors.grey[100],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                  color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                  color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary, width: 1.5),
            ),
            contentPadding:
                EdgeInsets.symmetric(horizontal: 4.w, vertical: 1.5.h),
          ),
        ),
      ],
    );
  }
}
