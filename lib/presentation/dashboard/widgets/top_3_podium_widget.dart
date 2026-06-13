import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import '../../../widgets/profile_avatar_widget.dart';
import '../../../widgets/profile_preview_overlay.dart';
import '../../../core/theme/app_colors.dart';

class Top3PodiumWidget extends StatefulWidget {
  final List<dynamic> salesmen;
  final bool isLoading;
  final VoidCallback? onRefresh;
  final String? initialShowroom;
  final bool forceFilterToInitial;
  final int scarfaceLimit; // 🔥 NEW

  const Top3PodiumWidget({
    super.key,
    required this.salesmen,
    required this.isLoading,
    this.onRefresh,
    this.initialShowroom,
    this.forceFilterToInitial = false,
    this.scarfaceLimit = 1000, // 🔥 NEW
  });

  @override
  State<Top3PodiumWidget> createState() => _Top3PodiumWidgetState();
}

class _Top3PodiumWidgetState extends State<Top3PodiumWidget>
    with SingleTickerProviderStateMixin {
  // --- RANK IMAGE SIZE ADJUSTMENTS ---
  double get _rank1BadgeSize => 100.0;
  double get _rank2BadgeSize => 85.0;
  double get _rank3BadgeSize => 90.0;

  double get _badgeTopSpacing => 18.0;

  double get _rank1BadgeOffsetX => 5.0;
  double get _rank2BadgeOffsetX => 5.0;
  double get _rank3BadgeOffsetX => 5.0;
  // -----------------------------------

  late AnimationController _controller;
  final Random _random = Random();
  final List<StarModel> _particles = [];

  String _selectedShowroom = 'All Showrooms';
  bool _hasManuallyChangedShowroom = false; // 🔥 Track manual override

  @override
  void initState() {
    super.initState();
    _initializeShowroom();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat();

    for (int i = 0; i < 40; i++) {
      _particles.add(StarModel(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        angle: 0.0,
        size: _random.nextDouble() * 2.5 + 0.5,
        speed: _random.nextDouble() * 0.002 + 0.001,
        opacity: _random.nextDouble() * 0.5,
      ));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _initializeShowroom() {
    if (widget.initialShowroom != null && widget.initialShowroom!.isNotEmpty) {
      // Find case-insensitive match in salesmen if already available
      String? matchedShowroom;
      for (var s in widget.salesmen) {
        final sName = s['showroom_name']?.toString() ?? '';
        if (sName.toLowerCase().trim() ==
            widget.initialShowroom!.toLowerCase().trim()) {
          matchedShowroom = sName;
          break;
        }
      }
      // 🔥 TASK 1 FIX: If the user's showroom isn't in the leaderboard yet, safely fallback to 'All Showrooms'
      _selectedShowroom = matchedShowroom ?? 'All Showrooms';
    } else {
      _selectedShowroom = 'All Showrooms';
    }
  }

  @override
  void didUpdateWidget(Top3PodiumWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!_hasManuallyChangedShowroom) {
      // Always try to sync the initialShowroom if we haven't manually changed it,
      // especially when new salesmen data arrives or initial showroom updates.
      if (widget.initialShowroom != null &&
          widget.initialShowroom!.isNotEmpty) {
        String? matchedShowroom;
        for (var s in widget.salesmen) {
          final sName = s['showroom_name']?.toString() ?? '';
          if (sName.toLowerCase().trim() ==
              widget.initialShowroom!.toLowerCase().trim()) {
            matchedShowroom = sName;
            break;
          }
        }

        // 🔥 TASK 1 FIX: If there's no match in the new data, auto-select All Showrooms
        final newSelection = matchedShowroom ?? 'All Showrooms';
        // If the exact matched name is different from what we hold, update it.
        if (_selectedShowroom != newSelection) {
          setState(() {
            _selectedShowroom = newSelection;
          });
        }
      }
    } else {
      // 🔥 FIX: If the user manually selected a showroom, but it suddenly disappears from the leaderboard data, reset it
      if (_selectedShowroom != 'All Showrooms') {
        bool exists = widget.salesmen.any((s) {
          final sName = s['showroom_name']?.toString() ?? '';
          return sName.toLowerCase().trim() ==
              _selectedShowroom.toLowerCase().trim();
        });
        if (!exists) {
          setState(() {
            _selectedShowroom = 'All Showrooms';
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
      return _buildSkeleton();
    }

    final List<dynamic> totalSalesmen = widget.salesmen;

    if (totalSalesmen.isEmpty) return const SizedBox.shrink();

    // 🔥 TASK 1 FIX: Smart Filter
    // Ensure that _selectedShowroom actually exists in the new array.
    // This stops the blank results glitch from happening if it tries to filter by an empty match.
    bool filterExists = false;
    if (_selectedShowroom != 'All Showrooms') {
      filterExists = totalSalesmen.any((s) {
        final sName = s['showroom_name']?.toString() ?? '';
        return sName.toLowerCase().trim() ==
            _selectedShowroom.toLowerCase().trim();
      });
    }
    String effectiveFilter = filterExists ? _selectedShowroom : 'All Showrooms';

    List<dynamic> filteredSalesmen = List.from(totalSalesmen);
    if (effectiveFilter != 'All Showrooms') {
      // Made case-insensitive to prevent empty lists when API case differs
      filteredSalesmen = totalSalesmen.where((s) {
        final sName = s['showroom_name']?.toString() ?? '';
        return sName.toLowerCase().trim() ==
            effectiveFilter.toLowerCase().trim();
      }).toList();
    }

    List<dynamic> displaySalesmen = filteredSalesmen.take(3).toList();

    final colors = AppColors(Theme.of(context).brightness == Brightness.dark);

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 1.w),
      decoration: BoxDecoration(
        color: colors.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colors.divider.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.textPrimary.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: Stack(
              children: [
                Positioned(
                  top: -2.h,
                  right: -4.w,
                  child: Icon(
                    Icons.workspace_premium,
                    size: 250,
                    color: Colors.white.withValues(alpha: 0.02),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: -10.w,
                  child: Container(
                    width: 40.w,
                    height: 20.h,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFF0091FF).withValues(alpha: 0.15),
                          Colors.transparent
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: -10.w,
                  child: Container(
                    width: 40.w,
                    height: 20.h,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFFAA00FF).withValues(alpha: 0.15),
                          Colors.transparent
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return CustomPaint(
                  painter: ParticleFieldPainter(
                    particles: _particles,
                    animationValue: _controller.value,
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 1.5.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(),
                SizedBox(height: 1.h),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (displaySalesmen.length >= 2)
                      Flexible(
                        flex: 1,
                        child: _buildPodiumItem(displaySalesmen[1], 2, 1.5.h),
                      ),
                    if (displaySalesmen.length >= 2) SizedBox(width: 1.5.w),
                    if (displaySalesmen.isNotEmpty)
                      Flexible(
                        flex: 1,
                        child: _buildPodiumItem(displaySalesmen[0], 1, 3.5.h),
                      ),
                    if (displaySalesmen.length >= 3) SizedBox(width: 1.5.w),
                    if (displaySalesmen.length >= 3)
                      Flexible(
                        flex: 1,
                        child: _buildPodiumItem(displaySalesmen[2], 3, 1.5.h),
                      ),
                  ],
                ),
                SizedBox(height: 1.h),
                _buildBottomPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeleton() {
    final colors = AppColors(Theme.of(context).brightness == Brightness.dark);
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 1.w),
      padding: EdgeInsets.all(4.w),
      decoration: BoxDecoration(
        color: colors.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: colors.divider.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _shimmerBox(120, 14),
              _shimmerBox(100, 12),
            ],
          ),
          SizedBox(height: 2.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: _skeletonPodiumColumn(height: 80)),
              SizedBox(width: 2.w),
              Expanded(child: _skeletonPodiumColumn(height: 110)),
              SizedBox(width: 2.w),
              Expanded(child: _skeletonPodiumColumn(height: 70)),
            ],
          ),
          SizedBox(height: 2.h),
          _shimmerBox(double.infinity, 36),
        ],
      ),
    );
  }

  Widget _skeletonPodiumColumn({required double height}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _shimmerBox(15.w, 15.w, isCircle: true),
        SizedBox(height: 1.h),
        _shimmerBox(30, height * 0.3),
      ],
    );
  }

  Widget _shimmerBox(double width, double height, {bool isCircle = false}) {
    final appColors = AppColors.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 1500),
      builder: (ctx, value, child) {
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: isCircle ? null : BorderRadius.circular(6),
            gradient: LinearGradient(
              colors: [
                appColors.textPrimary.withValues(alpha: 0.04),
                appColors.textPrimary.withValues(alpha: 0.12),
                appColors.textPrimary.withValues(alpha: 0.04),
              ],
              stops: [
                (value - 0.3).clamp(0.0, 1.0),
                value,
                (value + 0.3).clamp(0.0, 1.0),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        );
      },
      onEnd: () {
        if (mounted) setState(() {});
      },
    );
  }

  Widget _buildHeader() {
    final colors = AppColors.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "TOP 3",
                      style: GoogleFonts.inter(
                        textStyle: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          fontStyle: FontStyle.italic,
                          letterSpacing: 1.5,
                          height: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (widget.onRefresh != null)
                      GestureDetector(
                        onTap: widget.onRefresh,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.15)),
                          ),
                          child: Icon(
                            Icons.refresh_rounded,
                            color: colors.textPrimary.withValues(alpha: 0.7),
                            size: 18,
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    _buildShowroomDropdown(),
                  ],
                ),
                Transform(
                  transform: Matrix4.skewX(-0.15),
                  child: Stack(
                    children: [
                      Transform.translate(
                        offset: const Offset(3, 3),
                        child: Text(
                          "CHAMPIONS ",
                          style: GoogleFonts.inter(
                            textStyle: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              fontStyle: FontStyle.italic,
                              letterSpacing: 1.5,
                              foreground: Paint()
                                ..style = PaintingStyle.stroke
                                ..strokeWidth = 3
                                ..color =
                                    colors.textPrimary.withValues(alpha: 0.05),
                            ),
                          ),
                        ),
                      ),
                      Transform.translate(
                        offset: const Offset(3, 3),
                        child: Text(
                          "CHAMPIONS ",
                          style: GoogleFonts.inter(
                            textStyle: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              fontStyle: FontStyle.italic,
                              letterSpacing: 1.5,
                              color: colors.textPrimary.withValues(alpha: 0.1),
                            ),
                          ),
                        ),
                      ),
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [Color(0xFF2D31FA), Color(0xFF901CFE)],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          stops: [0.3, 1.0],
                        ).createShader(bounds),
                        child: Text(
                          "CHAMPIONS ",
                          style: GoogleFonts.inter(
                            textStyle: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              fontStyle: FontStyle.italic,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text("/// PERFORMANCE ARENA ///",
                        style: GoogleFonts.inter(
                          textStyle: TextStyle(
                            color: colors.textSecondary.withValues(alpha: 0.5),
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        )),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.redAccent.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    "LIVE",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildShowroomDropdown() {
    final colors = AppColors.of(context);
    final Set<String> uniqueShowrooms = {};
    for (var s in widget.salesmen) {
      final sName = s['showroom_name']?.toString() ?? '';
      if (sName.isNotEmpty && sName != 'All Showrooms') {
        uniqueShowrooms.add(sName);
      }
    }
    List<String> sortedShowrooms = uniqueShowrooms.toList();
    sortedShowrooms.sort();
    List<String> showrooms = ['All Showrooms', ...sortedShowrooms];

    String effectiveSelection = _selectedShowroom;
    if (!showrooms.contains(effectiveSelection)) {
      effectiveSelection = 'All Showrooms';
    }

    return Container(
      height: 32,
      constraints: const BoxConstraints(maxWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.divider),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: effectiveSelection,
          isExpanded: true,
          icon: Icon(Icons.arrow_drop_down,
              color: colors.textSecondary.withValues(alpha: 0.7), size: 20),
          dropdownColor: colors.surface,
          style: GoogleFonts.inter(
            textStyle: TextStyle(
              color: colors.textPrimary.withValues(alpha: 0.9),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          onChanged: (String? newValue) {
            if (newValue != null && mounted) {
              setState(() {
                _selectedShowroom = newValue;
                _hasManuallyChangedShowroom = true; // 🔒 User has taken control
              });
            }
          },
          items: showrooms.map<DropdownMenuItem<String>>((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildPodiumItem(dynamic user, int rank, double baseHeight) {
    final colors = AppColors(Theme.of(context).brightness == Brightness.dark);
    Color themeColor;
    Color neonColor;

    switch (rank) {
      case 1:
        themeColor = const Color(0xFFFFC107);
        neonColor = const Color(0xFFFFD700);
        break;
      case 2:
        themeColor = const Color(0xFFC0C0C0);
        neonColor = const Color(0xFFE0E0E0);
        break;
      default:
        themeColor = const Color(0xFFCD7F32);
        neonColor = const Color(0xFFE89B54);
    }

    final int score =
        int.tryParse(user['billed_count']?.toString() ?? '0') ?? 0;
    final bool isRealRank = score > 0;
    final String actualName = user['name'] ?? "Unknown";
    final String name = isRealRank ? actualName : "RANKED";
    final String photoUrl = user['profile_photo'] ?? '';

    double hexWidth = rank == 1 ? 20.w : 18.w;
    double hexHeight = rank == 1 ? 22.w : 19.w;
    double podiumNeckMargin =
        rank == 1 ? (hexHeight * 0.45) : (hexHeight * 0.45);

    final bool isScarfaceUser =
        user['avatar_animal']?.toString().toLowerCase() == 'scarface lion';

    // 🔥 TASK 1: Dynamic Re-locking Logic
    // If they have Scarface Lion but their score is below the current limit, revert to normal Lion
    String finalAnimal = user['avatar_animal']?.toString() ?? 'Lion';
    if (isScarfaceUser && score < widget.scarfaceLimit) {
      finalAnimal = 'Lion';
    }

    return GestureDetector(
      onTap: () {
        showDialog(
          context: context,
          barrierColor: Colors.black87,
          builder: (context) => ProfilePreviewOverlay(
            photoUrl: isRealRank ? photoUrl : null,
            animalName: finalAnimal,
            name: isRealRank ? actualName : 'RANKED',
            rank: rank,
          ),
        );
      },
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: rank == 1 ? 10 : 0,
            child: SizedBox(
              width: hexWidth,
              height: hexHeight,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: Container(
                      margin: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: themeColor,
                        boxShadow: [
                          BoxShadow(
                            color: themeColor.withValues(alpha: 0.8),
                            blurRadius: 40,
                            spreadRadius: 20,
                          )
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: -150,
                    bottom: -150,
                    left: -150,
                    right: -150,
                    child: LocalParticlesWidget(color: themeColor),
                  ),
                ],
              ),
            ),
          ),
          Container(
            margin: EdgeInsets.only(top: podiumNeckMargin),
            child: CustomPaint(
              painter: PodiumPainter(
                color: themeColor,
                isRank1: rank == 1,
              ),
              child: SizedBox(
                width: rank == 1 ? 26.w : 22.w,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(height: rank == 1 ? 55 : 45),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: Text(
                        (isRealRank ? actualName : 'RANKED')
                            .split(' ')
                            .where((s) => s.isNotEmpty)
                            .join('\n'),
                        style: GoogleFonts.orbitron(
                          color: colors.textPrimary,
                          fontSize: rank == 1 ? 11 : 9.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                          height: 1.1,
                        ),
                        maxLines: 3,
                        softWrap: true,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (score > 0)
                      Text(
                        "$score BILLED",
                        style: GoogleFonts.orbitron(
                          textStyle: TextStyle(
                            color: themeColor,
                            fontSize: rank == 1 ? 13 : 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            shadows: [
                              Shadow(
                                  color: themeColor.withValues(alpha: 0.5),
                                  blurRadius: 10),
                            ],
                          ),
                        ),
                        textAlign: TextAlign.center,
                      )
                    else
                      SizedBox(
                        height: 18,
                        width: rank == 1 ? 26.w : 22.w,
                        child: _SimpleMarqueeText(
                          text: "*** BECOME RANKED! START BILLING NOW ***",
                          style: GoogleFonts.inter(
                            textStyle: TextStyle(
                              color: Colors.red.shade700,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    SizedBox(height: _badgeTopSpacing),
                    Transform.translate(
                      offset: Offset(
                          rank == 1
                              ? _rank1BadgeOffsetX
                              : (rank == 2
                                  ? _rank2BadgeOffsetX
                                  : _rank3BadgeOffsetX),
                          0.0),
                      child: Transform.scale(
                        scale: rank == 1
                            ? _rank1BadgeSize / 45.0
                            : (rank == 2
                                ? _rank2BadgeSize / 35.0
                                : _rank3BadgeSize / 35.0),
                        child: Image.asset(
                          rank == 1
                              ? 'assets/leaderboard/ranking/top_1.png'
                              : rank == 2
                                  ? 'assets/leaderboard/ranking/top_2.png'
                                  : 'assets/leaderboard/ranking/top_3.png',
                          width: rank == 1 ? 45 : 35,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    SizedBox(height: baseHeight),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: rank == 1 ? 10 : 0,
            child: SizedBox(
              width: hexWidth,
              height: hexHeight,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: hexWidth,
                    height: hexHeight,
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: neonColor.withValues(alpha: 0.3),
                          blurRadius: 15,
                          spreadRadius: 2,
                        )
                      ],
                    ),
                    child: CustomPaint(
                      painter: HexagonPainter(
                        color: themeColor,
                        strokeWidth: rank == 1 ? 6 : 4,
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(rank == 1 ? 6.0 : 4.0),
                        child: ProfileAvatarWidget(
                          photoUrl: isRealRank ? photoUrl : null,
                          animalName:
                              finalAnimal, // 🔥 Pass the calculated animal
                          rank: rank,
                          name: isRealRank ? name : 'RANKED',
                          radius: rank == 1 ? 10.w : 8.w,
                          badgeRadius: 12,
                          badgeBottom: -20,
                          badgeRight: -8,
                          isHexagon: true,
                        ),
                      ),
                    ),
                  ),
                  if (rank > 1)
                    Positioned(
                      top: -45,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "YOU CAN BE #1!",
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              color: themeColor,
                              letterSpacing: 0.5,
                              fontWeight: FontWeight.bold,
                              shadows: [
                                Shadow(
                                    color: colors.cardBg,
                                    blurRadius: 4,
                                    offset: const Offset(1, 1)),
                              ],
                            ),
                          ),
                          Text(
                            "KEEP PUSHING",
                            style: GoogleFonts.inter(
                              fontSize: 8,
                              color:
                                  colors.textSecondary.withValues(alpha: 0.8),
                              letterSpacing: 1.5,
                              fontWeight: FontWeight.bold,
                              shadows: [
                                Shadow(
                                    color: themeColor.withValues(alpha: 0.3),
                                    blurRadius: 10),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (rank == 1)
                    Positioned(
                      top: -35,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.9, end: 1.1),
                        duration: const Duration(seconds: 1),
                        curve: Curves.easeInOutSine,
                        builder: (context, value, child) {
                          return Transform.scale(
                            scale: value,
                            child: const _SlowLottieCrown(size: 60),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: -5,
            child: Container(
              width: rank == 1 ? 28.w : 24.w,
              height: 10,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(50),
                border: Border(
                  bottom: BorderSide(color: neonColor, width: 3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: neonColor.withValues(alpha: 0.8),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildBottomPanel() {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.gold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.gold.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Icon(Icons.stars_rounded, color: colors.gold, size: 18),
          const SizedBox(width: 8),
          Text(
            "THE CHAMPION'S ARENA",
            style: GoogleFonts.orbitron(
              color: colors.gold.withValues(alpha: 0.8),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
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

class HexagonPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  HexagonPainter({required this.color, this.strokeWidth = 2});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

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

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class StarModel {
  double x;
  double y;
  double angle;
  double size;
  double speed;
  double opacity;

  StarModel({
    required this.x,
    required this.y,
    required this.angle,
    required this.size,
    required this.speed,
    required this.opacity,
  });
}

class ParticleFieldPainter extends CustomPainter {
  final List<StarModel> particles;
  final double animationValue;

  ParticleFieldPainter({required this.particles, required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;

    for (var p in particles) {
      double twinkle = (sin(animationValue * 4 * pi + p.x * 20) + 1) / 2;
      double finalOpacity = p.opacity * 0.3 + twinkle * 0.7;

      paint.color =
          Colors.white.withValues(alpha: finalOpacity.clamp(0.0, 1.0));

      double currentY = (p.y - animationValue * p.speed * 100) % 1.0;
      if (currentY < 0) currentY += 1.0;

      canvas.drawCircle(
        Offset(p.x * size.width, currentY * size.height),
        p.size,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant ParticleFieldPainter oldDelegate) => true;
}

class PodiumPainter extends CustomPainter {
  final Color color;
  final bool isRank1;

  PodiumPainter({required this.color, required this.isRank1});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          color.withValues(alpha: 0.3),
          color.withValues(alpha: 0.05),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    final path = Path();

    double neckWidth = w * 0.4;
    double topHeight = isRank1 ? 25.0 : 15.0;
    double neckStart = (w - neckWidth) / 2;
    double neckEnd = neckStart + neckWidth;

    path.moveTo(0, h);
    path.lineTo(0, topHeight + 10);
    path.quadraticBezierTo(0, topHeight, 10, topHeight);
    path.lineTo(neckStart - 10, topHeight);
    path.quadraticBezierTo(neckStart, topHeight, neckStart + 5, topHeight - 5);
    path.lineTo(neckStart + 10, 0);
    path.lineTo(neckEnd - 10, 0);
    path.lineTo(neckEnd - 5, topHeight - 5);
    path.quadraticBezierTo(neckEnd, topHeight, neckEnd + 10, topHeight);
    path.lineTo(w - 10, topHeight);
    path.quadraticBezierTo(w, topHeight, w, topHeight + 10);
    path.lineTo(w, h);
    path.close();

    canvas.drawPath(path, paint);

    final borderPath = Path()
      ..moveTo(0, h)
      ..lineTo(0, topHeight + 10)
      ..quadraticBezierTo(0, topHeight, 10, topHeight)
      ..lineTo(neckStart - 10, topHeight)
      ..quadraticBezierTo(neckStart, topHeight, neckStart + 5, topHeight - 5)
      ..lineTo(neckStart + 10, 0)
      ..lineTo(neckEnd - 10, 0)
      ..lineTo(neckEnd - 5, topHeight - 5)
      ..quadraticBezierTo(neckEnd, topHeight, neckEnd + 10, topHeight)
      ..lineTo(w - 10, topHeight)
      ..quadraticBezierTo(w, topHeight, w, topHeight + 10)
      ..lineTo(w, h);

    canvas.drawPath(borderPath, glowPaint);
    canvas.drawPath(borderPath, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class LocalParticlesWidget extends StatefulWidget {
  final Color color;
  const LocalParticlesWidget({super.key, required this.color});

  @override
  State<LocalParticlesWidget> createState() => _LocalParticlesWidgetState();
}

class _LocalParticlesWidgetState extends State<LocalParticlesWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<StarModel> _particles = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 10))
          ..addListener(() {
            for (var p in _particles) {
              p.x += cos(p.angle) * p.speed;
              p.y += sin(p.angle) * p.speed;

              if (p.x < 0.0) p.x = 1.0;
              if (p.x > 1.0) p.x = 0.0;
              if (p.y < 0.0) p.y = 1.0;
              if (p.y > 1.0) p.y = 0.0;

              p.angle += (_random.nextDouble() - 0.5) * 0.1;
            }
          })
          ..repeat();

    for (int i = 0; i < 35; i++) {
      _particles.add(StarModel(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        angle: _random.nextDouble() * 2 * pi,
        size: _random.nextDouble() * 2.5 + 1.0,
        speed: _random.nextDouble() * 0.002 + 0.0005,
        opacity: _random.nextDouble() * 0.5 + 0.2,
      ));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: PodiumParticlePainter(
            particles: _particles,
            animationValue: _controller.value,
            color: widget.color,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class PodiumParticlePainter extends CustomPainter {
  final List<StarModel> particles;
  final double animationValue;
  final Color color;

  PodiumParticlePainter({
    required this.particles,
    required this.animationValue,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (var p in particles) {
      double twinkle = (sin(animationValue * pi * 8 + p.x * 20) + 1) / 2;
      double currentOpacity = p.opacity * 0.4 + twinkle * 0.6;

      paint.color = color.withValues(alpha: currentOpacity.clamp(0.0, 1.0));

      canvas.drawCircle(
        Offset(p.x * size.width, p.y * size.height),
        p.size,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant PodiumParticlePainter oldDelegate) => true;
}

class _SlowLottieCrown extends StatefulWidget {
  final double size;
  const _SlowLottieCrown({required this.size});

  @override
  State<_SlowLottieCrown> createState() => _SlowLottieCrownState();
}

class _SlowLottieCrownState extends State<_SlowLottieCrown>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3500))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Lottie.asset(
      'assets/leaderboard/dashborad_widget_leaderboard/Crown rotate.json',
      width: widget.size,
      height: widget.size,
      fit: BoxFit.contain,
      controller: _controller,
    );
  }
}

class _SimpleMarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  const _SimpleMarqueeText({required this.text, required this.style});

  @override
  State<_SimpleMarqueeText> createState() => _SimpleMarqueeTextState();
}

class _SimpleMarqueeTextState extends State<_SimpleMarqueeText>
    with SingleTickerProviderStateMixin {
  late ScrollController _scrollController;
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 12000));

    _controller.addListener(() {
      if (_scrollController.hasClients) {
        final maxScroll = _scrollController.position.maxScrollExtent;
        if (maxScroll > 0) {
          _scrollController.jumpTo(_controller.value * maxScroll);
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.repeat();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(widget.text, style: widget.style),
          const SizedBox(width: 50),
          Text(widget.text, style: widget.style),
          const SizedBox(width: 50),
        ],
      ),
    );
  }
}
