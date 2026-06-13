import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';

import '../../../core/app_export.dart';
import '../../../widgets/custom_icon_widget.dart';

/// Customer Follow-up Tile Widget
/// Displays Pending & Finished counts for Walking Customers
class CustomerFollowupTileWidget extends StatelessWidget {
  final int pendingCount;
  final int billedCount;
  final VoidCallback onTap;

  const CustomerFollowupTileWidget({
    super.key,
    required this.pendingCount,
    required this.billedCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: primaryColor.withValues(alpha: 0.1),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(4.w),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.2),
            ),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.shadow.withValues(alpha: 0.08),
                offset: const Offset(0, 2),
                blurRadius: 8,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(3.w),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: CustomIconWidget(
                      iconName: 'groups', // Icon Name
                      color: primaryColor,
                      size: 32,
                    ),
                  ),
                  SizedBox(width: 3.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Customer Follow-up',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 0.5.h),
                        Text(
                          'Track & Close Walking Customers',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                ],
              ),
              SizedBox(height: 2.h),

              // Stats Row (Pending & Finished)
              Row(
                children: [
                  // Pending Box
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.all(3.w),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.orange.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.pending_actions,
                                  size: 16,
                                  color: theme.brightness == Brightness.dark
                                      ? Colors.orange[300]
                                      : Colors.orange[800]),
                              SizedBox(width: 1.w),
                              Text("Pending",
                                  style: TextStyle(
                                      color: theme.brightness == Brightness.dark
                                          ? Colors.orange[300]
                                          : Colors.orange[800],
                                      fontSize: 10.sp)),
                            ],
                          ),
                          SizedBox(height: 0.5.h),
                          Text(
                            "$pendingCount",
                            style: TextStyle(
                                fontSize: 16.sp,
                                fontWeight: FontWeight.bold,
                                color: theme.brightness == Brightness.dark
                                    ? Colors.orange[200]
                                    : Colors.orange[900]),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: 3.w),

                  // Finished Box
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.all(3.w),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.green.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.check_circle_outline,
                                  size: 16,
                                  color: theme.brightness == Brightness.dark
                                      ? Colors.green[300]
                                      : Colors.green[800]),
                              SizedBox(width: 1.w),
                              Text("Finished",
                                  style: TextStyle(
                                      color: theme.brightness == Brightness.dark
                                          ? Colors.green[300]
                                          : Colors.green[800],
                                      fontSize: 10.sp)),
                            ],
                          ),
                          SizedBox(height: 0.5.h),
                          Text(
                            "$billedCount",
                            style: TextStyle(
                                fontSize: 16.sp,
                                fontWeight: FontWeight.bold,
                                color: theme.brightness == Brightness.dark
                                    ? Colors.green[200]
                                    : Colors.green[900]),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
