import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/core/search/product_search.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/shopping/data/shopping_affiliate_repository.dart';
import 'package:k_youtube/features/shopping/presentation/purchase_name_field.dart';

final owner = StateProvider<String?>((ref) => 'one');

void main() {
  testWidgets('suggestions stay usable on a narrow display with enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          activeAccountIdProvider.overrideWithValue('one'),
          purchaseNamesProvider.overrideWith((ref, q) async =>
              [const PurchaseNameSuggestion('돼지고기 앞다리살', '공급업체 · 500g 판매 규격')]),
        ],
        child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!),
            home: Scaffold(
                body: ListView(children: [
              PurchaseNameField(
                  decoration: const InputDecoration(labelText: 'Purchase item'),
                  onChanged: (_) {})
            ])))));
    await tester.enterText(find.byType(TextFormField), '돼지');
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('돼지고기 앞다리살'));
    await tester.tap(find.text('돼지고기 앞다리살'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('partial, whitespace and all-word searches do not merge names', () {
    for (final q in ['돼지', '앞다리살', '돼지고기앞다리살', '앞다리 돼지']) {
      expect(productSearchMatches('돼지고기 앞다리살', q), isTrue);
    }
    expect(productSearchMatches('돼지고기 앞다리살', '앞다리 소고기'), isFalse);
    expect(productSearchMatches('Premium Soy Sauce', 'SAUCE premium'), isTrue);
    expect(productSearchMatches('돼지고기', '%'), isFalse);
  });

  testWidgets(
      'debounce, page and explicitly select a name without changing other fields',
      (tester) async {
    final queries = <({String query, int offset, String? workspace})>[];
    final values = <String>[];
    final name = TextEditingController();
    final amount = TextEditingController(text: '300');
    addTearDown(name.dispose);
    addTearDown(amount.dispose);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          activeAccountIdProvider.overrideWithValue('one'),
          purchaseNamesProvider.overrideWith((ref, q) async {
            queries.add(q);
            return [
              for (var i = q.offset; i < 8 && i < q.offset + 6; i++)
                PurchaseNameSuggestion('돼지고기 앞다리살 $i', '500g 상품 $i')
            ];
          }),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: ListView(children: [
          PurchaseNameField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name'),
              onChanged: values.add),
          TextField(controller: amount),
        ])))));
    await tester.enterText(find.byType(TextFormField), '돼');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextFormField), '돼지');
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pumpAndSettle();
    expect(queries, [(query: '돼지', offset: 0, workspace: null)]);
    expect(find.byType(ListTile), findsNWidgets(5));
    await tester.tap(find.text('More results'));
    await tester.pumpAndSettle();
    expect(queries.last.offset, 5);
    await tester.tap(find.text('돼지고기 앞다리살 6'));
    await tester.pumpAndSettle();
    expect(name.text, '돼지고기 앞다리살 6');
    expect(values.last, name.text);
    expect(amount.text, '300');
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets(
      'late responses and account changes cannot show or select old names',
      (tester) async {
    final pending = Completer<List<PurchaseNameSuggestion>>();
    await tester.pumpWidget(ProviderScope(
        overrides: [
          activeAccountIdProvider.overrideWith((ref) => ref.watch(owner)),
          purchaseNamesProvider.overrideWith(
              (ref, q) => q.query == '돼지' ? pending.future : Future.value([])),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: PurchaseNameField(
                    decoration: const InputDecoration(labelText: 'Name'),
                    onChanged: (_) {})))));
    await tester.enterText(find.byType(TextFormField), '돼지');
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pump();
    await tester.enterText(find.byType(TextFormField), '양파');
    pending.complete([const PurchaseNameSuggestion('돼지고기 앞다리살', 'old')]);
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pumpAndSettle();
    expect(find.text('돼지고기 앞다리살'), findsNothing);
    await tester.enterText(find.byType(TextFormField), '돼지');
    final container = ProviderScope.containerOf(
        tester.element(find.byType(PurchaseNameField)));
    container.read(owner.notifier).state = 'two';
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('unavailable catalog permits manual input and validation',
      (tester) async {
    final form = GlobalKey<FormState>();
    await tester.pumpWidget(ProviderScope(
        overrides: [
          activeAccountIdProvider.overrideWithValue('one'),
          purchaseNamesProvider
              .overrideWith((ref, q) => Future.error(StateError('offline'))),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: Form(
                    key: form,
                    child: PurchaseNameField(
                        decoration: const InputDecoration(labelText: 'Name'),
                        onChanged: (_) {},
                        validator: (s) =>
                            s!.trim().isEmpty ? 'Required' : null))))));
    await tester.enterText(find.byType(TextFormField), '새로운 재료');
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(form.currentState!.validate(), isTrue);
    expect(tester.takeException(), isNull);
  });
}
