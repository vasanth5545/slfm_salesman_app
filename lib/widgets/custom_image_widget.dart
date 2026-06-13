import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shimmer/shimmer.dart';
import '../core/app_export.dart';

extension ImageTypeExtension on String {
  ImageType get imageType {
    if (startsWith('http') || startsWith('https')) {
      return ImageType.network;
    } else if (endsWith('.svg')) {
      return ImageType.svg;
    } else if (startsWith('file://') ||
        startsWith('/') ||
        RegExp(r'^[a-zA-Z]:[/\\]').hasMatch(this) ||
        startsWith('data/')) {
      // 🛡️ FIX: Support Windows drive letters (C:\, D:\, etc.)
      return ImageType.file;
    } else {
      return ImageType.png;
    }
  }
}

enum ImageType { svg, png, network, file, unknown }

// ignore_for_file: must_be_immutable
class CustomImageWidget extends StatelessWidget {
  const CustomImageWidget({
    super.key,
    this.imageUrl,
    this.height,
    this.width,
    this.color,
    this.fit,
    this.alignment,
    this.onTap,
    this.radius,
    this.margin,
    this.border,
    this.placeHolder = 'assets/images/vijay.jpg',
    this.errorWidget,
    this.semanticLabel,
  });

  ///[imageUrl] is required parameter for showing image
  final String? imageUrl;

  final double? height;

  final double? width;

  final BoxFit? fit;

  final String placeHolder;

  final Color? color;

  final Alignment? alignment;

  final VoidCallback? onTap;

  final BorderRadius? radius;

  final EdgeInsetsGeometry? margin;

  final BoxBorder? border;

  /// Optional widget to show when the image fails to load.
  /// If null, a default asset image is shown.
  final Widget? errorWidget;

  /// Semantic label for the image to improve accessibility
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return alignment != null
        ? Align(alignment: alignment!, child: _buildWidget())
        : _buildWidget();
  }

  Widget _buildWidget() {
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: _buildCircleImage(),
      ),
    );
  }

  ///build the image with border radius
  _buildCircleImage() {
    if (radius != null) {
      return ClipRRect(
        borderRadius: radius ?? BorderRadius.zero,
        child: _buildImageWithBorder(),
      );
    } else {
      return _buildImageWithBorder();
    }
  }

  ///build the image with border and border radius style
  _buildImageWithBorder() {
    if (border != null) {
      return Container(
        decoration: BoxDecoration(
          border: border,
          borderRadius: radius,
        ),
        child: _buildImageView(),
      );
    } else {
      return _buildImageView();
    }
  }

  Widget _buildImageView() {
    // 🛡️ FIX: Guard against null or empty imageUrl to prevent asset load crash
    if (imageUrl == null || imageUrl!.isEmpty) {
      return Image.asset(
        placeHolder,
        height: height,
        width: width,
        fit: fit ?? BoxFit.cover,
        semanticLabel: semanticLabel,
      );
    }
    if (imageUrl != null) {
      switch (imageUrl!.imageType) {
        case ImageType.svg:
          return SizedBox(
            height: height,
            width: width,
            child: SvgPicture.asset(
              imageUrl!,
              height: height,
              width: width,
              fit: fit ?? BoxFit.contain,
              colorFilter: color != null
                  ? ColorFilter.mode(
                      color ?? Colors.transparent, BlendMode.srcIn)
                  : null,
              semanticsLabel: semanticLabel,
            ),
          );
        case ImageType.file:
          // 🛡️ FIX: Clean the 'file://' prefix if present so File() can read it properly
          String cleanPath = imageUrl!.replaceFirst('file://', '');
          return Image.file(
            File(cleanPath),
            height: height,
            width: width,
            fit: fit ?? BoxFit.cover,
            color: color,
            semanticLabel: semanticLabel,
            // 🛡️ SAFEGARD: If the local file was deleted by OS/User, prevent crash & show placeholder
            errorBuilder: (context, error, stackTrace) =>
                errorWidget ??
                Image.asset(
                  placeHolder,
                  height: height,
                  width: width,
                  fit: fit ?? BoxFit.cover,
                  semanticLabel: semanticLabel,
                ),
          );
        case ImageType.network:
          return CachedNetworkImage(
            height: height,
            width: width,
            fit: fit,
            imageUrl: imageUrl!,
            color: color,
            placeholder: (context, url) {
              return Shimmer.fromColors(
                baseColor: const Color(0xFF097A6B),
                highlightColor: const Color(0xFF0BA490),
                child: Container(
                  height: height,
                  width: width,
                  color: Colors.white,
                ),
              );
            },
            errorWidget: (context, url, error) =>
                errorWidget ??
                Image.asset(
                  placeHolder,
                  height: height,
                  width: width,
                  fit: fit ?? BoxFit.cover,
                  semanticLabel: semanticLabel,
                ),
          );
        case ImageType.png:
        default:
          return Image.asset(
            imageUrl!,
            height: height,
            width: width,
            fit: fit ?? BoxFit.cover,
            color: color,
            semanticLabel: semanticLabel,
            // Add error builder here as well for safety
            errorBuilder: (context, error, stackTrace) =>
                errorWidget ??
                Icon(Icons.broken_image_rounded,
                    color: Colors.grey, size: height ?? 40),
          );
      }
    }
    return SizedBox();
  }
}
