import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/application/auth_providers.dart';
import '../data/shopping_affiliate_repository.dart';
import 'shopping_assistant_dialogs.dart';
import '../application/shopping_market_provider.dart';

/// One persistent notice for the displayed product list, outside its scroll area.
class CoupangDisclosureFooter extends ConsumerWidget {
  const CoupangDisclosureFooter(
      {super.key,
      required this.ingredients,
      this.hasSelection = false,
      this.respectShoppingMarket = false});
  final Iterable<String> ingredients;
  final bool hasSelection;
  final bool respectShoppingMarket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (respectShoppingMarket && !ref.watch(shoppingMarketProvider).isKorea) {
      return const SizedBox.shrink();
    }
    if (ref.watch(activeAccountIdProvider) == null) {
      return const SizedBox.shrink();
    }
    var visible = hasSelection;
    for (final ingredient
        in ingredients.where((s) => s.trim().isNotEmpty).toSet()) {
      final rows = ref.watch(shoppingAffiliatesProvider(ingredient));
      visible = visible ||
          (rows.valueOrNull
                  ?.any((o) => o.program == 'coupang' && o.uri != null) ??
              false);
    }
    return visible ? const CoupangDisclosureText() : const SizedBox.shrink();
  }
}

class CoupangDisclosureText extends StatelessWidget {
  const CoupangDisclosureText({super.key});
  @override
  Widget build(BuildContext context) => Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
          top: false,
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Center(
                  heightFactor: 1,
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 980),
                      child: Text(
                          shopText(
                              context,
                              '이 링크는 쿠팡 파트너스 활동의 일환으로, 이에 따른 일정액의 수수료를 제공받습니다.',
                              'We may receive a commission through these Coupang Partners links.'),
                          style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: Theme.of(context).colorScheme.onSurface),
                          textAlign: TextAlign.center))))));
}

class CoupangDisclosureLayout extends StatelessWidget {
  const CoupangDisclosureLayout(
      {super.key,
      required this.child,
      required this.ingredients,
      this.hasSelection = false,
      this.respectShoppingMarket = false});
  final Widget child;
  final Iterable<String> ingredients;
  final bool hasSelection;
  final bool respectShoppingMarket;
  @override
  Widget build(BuildContext context) => Column(children: [
        Expanded(child: child),
        CoupangDisclosureFooter(
            respectShoppingMarket: respectShoppingMarket,
            ingredients: ingredients,
            hasSelection: hasSelection),
      ]);
}
