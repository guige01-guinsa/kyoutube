import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/core/theme/app_theme.dart';
import 'package:k_youtube/features/kitchen/data/shopping_persistence.dart';
import 'package:k_youtube/features/kitchen/domain/kitchen_models.dart';
import 'package:k_youtube/features/shopping/data/manual_shopping_repository.dart';
import 'package:k_youtube/features/shopping/data/shopping_affiliate_repository.dart';
import 'package:k_youtube/features/shopping/data/shopping_assistant_repository.dart';
import 'package:k_youtube/features/shopping/domain/manual_shopping.dart';
import 'package:k_youtube/features/shopping/domain/shopping_assistant.dart';
import 'package:k_youtube/features/shopping/domain/shopping_preparation.dart';
import 'package:k_youtube/features/shopping/presentation/manual_shopping_dialog.dart';
import 'shopping_purchase_controller_test.dart' show MemoryShoppingStore;
import 'shopping_assistant_test.dart' show shoppingList, shoppingItem;
import 'shopping_preparation_widget_test.dart' as prep;

class ManualRepository extends ManualShoppingRepository {
  final keys = <String>[];
  final payloads = <List<ManualShoppingItem>>[];
  bool fail = false;
  Completer<void>? barrier;
  @override
  Future<String> create(String key, List<ManualShoppingItem> items) async {
    keys.add(key);
    payloads.add(items);
    await barrier?.future;
    if (fail) throw TimeoutException('uncertain');
    return 'new-list';
  }
}

KitchenShoppingItem specified(String id, String spec, {String unit = 'g'}) =>
    KitchenShoppingItem(
        id: id,
        listId: 'manual',
        name: '진간장',
        ingredientText: '진간장 500 $unit $spec',
        purchaseSpecification: spec,
        quantity: 500,
        unit: unit,
        status: KitchenShoppingItemStatus.pending,
        reviewStatus: KitchenShoppingItemReviewStatus.confirmed,
        needsReview: false,
        isChecked: false,
        revision: 0,
        updatedAt: DateTime(2026, 9, 30));

void main() {
  setUpAll(() async {
    await (FontLoader('ManualPreview')
          ..addFont(rootBundle.load('assets/fonts/NanumGothic-Regular.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  const item = ManualShoppingItem(
      name: '진간장', quantity: 2, unit: 'bottle', specification: '1L');
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('input rejects cooking units, bad precision and invalid amounts', () {
    expect(item.valid, isTrue);
    for (final value in [
      0.0,
      -1.0,
      double.nan,
      double.infinity,
      0.0000001,
      1e10
    ]) {
      expect(ManualShoppingItem(name: 'a', quantity: value, unit: 'g').valid,
          isFalse);
    }
    expect(const ManualShoppingItem(name: 'a', quantity: 1, unit: 'cup').valid,
        isFalse);
    expect(ManualShoppingItem.fromJson(item.toJson()).toJson(), item.toJson());
  });
  test(
      'same identity retries across restart, and acknowledgement permits an intentional next list',
      () async {
    final store = MemoryShoppingStore(), repo = ManualRepository()..fail = true;
    ManualShoppingController make() => ManualShoppingController(
        repository: repo,
        keys: CompletionKeyStore(storage: store),
        currentUser: () => 'a');
    await expectLater(
        make().create('a', [item]), throwsA(isA<TimeoutException>()));
    repo.fail = false;
    expect(await make().create('a', [item]), 'new-list');
    expect(repo.keys.toSet(), hasLength(1));
    await make().acknowledge('a', [item]);
    await make().create('a', [item]);
    expect(repo.keys.toSet(), hasLength(2));
  });
  test('double taps coalesce and account changes suppress acknowledgement',
      () async {
    var owner = 'a';
    final repo = ManualRepository()..barrier = Completer<void>();
    final c = ManualShoppingController(
        repository: repo,
        keys: CompletionKeyStore(storage: MemoryShoppingStore()),
        currentUser: () => owner);
    final first = c.create('a', [item]), second = c.create('a', [item]);
    await Future<void>.delayed(Duration.zero);
    expect(repo.keys, hasLength(1));
    owner = 'b';
    final result = expectLater(first, throwsStateError),
        other = expectLater(second, throwsStateError);
    repo.barrier!.complete();
    await result;
    await other;
    expect(() => c.create('a', [item]), throwsStateError);
  });
  test('manual draft writes are ordered and isolated by owner', () async {
    final store = ManualShoppingDraftStore();
    await Future.wait([
      store.write('a', {'name': 'first'}),
      store.write('a', {'name': 'last'}),
      store.write('b', {'name': 'other'})
    ]);
    expect((await store.read('a'))!['name'], 'last');
    expect((await store.read('b'))!['name'], 'other');
    await store.write('a', null);
    expect(await store.read('a'), isNull);
    expect(await store.read('b'), isNotNull);
  });
  test(
      'different specifications and packages remain separate, even with AI approval',
      () {
    final groups = shoppingPurchaseGroups([
      shoppingList(specified('a', 'A')),
      shoppingList(specified('b', 'B')),
      shoppingList(specified('c', 'A'))
    ]);
    expect(groups, hasLength(2));
    expect(groups.map((g) => g.neededQuantity), containsAll([1000, 500]));
    final merged = mergePreparedGroups(groups, {
      for (final g in groups)
        preparationIdentity(g): preparationIdentity(groups.first)
    });
    expect(merged, hasLength(2));
    expect(
        shoppingPurchaseGroups([
          shoppingList(specified('a', 'A', unit: 'bottle')),
          shoppingList(specified('b', 'A', unit: 'bottle'))
        ]),
        hasLength(2));
  });
  test('only additions on same day and stock preserve unchanged checks', () {
    final original = shoppingPurchaseGroups(
        [shoppingList(shoppingItem('a', 1, 'kg', name: '당근'))]);
    final added = shoppingPurchaseGroups([
      shoppingList(shoppingItem('a', 1, 'kg', name: '당근')),
      shoppingList(shoppingItem('b', 500, 'g', name: '당근'))
    ]);
    String fp(List<ShoppingPurchaseGroup> groups,
            {String day = '2026-09-30', List stock = const []}) =>
        jsonEncode([groups.map(preparationIdentity).toList(), stock, day]);
    expect(preparationHasOnlyAdditions(fp(original), fp(added)), isTrue);
    expect(preparationHasOnlyAdditions(fp(added), fp(original)), isFalse);
    expect(
        preparationHasOnlyAdditions(fp(original), fp(added, day: '2026-10-01')),
        isFalse);
    expect(
        preparationHasOnlyAdditions(
            fp(original), fp(added, stock: ['changed'])),
        isFalse);
  });
  testWidgets(
      'confirmed list can reopen and reconfirm without losing reviewed amounts',
      (tester) async {
    final store = prep.MemoryPreparationStore();
    await prep.pump(tester, store);
    await tester.tap(find.byTooltip('구매 항목 수정'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '구매 예정량'), '800');
    await prep.tapText(tester, '저장');
    await prep.tapText(tester, '구매 리스트 확정');
    expect(store.data!['confirmed'], true);
    await prep.tapText(tester, '구매 리스트 확정됨 · 목록 수정');
    expect(store.data!['confirmed'], false);
    expect((store.data!['edits'] as Map).values.single['quantity'], 800);
    expect(find.text('구매처 찾기'), findsNothing);
    await prep.tapText(tester, '구매 리스트 확정');
    expect(store.data!['confirmed'], true);
  });
  Future<void> dialog(WidgetTester tester,
      {ManualRepository? repository,
      String locale = 'ko',
      double width = 390,
      double scale = 1,
      GlobalKey? capture}) async {
    tester.view.physicalSize = Size(width, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = ManualShoppingController(
        repository: repository ?? ManualRepository(),
        keys: CompletionKeyStore(storage: MemoryShoppingStore()),
        currentUser: () => 'a');
    await tester.pumpWidget(ProviderScope(
        overrides: [
          activeAccountIdProvider.overrideWithValue('a'),
          manualShoppingControllerProvider.overrideWith((ref) async => c)
        ],
        child: MaterialApp(
            theme: AppTheme.light.copyWith(
                textTheme:
                    AppTheme.light.textTheme.apply(fontFamily: 'ManualPreview'),
                filledButtonTheme: FilledButtonThemeData(
                    style: AppTheme.light.filledButtonTheme.style?.copyWith(
                        textStyle: const WidgetStatePropertyAll(TextStyle(
                            fontFamily: 'ManualPreview',
                            fontWeight: FontWeight.w600))))),
            locale: Locale(locale),
            supportedLocales: const [Locale('ko'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            builder: (_, child) => MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: RepaintBoundary(key: capture, child: child!)),
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () => showDialog<String>(
                            context: context,
                            builder: (_) =>
                                const ManualShoppingDialog(owner: 'a')),
                        child: const Text('open')))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'manual batch retains exact quantities and locks uncertain submissions for safe retry',
      (tester) async {
    final repo = ManualRepository()..fail = true;
    await dialog(tester, repository: repo);
    await tester.enterText(find.byKey(const ValueKey('manual-name')), '우유');
    await tester.enterText(
        find.byKey(const ValueKey('manual-quantity')), '500');
    await tester.pumpAndSettle();
    await tester.tap(find.text('장보기 목록에 추가'));
    await tester.pumpAndSettle();
    expect(repo.payloads.single.single.quantity, 500);
    expect(
        tester
            .widget<TextField>(find.descendant(
                of: find.byKey(const ValueKey('manual-name')),
                matching: find.byType(TextField)))
            .enabled,
        false);
    repo.fail = false;
    await tester.tap(find.text('저장 결과 다시 확인'));
    await tester.pumpAndSettle();
    expect(repo.keys.toSet(), hasLength(1));
    expect(find.byType(ManualShoppingDialog), findsNothing);
    expect(await ManualShoppingDraftStore().read('a'), isNull);
  });
  for (final language in ['ko', 'en']) {
    testWidgets('manual input fits narrow screens and large $language text',
        (tester) async {
      await dialog(tester, locale: language, width: 320, scale: 2);
      await tester.enterText(find.byKey(const ValueKey('manual-name')), '두부');
      expect(tester.takeException(), isNull);
    });
  }
  for (final width in [390.0, 1440.0]) {
    testWidgets('manual dialog preview at $width', (tester) async {
      final key = GlobalKey();
      await dialog(tester, width: width, capture: key);
      await tester.enterText(find.byKey(const ValueKey('manual-name')), '설탕');
      await tester.enterText(
          find.byKey(const ValueKey('manual-quantity')), '1000');
      await tester.enterText(
          find.byKey(const ValueKey('manual-specification')), '1kg');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final output = Platform.environment['SCOUT_MANUAL_PREVIEW'];
      if (output != null) {
        await tester.runAsync(() async {
          final render =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await render.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File('$output/manual-${width.toInt()}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
  testWidgets(
      'Coupang exploration uses only search terms and never creates a list',
      (tester) async {
    Uri? opened;
    await tester.pumpWidget(ProviderScope(
        overrides: [
          activeAccountIdProvider.overrideWithValue('a'),
          shoppingAffiliatesProvider('우유').overrideWith((ref) async => []),
          shoppingLinkLauncherProvider.overrideWithValue((uri) async {
            opened = uri;
            return true;
          })
        ],
        child: const MaterialApp(
            locale: Locale('ko'),
            supportedLocales: [Locale('ko'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Scaffold(
                body: ManualShoppingProductsDialog(
                    ingredient: '우유', specification: '1L')))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('쿠팡 일반 검색으로 규격 확인'));
    await tester.pumpAndSettle();
    expect(opened!.host, 'www.coupang.com');
    expect(opened!.queryParameters, {'q': '우유 1L'});
  });
}
