import 'package:flutter/material.dart';
import 'package:flutter/services.dart';


/// App bar style variants for different screen contexts
enum CustomAppBarStyle {
  /// Standard app bar with back button and title
  standard,

  /// Dashboard style with no back button, optional actions
  dashboard,

  /// Camera overlay style with transparent background
  cameraOverlay,

  /// Modal style for bottom sheets and dialogs
  modal,
}

/// Custom app bar for furniture showroom application
/// Implements professional retail appearance with contextual variations
class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final CustomAppBarStyle style;
  final List<Widget>? actions;
  final VoidCallback? onBackPressed;
  final bool showBackButton;
  final Widget? leading;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool centerTitle;
  final double elevation;

  final bool? isOnline;

  const CustomAppBar({
    super.key,
    required this.title,
    this.style = CustomAppBarStyle.standard,
    this.actions,
    this.onBackPressed,
    this.showBackButton = true,
    this.leading,
    this.backgroundColor,
    this.foregroundColor,
    this.centerTitle = false,
    this.elevation = 1.0,
    this.isOnline,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  void _handleBackPress(BuildContext context) {
    HapticFeedback.lightImpact();
    if (onBackPressed != null) {
      onBackPressed!();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Determine colors based on style
    Color effectiveBackgroundColor;
    Color effectiveForegroundColor;
    double effectiveElevation;
    SystemUiOverlayStyle overlayStyle;

    switch (style) {
      case CustomAppBarStyle.cameraOverlay:
        effectiveBackgroundColor = Colors.transparent;
        effectiveForegroundColor = Colors.white;
        effectiveElevation = 0;
        overlayStyle = SystemUiOverlayStyle.light;
        break;
      case CustomAppBarStyle.modal:
        effectiveBackgroundColor = backgroundColor ?? colorScheme.surface;
        effectiveForegroundColor = foregroundColor ?? colorScheme.onSurface;
        effectiveElevation = 0;
        overlayStyle = theme.brightness == Brightness.light
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light;
        break;
      case CustomAppBarStyle.dashboard:
      case CustomAppBarStyle.standard:
        effectiveBackgroundColor = backgroundColor ?? colorScheme.surface;
        effectiveForegroundColor = foregroundColor ?? colorScheme.onSurface;
        effectiveElevation = elevation;
        overlayStyle = theme.brightness == Brightness.light
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light;
    }

    // Determine leading widget
    Widget? effectiveLeading;
    if (leading != null) {
      effectiveLeading = leading;
    } else if (showBackButton && style != CustomAppBarStyle.dashboard) {
      final canPop = Navigator.of(context).canPop();
      if (canPop) {
        effectiveLeading = IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: effectiveForegroundColor,
          ),
          onPressed: () => _handleBackPress(context),
          tooltip: 'Back',
        );
      }
    }

    return AppBar(
      systemOverlayStyle: overlayStyle,
      backgroundColor: effectiveBackgroundColor,
      foregroundColor: effectiveForegroundColor,
      elevation: effectiveElevation,
      shadowColor: colorScheme.shadow,
      centerTitle: centerTitle || style == CustomAppBarStyle.modal,
      leading: effectiveLeading,
      automaticallyImplyLeading: false,
      title: _buildTitle(context, effectiveForegroundColor),
      actions: actions != null
          ? [
              ...actions!,
              const SizedBox(width: 8),
            ]
          : null,
    );
  }

  Widget _buildTitle(BuildContext context, Color foregroundColor) {
    final theme = Theme.of(context);

    if (style == CustomAppBarStyle.cameraOverlay) {
      return Text(
        title,
        style: theme.appBarTheme.titleTextStyle?.copyWith(
          color: foregroundColor,
          fontWeight: FontWeight.w600,
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: 0.3),
              offset: const Offset(0, 1),
              blurRadius: 2,
            ),
          ],
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            title,
            style: theme.appBarTheme.titleTextStyle?.copyWith(
              color: foregroundColor,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        if (isOnline != null) ...[
          const SizedBox(width: 8),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isOnline! ? Colors.green : Colors.grey,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (isOnline! ? Colors.green : Colors.grey)
                      .withValues(alpha: 0.4),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Text(
            isOnline! ? 'Active' : 'Offline',
            style: theme.textTheme.labelSmall?.copyWith(
              color: isOnline! ? Colors.green : Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ],
    );
  }
}

/// Pre-configured app bar for dashboard screens
class CustomDashboardAppBar extends CustomAppBar {
  const CustomDashboardAppBar({
    super.key,
    required super.title,
    super.actions,
  }) : super(
          style: CustomAppBarStyle.dashboard,
          showBackButton: false,
          centerTitle: false,
        );
}

/// Pre-configured app bar for camera overlay screens
class CustomCameraAppBar extends CustomAppBar {
  const CustomCameraAppBar({
    super.key,
    required super.title,
    super.actions,
    super.onBackPressed,
  }) : super(
          style: CustomAppBarStyle.cameraOverlay,
          elevation: 0,
        );
}

/// Pre-configured app bar for modal presentations
class CustomModalAppBar extends CustomAppBar {
  const CustomModalAppBar({
    super.key,
    required super.title,
    super.actions,
    super.onBackPressed,
  }) : super(
          style: CustomAppBarStyle.modal,
          centerTitle: true,
          elevation: 0,
        );
}
