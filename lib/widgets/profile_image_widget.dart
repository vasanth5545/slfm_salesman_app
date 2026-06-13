import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluentui_emoji_icon/fluentui_emoji_icon.dart';
import '../core/constants/animal_data.dart';
import '../core/constants/api_urls.dart';

class ProfileImageWidget extends StatelessWidget {
  final String? profilePhoto;
  final String? avatarAnimal;
  final String name;
  final double size;
  final double? fontSize;
  final Color? backgroundColor;
  final Color? iconColor;

  final bool isHexagon;
  final double scale;
  final double offsetX;
  final double offsetY;

  const ProfileImageWidget({
    super.key,
    this.profilePhoto,
    this.avatarAnimal,
    required this.name,
    this.size = 40,
    this.fontSize,
    this.backgroundColor,
    this.iconColor,
    this.isHexagon = false,
    this.scale = 1.0,    // Big/Small adjustment
    this.offsetX = 0.0,  // Left/Right adjustment
    this.offsetY = 0.0,  // Top/Bottom adjustment
  });

  String get _fullPhotoUrl {
    if (profilePhoto == null || profilePhoto!.isEmpty) return '';
    // Construct full URL. Assumes path is relative to domain root.
    // ApiUrl.baseUrl is https://.../api
    final domain = ApiUrl.baseUrl.replaceAll('/api', '');
    return '$domain/$profilePhoto';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 1. Show Network Photo if available
    if (profilePhoto != null && profilePhoto!.isNotEmpty) {
      Widget image = CachedNetworkImage(
        imageUrl: _fullPhotoUrl,
        fit: BoxFit.cover,
        placeholder: (context, url) => Center(
          child: SizedBox(
            width: size * 0.5,
            height: size * 0.5,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        errorWidget: (context, url, error) => _buildFallback(theme),
      );

      if (isHexagon) {
        return SizedBox(
          width: size,
          height: size,
          child: ClipPath(
            clipper: HexagonClipper(),
            child: Container(
              color: backgroundColor ??
                  theme.colorScheme.primaryContainer.withValues(alpha: 0.1),
              child: image,
            ),
          ),
        );
      }

      return Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: backgroundColor ??
              theme.colorScheme.primaryContainer.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: image,
      );
    }

    // 2. Show Animal Icon (Asset or Emoji) if available
    if (avatarAnimal != null &&
        avatarAnimal!.isNotEmpty &&
        avatarAnimal != "0") {
      final String? assetPath = AnimalData.getAssetPath(avatarAnimal);
      final fluentData = AnimalData.getIcon(avatarAnimal);

      if (assetPath != null || fluentData != null) {
        Widget animalIcon;
        if (assetPath != null) {
          // Use PNG Asset
          animalIcon = Transform.translate(
            offset: Offset(offsetX, offsetY),
            child: Transform.scale(
              scale: scale,
              child: Image.asset(
                assetPath,
                width: size,
                height: size,
                fit: BoxFit.contain, // Changed from cover to contain for better scaling
              ),
            ),
          );
        } else {
          // Fallback to Fluent UI Emoji Icon
          final double iconSize = size * 0.65;
          animalIcon = Center(
            child: Transform.translate(
              offset: Offset(offsetX, offsetY),
              child: Transform.scale(
                scale: scale,
                child: SizedBox(
                  width: iconSize,
                  height: iconSize,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: fluentData != null
                        ? FluentUiEmojiIcon(
                            fl: fluentData,
                            w: iconSize,
                            h: iconSize,
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          );
        }

        if (isHexagon) {
          return SizedBox(
            width: size,
            height: size,
            child: ClipPath(
              clipper: HexagonClipper(),
              child: Container(
                color: backgroundColor ??
                    const Color(0xFF0D1025), // 🔥 DARK ESPORTS BACK
                child: animalIcon,
              ),
            ),
          );
        }

        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: backgroundColor ??
                theme.colorScheme.primaryContainer.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: animalIcon,
        );
      }
    }

    // 3. Fallback to Initials
    return _buildFallback(theme);
  }

  Widget _buildFallback(ThemeData theme) {
    final initials = name
        .trim()
        .split(' ')
        .map((e) => e.isNotEmpty ? e[0] : '')
        .take(2)
        .join()
        .toUpperCase();

    final Widget fallbackText = Text(
      initials.isNotEmpty ? initials : 'S',
      style: TextStyle(
        color: Colors.white,
        fontSize: fontSize ?? (size * 0.4),
        fontWeight: FontWeight.bold,
      ),
    );

    if (isHexagon) {
      return SizedBox(
        width: size,
        height: size,
        child: ClipPath(
          clipper: HexagonClipper(),
          child: Container(
            color: backgroundColor ?? theme.colorScheme.primary,
            alignment: Alignment.center,
            child: fallbackText,
          ),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor ?? theme.colorScheme.primary,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: fallbackText,
    );
  }
}

class HexagonClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    final width = size.width;
    final height = size.height;

    path.moveTo(width * 0.5, 0);
    path.lineTo(width, height * 0.25);
    path.lineTo(width, height * 0.75);
    path.lineTo(width * 0.5, height);
    path.lineTo(0, height * 0.75);
    path.lineTo(0, height * 0.25);
    path.close();

    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
