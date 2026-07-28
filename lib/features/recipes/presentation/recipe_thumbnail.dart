import 'package:flutter/material.dart';

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
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final cacheWidth = (width * devicePixelRatio).round();
    final cacheHeight = (height * devicePixelRatio).round();

    return RepaintBoundary(
      child: ClipRRect(
        clipBehavior: Clip.hardEdge,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: width,
          height: height,
          child: hasImage
              ? Image.network(
                  imageUrl!,
                  fit: BoxFit.cover,
                  cacheWidth: cacheWidth,
                  cacheHeight: cacheHeight,
                  filterQuality: FilterQuality.none,
                  isAntiAlias: false,
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
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      color: colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.restaurant_menu,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }
}
