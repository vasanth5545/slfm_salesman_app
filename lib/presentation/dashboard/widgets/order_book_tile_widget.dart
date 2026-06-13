import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';

import '../../../core/app_export.dart';
import '../../../widgets/custom_icon_widget.dart';

/// Order book tile widget - LOCKED MODE
/// Keeps all original code structure but visually indicates "Coming Soon" state
/// using Gray colors and a Lock Badge overlay without opacity blur.
class OrderBookTileWidget extends StatelessWidget {
  final int pendingOrdersCount;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const OrderBookTileWidget({
    super.key,
    required this.pendingOrdersCount,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Define adaptive disabled colors for Dark Mode
    final disabledColor = theme.colorScheme.onSurface.withValues(alpha: 0.4);
    final disabledLightColor =
        theme.colorScheme.onSurface.withValues(alpha: 0.05);
    final disabledTextColor =
        theme.colorScheme.onSurface.withValues(alpha: 0.5);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            // --- MAIN CONTENT (Grayed Out) ---
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(4.w),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface, // Keep card background
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.2),
                ),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.shadow
                        .withValues(alpha: 0.05), // Lighter shadow
                    offset: const Offset(0, 2),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Icon Container - Gray
                      Container(
                        padding: EdgeInsets.all(3.w),
                        decoration: BoxDecoration(
                          color: disabledLightColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: CustomIconWidget(
                          iconName: 'receipt_long',
                          color: disabledColor, // Gray Icon
                          size: 32,
                        ),
                      ),
                      SizedBox(width: 3.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Order Book',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: disabledTextColor, // Gray Title
                              ),
                            ),
                            SizedBox(height: 0.5.h),
                            Text(
                              'View and manage customer orders',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: disabledTextColor.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                      CustomIconWidget(
                        iconName: 'chevron_right',
                        color: disabledTextColor.withValues(alpha: 0.5),
                        size: 24,
                      ),
                    ],
                  ),
                  SizedBox(height: 2.h),

                  // Pending Orders Row - Gray
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 3.w, vertical: 1.5.h),
                    decoration: BoxDecoration(
                      color: disabledLightColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pending Orders',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: disabledTextColor,
                              ),
                            ),
                            SizedBox(height: 0.5.h),
                            Text(
                              '$pendingOrdersCount orders',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: disabledTextColor, // Gray Text
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: EdgeInsets.all(2.w),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CustomIconWidget(
                                iconName: 'pending',
                                color: disabledTextColor,
                                size: 16,
                              ),
                              SizedBox(width: 1.w),
                              Text(
                                'Action Required',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: disabledTextColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 1.h),

                  // Quick Stats - Gray
                  Row(
                    children: [
                      Expanded(
                        child: _buildQuickStat(
                          theme,
                          'Today',
                          '0',
                          disabledColor,
                        ),
                      ),
                      SizedBox(width: 2.w),
                      Expanded(
                        child: _buildQuickStat(
                          theme,
                          'This Week',
                          '0',
                          disabledColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // --- COMING SOON BADGE OVERLAY ---
            Positioned.fill(
              child: Center(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 1.h),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.2),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.shadow.withValues(alpha: 0.1),
                        blurRadius: 12,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.lock_outline,
                        size: 16,
                        color: disabledTextColor,
                      ),
                      SizedBox(width: 2.w),
                      Text(
                        "Coming Soon",
                        style: TextStyle(
                          color: disabledTextColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 11.sp,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStat(
    ThemeData theme,
    String label,
    String value,
    Color color,
  ) {
    // Use theme-based surface variant for disabled look
    final grayColor = theme.colorScheme.onSurface.withValues(alpha: 0.4);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 2.w, vertical: 1.h),
      decoration: BoxDecoration(
        color: grayColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: grayColor,
            ),
          ),
          SizedBox(height: 0.5.h),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: grayColor,
            ),
          ),
        ],
      ),
    );
  }
}
