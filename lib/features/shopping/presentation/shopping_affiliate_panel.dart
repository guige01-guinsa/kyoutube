import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/localization/localized_text.dart';
import '../../auth/application/auth_providers.dart';
import '../data/shopping_affiliate_repository.dart';
import '../data/shopping_assistant_repository.dart';
import 'coupang_disclosure.dart';
import 'coupang_general_search.dart';
import 'ingredient_thumbnail.dart';

class ShoppingAffiliatePanel extends ConsumerWidget {
  const ShoppingAffiliatePanel(
      {super.key,
      required this.ingredient,
      this.showCoupangDisclosure = true,
      this.showEmptyCoupang = false,
      this.coupangOnly = false});
  final String ingredient;
  final bool showEmptyCoupang;
  final bool coupangOnly;
  final bool showCoupangDisclosure;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(activeAccountIdProvider);
    return ref.watch(shoppingAffiliatesProvider(ingredient)).when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LocalizedText(
                        '제휴 상품을 불러오지 못했습니다. 일반 검색은 계속 사용할 수 있습니다.'),
                    if (showEmptyCoupang)
                      CoupangGeneralSearch(ingredient: ingredient),
                    TextButton.icon(
                        onPressed: () => ref
                            .invalidate(shoppingAffiliatesProvider(ingredient)),
                        icon: const Icon(Icons.refresh),
                        label: const LocalizedText('제휴 상품 다시 불러오기')),
                  ])),
          data: (offers) {
            // Temporarily hide Naver without deleting the saved links.
            final visible = [
              ...offers.where((o) => o.program == 'coupang'),
              if (!coupangOnly)
                ...offers.where(
                    (o) => o.program != 'coupang' && o.program != 'naver'),
            ];
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (visible.where((o) => o.program == 'coupang').length > 1)
                    LocalizedText(
                        '쿠팡 제휴 상품 ${visible.where((o) => o.program == 'coupang').length}개입니다. 상품명과 판매 규격을 비교해 선택해 주세요.'),
                  if (showEmptyCoupang &&
                      !visible.any((o) => o.program == 'coupang'))
                    CoupangGeneralSearch(ingredient: ingredient),
                  for (final offer in visible)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (offer.program == 'coupang') ...[
                              offer.imageUrl != null
                                  ? _AffiliateImage(imageUrl: offer.imageUrl)
                                  : IngredientThumbnail(
                                      ingredient: ingredient, size: 64),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (offer.program != 'coupang')
                                    LocalizedText(offer.program == 'youtube'
                                        ? '영상의 상품 태그를 통한 구매로 채널 운영자가 수수료를 받을 수 있습니다.'
                                        : '이 링크를 통한 구매로 레시피 스카우트 운영자가 수수료를 받을 수 있습니다. 최종 가격과 배송비는 판매처에서 확인하세요.'),
                                  Text(offer.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall),
                                  if (offer.specification.isNotEmpty)
                                    Text(offer.specification),
                                  if (offer.isSuggestedMatch)
                                    const LocalizedText(
                                        '유사 상품입니다. 재료의 종류·부위와 판매 규격을 확인한 뒤 구매해 주세요.'),
                                  OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                          minimumSize: const Size(0, 36),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          visualDensity: VisualDensity.compact),
                                      onPressed: () async {
                                        if (account == null ||
                                            ref.read(activeAccountIdProvider) !=
                                                account) {
                                          return;
                                        }
                                        try {
                                          final opened = await ref.read(
                                                  shoppingLinkLauncherProvider)(
                                              offer.uri!);
                                          if (opened) return;
                                        } catch (_) {
                                          /* Show the same recoverable message. */
                                        }
                                        if (context.mounted &&
                                            ref.read(activeAccountIdProvider) ==
                                                account) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(SnackBar(
                                                  content: Text(context.tr(
                                                      '주소를 열지 못했습니다. 다시 시도해 주세요.'))));
                                        }
                                      },
                                      icon: const Icon(Icons.open_in_new),
                                      label: LocalizedText(
                                          offer.program == 'youtube'
                                              ? '상품 태그 영상 보기'
                                              : offer.program == 'coupang'
                                                  ? '구매'
                                                  : '제휴 상품 열기')),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (showCoupangDisclosure &&
                      visible.any((o) => o.program == 'coupang'))
                    const CoupangDisclosureText(),
                ]);
          },
        );
  }
}

class _AffiliateImage extends StatelessWidget {
  const _AffiliateImage({this.imageUrl});
  final String? imageUrl;

  @override
  Widget build(BuildContext context) => Semantics(
      container: true,
      excludeSemantics: true,
      label: '쿠팡 상품 사진',
      image: true,
      child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
              width: 64,
              height: 64,
              child: imageUrl == null
                  ? const ColoredBox(
                      color: Color(0xfff5f2f4),
                      child: Icon(Icons.shopping_bag_outlined))
                  : Image.network(imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const ColoredBox(
                          color: Color(0xfff5f2f4),
                          child: Icon(Icons.shopping_bag_outlined))))));
}
