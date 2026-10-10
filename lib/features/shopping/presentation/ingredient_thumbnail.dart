import 'package:flutter/material.dart';
import '../../../core/localization/app_localizations.dart';
import '../domain/ingredient_photo.dart';

class IngredientThumbnail extends StatelessWidget {
  const IngredientThumbnail(
      {super.key, required this.ingredient, this.size = 56});
  final String ingredient;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations(Localizations.localeOf(context));
    final photo = IngredientPhoto.find(ingredient);
    final asset = photo?.asset ?? IngredientPhoto.fallbackAsset;
    final label = l10n.bilingual('재료 대표 이미지 · 실제 판매상품 사진이 아닙니다.',
        'Representative ingredient image, not a photo of the sale product.');
    final colors = Theme.of(context).colorScheme;
    Widget placeholder() => ColoredBox(
        color: colors.surfaceContainerHighest,
        child: Center(
            child: Icon(Icons.restaurant_outlined,
                size: size * .42, color: colors.onSurfaceVariant)));
    return Semantics(
      image: true,
      label: '$ingredient · $label',
      child: ExcludeSemantics(
        child: Tooltip(
          message: label,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox.square(
              dimension: size,
              child: Stack(fit: StackFit.expand, children: [
                Image.asset(asset,
                    fit: BoxFit.cover,
                    cacheWidth: 168,
                    errorBuilder: (_, __, ___) => placeholder()),
                Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                        width: double.infinity,
                        color: const Color(0xEFFFFFFF),
                        child: Text(l10n.bilingual('대표', 'Sample'),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 10,
                                height: 1.3,
                                color: Color(0xFF49403F))))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
