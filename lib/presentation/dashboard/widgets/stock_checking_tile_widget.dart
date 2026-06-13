import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';

import '../../../core/app_export.dart';
import '../../../widgets/custom_icon_widget.dart';

/// Stock checking tile widget - LOCKED MODE
/// Displays content in Light Gray to indicate inactive state without blurring
class StockCheckingTileWidget extends StatelessWidget {
  final int lastScanCount;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const StockCheckingTileWidget({
    super.key,
    required this.lastScanCount,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Using adaptive theme colors for a "Disabled" look that works in Dark Mode
    final disabledColor = theme.colorScheme.onSurface.withValues(alpha: 0.4);
    final disabledLightColor =
        theme.colorScheme.onSurface.withValues(alpha: 0.05);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            // --- CONTENT (Visible but Grayed Out) ---
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(4.w),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface, // Keep surface color
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Icon with Gray styling
                      Container(
                        padding: EdgeInsets.all(3.w),
                        decoration: BoxDecoration(
                          color: disabledLightColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: CustomIconWidget(
                          iconName: 'qr_code_scanner',
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
                              'Stock Checking',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: disabledColor, // Gray Text
                              ),
                            ),
                            SizedBox(height: 0.5.h),
                            Text(
                              'Scan QR codes to verify stock',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: disabledColor.withValues(
                                    alpha: 0.7), // Lighter Gray
                              ),
                            ),
                          ],
                        ),
                      ),
                      CustomIconWidget(
                        iconName: 'chevron_right',
                        color: disabledColor.withValues(alpha: 0.5),
                        size: 24,
                      ),
                    ],
                  ),
                  SizedBox(height: 2.h),
                  // Last Scan Info - Grayed Out
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
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Last Scan Count',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: disabledColor,
                                ),
                              ),
                              SizedBox(height: 0.5.h),
                              Text(
                                '$lastScanCount items',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: disabledColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
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
                                iconName: 'check_circle',
                                color: disabledColor,
                                size: 16,
                              ),
                              SizedBox(width: 1.w),
                              Text(
                                'Verified',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: disabledColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // --- LOCK BADGE (Centered) ---
            // Subtle badge that doesn't hide the content
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
                        color: disabledColor,
                      ),
                      SizedBox(width: 2.w),
                      Text(
                        "Coming Soon",
                        style: TextStyle(
                          color: disabledColor,
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
}
