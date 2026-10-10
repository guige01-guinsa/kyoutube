import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/kitchen/application/kitchen_providers.dart';
import 'package:k_youtube/features/kitchen/domain/kitchen_models.dart';
import 'package:k_youtube/features/shopping/data/shopping_preparation_store.dart';
import 'package:k_youtube/features/shopping/data/shopping_affiliate_repository.dart';
import 'package:k_youtube/features/shopping/data/shopping_classification_repository.dart';
import 'package:k_youtube/features/shopping/domain/shopping_preparation.dart';
import 'package:k_youtube/features/shopping/presentation/shopping_preparation_page.dart';
import 'package:k_youtube/features/shopping/presentation/shopping_assistant_dialogs.dart';
import 'shopping_assistant_test.dart' show shoppingItem, shoppingList;

class MemoryPreparationStore extends ShoppingPreparationStore {
  Map<String, dynamic>? data;
  bool fail = false;
  @override
  Future<Map<String, dynamic>?> read(String account) async => data;
  @override
  Future<void> write(String account, Map<String, dynamic> value) async {
    if (fail) throw StateError('offline');
    data = value;
  }
}

class FakeClassification extends ShoppingClassificationRepository {
  bool fail = false;
  bool merge = false;
  List<String>? sent;
  @override
  Future<ShoppingClassification> classify(List<String> names) async {
    sent = names;
    if (fail) throw StateError('unavailable');
    return ShoppingClassification(
        [for (final _ in names) ShoppingCategory.produce],
        merge
            ? [
                [1, 0]
              ]
            : []);
  }
}

Future<void> pump(WidgetTester tester, MemoryPreparationStore store,
    {FakeClassification? ai,
    ShoppingAffiliateRepository? catalog,
    String? secondName,
    String name = '당근',
    bool unknown = false,
    String language = 'ko',
    double width = 390,
    double scale = 1}) async {
  tester.view.physicalSize = Size(width, 850);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        authUserProvider.overrideWith((ref) => Stream.value(const User(
            id: 'a',
            appMetadata: {},
            userMetadata: {},
            aud: 'authenticated',
            createdAt: '2026-09-27'))),
        shoppingPreparationStoreProvider.overrideWithValue(store),
        if (catalog != null)
          shoppingAffiliateRepositoryProvider.overrideWithValue(catalog),
        if (ai != null)
          shoppingClassificationRepositoryProvider.overrideWithValue(ai),
        kitchenShoppingListsProvider.overrideWith((ref) async => [
              shoppingList(shoppingItem(
                  'a', unknown ? null : 1, unknown ? null : 'kg',
                  name: name, review: unknown)),
              if (!unknown)
                shoppingList(
                    shoppingItem('b', 500, 'g', name: secondName ?? name)),
            ]),
        kitchenIngredientsProvider.overrideWith((ref) async => [
              const KitchenIngredient(
                  id: 'stock', name: '당근', quantity: 500, unit: 'g')
            ]),
      ],
      child: MaterialApp(
          locale: Locale(language),
          supportedLocales: const [Locale('ko'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate
          ],
          builder: (_, child) => MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: const ShoppingPreparationPage())));
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String text) async {
  final f = find.text(text);
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(f, 200,
        scrollable: find.byType(Scrollable).first);
  }
  await tester.ensureVisible(f.last);
  await tester.pumpAndSettle();
  await tester.tap(f.last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('AI matching requires approval before compatible units merge',
      (tester) async {
    final store = MemoryPreparationStore();
    await pump(tester, store,
        ai: FakeClassification()..merge = true,
        name: '손질 당근',
        secondName: '당근');
    await tapText(tester, 'AI 분류·같은 재료 찾기');
    expect(find.text('구매 1500 g'), findsNothing);
    await tapText(tester, '같은 재료로 확인·합치기');
    expect(find.text('구매 1500 g'), findsOneWidget);
    expect(find.text('확인한 보유량: 0 g'), findsNothing);
    expect(store.data!['confirmed'], isFalse);
    await tapText(tester, '동일 재료 합치기 취소');
    expect(find.text('구매 1500 g'), findsNothing);
  });
  testWidgets('AI changes categories only and still requires confirmation',
      (tester) async {
    final store = MemoryPreparationStore();
    final ai = FakeClassification();
    await pump(tester, store, ai: ai, name: '손질 당근');
    await tapText(tester, 'AI 분류·같은 재료 찾기');
    expect(ai.sent, ['손질 당근']);
    expect(store.data!['confirmed'], isFalse);
    final edit = (store.data!['edits'] as Map).values.single as Map;
    expect(edit['category'], 'produce');
    expect(edit['quantity'], 1500);
    expect(edit['stock'], 0);
    expect(find.text('구매처 찾기'), findsNothing);
  });
  testWidgets('AI failure leaves manual classification usable', (tester) async {
    final ai = FakeClassification()..fail = true;
    await pump(tester, MemoryPreparationStore(), ai: ai, name: '손질 당근');
    await tapText(tester, 'AI 분류·같은 재료 찾기');
    await tester.tap(find.byTooltip('구매 항목 수정'));
    await tester.pumpAndSettle();
    expect(
        find.byType(DropdownButtonFormField<ShoppingCategory>), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'stock is explicit, edited purchase stays separate, and record inherits both',
      (tester) async {
    final store = MemoryPreparationStore();
    await pump(tester, store);
    expect(find.text('확인한 보유량: 0 g'), findsNothing);
    expect(find.text('구매 1500 g'), findsOneWidget);
    await tester.tap(find.byTooltip('구매 항목 수정'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, '확인한 보유량'), '500');
    expect(
        tester
            .widget<TextFormField>(find.widgetWithText(TextFormField, '구매 예정량'))
            .controller!
            .text,
        '1000');
    await tester.enterText(
        find.widgetWithText(TextFormField, '구매 예정량'), '1200');
    await tapText(tester, '저장');
    await tapText(tester, '구매 리스트 확정');
    expect(store.data!['confirmed'], isTrue);
    await tapText(tester, '수량 확인 · 구매 기록');
    final dialog = tester
        .widget<ShoppingPurchaseDialog>(find.byType(ShoppingPurchaseDialog));
    expect(dialog.confirmedStock, 500);
    expect(dialog.suggestedQuantity, 1200);
    expect(dialog.group.neededQuantity, 1500);
    expect(tester.takeException(), isNull);
  });
  testWidgets('unknown quantity blocks confirmation until explicitly excluded',
      (tester) async {
    final store = MemoryPreparationStore();
    await pump(tester, store, unknown: true);
    await tester.ensureVisible(find.text('구매 리스트 확정'));
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, '구매 리스트 확정'))
            .onPressed,
        isNull);
    await tester.tap(find.byTooltip('구매 항목 수정'));
    await tester.pumpAndSettle();
    await tapText(tester, '이번 구매에 포함');
    await tapText(tester, '저장');
    await tapText(tester, '구매 리스트 확정');
    expect(store.data!['confirmed'], isTrue);
    expect(find.text('구매처 찾기'), findsNothing);
  });
  testWidgets('failed save cannot confirm and retry retains edits',
      (tester) async {
    final store = MemoryPreparationStore()..fail = true;
    await pump(tester, store);
    await tapText(tester, '구매 리스트 확정');
    expect(find.text('구매 리스트 확정됨'), findsNothing);
    expect(store.data, isNull);
    store.fail = false;
    await tapText(tester, '구매 리스트 확정');
    expect(store.data!['confirmed'], isTrue);
  });
  testWidgets('changed sources invalidate a previous confirmation',
      (tester) async {
    final store = MemoryPreparationStore();
    await pump(tester, store);
    await tapText(tester, '구매 리스트 확정');
    await tester.pumpWidget(const SizedBox());
    await pump(tester, store, unknown: true);
    expect(find.text('구매 리스트 확정됨'), findsNothing);
    expect(find.text('수량 확인 필요'), findsOneWidget);
  });
  for (final language in ['ko', 'en']) {
    testWidgets('$language layout supports 320px and 200% text',
        (tester) async {
      await pump(tester, MemoryPreparationStore(),
          language: language, width: 320, scale: 2);
      final edit =
          find.byTooltip(language == 'ko' ? '구매 항목 수정' : 'Edit purchase item');
      await tester.scrollUntilVisible(edit, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tapText(tester, language == 'ko' ? '저장' : 'Save');
      await tapText(
          tester, language == 'ko' ? '구매 리스트 확정' : 'Confirm purchase list');
      expect(tester.takeException(), isNull);
    });
  }
}
