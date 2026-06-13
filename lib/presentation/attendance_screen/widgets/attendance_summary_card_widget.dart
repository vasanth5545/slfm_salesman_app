import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';

import '../../../core/app_export.dart';

class AttendanceSummaryCardWidget extends StatelessWidget {
  final DateTime? todayClockIn;
  final DateTime? todayClockOut;
  final String attendanceRate;
  final String weeklyTotal;
  final String monthlyTotal;
  final String totalWorkedDays;
  final String totalLeavesUsed;
  final List<String> excludedDates; // 🔥 NEW

  const AttendanceSummaryCardWidget({
    super.key,
    this.todayClockIn,
    this.todayClockOut,
    this.attendanceRate = "0%",
    this.weeklyTotal = "0h 0m",
    this.monthlyTotal = "0h 0m",
    this.totalWorkedDays = "0", // 🆕
    this.totalLeavesUsed = "0", // 🆕
    this.excludedDates = const [], // 🔥 NEW
  });

  String _calculateHours() {
    if (todayClockIn == null) return '0h 0m';

    final endTime = todayClockOut ?? DateTime.now();
    final duration = endTime.difference(todayClockIn!);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    return '${hours}h ${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 4.w),
      padding: EdgeInsets.all(4.w),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.05),
            offset: const Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CustomIconWidget(
                iconName: 'schedule',
                color: theme.colorScheme.primary,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'Today\'s Summary',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: 2.h),
          Row(
            children: [
              Expanded(
                child: _buildSummaryItem(
                  context,
                  'Hours Today',
                  _calculateHours(),
                  'access_time',
                  theme.colorScheme.primary,
                ),
              ),
              SizedBox(width: 3.w),
              Expanded(
                child: _buildSummaryItem(
                  context,
                  'Weekly Hours',
                  weeklyTotal,
                  'calendar_view_week',
                  AppTheme.successLight,
                ),
              ),
            ],
          ),
          SizedBox(height: 2.h),
          Row(
            children: [
              Expanded(
                child: _buildSummaryItem(
                  context,
                  'Monthly Hours',
                  monthlyTotal,
                  'calendar_month',
                  Colors.blue,
                ),
              ),
              SizedBox(width: 3.w),
              Expanded(
                child: _buildSummaryItem(
                  context,
                  'Attendance Rate',
                  attendanceRate,
                  'trending_up',
                  AppTheme.successLight,
                ),
              ),
            ],
          ),
          SizedBox(height: 2.h),
          // 🆕 ROW: WORKED DAYS & LEAVES
          Row(
            children: [
              Expanded(
                child: _buildSummaryItem(
                  context,
                  'Days Worked',
                  totalWorkedDays,
                  'work_history',
                  Colors.teal,
                ),
              ),
              SizedBox(width: 3.w),
              Expanded(
                child: _buildSummaryItem(
                  context,
                  'Leaves Used',
                  totalLeavesUsed,
                  'event_busy',
                  Colors.redAccent,
                ),
              ),
            ],
          ),
          // 🔥 NEW SECTION: EXCLUDED DATES
          if (excludedDates.isNotEmpty) ...[
            SizedBox(height: 2.h),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(3.w),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Colors.red, size: 16),
                      SizedBox(width: 8),
                      Text(
                        "Excluded Dates (No Clock Out)",
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 1.h),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: excludedDates.map((date) {
                      return Chip(
                        label: Text(
                          date,
                          style:
                              TextStyle(fontSize: 10.sp, color: Colors.white),
                        ),
                        backgroundColor: Colors.red.shade400,
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryItem(
    BuildContext context,
    String label,
    String value,
    String iconName,
    Color color,
  ) {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.all(3.w),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CustomIconWidget(
                iconName: iconName,
                color: color,
                size: 16,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 10.sp,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: 0.5.h),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
                fontSize: 16.sp,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
