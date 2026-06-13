import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/feature_control_service.dart';

/// Navigation item configuration for bottom bar
class CustomBottomBarItem {
  final String route;
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const CustomBottomBarItem({
    required this.route,
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

/// Custom bottom navigation bar for furniture showroom application
/// Implements bottom-heavy design for thumb-reachable navigation
class CustomBottomBar extends StatelessWidget {
  final String currentRoute;
  final Function(String)? onTap;

  const CustomBottomBar({
    super.key,
    required this.currentRoute,
    this.onTap,
  });

  // Navigation items based on Mobile Navigation Hierarchy
  static const List<CustomBottomBarItem> _allNavigationItems = [
    CustomBottomBarItem(
      route: '/dashboard',
      icon: Icons.dashboard_outlined,
      activeIcon: Icons.dashboard,
      label: 'Dashboard',
    ),
    CustomBottomBarItem(
      route: '/attendance-screen',
      icon: Icons.camera_alt_outlined,
      activeIcon: Icons.camera_alt,
      label: 'Attendance',
    ),
    /*
    CustomBottomBarItem(
      route: '/customer-billing-screen',
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long,
      label: 'Billing',
    ),
    */
    CustomBottomBarItem(
      route: '/lunch-screen',
      icon: Icons.restaurant_outlined,
      activeIcon: Icons.restaurant,
      label: 'Lunch',
    ),
    /*
    CustomBottomBarItem(
      route: '/stock-checking-screen',
      icon: Icons.qr_code_scanner_outlined,
      activeIcon: Icons.qr_code_scanner,
      label: 'Stock',
    ),
    */
    CustomBottomBarItem(
      route: '/leaderboard',
      icon: Icons.emoji_events_outlined,
      activeIcon: Icons.emoji_events,
      label: 'Leaderboard',
    ),
  ];

  void _handleTap(
      BuildContext context, CustomBottomBarItem item, int currentIndex) {
    if (item.route == currentRoute) return;

    // 🍽️ LUNCH GATE: Block lunch page access based on rules
    if (item.route == '/lunch-screen') {
      final service = FeatureControlService();

      // 🔥 Compute: Is today's lunch genuinely in-progress?
      final now = DateTime.now();
      final today =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final bool isTodayInProgress = service.lunchInProgress.value &&
          service.lunchStatusDate.value == today;

      debugPrint("🍽️ LUNCH GATE CHECK: manual=${service.lunchIsManual.value}, "
          "windowOpen=${service.lunchWindowOpen.value}, "
          "inProgress=${service.lunchInProgress.value}, "
          "completed=${service.lunchCompleted.value}, "
          "statusDate=${service.lunchStatusDate.value}, "
          "today=$today, isTodayInProgress=$isTodayInProgress");

      // 🔥 Rule 0: Admin manual override — always allow
      if (service.lunchIsManual.value) {
        debugPrint("🍽️ LUNCH GATE: Rule 0 — Admin MANUAL ON → ALLOW");
      }
      // 🔥 Rule 1: Time window open (1-4 PM) — allow
      else if (service.lunchWindowOpen.value) {
        debugPrint("🍽️ LUNCH GATE: Rule 1 — Window OPEN (1-4 PM) → ALLOW");
      }
      // 🔥 Rule 2: Today's Lunch In done but NOT Out — allow for Lunch Out anytime today
      else if (isTodayInProgress) {
        debugPrint("🍽️ LUNCH GATE: Rule 2 — Today In-Progress → ALLOW");
      }
      // 🔥 Rule 3: Lunch completed TODAY — allow (view records)
      else if (service.lunchCompleted.value &&
          service.lunchStatusDate.value == today) {
        debugPrint("🍽️ LUNCH GATE: Rule 3 — Today Completed → ALLOW");
      }
      // 🔥 Rule 3: Lunch completed (In + Out done) OR no lunch at all — LOCK
      else {
        HapticFeedback.mediumImpact();
        final st = service.lunchStartTime.value;
        final et = service.lunchEndTime.value;
        String timeText = '${_to12hr(st)} to ${_to12hr(et)}';

        // Different message if lunch is already completed
        final msg = service.lunchCompleted.value
            ? '✅ இன்றைய Lunch முடிந்தது! மீண்டும் access செய்ய முடியாது.'
            : '🍽️ Lunch Break — $timeText மட்டும் access செய்ய முடியும்!';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              msg,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            backgroundColor: service.lunchCompleted.value
                ? Colors.green.shade800
                : Colors.orange.shade900,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        return; // ❌ Block
      }
    }

    // RESTRICTED LOGIC: Only allow Dashboard, Attendance, Lunch, and Leaderboard
    if (item.route == '/dashboard' ||
        item.route == '/attendance-screen' ||
        item.route == '/lunch-screen' ||
        item.route == '/leaderboard' ||
        item.route == '/customer-billing-screen') {
      HapticFeedback.lightImpact();
      if (onTap != null) {
        onTap!(item.route);
      } else {
        // 🔥 Screens that are PUSHED on top of dashboard (not replaced)
        const pushedRoutes = ['/leaderboard', '/lunch-screen'];

        // If we're on a pushed screen and going back to dashboard → just pop
        if (pushedRoutes.contains(currentRoute) && item.route == '/dashboard') {
          Navigator.pop(context);
        }
        // Push lunch & leaderboard: clear any stacked screens above dashboard first
        else if (pushedRoutes.contains(item.route)) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            item.route,
            ModalRoute.withName('/dashboard'),
          );
        }
        // All other routes: replace
        else {
          Navigator.pushReplacementNamed(context, item.route);
        }
      }
    } else {
      // Block feature and show "Coming Soon"
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${item.label} - Coming Soon...'),
          duration: const Duration(milliseconds: 800),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final featureService = FeatureControlService();

    return ValueListenableBuilder<bool>(
      valueListenable: featureService.leaderboardVisible,
      builder: (context, isLeaderboardVisible, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: featureService.lunchWindowOpen,
          builder: (context, isLunchOpen, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: featureService.lunchIsManual,
              builder: (context, isManual, _) {
                // Filter items based on visibility
                final visibleItems = _allNavigationItems.where((item) {
                  if (item.route == '/leaderboard') return isLeaderboardVisible;
                  return true;
                }).toList();

                final currentIndex = visibleItems
                    .indexWhere((item) => item.route == currentRoute);

                final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;
                // Add a minimum padding just in case, but rely on the system's bottom padding for gesture bars.
                final effectiveBottomPadding = bottomPadding > 0 ? bottomPadding : 0.0;

                return Container(
                  padding: EdgeInsets.only(bottom: effectiveBottomPadding),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.shadow.withValues(alpha: 0.08),
                        offset: const Offset(0, -2),
                        blurRadius: 8,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                  child: SizedBox(
                    height: 64,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: List.generate(
                        visibleItems.length,
                        (index) => _buildNavigationItem(
                          context,
                          visibleItems[index],
                          index == currentIndex,
                          () => _handleTap(
                              context, visibleItems[index], currentIndex),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildNavigationItem(
    BuildContext context,
    CustomBottomBarItem item,
    bool isActive,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        splashColor: colorScheme.primary.withValues(alpha: 0.1),
        highlightColor: colorScheme.primary.withValues(alpha: 0.05),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon with scale animation
              AnimatedScale(
                scale: isActive ? 1.1 : 1.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: Icon(
                  isActive ? item.activeIcon : item.icon,
                  size: 24,
                  color: isActive
                      ? colorScheme.primary
                      : theme.bottomNavigationBarTheme.unselectedItemColor,
                ),
              ),
              const SizedBox(height: 4),
              // Label with fade animation
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                style: (isActive
                        ? theme.bottomNavigationBarTheme.selectedLabelStyle
                        : theme
                            .bottomNavigationBarTheme.unselectedLabelStyle) ??
                    theme.textTheme.labelSmall!,
                child: Text(
                  item.label,
                  style: TextStyle(
                    color: isActive
                        ? colorScheme.primary
                        : theme.bottomNavigationBarTheme.unselectedItemColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Convert "HH:MM" (24hr) to "H:MM AM/PM"
  String _to12hr(String time24) {
    try {
      final parts = time24.split(':');
      int hour = int.parse(parts[0]);
      final min = parts[1];
      final ampm = hour >= 12 ? 'PM' : 'AM';
      hour = hour % 12;
      if (hour == 0) hour = 12;
      return '$hour:$min $ampm';
    } catch (_) {
      return time24;
    }
  }
}
