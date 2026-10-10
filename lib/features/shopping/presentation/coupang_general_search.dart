import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/application/auth_providers.dart';
import '../data/shopping_assistant_repository.dart';
import '../domain/shopping_assistant.dart';
import 'shopping_assistant_dialogs.dart';

/// Personal shopping only. Business purchases use their approval-aware service.
class CoupangGeneralSearch extends ConsumerWidget {
  const CoupangGeneralSearch(
      {super.key, required this.ingredient, this.enabled = true});
  final String ingredient;
  final bool enabled;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = ref.watch(activeAccountIdProvider);
    String t(String ko, String en) => shopText(context, ko, en);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      OutlinedButton.icon(
          onPressed: !enabled || owner == null || ingredient.trim().isEmpty
              ? null
              : () async {
                  if (ref.read(activeAccountIdProvider) != owner) return;
                  try {
                    if (await ref.read(shoppingLinkLauncherProvider)(
                        shoppingSearchUri(
                            ShoppingSearchStore.coupang, ingredient))) {
                      return;
                    }
                  } catch (_) {
                    /* Allow retry without changing purchase records. */
                  }
                  if (context.mounted &&
                      ref.read(activeAccountIdProvider) == owner) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(t('쿠팡을 열지 못했습니다. 다시 시도해 주세요.',
                            'Could not open Coupang. Retry.'))));
                  }
                },
          icon: const Icon(Icons.open_in_new),
          label: Text(t('쿠팡에서 다른 상품 찾기', 'Find other products on Coupang'))),
      Text(
          t('일반 검색은 제휴 링크가 아닙니다. 판매 규격을 확인하고 돌아와 실제 구매량을 기록하세요.',
              'General search is not an affiliate link. Check the package size and return to record your actual purchase.'),
          style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}
