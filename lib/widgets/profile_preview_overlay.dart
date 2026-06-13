import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fluentui_emoji_icon/fluentui_emoji_icon.dart';
import 'package:sizer/sizer.dart';
import '../core/constants/animal_data.dart';
import '../core/theme/app_colors.dart';
import './profile_image_widget.dart';

class ProfilePreviewOverlay extends StatelessWidget {
  final String? photoUrl;
  final String? animalName;
  final String name;
  final int rank;

  const ProfilePreviewOverlay({
    super.key,
    this.photoUrl,
    this.animalName,
    required this.name,
    required this.rank,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors(Theme.of(context).brightness == Brightness.dark);

    // Resolve final animal (same logic as AvatarWidget)
    final String? top3Animal = AnimalData.getTop3Animal(rank);
    final bool isSpecialAvatar = animalName?.toLowerCase() == 'scarface lion';
    final String? finalAnimal = (rank <= 3 && rank >= 1)
        ? (isSpecialAvatar ? animalName : top3Animal)
        : animalName;
    final String? assetPath = AnimalData.getAssetPath(finalAnimal);

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Material(
        color: Colors.black.withValues(alpha: 0.85),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // --- FULL PROFILE CONTAINER ---
              Stack(
                alignment: Alignment.topRight,
                children: [
                  Container(
                    width: 80.w,
                    height: 80.w,
                    decoration: BoxDecoration(
                      color: colors.surface.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: colors.neonBlue.withValues(alpha: 0.5),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: colors.neonBlue.withValues(alpha: 0.2),
                          blurRadius: 40,
                          spreadRadius: 10,
                        )
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ProfileImageWidget(
                      profilePhoto: photoUrl,
                      avatarAnimal: finalAnimal,
                      name: name,
                      size: 80.w,
                      isHexagon: false,
                      scale: (AnimalData.getAdjustments(finalAnimal)['scale'] ?? 1.0) * 1.2, // Slightly larger in preview
                      offsetX: AnimalData.getAdjustments(finalAnimal)['x'] ?? 0.0,
                      offsetY: AnimalData.getAdjustments(finalAnimal)['y'] ?? 0.0,
                    ),
                  ),
                  // Close Button
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.black26,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // --- USER INFO ---
              Text(
                name.toUpperCase().replaceAll(' ', '\n'),
                textAlign: TextAlign.center,
                style: GoogleFonts.orbitron(
                  fontSize: 22,
                  color: Colors.white,
                  letterSpacing: 2,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 10),

              // --- ANIMAL TAG ---
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: colors.neonBlue.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: colors.neonBlue.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (assetPath != null)
                      Image.asset(assetPath, width: 24, height: 24)
                    else if (finalAnimal != null &&
                        AnimalData.getIcon(finalAnimal) != null)
                      FluentUiEmojiIcon(
                        fl: AnimalData.getIcon(finalAnimal)!,
                        w: 24,
                        h: 24,
                      ),
                    const SizedBox(width: 8),
                    Text(
                      finalAnimal ?? "Unknown",
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: colors.neonBlue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 15),

              // --- RANK BADGE ---
              if (rank > 0 && rank <= 3)
                Text(
                  "RANKED #$rank CHAMPION",
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: rank == 1
                        ? Colors.amber
                        : (rank == 2 ? Colors.grey : Colors.brown),
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
