import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/shopping/data/shopping_affiliate_repository.dart';
import 'package:k_youtube/features/shopping/presentation/coupang_disclosure.dart';
import 'package:k_youtube/features/shopping/presentation/coupang_purchase_planner.dart';
import 'coupang_purchase_plan_test.dart' show PlannerOffers;

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
        'one fixed disclosure for several products at text scale $scale',
        (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
          overrides: [
            activeAccountIdProvider.overrideWithValue('user'),
            shoppingAffiliateRepositoryProvider
                .overrideWithValue(PlannerOffers()),
          ],
          child: MaterialApp(
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: Scaffold(
                  body: CoupangDisclosureLayout(
                      ingredients: const ['소면', '국수'],
                      child: ListView(children: [
                        for (final name in ['소면', '국수'])
                          CoupangPurchasePlanner(
                              ingredient: name,
                              unit: 'g',
                              needed: 1200,
                              value: null,
                              onChanged: (_) {}),
                        const SizedBox(height: 700),
                      ]))))));
      await tester.pumpAndSettle();
      expect(find.byType(CoupangDisclosureText), findsOneWidget);
      expect(find.text('Coupang partner product'), findsNothing);
      const text =
          'We may receive a commission through these Coupang Partners links.';
      expect(find.text(text), findsOneWidget);
      final position = tester.getRect(find.byType(CoupangDisclosureText));
      expect(tester.widget<Text>(find.text(text)).style!.fontSize, 12);
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(CoupangDisclosureText)), position);
      expect(position.bottom, lessThanOrEqualTo(740));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('no disclosure for a list without Coupang products',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [
          activeAccountIdProvider.overrideWithValue('user'),
          shoppingAffiliateRepositoryProvider
              .overrideWithValue(PlannerOffers()..rows = []),
        ],
        child: const MaterialApp(
            home:
                Scaffold(body: CoupangDisclosureFooter(ingredients: ['소면'])))));
    await tester.pumpAndSettle();
    expect(find.byType(CoupangDisclosureText), findsNothing);
  });
}
