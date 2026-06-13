import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import '../../../core/app_export.dart';
import '../models/attendance_chat_message.dart';
import '../../../widgets/custom_image_widget.dart';

class ChatMessageBubble extends StatefulWidget {
  final AttendanceChatMessage message;
  final int index;
  final Function(AttendanceChatMessage)? onRetry;
  final Function(AttendanceChatMessage)? onDelete;

  const ChatMessageBubble({
    super.key,
    required this.message,
    this.index = 0,
    this.onRetry,
    this.onDelete,
  });

  static void resetAnimations() {
    _ChatMessageBubbleState._animatedMessageIds.clear();
    _ChatMessageBubbleState._isInitialLoad = true;
  }

  @override
  State<ChatMessageBubble> createState() => _ChatMessageBubbleState();
}

class _ChatMessageBubbleState extends State<ChatMessageBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  late Animation<Offset> _slideAnimation;

  // Track which messages have already been animated so we don't re-animate on scroll
  static final Set<String> _animatedMessageIds = {};

  // Flag to know if this is the first batch of messages loading
  static bool _isInitialLoad = true;
  
  // 🔥 FIX: Track if we should use SizeTransition
  bool _useSizeTransition = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600), // 🔥 Snappy and beautiful
    );

    _animation = CurvedAnimation(
      parent: _controller,
      curve:
          Curves.easeOutQuart, // 🔥 Smooth premium glide instead of bouncy jump
    );

    // Slide animation uses a standard smooth curve to slide from bottom
    _slideAnimation = Tween<Offset>(
      begin: const Offset(
          0.0, 0.15), // 🔥 Reduced from 0.5 to 0.15 for more subtle entrance
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutQuart,
    ));

    // 🔥 Disable SizeTransition for initial batch to save layout passes on low-end devices
    _useSizeTransition = !_isInitialLoad;

    if (!_animatedMessageIds.contains(widget.message.id)) {
      _animatedMessageIds.add(widget.message.id);

      // Add a base delay during initial load so the crossfade transition completes
      // before the animations start. Reduced since AnimatedSwitcher handles smoothness.
      int baseDelay =
          _isInitialLoad ? 150 : 0; // Shorter delay — crossfade covers the gap

      // Turn off initial load flag after a longer window to ensure all initial items get the delay
      if (_isInitialLoad) {
        Future.delayed(const Duration(milliseconds: 1000), () {
          _isInitialLoad = false;
        });
      }

      // Stagger delay based on index for a beautiful cascading entrance
      int staggerDelay =
          baseDelay + (widget.index * 30); // Faster cascade (30ms)
      if (staggerDelay > 600) {
        staggerDelay = 600; // Cap it so it doesn't delay too long
      }

      if (widget.message.type == ChatMessageType.system &&
          !widget.message.isSentByMe) {
        Future.delayed(Duration(milliseconds: 300 + staggerDelay), () {
          if (mounted) {
            _controller.forward();
          }
        });
      } else {
        if (staggerDelay > 0) {
          Future.delayed(Duration(milliseconds: staggerDelay), () {
            if (mounted) _controller.forward();
          });
        } else {
          // Instant for index 0 (newest message) when not initial load
          _controller.forward();
        }
      }
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget content = _buildContent(context);

    // If already fully animated, skip transition widgets completely for performance
    if (_controller.value == 1.0) {
      return content;
    }

    Widget animatedContent = FadeTransition(
      opacity: _animation,
      child: SlideTransition(
        position: _slideAnimation,
        child: content,
      ),
    );

    // 🔥 FIX: Only use SizeTransition for new messages, not initial load
    if (_useSizeTransition) {
      return SizeTransition(
        sizeFactor: _animation,
        axisAlignment: 1.0, // Expand from the bottom upwards for reverse list
        child: animatedContent,
      );
    } else {
      return animatedContent;
    }
  }

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);

    if (widget.message.type == ChatMessageType.dateHeader) {
      return _buildDateHeaderBubble(context, theme);
    }

    if (!widget.message.isSentByMe) {
      return _buildSystemBubble(context, theme);
    }

    final bool hasImage = (widget.message.imagePath != null &&
            widget.message.imagePath!.isNotEmpty) ||
        (widget.message.imageUrl != null &&
            widget.message.imageUrl!.isNotEmpty);

    final bool isPhotoMessage =
        (widget.message.type == ChatMessageType.clockIn ||
                widget.message.type == ChatMessageType.clockOut ||
                widget.message.type == ChatMessageType.reEntry) &&
            hasImage;

    if (isPhotoMessage) {
      return _buildPhotoBubble(context, theme);
    }

    return _buildUserBubble(context, theme);
  }

  // ─── SYSTEM MESSAGE (Left aligned, grey) ───
  Widget _buildSystemBubble(BuildContext context, ThemeData theme) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: theme.brightness == Brightness.dark
                ? theme.colorScheme.surfaceContainerHighest
                : const Color(
                    0xFFE8F5E9), // Elegant soft mint/light-green matching the app's green theme
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.message.text,
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onSurface,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                DateFormat('hh:mm a').format(widget.message.timestamp),
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── DATE HEADER BUBBLE ───
  Widget _buildDateHeaderBubble(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark
                  ? theme.colorScheme.surfaceContainerHighest
                  : const Color(0xFFF1F3F4), // Clean flat silver-grey for dates
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              widget.message.text,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  // ─── WHATSAPP PHOTO BUBBLE ───
  Widget _buildPhotoBubble(BuildContext context, ThemeData theme) {
    Color bubbleColor = const Color(0xFF075E54); // Always Dark Teal for Photos

    bool hasText = widget.message.text.isNotEmpty;

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        child: GestureDetector(
          onTap: () => _openPhotoViewer(context),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(4),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Photo ──
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ConstrainedBox(
                        // 🔥 FIX: Flexible constraints for photo aspect ratio
                        constraints: BoxConstraints(
                          maxHeight:
                              350, // 🔥 Increased from 220 for better visibility
                          minHeight: 350,
                          maxWidth: double.infinity,
                        ),
                        child: _buildImage(context),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: _buildPhotoTypeBadge(bubbleColor),
                    ),
                    if (widget.message.uploadStatus == UploadStatus.failed &&
                        widget.onRetry != null)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: () => widget.onRetry!(widget.message),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.3),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.refresh,
                                        size: 14, color: Colors.white),
                                    SizedBox(width: 4),
                                    Text(
                                      "Retry",
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (widget.onDelete != null) ...[
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => widget.onDelete!(widget.message),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade900.withValues(alpha: 0.9),
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.3),
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.delete,
                                          size: 14, color: Colors.white),
                                      SizedBox(width: 4),
                                      Text(
                                        "Delete",
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),

                // ── Caption below photo (WhatsApp Style) ──
                if (hasText)
                  Padding(
                    padding: const EdgeInsets.only(
                        left: 6, right: 4, top: 6, bottom: 2),
                    child: Stack(
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: widget.message.text),
                              const WidgetSpan(
                                child: SizedBox(width: 75), // Spacer for time
                              ),
                            ],
                          ),
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                            height: 1.3,
                          ),
                        ),
                        // Time + Ticks absolutely positioned to bottom right
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                DateFormat('hh:mm:ss a')
                                    .format(widget.message.timestamp),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white.withValues(alpha: 0.7),
                                ),
                              ),
                              const SizedBox(width: 4),
                              _buildStatusTick(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoTypeBadge(Color borderColor) {
    IconData icon;
    String label;
    if (widget.message.type == ChatMessageType.clockIn) {
      icon = Icons.login_rounded;
      label = "Clock In";
    } else if (widget.message.type == ChatMessageType.clockOut) {
      icon = Icons.logout_rounded;
      label = "Clock Out";
    } else {
      icon = Icons.replay_rounded;
      label = "Re-Entry";
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: borderColor.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 4,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImage(BuildContext context) {
    // Prefer server URL if available, otherwise fallback to local path
    String? primaryUrl;
    String? fallbackUrl;

    if (widget.message.imageUrl != null &&
        widget.message.imageUrl!.isNotEmpty &&
        widget.message.imageUrl!.startsWith('http')) {
      primaryUrl = widget.message.imageUrl;
      fallbackUrl = widget.message.imagePath;
    } else if (widget.message.imagePath != null &&
        widget.message.imagePath!.isNotEmpty) {
      primaryUrl = widget.message.imagePath;
      fallbackUrl = widget.message.imageUrl;
    } else {
      primaryUrl = widget.message.imageUrl;
      fallbackUrl = null;
    }

    if (primaryUrl != null && primaryUrl.isNotEmpty) {
      return CustomImageWidget(
        imageUrl: primaryUrl,
        width: double.infinity,
        height: 350,
        fit: BoxFit.cover,
        errorWidget: fallbackUrl != null && fallbackUrl.isNotEmpty
            ? CustomImageWidget(
                imageUrl: fallbackUrl,
                width: double.infinity,
                height: 350,
                fit: BoxFit.cover,
                errorWidget: _buildErrorPlaceholder(context),
              )
            : _buildErrorPlaceholder(context),
      );
    }

    return _buildEmptyPlaceholder();
  }

  Widget _buildErrorPlaceholder(BuildContext context) {
    return Container(
      height: 350,
      width: double.infinity,
      color: const Color(0xFF075E54), // Green background
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_not_supported, color: Colors.white54, size: 48),
            SizedBox(height: 8),
            Text(
              "No Photo",
              style: TextStyle(
                color: Colors.white54,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyPlaceholder() {
    return Container(
      height: 350,
      width: double.infinity,
      color: const Color(0xFF075E54), // Green background
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.no_photography, color: Colors.white54, size: 48),
            SizedBox(height: 8),
            Text(
              "No Photo",
              style: TextStyle(
                color: Colors.white54,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openPhotoViewer(BuildContext context) {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (context, animation, secondaryAnimation) {
          return _FullScreenPhotoViewer(message: widget.message);
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  Widget _buildUserBubble(BuildContext context, ThemeData theme) {
    final bool isLeave = widget.message.type == ChatMessageType.leaveRequest;

    Color bubbleColor;
    if (widget.message.type == ChatMessageType.clockIn ||
        widget.message.type == ChatMessageType.reEntry) {
      bubbleColor = const Color(0xFF075E54);
    } else if (widget.message.type == ChatMessageType.clockOut) {
      bubbleColor = const Color(0xFF075E54); // Changed to Green
    } else if (isLeave) {
      bubbleColor = const Color(0xFF1F3A5F);
    } else {
      bubbleColor = theme.colorScheme.primary;
    }

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(4),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTypeBadge(theme),
                const SizedBox(height: 4),
                Text(
                  widget.message.text,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                    height: 1.4,
                  ),
                ),
                if (isLeave) ...[
                  const SizedBox(height: 6),
                  _buildLeaveDetails(theme),
                ],
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      DateFormat('hh:mm:ss a').format(widget.message.timestamp),
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(width: 4),
                    _buildStatusTick(),
                    if (widget.message.uploadStatus == UploadStatus.failed &&
                        widget.onRetry != null) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => widget.onRetry!(widget.message),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.5)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.refresh,
                                  size: 12, color: Colors.white),
                              SizedBox(width: 4),
                              Text(
                                "Retry",
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (widget.onDelete != null) ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => widget.onDelete!(widget.message),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red.shade900.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.5)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.delete,
                                    size: 12, color: Colors.white),
                                SizedBox(width: 4),
                                Text(
                                  "Delete",
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypeBadge(ThemeData theme) {
    IconData icon;
    String label;
    Color badgeColor;

    switch (widget.message.type) {
      case ChatMessageType.clockIn:
        icon = Icons.login_rounded;
        label = "Clock In";
        badgeColor = const Color(0xFF25D366);
      case ChatMessageType.clockOut:
        icon = Icons.logout_rounded;
        label = "Clock Out";
        badgeColor = const Color(0xFFFF6B6B);
      case ChatMessageType.reEntry:
        icon = Icons.replay_rounded;
        label = "Re-Entry";
        badgeColor = const Color(0xFFFFA726);
      case ChatMessageType.leaveRequest:
        icon = Icons.calendar_month_rounded;
        label = "Leave Application (${widget.message.leaveType ?? 'Full Day'})";
        badgeColor = const Color(0xFF64B5F6);
      default:
        icon = Icons.info_outline;
        label = "Info";
        badgeColor = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: badgeColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: badgeColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaveDetails(ThemeData theme) {
    final dateFormat = DateFormat('dd MMM yyyy');
    String dateText = "";

    if (widget.message.leaveStartDate != null) {
      dateText = dateFormat.format(widget.message.leaveStartDate!);
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (dateText.isNotEmpty)
            Row(
              children: [
                const Icon(Icons.calendar_today,
                    size: 12, color: Colors.white70),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    dateText,
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ),
              ],
            ),
          if (widget.message.leaveReason != null &&
              widget.message.leaveReason!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.note, size: 12, color: Colors.white70),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    widget.message.leaveReason!,
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ),
              ],
            ),
          ],
          if (widget.message.leaveStatus != LeaveStatus.none) ...[
            const SizedBox(height: 6),
            _buildLeaveStatusBadge(),
          ],
        ],
      ),
    );
  }

  Widget _buildLeaveStatusBadge() {
    IconData icon;
    String text;
    Color color;

    switch (widget.message.leaveStatus) {
      case LeaveStatus.pending:
        icon = Icons.hourglass_empty;
        text = "Pending ⏳";
        color = Colors.orange;
      case LeaveStatus.approved:
        icon = Icons.check_circle;
        text = "Approved ✅";
        color = Colors.green;
      case LeaveStatus.rejected:
        icon = Icons.cancel;
        text = "Rejected ❌";
        color = Colors.red;
      case LeaveStatus.none:
        return const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusTick() {
    switch (widget.message.uploadStatus.name) {
      case 'sending':
        return const Icon(Icons.access_time, size: 13, color: Colors.white70);
      case 'sent':
        return const Icon(Icons.check, size: 15, color: Colors.white70);
      case 'delivered':
        return const Icon(Icons.done_all, size: 15, color: Colors.white70);
      case 'success':
        return const Icon(Icons.done_all, size: 15, color: Color(0xFF53BDEB));
      case 'failed':
      default:
        return const Icon(Icons.error_outline,
            size: 15, color: Colors.redAccent);
    }
  }
}

class _FullScreenPhotoViewer extends StatelessWidget {
  final AttendanceChatMessage message;

  const _FullScreenPhotoViewer({required this.message});

  @override
  Widget build(BuildContext context) {
    String label;
    Color headerColor;
    if (message.type == ChatMessageType.clockIn) {
      label = "Clock In";
      headerColor = const Color(0xFF075E54);
    } else if (message.type == ChatMessageType.clockOut) {
      label = "Clock Out";
      headerColor = const Color(0xFF075E54); // Changed to Green
    } else {
      label = "Re-Entry";
      headerColor = const Color(0xFFFFA726);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: SizedBox(
                width: MediaQuery.of(context).size.width,
                child: _buildFullImage(context),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back,
                          color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: headerColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('hh:mm:ss a  •  dd MMM yyyy')
                              .format(message.timestamp),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    _buildViewerStatusBadge(),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Text(
                  message.text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFullImage(BuildContext context) {
    // Prefer server URL if available, otherwise fallback to local path
    String? primaryUrl;
    String? fallbackUrl;

    if (message.imageUrl != null &&
        message.imageUrl!.isNotEmpty &&
        message.imageUrl!.startsWith('http')) {
      primaryUrl = message.imageUrl;
      fallbackUrl = message.imagePath;
    } else if (message.imagePath != null && message.imagePath!.isNotEmpty) {
      primaryUrl = message.imagePath;
      fallbackUrl = message.imageUrl;
    } else {
      primaryUrl = message.imageUrl;
      fallbackUrl = null;
    }

    if (primaryUrl != null && primaryUrl.isNotEmpty) {
      return CustomImageWidget(
        imageUrl: primaryUrl,
        fit: BoxFit.fitWidth,
        width: double.infinity,
        errorWidget: fallbackUrl != null && fallbackUrl.isNotEmpty
            ? CustomImageWidget(
                imageUrl: fallbackUrl,
                fit: BoxFit.fitWidth,
                width: double.infinity,
                errorWidget: _buildErrorPlaceholder(context),
              )
            : _buildErrorPlaceholder(context),
      );
    }

    return const Center(
      child: Icon(Icons.photo_camera, color: Colors.white38, size: 64),
    );
  }

  Widget _buildErrorPlaceholder(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFF097A6B),
      highlightColor: const Color(0xFF0BA490),
      child: Container(
        height: double.infinity,
        width: double.infinity,
        color: Colors.white,
      ),
    );
  }

  Widget _buildViewerStatusBadge() {
    IconData icon;
    Color color;

    switch (message.uploadStatus.name) {
      case 'sending':
        icon = Icons.access_time;
        color = Colors.white70;
      case 'sent':
        icon = Icons.check;
        color = Colors.white70;
      case 'delivered':
        icon = Icons.done_all;
        color = Colors.white70;
      case 'success':
        icon = Icons.done_all;
        color = const Color(0xFF53BDEB);
      case 'failed':
      default:
        icon = Icons.error_outline;
        color = Colors.redAccent;
    }

    return Icon(icon, size: 22, color: color);
  }
}
