import 'package:flutter/material.dart';

import '../models/attendance_chat_message.dart';
import 'chat_message_bubble.dart';
import 'chat_input_bar.dart';

class AttendanceChatView extends StatelessWidget {
  final ThemeData theme;
  final bool isLoadingMore;
  final ValueNotifier<List<AttendanceChatMessage>> chatMessagesNotifier;
  final ScrollController scrollController;
  final ValueNotifier<bool> showScrollToBottom;
  final TextEditingController messageController;
  final FocusNode messageFocusNode;
  final String? selectedLeaveType;
  final DateTimeRange? selectedRange;
  final bool isDayComplete;
  final bool isClockInMode;

  final VoidCallback onCameraTap;
  final VoidCallback onSendTap;
  final Future<void> Function(String) onLeaveChipSelected;
  final VoidCallback onClearSelection;
  final void Function(AttendanceChatMessage) onManualRetry;
  final void Function(AttendanceChatMessage) onManualDelete;

  const AttendanceChatView({
    super.key,
    required this.theme,
    required this.isLoadingMore,
    required this.chatMessagesNotifier,
    required this.scrollController,
    required this.showScrollToBottom,
    required this.messageController,
    required this.messageFocusNode,
    required this.selectedLeaveType,
    required this.selectedRange,
    required this.isDayComplete,
    required this.isClockInMode,
    required this.onCameraTap,
    required this.onSendTap,
    required this.onLeaveChipSelected,
    required this.onClearSelection,
    required this.onManualRetry,
    required this.onManualDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (isLoadingMore)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage(
                  theme.brightness == Brightness.dark
                      ? 'assets/images/chatscreen_background_dark.png'
                      : 'assets/images/chatscreen_background_light.png',
                ),
                fit: BoxFit.cover,
              ),
            ),
            child: Stack(
              children: [
                ValueListenableBuilder<List<AttendanceChatMessage>>(
                  valueListenable: chatMessagesNotifier,
                  builder: (context, messages, child) {
                    final reversedMessages = messages.reversed.toList();
                    return ListView.builder(
                      reverse: true,
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      itemCount: reversedMessages.length,
                      itemBuilder: (context, index) {
                        return ChatMessageBubble(
                          message: reversedMessages[index],
                          index: index,
                          onRetry: (msg) => onManualRetry(msg),
                          onDelete: (msg) => onManualDelete(msg),
                        );
                      },
                    );
                  },
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: showScrollToBottom,
                  builder: (context, show, child) {
                    if (!show) {
                      return const SizedBox.shrink();
                    }
                    return Positioned(
                      right: 16,
                      bottom: 16,
                      child: FloatingActionButton.small(
                        onPressed: () {
                          if (scrollController.hasClients) {
                            scrollController.animateTo(0.0,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOut);
                          }
                        },
                        backgroundColor: Colors.white,
                        elevation: 4,
                        shape: const CircleBorder(),
                        child: Icon(Icons.keyboard_arrow_down,
                            color: theme.colorScheme.onSurfaceVariant,
                            size: 24),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        ChatInputBar(
          messageController: messageController,
          messageFocusNode: messageFocusNode,
          selectedLeaveType: selectedLeaveType,
          selectedRange: selectedRange,
          isDayComplete: isDayComplete,
          isClockInMode: isClockInMode,
          onCameraTap: onCameraTap,
          onSendTap: onSendTap,
          onLeaveChipSelected: onLeaveChipSelected,
          onClearSelection: onClearSelection,
        ),
      ],
    );
  }
}
