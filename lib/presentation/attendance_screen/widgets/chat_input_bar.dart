import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/app_export.dart';

class ChatInputBar extends StatelessWidget {
  final TextEditingController messageController;
  final FocusNode? messageFocusNode;
  final String? selectedLeaveType;
  final DateTimeRange? selectedRange;
  final bool isDayComplete;
  final bool isClockInMode;
  final VoidCallback onCameraTap;
  final VoidCallback onSendTap;
  final ValueChanged<String> onLeaveChipSelected;
  final VoidCallback onClearSelection;

  const ChatInputBar({
    super.key,
    required this.messageController,
    this.messageFocusNode,
    this.selectedLeaveType,
    this.selectedRange,
    this.isDayComplete = false,
    this.isClockInMode = true,
    required this.onCameraTap,
    required this.onSendTap,
    required this.onLeaveChipSelected,
    required this.onClearSelection,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            offset: const Offset(0, -1),
            blurRadius: 4,
            color: Colors.black.withValues(alpha: 0.06),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewPaddingOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ─── Leave Type Chips + Date Chip ───
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildLeaveChip(context, "Full Day"),
                  const SizedBox(width: 8),
                  _buildLeaveChip(context, "Half Day"),
                  if (selectedRange != null) ...[
                    const SizedBox(width: 8),
                    Chip(
                      label: Text(
                        selectedRange!.start == selectedRange!.end
                            ? DateFormat('dd MMM').format(selectedRange!.start)
                            : "${DateFormat('dd MMM').format(selectedRange!.start)} - ${DateFormat('dd MMM').format(selectedRange!.end)}",
                        style:
                            const TextStyle(fontSize: 12, color: Colors.white),
                      ),
                      backgroundColor: AppTheme.secondaryLight,
                      deleteIcon: const Icon(Icons.close,
                          size: 14, color: Colors.white),
                      onDeleted: onClearSelection,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: EdgeInsets.zero,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),

            // ─── Input Row: TextField (with Camera inside) + Send ───
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Message input
                Expanded(
                  child: TextField(
                    controller: messageController,
                    focusNode: messageFocusNode,
                    readOnly: selectedRange == null,
                    maxLines: 3,
                    minLines: 1,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                      hintText: selectedRange == null
                          ? isDayComplete
                              ? "இன்றைய Attendance முடிந்தது ✓"
                              : isClockInMode
                                  ? "Tap camera to Clock In"
                                  : "Tap camera to Clock Out"
                          : "காரணம் எழுதுங்கள் (Optional)...",
                      hintStyle: TextStyle(
                        fontSize: 16, // Slightly larger like WhatsApp
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(
                          color:
                              theme.colorScheme.outline.withValues(alpha: 0.3),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(
                          color:
                              theme.colorScheme.outline.withValues(alpha: 0.3),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(
                          color: theme.colorScheme.primary,
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      isDense: true,
                      // Camera moved inside TextField
                      suffixIcon: IconButton(
                        icon: Icon(
                          isDayComplete
                              ? Icons.check_circle_outline
                              : Icons.photo_camera_rounded,
                          color: isDayComplete
                              ? Colors.grey
                              : const Color(
                                  0xFF075E54), // Always green for In/Out
                          size: 26, // Slightly larger icon to match WhatsApp
                        ),
                        onPressed: isDayComplete ? null : onCameraTap,
                      ),
                    ),
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
                const SizedBox(width: 8),

                // Send button (only active when leave date is selected)
                Material(
                  color: isDayComplete
                      ? Colors.grey.shade400
                      : const Color(0xFF075E54), // Always Green for In/Out
                  shape: const CircleBorder(),
                  child: InkWell(
                    onTap: selectedRange != null ? onSendTap : null,
                    customBorder: const CircleBorder(),
                    child: const Padding(
                      padding: EdgeInsets.all(10), // kept original padding
                      child: Icon(Icons.send_rounded,
                          color: Colors.white, size: 22),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaveChip(BuildContext context, String type) {
    final bool isSelected = selectedLeaveType == type;
    return ChoiceChip(
      label: Text(
        type,
        style: TextStyle(
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          color: isSelected
              ? Colors.white
              : Theme.of(context).colorScheme.onSurface,
        ),
      ),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          onLeaveChipSelected(type);
        }
      },
      avatar: isSelected
          ? const Icon(Icons.check, size: 14, color: Colors.white)
          : null,
      selectedColor: AppTheme.primaryLight,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected
              ? AppTheme.primaryLight
              : Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      visualDensity: VisualDensity.compact,
    );
  }
}
