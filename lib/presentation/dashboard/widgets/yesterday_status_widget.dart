import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';

class YesterdayStatusWidget extends StatefulWidget {
  final String status;
  final String reason;
  final VoidCallback onDismiss;

  const YesterdayStatusWidget({
    super.key,
    required this.status,
    required this.reason,
    required this.onDismiss,
  });

  @override
  State<YesterdayStatusWidget> createState() => _YesterdayStatusWidgetState();
}

class _YesterdayStatusWidgetState extends State<YesterdayStatusWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _blinkController;
  late Animation<double> _blinkAnimation;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _blinkAnimation = Tween<double>(begin: 1.0, end: 0.3).animate(
      CurvedAnimation(parent: _blinkController, curve: Curves.easeInOut),
    );

    final s = widget.status.toLowerCase();
    if (s.contains('miss')) {
      _blinkController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.status.toLowerCase();

    Color accentColor;
    Color bgColor;
    IconData iconData;

    if (s == 'present' || s == 'in') {
      accentColor = Colors.green.shade600;
      bgColor = Colors.green.shade50;
      iconData = Icons.check_circle_outline_rounded;
    } else if (s.contains('half')) {
      accentColor = Colors.orange.shade600;
      bgColor = Colors.orange.shade50;
      iconData = Icons.timelapse_rounded;
    } else if (s == 'leave' || s == 'absent' || s.contains('miss')) {
      accentColor = Colors.red.shade600;
      bgColor = Colors.red.shade50;
      iconData = s.contains('miss')
          ? Icons.warning_amber_rounded
          : Icons.cancel_outlined;
    } else {
      accentColor = Colors.blue.shade600;
      bgColor = Colors.blue.shade50;
      iconData = Icons.info_outline_rounded;
    }

    final isMissout = s.contains('miss');

    Widget content = Container(
      margin: EdgeInsets.only(bottom: 3.h),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.05),
            offset: const Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: 4,
                color: accentColor,
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(4.w, 3.w, 2.w, 3.w),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(iconData, color: accentColor, size: 24),
                  SizedBox(width: 3.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Yesterday's Status: ${widget.status}",
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: accentColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 0.5.h),
                        Text(
                          widget.reason,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 18, color: accentColor),
                    onPressed: widget.onDismiss,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (isMissout) {
      return FadeTransition(
        opacity: _blinkAnimation,
        child: content,
      );
    }

    return content;
  }
}
