import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:sizer/sizer.dart';
import 'package:slfm_salesman_app/widgets/profile_avatar_widget.dart';

class ScarfaceIntroOverlay extends StatefulWidget {
  final String? photoUrl;
  final String name;
  final VoidCallback onComplete;

  const ScarfaceIntroOverlay({
    super.key,
    required this.photoUrl,
    required this.name,
    required this.onComplete,
  });

  @override
  State<ScarfaceIntroOverlay> createState() => _ScarfaceIntroOverlayState();
}

class _ScarfaceIntroOverlayState extends State<ScarfaceIntroOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _positionAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    // Phase 1: Large Center -> Phase 2: Shrink to Corner
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 40),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.22)
            .chain(CurveTween(curve: Curves.elasticIn)),
        weight: 60,
      ),
    ]).animate(_controller);

    _positionAnimation = TweenSequence<Offset>([
      TweenSequenceItem(tween: ConstantTween<Offset>(Offset.zero), weight: 40),
      TweenSequenceItem(
        tween: Tween<Offset>(
          begin: Offset.zero,
          end: const Offset(45, 45), // Target breakout position approx
        ).chain(CurveTween(curve: Curves.easeInOutBack)),
        weight: 60,
      ),
    ]).animate(_controller);

    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: 0.0), weight: 45),
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: 1.0), weight: 55),
    ]).animate(_controller);

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.85),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background Particles
          Lottie.asset(
            'assets/leaderboard/Crown.json',
            width: 100.w,
            height: 100.h,
            fit: BoxFit.contain,
            repeat: true,
          ),

          // The Reveal Content
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  // 1. Profile Hexagon (Fades in)
                  Opacity(
                    opacity: _opacityAnimation.value,
                    child: ProfileAvatarWidget(
                      photoUrl: widget.photoUrl,
                      animalName: 'Scarface Lion',
                      name: widget.name,
                      rank: 1,
                      radius: 35.w,
                      badgeRadius: 40,
                      isHexagon: true,
                    ),
                  ),

                  // 2. Jumping/Shrinking Scarface
                  // Use Opacity 1.0 until shrink starts?
                  // We only show this one when profile is NOT fully revealed or we hide the badge inside ProfileAvatarWidget
                  // For simplicity, we just overlay this one.
                  if (_opacityAnimation.value < 0.9)
                    Transform.translate(
                      offset: _positionAnimation.value,
                      child: Transform.scale(
                        scale: _scaleAnimation.value * 2.5, // Start BIG
                        child: Image.asset(
                          'assets/leaderboard/SCARFACE_LION.png',
                          width: 120,
                          height: 120,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),

          // Tap to Dismiss
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onComplete,
              onPanStart: (_) {},
              onPanUpdate: (_) {},
              onPanEnd: (_) {},
              onPanCancel: () {},
            ),
          ),
        ],
      ),
    );
  }
}
