import 'private_recipe_image.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class RecipeThumbnail extends StatelessWidget {
  const RecipeThumbnail({
    super.key,
    required this.imageUrl,
    this.width = 72,
    this.height = 72,
  });

  final String? imageUrl;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final hasImage = (imageUrl ?? '').isNotEmpty;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = width.isFinite && width > 0
        ? (width * pixelRatio).ceil().clamp(1, 4096).toInt()
        : null;
    final cacheHeight = height.isFinite && height > 0
        ? (height * pixelRatio).ceil().clamp(1, 4096).toInt()
        : null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: width,
        height: height,
        child: hasImage
            ? PrivateRecipeImage(
                imageUrl!,
                fit: BoxFit.cover,
                cacheWidth: cacheWidth,
                cacheHeight: cacheHeight,
                errorBuilder: (_, __, ___) => _ThumbnailPlaceholder(
                  width: width,
                  height: height,
                ),
              )
            : _ThumbnailPlaceholder(
                width: width,
                height: height,
              ),
      ),
    );
  }
}

class _ThumbnailPlaceholder extends StatelessWidget {
  const _ThumbnailPlaceholder({
    required this.width,
    required this.height,
  });

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: const BoxDecoration(
          gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[ScoutStyle.mint, Color(0xFFF4E8D6)],
      )),
      alignment: Alignment.center,
      child: Icon(
        Icons.ramen_dining_rounded,
        size: height > 100 ? 56 : 28,
        color: ScoutStyle.forest,
      ),
    );
  }
}
