import 'package:flutter/material.dart';
import 'package:fluentui_emoji_icon/fluentui_emoji_icon.dart';
import '../core/constants/animal_data.dart';
import './profile_image_widget.dart';

class ProfileAvatarWidget extends StatelessWidget {
  final String? photoUrl;
  final String? animalName;
  final String name;
  final int rank;
  final double radius;
  final double badgeRadius;
  final bool showRankBadge;

  final bool isHexagon;
  final double? badgeBottom;
  final double? badgeRight;

  const ProfileAvatarWidget({
    super.key,
    this.photoUrl,
    this.animalName,
    required this.name,
    required this.rank,
    this.radius = 20,
    this.badgeRadius = 8,
    this.showRankBadge = false,
    this.isHexagon = false,
    this.badgeBottom,
    this.badgeRight,
  });

  @override
  Widget build(BuildContext context) {
    // Determine which animal to show
    // Locked Top 3: 1=Lion, 2=Tiger, 3=Elephant
    final String? top3Animal = AnimalData.getTop3Animal(rank);

    // 🔥 FIX: If the user explicitly has a special avatar like "Scarface Lion", 
    // it should override the default Top 3 rank icon.
    final bool isSpecialAvatar =
        animalName?.toLowerCase() == 'scarface lion';

    final String? finalAnimal = (rank <= 3 && rank >= 1)
        ? (isSpecialAvatar ? animalName : top3Animal)
        : animalName;

    final String? assetPath = AnimalData.getAssetPath(finalAnimal);
    final adjustments = AnimalData.getAdjustments(finalAnimal);

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        ProfileImageWidget(
          profilePhoto: photoUrl,
          avatarAnimal: finalAnimal,
          name: name,
          size: radius * 2,
          isHexagon: isHexagon,
          scale: adjustments['scale'] ?? 1.0,
          offsetX: adjustments['x'] ?? 0.0,
          offsetY: adjustments['y'] ?? 0.0,
        ),

        // ANIMAL BADGE (Bottom Right)
        if (photoUrl != null &&
            photoUrl!.isNotEmpty &&
            finalAnimal != null &&
            finalAnimal != "0" &&
            (assetPath != null || AnimalData.getIcon(finalAnimal) != null))
          Positioned(
            bottom: badgeBottom ?? -10,
            right: badgeRight ?? -10,
            child: Container(
              width: badgeRadius * 2.8,
              height: badgeRadius * 2.8,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1025), // 🔥 GUARANTEED BLACK BACK
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 6,
                    spreadRadius: 1,
                  )
                ],
              ),
              child: Center(
                child: Transform.translate(
                  offset: Offset(adjustments['x']!, adjustments['y']!),
                  child: Transform.scale(
                    scale: adjustments['scale']!,
                    child: FittedBox(
                      fit: BoxFit.contain,
                        child: assetPath != null
                            ? Image.asset(assetPath,
                                width: badgeRadius * 2, height: badgeRadius * 2)
                            : (AnimalData.getIcon(finalAnimal) != null
                                ? FluentUiEmojiIcon(
                                    w: badgeRadius * 2,
                                    h: badgeRadius * 2,
                                    fl: AnimalData.getIcon(finalAnimal)!,
                                  )
                                : const SizedBox.shrink()),
                    ),
                  ),
                ),
              ),
            ),
          ),

        // RANK BADGE (Bottom Left - primarily for ranking lists)
        if (showRankBadge && rank > 0)
          Positioned(
            bottom: -2,
            left: -2,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: rank == 1
                    ? const Color(0xFFFFD700) // Gold
                    : rank == 2
                        ? const Color(0xFFC0C0C0) // Silver
                        : rank == 3
                            ? const Color(0xFFCD7F32) // Bronze
                            : const Color(0xFF0D1025),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF060818), width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black45,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  )
                ],
              ),
              child: Center(
                child: Text(
                  '$rank',
                  style: TextStyle(
                    color: rank <= 3 ? Colors.black : Colors.white,
                    fontSize: badgeRadius,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
