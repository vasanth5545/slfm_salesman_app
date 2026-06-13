import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/app_export.dart';

/// Today's attendance summary dialog (modal bottom sheet)
class TodaySummaryDialog extends StatefulWidget {
  final DateTime? todayClockIn;
  final DateTime? todayClockOut;
  final String attendanceRate;
  final String weeklyTotal;
  final String monthlyTotal;
  final String totalWorkedDays;
  final String totalLeavesUsed;
  final List<String> excludedDates;
  final String currentStatus;
  final Future<Map<String, dynamic>?> Function()? onRefresh;

  const TodaySummaryDialog({
    super.key,
    this.todayClockIn,
    this.todayClockOut,
    this.attendanceRate = "0%",
    this.weeklyTotal = "0h 0m",
    this.monthlyTotal = "0h 0m",
    this.totalWorkedDays = "0",
    this.totalLeavesUsed = "0",
    this.excludedDates = const [],
    this.currentStatus = "Not Marked",
    this.onRefresh,
  });

  static void show(
    BuildContext context, {
    DateTime? todayClockIn,
    DateTime? todayClockOut,
    String attendanceRate = "0%",
    String weeklyTotal = "0h 0m",
    String monthlyTotal = "0h 0m",
    String totalWorkedDays = "0",
    String totalLeavesUsed = "0",
    List<String> excludedDates = const [],
    String currentStatus = "Not Marked",
    Future<Map<String, dynamic>?> Function()? onRefresh,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => TodaySummaryDialog(
        todayClockIn: todayClockIn,
        todayClockOut: todayClockOut,
        attendanceRate: attendanceRate,
        weeklyTotal: weeklyTotal,
        monthlyTotal: monthlyTotal,
        totalWorkedDays: totalWorkedDays,
        totalLeavesUsed: totalLeavesUsed,
        excludedDates: excludedDates,
        currentStatus: currentStatus,
        onRefresh: onRefresh,
      ),
    );
  }

  @override
  State<TodaySummaryDialog> createState() => _TodaySummaryDialogState();
}

class _TodaySummaryDialogState extends State<TodaySummaryDialog>
    with TickerProviderStateMixin {
  late AnimationController _skeletonController;
  bool _isRefreshing = false;

  // Local state for live updates
  late DateTime? _currentIn;
  late DateTime? _currentOut;
  late String _currentRate;
  late String _currentWeekly;
  late String _currentMonthly;
  late String _currentWorked;
  late String _currentLeaves;
  late List<String> _currentExcluded;
  late String _status;

  @override
  void initState() {
    super.initState();
    _skeletonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _currentIn = widget.todayClockIn;
    _currentOut = widget.todayClockOut;
    _currentRate = widget.attendanceRate;
    _currentWeekly = widget.weeklyTotal;
    _currentMonthly = widget.monthlyTotal;
    _currentWorked = widget.totalWorkedDays;
    _currentLeaves = widget.totalLeavesUsed;
    _currentExcluded = List.from(widget.excludedDates);
    _status = widget.currentStatus;

    // 🔥 Auto-refresh seamlessly if the data is 0 when the dialog opens
    if ((_currentRate == "0%" ||
            _currentWorked == "0" ||
            _currentWorked == "0.0") &&
        widget.onRefresh != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleRefresh(silent: true);
      });
    }
  }

  @override
  void dispose() {
    _skeletonController.dispose();
    super.dispose();
  }

  String _formatDbTime(String timeStr) {
    if (timeStr.isEmpty || timeStr == "00:00:00" || timeStr == "0h 0m") {
      return "0h 0m";
    }
    if (timeStr.contains('h')) return timeStr;
    final parts = timeStr.split(':');
    if (parts.length >= 2) {
      int h = int.tryParse(parts[0]) ?? 0;
      int m = int.tryParse(parts[1]) ?? 0;
      return "${h}h ${m}m";
    }
    return timeStr;
  }

  String _calculateHoursToday() {
    if (_currentIn == null) return '0h 0m';
    final endTime = _currentOut ?? DateTime.now();
    final duration = endTime.difference(_currentIn!);
    return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
  }

  Future<void> _handleRefresh({bool silent = false}) async {
    if (widget.onRefresh == null || _isRefreshing) return;

    setState(() => _isRefreshing = true);
    try {
      final newData = await widget.onRefresh!();
      if (newData != null && mounted) {
        setState(() {
          final perf = newData['performance_data'];
          if (perf != null) {
            _currentRate =
                "${perf['attendance_percentage'] ?? perf['attendance_rate'] ?? 0}%";
            _currentWeekly = _formatDbTime(
                perf['weekly_working_hours']?.toString() ??
                    perf['weekly_total']?.toString() ??
                    perf['week_hours']?.toString() ??
                    "0h 0m");
            _currentMonthly = _formatDbTime(
                perf['total_working_hours']?.toString() ??
                    perf['monthly_total']?.toString() ??
                    perf['month_hours']?.toString() ??
                    "0h 0m");
            _currentWorked =
                (perf['total_worked_days'] ?? perf['working_days'] ?? 0)
                    .toString();
            _currentLeaves = (perf['total_days_consumed'] ??
                    perf['total_leaves_used'] ??
                    perf['leaves_used'] ??
                    0)
                .toString();
          }
          _currentIn = newData['today_clock_in'];
          _currentOut = newData['today_clock_out'];
          _status = newData['status'] ?? "Not Marked";
          _currentExcluded = (newData['excluded_dates'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [];
        });

        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Performance data refreshed! ✅"),
              duration: Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Refresh failed: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryLight.withValues(alpha: 0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.analytics_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // 🔥 FIX 3: Expanded to prevent 11px RenderFlex overflow
                  Expanded(
                    child: Text(
                      "Today's Summary",
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  if (widget.onRefresh != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: _isRefreshing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.refresh_rounded, size: 20),
                              onPressed: () => _handleRefresh(),
                              constraints: const BoxConstraints(),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                            ),
                    ),
                  _buildStatusChip(theme),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: _isRefreshing
                    ? _buildSkeletonContent(theme)
                    : Column(
                        children: [
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: _buildTimeCard(
                                    theme,
                                    "In Time",
                                    _currentIn != null
                                        ? DateFormat('hh:mm a')
                                            .format(_currentIn!)
                                        : "--:--",
                                    Icons.login_rounded,
                                    const Color(0xFF00E676), // Bright Green
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildTimeCard(
                                    theme,
                                    "Out Time",
                                    _currentOut != null
                                        ? DateFormat('hh:mm a')
                                            .format(_currentOut!)
                                        : "--:--",
                                    Icons.logout_rounded,
                                    const Color(0xFFFF1744), // Bright Red
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                  child: _buildStatCard(theme, "Hours Today",
                                      _calculateHoursToday(), Colors.blue)),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: _buildStatCard(theme, "Weekly",
                                      _currentWeekly, AppTheme.successLight)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                  child: _buildStatCard(theme, "Monthly",
                                      _currentMonthly, Colors.indigo)),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: _buildStatCard(theme, "Rate",
                                      _currentRate, Colors.teal)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                  child: _buildStatCard(theme, "Days Worked",
                                      _currentWorked, Colors.deepPurple)),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: _buildStatCard(theme, "Leaves Used",
                                      _currentLeaves, Colors.redAccent)),
                            ],
                          ),
                          if (_currentExcluded.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: Colors.red.withValues(alpha: 0.2)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.warning_amber_rounded,
                                          color: Colors.red, size: 16),
                                      const SizedBox(width: 6),
                                      Text(
                                        "Excluded Dates (No Clock Out)",
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: _currentExcluded.map((date) {
                                      return Chip(
                                        label: Text(date,
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.white)),
                                        backgroundColor: Colors.red.shade400,
                                        padding: EdgeInsets.zero,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
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
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonContent(ThemeData theme) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildSkeletonTimeCard(theme)),
            const SizedBox(width: 12),
            Expanded(child: _buildSkeletonTimeCard(theme)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildSkeletonStatCard(theme)),
            const SizedBox(width: 8),
            Expanded(child: _buildSkeletonStatCard(theme)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _buildSkeletonStatCard(theme)),
            const SizedBox(width: 8),
            Expanded(child: _buildSkeletonStatCard(theme)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _buildSkeletonStatCard(theme)),
            const SizedBox(width: 8),
            Expanded(child: _buildSkeletonStatCard(theme)),
          ],
        ),
      ],
    );
  }

  Widget _buildSkeletonTimeCard(ThemeData theme) {
    final baseColor =
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3);
    return FadeTransition(
      opacity: Tween<double>(begin: 0.4, end: 0.8).animate(_skeletonController),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 60,
              height: 12,
              decoration: BoxDecoration(
                color: baseColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: 80,
              height: 24,
              decoration: BoxDecoration(
                color: baseColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonStatCard(ThemeData theme) {
    final baseColor =
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3);
    return FadeTransition(
      opacity: Tween<double>(begin: 0.4, end: 0.8).animate(_skeletonController),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.1)),
        ),
        child: Column(
          children: [
            Container(
              width: 50,
              height: 10,
              decoration: BoxDecoration(
                color: baseColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: 40,
              height: 16,
              decoration: BoxDecoration(
                color: baseColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(ThemeData theme) {
    Color color;
    String label = _status;

    if (label.contains('Half Day')) {
      label = 'Half Day Leave';
      color = Colors.orange;
    } else if (label.contains('Full Day')) {
      label = 'Full Day Leave';
      color = Colors.red;
    } else if (label.contains('Leave')) {
      label = 'On Leave';
      color = Colors.red;
    } else if (label == 'Present') {
      color = AppTheme.successLight;
    } else if (label == 'Half Day') {
      color = Colors.orange;
    } else if (label == 'Absent') {
      color = Colors.red;
    } else {
      color = Colors.grey;
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 130),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.4),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildTimeCard(
      ThemeData theme, String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color.withValues(alpha: 0.7)),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: color,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      ThemeData theme, String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              )),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: color,
                )),
          ),
        ],
      ),
    );
  }
}
