import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class AttendanceSkeletonViews {
  static Widget buildSkeletonLoadingView({
    required ThemeData theme,
    required bool allowRemoteAttendance,
    required bool showHistory,
    required AnimationController skeletonController,
    double bottomPadding = 0.0,
  }) {
    if (allowRemoteAttendance || showHistory) {
      return buildHistorySkeleton(
        theme: theme,
        skeletonController: skeletonController,
        bottomPadding: bottomPadding,
      );
    }

    final isDark = theme.brightness == Brightness.dark;

    // Match ChatMessageBubble system color
    final baseColor = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : const Color(0xFFE8F5E9);

    // Match ChatMessageBubble user color
    final myColor = const Color(0xFF075E54);

    return Column(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage(
                  isDark
                      ? 'assets/images/chatscreen_background_dark.png'
                      : 'assets/images/chatscreen_background_light.png',
                ),
                colorFilter: ColorFilter.mode(
                  Colors.black.withValues(alpha: isDark ? 0.6 : 0.2),
                  BlendMode.darken,
                ),
                fit: BoxFit.cover,
              ),
            ),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildSkeletonBubble(baseColor, false, 200, skeletonController),
                _buildSkeletonBubble(myColor, true, 200, skeletonController,
                    isImage: true),
                _buildSkeletonBubble(myColor, true, 180, skeletonController),
                _buildSkeletonBubble(baseColor, false, 240, skeletonController),
                _buildSkeletonBubble(baseColor, false, 200, skeletonController,
                    isImage: true),
                _buildSkeletonBubble(myColor, true, 220, skeletonController),
                _buildSkeletonBubble(myColor, true, 240, skeletonController,
                    isImage: true),
                _buildSkeletonBubble(baseColor, false, 150, skeletonController),
                _buildSkeletonBubble(myColor, true, 180, skeletonController),
                _buildSkeletonBubble(baseColor, false, 200, skeletonController),
                _buildSkeletonBubble(myColor, true, 220, skeletonController,
                    isImage: true),
                _buildSkeletonBubble(myColor, true, 120, skeletonController),
              ],
            ),
          ),
        ),
        if (!allowRemoteAttendance)
          Container(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + bottomPadding),
            color: theme.scaffoldBackgroundColor,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[900] : Colors.grey[200],
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  height: 50,
                  width: 50,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[800] : Colors.grey[300],
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static Widget buildHistorySkeleton({
    required ThemeData theme,
    required AnimationController skeletonController,
    double bottomPadding = 0.0,
  }) {
    final baseColor = theme.colorScheme.surfaceContainerHighest;
    final highlightColor = theme.colorScheme.surface;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          color: theme.colorScheme.surface,
          child: Shimmer.fromColors(
            baseColor: baseColor,
            highlightColor: highlightColor,
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                      color: Colors.white, shape: BoxShape.circle),
                ),
                const SizedBox(width: 12),
                Container(width: 140, height: 16, color: Colors.white),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: 10,
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPadding),
            physics: const NeverScrollableScrollPhysics(),
            itemBuilder: (context, index) {
              return Shimmer.fromColors(
                baseColor: baseColor,
                highlightColor: highlightColor,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: baseColor.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 55,
                        height: 55,
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                                width: 120, height: 14, color: Colors.white),
                            const SizedBox(height: 8),
                            Container(
                                width: 180, height: 12, color: Colors.white),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  static Widget _buildSkeletonBubble(
    Color color,
    bool isMe,
    double width,
    AnimationController skeletonController, {
    bool isImage = false,
  }) {
    return Shimmer.fromColors(
      baseColor: color.withValues(alpha: 0.85),
      highlightColor: color.withValues(alpha: 0.4),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          height: isImage ? 350 : 60,
          width: isImage ? 200 : width,
          decoration: BoxDecoration(
            color:
                Colors.white, // Shimmer requires an opaque child to draw over
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMe ? 16 : 0),
              bottomRight: Radius.circular(isMe ? 0 : 16),
            ),
            border: Border.all(
              color: color.withValues(alpha: 0.9),
              width: 1,
            ),
          ),
        ),
      ),
    );
  }
}
