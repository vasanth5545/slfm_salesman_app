import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sizer/sizer.dart';

import '../../../core/app_export.dart';

class AttendanceHistoryListWidget extends StatefulWidget {
  final List<Map<String, dynamic>> attendanceHistory;
  final List<Map<String, dynamic>>? performanceDataList;

  const AttendanceHistoryListWidget({
    super.key,
    required this.attendanceHistory,
    this.performanceDataList,
  });

  @override
  State<AttendanceHistoryListWidget> createState() =>
      _AttendanceHistoryListWidgetState();
}

class _AttendanceHistoryListWidgetState
    extends State<AttendanceHistoryListWidget> {
  List<Widget> _cachedListViewChildren = [];
  bool _needsRebuild = true;
  late ThemeData _cachedTheme;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = Theme.of(context);
    if (_needsRebuild || _cachedTheme != theme) {
      _cachedTheme = theme;
      _buildCachedChildren();
      _needsRebuild = false;
    }
  }

  @override
  void didUpdateWidget(covariant AttendanceHistoryListWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.attendanceHistory != oldWidget.attendanceHistory ||
        widget.performanceDataList != oldWidget.performanceDataList) {
      _buildCachedChildren();
    }
  }

  void _buildCachedChildren() {
    final theme = _cachedTheme;

    // 1. Combine and Deduplicate records
    Map<String, Map<String, dynamic>> uniqueRecords = {};
    for (var item in widget.attendanceHistory) {
      String dateStr = item['date']?.toString() ?? "";
      String normalized = _cleanDateString(dateStr);
      if (normalized.isEmpty) continue;

      if (!uniqueRecords.containsKey(normalized)) {
        uniqueRecords[normalized] = item;
      } else {
        var existing = uniqueRecords[normalized]!;
        if ((existing['clock_in'] == null ||
                existing['clock_in'].toString().isEmpty) &&
            (item['clock_in'] != null &&
                item['clock_in'].toString().isNotEmpty)) {
          uniqueRecords[normalized] = item;
        }
      }
    }

    List<Map<String, dynamic>> allData = uniqueRecords.values.toList();

    // 2. Sort all records by date descending (Newest first)
    allData.sort((a, b) {
      try {
        String d1 = _cleanDateString(a['date'].toString());
        String d2 = _cleanDateString(b['date'].toString());
        DateTime? dateA = DateTime.tryParse(d1);
        DateTime? dateB = DateTime.tryParse(d2);

        if (dateA != null && dateB != null) {
          return dateB.compareTo(dateA);
        }
        return 0;
      } catch (e) {
        return 0;
      }
    });

    // 3. Group by Month associated with Year
    Map<String, List<dynamic>> groupedByMonth = {};
    for (var item in allData) {
      try {
        String dateStr = item['date'] ?? '';
        DateTime? date = DateTime.tryParse(dateStr);
        if (date == null) {
          try {
            date = DateFormat("d MMM yyyy").parse(dateStr);
          } catch (_) {}
        }

        if (date != null) {
          String monthKey = DateFormat("MMMM yyyy").format(date);
          if (!groupedByMonth.containsKey(monthKey)) {
            groupedByMonth[monthKey] = [];
          }
          groupedByMonth[monthKey]!.add(item);
        }
      } catch (e) {
        debugPrint('History item parse error: $e');
      }
    }

    // 4. Build the UI List
    List<Widget> listViewChildren = [];

    if (allData.isEmpty) {
      listViewChildren.add(_buildEmptyState(theme));
      setState(() {
        _cachedListViewChildren = listViewChildren;
      });
      return;
    }

    groupedByMonth.forEach((month, records) {
      listViewChildren.add(_buildSectionHeader(
          theme, month.toUpperCase(), theme.colorScheme.primary));

      List<Widget> recordWidgets = [];
      for (var i = 0; i < records.length; i++) {
        recordWidgets.add(
            _buildHistoryCard(context, records[i] as Map<String, dynamic>));
      }

      Widget summaryWidget = _buildCalculationSummary(context, records);

      // ✅ FIX 1: Summary-ஐ month-ல் முதல் card-க்கு முன்னாடி insert செய்கிறோம் (index 0)
      // பழைய bug: insert(1) → summary second card-க்கு பக்கத்தில் போகும்
      if (recordWidgets.isNotEmpty) {
        recordWidgets.insert(0, summaryWidget);
      } else {
        recordWidgets.add(summaryWidget);
      }

      listViewChildren.addAll(recordWidgets);
    });

    setState(() {
      _cachedListViewChildren = listViewChildren;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = _cachedTheme;

    return Column(
      children: [
        // --- HEADER ---
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.shadow.withValues(alpha: 0.05),
                offset: const Offset(0, 2),
                blurRadius: 4,
              ),
            ],
          ),
          child: Row(
            children: [
              CustomIconWidget(
                iconName: 'history',
                color: theme.colorScheme.primary,
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Activity Log',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${widget.attendanceHistory.length} records',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 4.w,
              right: 4.w,
              top: 2.h,
              bottom: MediaQuery.paddingOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ..._cachedListViewChildren,
                SizedBox(height: 12.h),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCalculationSummary(BuildContext context, List<dynamic> records) {
    final theme = Theme.of(context);

    int excludedCount = 0;
    Set<String> uniqueDates = {};

    int presentCount = 0;
    int absentCount = 0;
    int halfDayCount = 0;
    int leaveCount = 0;
    List<String> excludedDatesList = [];

    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);

    // எந்த மாதத்திற்கான Records என்பதை முதலில் கண்டுபிடிக்கிறோம்
    String groupMonthFormat = "";
    if (records.isNotEmpty) {
      try {
        String dStr = records.first['date']?.toString() ?? "";
        DateTime? d = DateTime.tryParse(dStr);
        d ??= DateFormat("d MMM yyyy").parse(dStr);
        groupMonthFormat = DateFormat("yyyy-MM").format(d);
      } catch (_) {}
    }

    for (var record in records) {
      final String date = record['date']?.toString() ?? "";
      if (date.isEmpty) continue;
      final String status = record['status']?.toString() ?? "";

      final String clockOut = record['clock_out_time']?.toString() ??
          record['clockOut']?.toString() ??
          record['clock_out']?.toString() ??
          "";

      bool isToday =
          date == todayStr || date == DateFormat('dd MMM yyyy').format(now);

      final String clockIn = record['clock_in_time']?.toString() ??
          record['clockIn']?.toString() ??
          record['clock_in']?.toString() ??
          "";

      bool isOutMissing = clockOut.isEmpty ||
          clockOut == "00:00:00" ||
          clockOut == "null" ||
          clockOut == "--:--";

      bool isInPresent = clockIn.isNotEmpty &&
          clockIn != "00:00:00" &&
          clockIn != "null" &&
          clockIn != "--:--";

      bool isExcluded = false;
      if (!isToday &&
          isOutMissing &&
          isInPresent &&
          (status.contains('Present') || status.contains('Half Day'))) {
        isExcluded = true;
        excludedCount++;
        try {
          DateTime? d = DateTime.tryParse(date);
          d ??= DateFormat("d MMM yyyy").parse(date);
          excludedDatesList.add(DateFormat("dd MMM").format(d));
        } catch (e) {
          excludedDatesList.add(date);
        }
      }

      if (isExcluded) {
        continue;
      }

      uniqueDates.add(date);

      if (status == 'Present' || status == 'Late') {
        presentCount++;
      } else if (status == 'Absent' || status.contains('Absent')) {
        absentCount++;
      } else if (status.contains('Half Day')) {
        halfDayCount++;
      } else if (status == 'On Leave' ||
          status == 'Leave' ||
          status == 'Approved') {
        leaveCount++;
      }
    }

    int totalConsidered = uniqueDates.length;
    double totalWork = presentCount.toDouble() + (halfDayCount * 0.5);
    double totalLeave =
        leaveCount.toDouble() + absentCount.toDouble() + (halfDayCount * 0.5);

    // Server Data-வை வைத்து Override செய்கிறோம்
    Map<String, dynamic>? performanceData;
    if (widget.performanceDataList != null) {
      try {
        performanceData = widget.performanceDataList!.firstWhere((element) {
          return element['report_month'] == groupMonthFormat;
        }, orElse: () => <String, dynamic>{});

        if (performanceData.isEmpty) {
          performanceData = null;
        }
      } catch (_) {}
    }

    if (performanceData != null) {
      presentCount =
          int.tryParse(performanceData['total_present']?.toString() ?? '') ??
              presentCount;
      absentCount =
          int.tryParse(performanceData['total_absent']?.toString() ?? '') ??
              absentCount;
      halfDayCount =
          int.tryParse(performanceData['total_half_days']?.toString() ?? '') ??
              halfDayCount;
      leaveCount = int.tryParse(
              performanceData['total_full_leaves']?.toString() ?? '') ??
          leaveCount;

      if (performanceData['excluded_dates'] is List) {
        List<dynamic> exList = performanceData['excluded_dates'];
        excludedCount = exList.length;
        excludedDatesList = exList.map((e) {
          try {
            DateTime? d = DateTime.tryParse(e.toString());
            return d != null ? DateFormat("dd MMM").format(d) : e.toString();
          } catch (_) {
            return e.toString();
          }
        }).toList();
      }

      var workRaw = performanceData['total_worked_days'] ??
          performanceData['working_days'] ??
          totalWork;
      totalWork = double.tryParse(workRaw.toString()) ?? totalWork.toDouble();

      var leaveRaw = performanceData['total_days_consumed'] ??
          performanceData['total_leaves_used'] ??
          totalLeave;
      totalLeave =
          double.tryParse(leaveRaw.toString()) ?? totalLeave.toDouble();
      totalConsidered = (totalWork + totalLeave).toInt();
    }

    return Container(
      width: double.infinity,
      margin: EdgeInsets.symmetric(vertical: 2.h),
      padding: EdgeInsets.all(5.w),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.analytics_outlined,
                  color: theme.colorScheme.primary, size: 20),
              SizedBox(width: 2.w),
              Flexible(
                child: Text(
                  "SUMMARY REPORT",
                  style: TextStyle(
                    fontSize: 11.sp,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: theme.colorScheme.primary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Divider(height: 3.h, thickness: 1),
          _buildSummaryRow(theme, "Total Considered", "$totalConsidered Days",
              isBold: true),
          SizedBox(height: 1.5.h),
          _buildSummaryRow(theme, "Present (Full Work)", "$presentCount"),
          _buildSummaryRow(theme, "Absent (No Work)", "$absentCount",
              isError: absentCount > 0),
          _buildSummaryRow(theme, "Half Day Status", "$halfDayCount"),
          _buildSummaryRow(theme, "Full Leave Applied", "$leaveCount"),
          if (excludedCount > 0) ...[
            _buildSummaryRow(theme, "Excluded (No Out)", "$excludedCount",
                isError: true),
            Padding(
              padding: EdgeInsets.only(top: 0.5.h, bottom: 0.5.h),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: excludedDatesList.map((d) {
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      border:
                          Border.all(color: Colors.red.withValues(alpha: 0.3)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      d,
                      style: TextStyle(
                          fontSize: 9.sp,
                          color: Colors.red.shade400,
                          fontWeight: FontWeight.bold),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
          Divider(height: 3.h, thickness: 1),
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.all(3.w),
                  child: _buildSummaryRow(theme, "Total Work\nCalculation",
                      "($presentCount + $halfDayCount*0.5) = $totalWork Days",
                      isPrimary: true),
                ),
                // ✅ FIX 3: Future.delayed நீக்கப்பட்டது — showDialog direct-ஆக call ஆகும்
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      _showLeaveDetailsDialog(context, theme, records);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: EdgeInsets.only(
                          left: 3.w, right: 3.w, bottom: 3.w, top: 1.h),
                      child: _buildSummaryRow(
                          theme,
                          "Total Leave\n(Status/Cut)",
                          "($leaveCount + $absentCount + $halfDayCount*0.5) = $totalLeave Days",
                          isError: true),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ✅ FIX 3: Future.delayed முழுவதும் நீக்கப்பட்டது
  // showDialog direct-ஆக call ஆகும் — context.mounted check தேவையில்லை
  void _showLeaveDetailsDialog(
      BuildContext context, ThemeData theme, List<dynamic> records) {
    final List<Map<String, dynamic>> leaveRecords = [];
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);
    final todayDisplayStr = DateFormat('dd MMM yyyy').format(now);

    for (var record in records) {
      final String status = record['status']?.toString() ?? "";
      final String date = record['date']?.toString() ?? "";
      if (date.isEmpty) continue;

      if (status == 'Absent' ||
          status.contains('Absent') ||
          status.contains('Half Day') ||
          status == 'On Leave' ||
          status == 'Leave' ||
          status == 'Approved') {
        final String clockOut = record['clock_out_time']?.toString() ??
            record['clockOut']?.toString() ??
            record['clock_out']?.toString() ??
            "";
        final String clockIn = record['clock_in_time']?.toString() ??
            record['clockIn']?.toString() ??
            record['clock_in']?.toString() ??
            "";

        bool isToday = date == todayStr || date == todayDisplayStr;
        bool isOutMissing = clockOut.isEmpty ||
            clockOut == "00:00:00" ||
            clockOut == "null" ||
            clockOut == "--:--";
        bool isInPresent = clockIn.isNotEmpty &&
            clockIn != "00:00:00" &&
            clockIn != "null" &&
            clockIn != "--:--";

        // ✅ FIX 2: 'Present' check நீக்கப்பட்டது — இங்கே loop-ல் வரும் records
        // already Absent/Leave/HalfDay மட்டுமே. 'Present' இங்கே match ஆகவே ஆகாது.
        // பழைய bug: (status == 'Present' || status == 'Half Day') — 'Present' dead code
        if (!isToday && isOutMissing && isInPresent && status.contains('Half Day')) {
          continue;
        }

        String displayStatus = status;
        Color badgeColor = Colors.orange;
        if (status.contains('Absent')) badgeColor = Colors.red;
        if (status.contains('Half Day')) {
          badgeColor = Colors.blue;
        }

        leaveRecords.add({
          ...Map<String, dynamic>.from(record),
          '_displayStatus': displayStatus,
          '_badgeColor': badgeColor,
          '_cleanDate': _cleanDateString(date),
        });
      }
    }

    leaveRecords.sort((a, b) {
      try {
        DateTime? d1 = DateTime.tryParse(a['date'] ?? "");
        d1 ??= DateFormat("d MMM yyyy").parse(a['date'] ?? "");
        DateTime? d2 = DateTime.tryParse(b['date'] ?? "");
        d2 ??= DateFormat("d MMM yyyy").parse(b['date'] ?? "");
        return d2.compareTo(d1);
      } catch (_) {
        return 0;
      }
    });

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.event_busy, color: Colors.orange.shade700, size: 24),
              const SizedBox(width: 8),
              Text(
                "Leave & Absent Details",
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: leaveRecords.isEmpty
                ? Padding(
                    padding: EdgeInsets.all(4.w),
                    child: Text("No leave or absent records found.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant)),
                  )
                : ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: 60.h),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: leaveRecords.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final record = leaveRecords[index];
                        final displayStatus = record['_displayStatus'];
                        final badgeColor = record['_badgeColor'] as Color;
                        final cleanDate = record['_cleanDate'];

                        return Padding(
                          padding: EdgeInsets.symmetric(vertical: 1.5.h),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  cleanDate,
                                  style: TextStyle(
                                    fontSize: 11.sp,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: badgeColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: badgeColor.withValues(alpha: 0.3)),
                                ),
                                child: Text(
                                  displayStatus,
                                  style: TextStyle(
                                    color: badgeColor,
                                    fontSize: 9.sp,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                "Close",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11.sp,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSummaryRow(ThemeData theme, String label, String value,
      {bool isBold = false, bool isPrimary = false, bool isError = false}) {
    final double labelSize = (isPrimary || isError) ? 11.sp : 10.sp;
    final double valueSize = (isPrimary || isError) ? 10.5.sp : 9.5.sp;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 0.8.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: TextStyle(
                fontSize: labelSize,
                fontWeight: isBold || isPrimary || isError
                    ? FontWeight.bold
                    : FontWeight.w500,
                color: isPrimary
                    ? Colors.green.shade400
                    : isError
                        ? Colors.red.shade400
                        : theme.colorScheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
          ),
          SizedBox(width: 2.w),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.right,
              softWrap: true,
              style: TextStyle(
                fontSize: valueSize,
                fontWeight: FontWeight.bold,
                color: isPrimary
                    ? Colors.green.shade400
                    : isError
                        ? Colors.red.shade400
                        : theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title, Color color) {
    return Padding(
      padding: EdgeInsets.only(bottom: 1.5.h, top: 0.5.h),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2)),
          ),
          SizedBox(width: 2.w),
          Text(
            title,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 11.sp,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CustomIconWidget(
            iconName: 'event_busy',
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            size: 64,
          ),
          SizedBox(height: 2.h),
          Text(
            'No attendance in the last 30 days',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  String _calculateDurationSafely(String inStr, String outStr) {
    if (inStr.isEmpty ||
        outStr.isEmpty ||
        inStr == "--:--" ||
        outStr == "--:--" ||
        inStr == "null" ||
        outStr == "null") {
      return "--";
    }
    try {
      DateTime? dIn = _parseFlexibleTime(inStr);
      DateTime? dOut = _parseFlexibleTime(outStr);
      if (dIn == null || dOut == null) return "--";
      Duration diff = dOut.difference(dIn);
      if (diff.isNegative) return "--";
      int h = diff.inHours;
      int m = diff.inMinutes.remainder(60);
      return "${h}h ${m}m";
    } catch (e) {
      return "--";
    }
  }

  DateTime? _parseFlexibleTime(String raw) {
    if (raw.isEmpty || raw == '--:--' || raw == 'null') return null;
    DateTime? parsed = DateTime.tryParse(raw);
    if (parsed != null) return parsed;
    if (raw.toUpperCase().contains('AM') || raw.toUpperCase().contains('PM')) {
      try {
        return DateFormat('hh:mm:ss a').parse(raw);
      } catch (_) {
        try {
          return DateFormat('hh:mm a').parse(raw);
        } catch (_) {}
      }
    }
    try {
      return DateFormat('HH:mm:ss').parse(raw);
    } catch (_) {
      try {
        return DateFormat('HH:mm').parse(raw);
      } catch (_) {}
    }
    return null;
  }

  Widget _buildHistoryCard(BuildContext context, Map<String, dynamic> record) {
    return _ExpandableHistoryCard(
      record: record,
      formatTimeAmPm: _formatTimeAmPm,
      cleanDateString: _cleanDateString,
      calculateDuration: _calculateDurationSafely,
      parseExtraBreakTime: _parseExtraBreakTime,
      formatExtraBreakTime: _formatExtraBreakTime,
      buildImage: _buildImage,
    );
  }

  String _cleanDateString(String dateStr) {
    if (dateStr.isEmpty) return "";
    String clean = dateStr.trim();
    if (clean.contains(" to ")) {
      clean = clean.split(" to ")[0].trim();
    }
    if (clean.contains("T")) {
      clean = clean.split("T")[0];
    }
    if (clean.contains(" ")) {
      clean = clean.split(" ")[0];
    }
    return clean;
  }

  String _formatTimeAmPm(String raw) {
    if (raw.isEmpty || raw == '--:--' || raw == 'null') return raw;
    try {
      DateTime? parsed = DateTime.tryParse(raw);
      if (parsed != null) {
        return DateFormat('hh:mm a').format(parsed);
      }
      if (raw.toUpperCase().contains('AM') ||
          raw.toUpperCase().contains('PM')) {
        try {
          parsed = DateFormat('hh:mm:ss a').parse(raw);
          return DateFormat('hh:mm a').format(parsed);
        } catch (_) {
          try {
            parsed = DateFormat('hh:mm a').parse(raw);
            return DateFormat('hh:mm a').format(parsed);
          } catch (_) {}
        }
      }
      final formats = ['HH:mm:ss', 'HH:mm'];
      for (final fmt in formats) {
        try {
          parsed = DateFormat(fmt).parse(raw);
          return DateFormat('hh:mm a').format(parsed);
        } catch (_) {}
      }
    } catch (_) {}
    return raw;
  }

  Widget _buildImage(ThemeData theme, String? imageUrl, String? semanticLabel,
      {double? customSize}) {
    final double size = customSize ?? 15.w;
    final String safeUrl = (imageUrl ?? '').trim();

    final Widget fallbackImage = Image.asset(
      'assets/images/vijay.jpg',
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          width: size,
          height: size,
          color: theme.colorScheme.primaryContainer,
          child: Center(
            child: Icon(Icons.person, color: theme.colorScheme.primary),
          ),
        );
      },
    );

    if (safeUrl.isEmpty || safeUrl == 'mock_url.jpg') {
      return fallbackImage;
    }

    if (safeUrl.startsWith('http')) {
      return CustomImageWidget(
        imageUrl: safeUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        semanticLabel: semanticLabel,
        errorWidget: fallbackImage,
      );
    }

    if (safeUrl.startsWith('/') ||
        safeUrl.startsWith('file://') ||
        RegExp(r'^[a-zA-Z]:[/\\]').hasMatch(safeUrl)) {
      return Image.file(
        File(safeUrl.replaceFirst('file://', '')),
        width: size,
        height: size,
        fit: BoxFit.cover,
        semanticLabel: semanticLabel,
        errorBuilder: (context, error, stackTrace) => fallbackImage,
      );
    }

    return Image.asset(
      safeUrl,
      width: size,
      height: size,
      fit: BoxFit.cover,
      semanticLabel: semanticLabel,
      errorBuilder: (context, error, stackTrace) => fallbackImage,
    );
  }

  int _parseExtraBreakTime(Map<String, dynamic> record) {
    if (record.containsKey('extra_break_time')) {
      return int.tryParse(record['extra_break_time'].toString()) ?? 0;
    }
    if (record.containsKey('server_data')) {
      try {
        final serverData = record['server_data'];
        Map<String, dynamic>? parsed;
        if (serverData is String) {
          parsed = Map<String, dynamic>.from(json.decode(serverData) as Map);
        } else if (serverData is Map) {
          parsed = Map<String, dynamic>.from(serverData);
        }
        if (parsed != null && parsed.containsKey('extra_break_time')) {
          return int.tryParse(parsed['extra_break_time'].toString()) ?? 0;
        }
      } catch (_) {}
    }
    return 0;
  }

  String _formatExtraBreakTime(int totalSeconds) {
    if (totalSeconds <= 0) return "";
    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds % 3600) ~/ 60;
    final int seconds = totalSeconds % 60;

    if (hours > 0) {
      return "+${hours}h ${minutes.toString().padLeft(2, '0')}m ${seconds.toString().padLeft(2, '0')}s";
    } else if (minutes > 0) {
      return "+${minutes}m ${seconds.toString().padLeft(2, '0')}s";
    } else {
      return "+${seconds}s";
    }
  }
}

class _ExpandableHistoryCard extends StatefulWidget {
  final Map<String, dynamic> record;
  final String Function(String) formatTimeAmPm;
  final String Function(String) cleanDateString;
  final String Function(String, String) calculateDuration;
  final int Function(Map<String, dynamic>) parseExtraBreakTime;
  final String Function(int) formatExtraBreakTime;
  final Widget Function(ThemeData, String?, String?, {double? customSize})
      buildImage;

  const _ExpandableHistoryCard({
    required this.record,
    required this.formatTimeAmPm,
    required this.cleanDateString,
    required this.calculateDuration,
    required this.parseExtraBreakTime,
    required this.formatExtraBreakTime,
    required this.buildImage,
  });

  @override
  State<_ExpandableHistoryCard> createState() => _ExpandableHistoryCardState();
}

class _ExpandableHistoryCardState extends State<_ExpandableHistoryCard>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final record = widget.record;
    final String? thumbnail = record["thumbnail"];

    final String clockOut = record['clock_out_time']?.toString() ??
        record['clockOut']?.toString() ??
        record['clock_out']?.toString() ??
        "";

    final String clockIn = record['clock_in_time']?.toString() ??
        record['clockIn']?.toString() ??
        record['clock_in']?.toString() ??
        "";

    final String dateStr = record["date"]?.toString() ?? "";
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);
    final todayStrAlt = DateFormat('dd MMM yyyy').format(now);
    final bool isToday =
        (dateStr == todayStr || dateStr == todayStrAlt || dateStr == "Today");

    bool isOutMissing = clockOut.isEmpty ||
        clockOut == "00:00:00" ||
        clockOut == "null" ||
        clockOut == "--:--";

    final String status = record["status"]?.toString() ?? "";
    bool isExcludedStatus = false;
    if (!isToday &&
        isOutMissing &&
        (status.contains('Present') || status.contains('Half Day'))) {
      isExcludedStatus = true;
    }

    final bool isAbsent = status == 'Absent';
    final bool isOnLeave =
        status == 'On Leave' || status == 'Leave' || status == 'Approved';
    final bool isExcluded = status == 'Excluded' || isExcludedStatus;

    Color badgeColor = Colors.grey;
    if (isAbsent) {
      badgeColor = Colors.red;
    } else if (isOnLeave) {
      badgeColor = Colors.orange;
    } else if (status.contains('Half Day')) {
      badgeColor = Colors.blue;
    } else if (status.contains('Present')) {
      badgeColor = Colors.green;
    } else if (status.contains('Late')) {
      badgeColor = Colors.purple;
    } else if (isExcluded) {
      badgeColor = Colors.redAccent;
    }

    List<Widget> contentWidgets = [];
    if (isAbsent) {
      contentWidgets = [
        SizedBox(height: 0.5.h),
        Text("Marked Absent",
            style: TextStyle(
                color: Colors.red,
                fontSize: 11.sp,
                fontWeight: FontWeight.bold)),
      ];
    } else if (isOnLeave) {
      contentWidgets = [
        SizedBox(height: 0.5.h),
        Text("Official Leave Applied",
            style:
                TextStyle(color: Colors.orange, fontWeight: FontWeight.w500)),
      ];
    } else {
      contentWidgets = [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Text("In: ",
                  style: TextStyle(color: Colors.grey, fontSize: 10.sp)),
              Text(widget.formatTimeAmPm(clockIn),
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 10.sp)),
              SizedBox(width: 3.w),
              Text("Out: ",
                  style: TextStyle(color: Colors.grey, fontSize: 10.sp)),
              Text(widget.formatTimeAmPm(clockOut.isEmpty ? "--:--" : clockOut),
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 10.sp)),
            ],
          ),
        ),
        SizedBox(height: 0.5.h),
        Text("Duration: ${widget.calculateDuration(clockIn, clockOut)}",
            style: TextStyle(
                color: Colors.green,
                fontSize: 10.sp,
                fontWeight: FontWeight.bold)),
      ];
    }

    final int extraBreakTime = widget.parseExtraBreakTime(record);
    final String adminApproval = record['admin_approval']?.toString() ?? '';

    final String lunchIn = record['lunch_in_time']?.toString() ?? "";
    final String lunchOut = record['lunch_out_time']?.toString() ?? "";
    final String lunchExtra =
        record['lunch_extra_break_display']?.toString() ?? "";
    final bool hasLunch = lunchIn.isNotEmpty;

    return Container(
      margin: EdgeInsets.only(bottom: 1.5.h),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.05),
            offset: const Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: hasLunch
              ? () => setState(() => _isExpanded = !_isExpanded)
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            padding: EdgeInsets.all(3.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: isAbsent
                          ? Container(
                              width: 15.w,
                              height: 15.w,
                              color: theme.colorScheme.error
                                  .withValues(alpha: 0.1),
                              child: Icon(Icons.close,
                                  color: theme.colorScheme.error, size: 24),
                            )
                          : isOnLeave
                              ? Container(
                                  width: 15.w,
                                  height: 15.w,
                                  color: Colors.orange.withValues(alpha: 0.1),
                                  child: const Icon(Icons.beach_access,
                                      color: Colors.orange, size: 24),
                                )
                              : widget.buildImage(theme, thumbnail,
                                  record["semanticLabel"] as String?),
                    ),
                    SizedBox(width: 3.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Row(
                                  children: [
                                    CustomIconWidget(
                                      iconName: 'calendar_today',
                                      color: theme.colorScheme.primary,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        widget.cleanDateString(
                                            record["date"]?.toString() ?? ""),
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 10.sp,
                                        ),
                                      ),
                                    ),
                                    if (isExcludedStatus) ...[
                                      SizedBox(width: 2.w),
                                      Text(
                                        "(Excluded)",
                                        style: TextStyle(
                                            color: Colors.red.shade400,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 9.sp),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 4),
                              if (status.isNotEmpty)
                                Container(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 2.w, vertical: 0.2.h),
                                  decoration: BoxDecoration(
                                    color: badgeColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    status,
                                    style: TextStyle(
                                      color: badgeColor,
                                      fontSize: 9.sp,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          SizedBox(height: 0.5.h),
                          ...contentWidgets,
                          if (extraBreakTime > 0) ...[
                            SizedBox(height: 0.5.h),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Container(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 2.w, vertical: 0.3.h),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                        color: Colors.amber
                                            .withValues(alpha: 0.4)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.schedule,
                                          size: 12,
                                          color: Colors.amber.shade700),
                                      SizedBox(width: 1.w),
                                      Text(
                                        widget.formatExtraBreakTime(
                                            extraBreakTime),
                                        style: TextStyle(
                                          color: Colors.amber.shade700,
                                          fontSize: 9.sp,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      if (adminApproval == 'Under Review') ...[
                                        SizedBox(width: 1.w),
                                        Text(
                                          "Under Review",
                                          style: TextStyle(
                                            color: Colors.orange.shade700,
                                            fontSize: 8.sp,
                                            fontWeight: FontWeight.w600,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (hasLunch) ...[
                            SizedBox(height: 0.5.h),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Icon(
                                  Icons.restaurant,
                                  size: 12,
                                  color: const Color(0xFF25D366),
                                ),
                                SizedBox(width: 1.w),
                                Text(
                                  _isExpanded ? "Hide Lunch ▲" : "Show Lunch ▼",
                                  style: TextStyle(
                                    color: const Color(0xFF25D366),
                                    fontSize: 9.sp,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 300),
                  crossFadeState: _isExpanded && hasLunch
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: const SizedBox.shrink(),
                  secondChild: hasLunch
                      ? Padding(
                          padding: EdgeInsets.only(top: 1.5.h),
                          child: Container(
                            padding: EdgeInsets.all(3.w),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFF25D366)
                                      .withValues(alpha: 0.08),
                                  const Color(0xFF128C7E)
                                      .withValues(alpha: 0.05),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFF25D366)
                                    .withValues(alpha: 0.25),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF25D366)
                                            .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Icon(Icons.restaurant,
                                          size: 14,
                                          color: const Color(0xFF25D366)),
                                    ),
                                    SizedBox(width: 2.w),
                                    Text(
                                      "Lunch Session",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10.sp,
                                        color: const Color(0xFF128C7E),
                                      ),
                                    ),
                                    const Spacer(),
                                    if (lunchExtra.isNotEmpty)
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 2.w, vertical: 0.3.h),
                                        decoration: BoxDecoration(
                                          color:
                                              Colors.red.withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                              color: Colors.red
                                                  .withValues(alpha: 0.3)),
                                        ),
                                        child: Text(
                                          lunchExtra,
                                          style: TextStyle(
                                            color: Colors.red.shade700,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 9.sp,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                SizedBox(height: 1.h),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text("Lunch In",
                                              style: TextStyle(
                                                  color: Colors.grey.shade600,
                                                  fontSize: 9.sp)),
                                          SizedBox(height: 0.3.h),
                                          Row(
                                            children: [
                                              Icon(Icons.login,
                                                  size: 12,
                                                  color:
                                                      const Color(0xFF25D366)),
                                              SizedBox(width: 1.w),
                                              Text(
                                                widget.formatTimeAmPm(lunchIn),
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 10.sp,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      height: 4.h,
                                      width: 1,
                                      color: const Color(0xFF25D366)
                                          .withValues(alpha: 0.3),
                                    ),
                                    Expanded(
                                      child: Padding(
                                        padding: EdgeInsets.only(left: 3.w),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text("Lunch Out",
                                                style: TextStyle(
                                                    color: Colors.grey.shade600,
                                                    fontSize: 9.sp)),
                                            SizedBox(height: 0.3.h),
                                            Row(
                                              children: [
                                                Icon(Icons.logout,
                                                    size: 12,
                                                    color:
                                                        Colors.orange.shade700),
                                                SizedBox(width: 1.w),
                                                Text(
                                                  lunchOut.isEmpty
                                                      ? "--:--"
                                                      : widget.formatTimeAmPm(
                                                          lunchOut),
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 10.sp,
                                                  ),
                                                ),
                                              ],
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
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
