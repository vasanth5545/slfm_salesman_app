import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';

/// 🍽️ WhatsApp-style Lunch Time Dashboard Tile
/// Shows current lunch status with green accent design
class LunchTimeTileWidget extends StatelessWidget {
  final String lunchStatus; // 'not_started', 'in_progress', 'completed'
  final String? lunchInTime;
  final String? lunchOutTime;
  final String? extraBreakDisplay; // e.g. '+15m'
  final bool isInWindow; // Whether current time is in 1PM-4PM window
  final String lunchStartTime;
  final String lunchEndTime;
  final VoidCallback onTap;

  const LunchTimeTileWidget({
    super.key,
    required this.lunchStatus,
    this.lunchInTime,
    this.lunchOutTime,
    this.extraBreakDisplay,
    this.isInWindow = false,
    this.lunchStartTime = '13:00',
    this.lunchEndTime = '16:00',
    required this.onTap,
  });

  // Convert 24-hour time "13:00" or "13:00:00" to "01:00 PM"
  String _formatTime(String time24) {
    try {
      final parts = time24.split(':');
      if (parts.length < 2) return time24;
      int h = int.parse(parts[0]);
      int m = int.parse(parts[1]);
      String ampm = h >= 12 ? 'PM' : 'AM';
      h = h % 12;
      if (h == 0) h = 12;
      String mm = m.toString().padLeft(2, '0');
      String hh = h.toString().padLeft(2, '0');
      return "$hh:$mm $ampm";
    } catch (_) {
      return time24;
    }
  }

  // Convert "13:00" to "01" or "01 PM" depending on format needs
  String _formatShortTimeRange() {
    try {
      final startParts = lunchStartTime.split(':');
      final endParts = lunchEndTime.split(':');
      int hStart = int.parse(startParts[0]);
      int hEnd = int.parse(endParts[0]);
      
      String ampmEnd = hEnd >= 12 ? 'PM' : 'AM';
      
      hStart = hStart % 12;
      if (hStart == 0) hStart = 12;
      
      hEnd = hEnd % 12;
      if (hEnd == 0) hEnd = 12;
      
      return "${hStart.toString().padLeft(2, '0')}-${hEnd.toString().padLeft(2, '0')} $ampmEnd";
    } catch (_) {
      return '01-04 PM';
    }
  }

  // WhatsApp-style colors
  static const Color _whatsAppDarkBg = Color(0xFF1F2C34);
  static const Color _whatsAppGreen = Color(0xFF25D366);
  static const Color _whatsAppTeal = Color(0xFF00A884);
  static const Color _whatsAppLightBubble = Color(0xFF005C4B);
  static const Color _whatsAppTextSecondary = Color(0xFF8696A0);

  Color _getStatusColor() {
    switch (lunchStatus) {
      case 'in_progress':
        return _whatsAppGreen;
      case 'completed':
        return _whatsAppTeal;
      default:
        return _whatsAppTextSecondary;
    }
  }

  IconData _getStatusIcon() {
    switch (lunchStatus) {
      case 'in_progress':
        return Icons.lunch_dining;
      case 'completed':
        return Icons.check_circle_rounded;
      default:
        return Icons.restaurant_menu_rounded;
    }
  }

  String _getStatusText() {
    switch (lunchStatus) {
      case 'in_progress':
        return 'On Lunch Break';
      case 'completed':
        return 'Lunch Completed';
      default:
        if (isInWindow) return 'Tap to Start Lunch';
        return 'Lunch Period: ${_formatShortTimeRange()}';
    }
  }

  String _getSubtitleText() {
    switch (lunchStatus) {
      case 'in_progress':
        return 'Started at ${lunchInTime ?? '--:--'}';
      case 'completed':
        return '${lunchInTime ?? '--:--'} → ${lunchOutTime ?? '--:--'}';
      default:
        if (isInWindow) return 'Take your 1-hour lunch break';
        return 'Available between ${_formatTime(lunchStartTime)} - ${_formatTime(lunchEndTime)}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final statusColor = _getStatusColor();

    // WhatsApp-style card colors
    final cardBg = isDark ? _whatsAppDarkBg : const Color(0xFFF0F2F5);
    final textPrimary = isDark ? Colors.white : const Color(0xFF111B21);
    final textSecondary =
        isDark ? _whatsAppTextSecondary : const Color(0xFF667781);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: _whatsAppGreen.withValues(alpha: 0.1),
        highlightColor: _whatsAppGreen.withValues(alpha: 0.05),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(4.w),
          decoration: BoxDecoration(
            color: isDark ? cardBg : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: lunchStatus == 'in_progress'
                  ? _whatsAppGreen.withValues(alpha: 0.4)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : theme.colorScheme.outline.withValues(alpha: 0.15)),
              width: lunchStatus == 'in_progress' ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: lunchStatus == 'in_progress'
                    ? _whatsAppGreen.withValues(alpha: 0.08)
                    : theme.colorScheme.shadow.withValues(alpha: 0.06),
                offset: const Offset(0, 4),
                blurRadius: 12,
              ),
            ],
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- TOP ROW: Icon + Title + Arrow ---
                  Row(
                    children: [
                      // WhatsApp-style icon container
                      Container(
                        padding: EdgeInsets.all(2.5.w),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: lunchStatus == 'in_progress'
                                ? [_whatsAppGreen, _whatsAppTeal]
                                : [
                                    _whatsAppGreen.withValues(alpha: 0.15),
                                    _whatsAppTeal.withValues(alpha: 0.15)
                                  ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _getStatusIcon(),
                          color: lunchStatus == 'in_progress'
                              ? Colors.white
                              : _whatsAppGreen,
                          size: 28,
                        ),
                      ),
                      SizedBox(width: 3.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Lunch Time',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: textPrimary,
                                fontSize: 17,
                              ),
                            ),
                            SizedBox(height: 0.3.h),
                            Text(
                              '${_formatTime(lunchStartTime)} - ${_formatTime(lunchEndTime)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Chevron
                      Icon(
                        Icons.chevron_right_rounded,
                        color: textSecondary,
                        size: 24,
                      ),
                    ],
                  ),
                  SizedBox(height: 2.h),

                  // --- STATUS BAR: WhatsApp chat bubble style ---
                  Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: 3.5.w, vertical: 1.5.h),
                    decoration: BoxDecoration(
                      color: isDark
                          ? _whatsAppLightBubble.withValues(alpha: 0.3)
                          : statusColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        // Status dot with pulse animation for in_progress
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                            boxShadow: lunchStatus == 'in_progress'
                                ? [
                                    BoxShadow(
                                      color:
                                          _whatsAppGreen.withValues(alpha: 0.4),
                                      blurRadius: 6,
                                      spreadRadius: 1,
                                    )
                                  ]
                                : null,
                          ),
                        ),
                        SizedBox(width: 2.5.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _getStatusText(),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: statusColor,
                                  fontSize: 13,
                                ),
                              ),
                              SizedBox(height: 0.3.h),
                              Text(
                                _getSubtitleText(),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Time display or Action hint
                        if (lunchStatus == 'not_started' && isInWindow)
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 3.w, vertical: 0.8.h),
                            decoration: BoxDecoration(
                              color: _whatsAppGreen,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'START',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 10,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),

                        if (lunchStatus == 'in_progress')
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 3.w, vertical: 0.8.h),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'END',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 10,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),

                        if (lunchStatus == 'completed')
                          Icon(
                            Icons.done_all_rounded,
                            color: _whatsAppTeal,
                            size: 22,
                          ),
                      ],
                    ),
                  ),
                ],
              ),

              // --- EXTRA BREAK BADGE (Top-right, always visible if > 0) ---
              if (extraBreakDisplay != null && extraBreakDisplay!.isNotEmpty)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 2.w, vertical: 0.4.h),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade800,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.amber.withValues(alpha: 0.3),
                          blurRadius: 4,
                          spreadRadius: 0.5,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.timer_off_rounded,
                          color: Colors.white,
                          size: 12,
                        ),
                        SizedBox(width: 1.w),
                        Text(
                          extraBreakDisplay!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
