import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:k_youtube/core/theme/app_theme.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/kitchen/application/kitchen_providers.dart';
import 'package:k_youtube/features/kitchen/data/shopping_persistence.dart';
import 'package:k_youtube/features/recipes/application/recipe_providers.dart';
import 'package:k_youtube/features/shopping/application/shopping_purchase_controller.dart';
import 'package:k_youtube/features/shopping/data/shopping_assistant_repository.dart';
import 'package:k_youtube/features/shopping/domain/shopping_assistant.dart';
import 'package:k_youtube/features/shopping/presentation/shopping_assistant_page.dart';
import 'shopping_assistant_test.dart' show shoppingItem, shoppingList;
import 'shopping_purchase_controller_test.dart' show MemoryShoppingStore;

User _user(String id) => User(
    id: id,
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-09-13');

class _Repo extends ShoppingAssistantRepository {
  final saved = <Map<String, dynamic>>[];
  final favoritesList = <ShoppingFavorite>[];
  @override
  Future<List<ShoppingFavorite>> favorites() async => favoritesList;
  @override
  Future<void> saveFavorite(ShoppingFavorite favorite) async {
    favoritesList.add(favorite);
  }

  @override
  Future<void> removeFavorite(String id) async {
    favoritesList.removeWhere((f) => f.id == id);
  }

  @override
  Future<List<ShoppingPurchaseRecord>> records(
          {String? ingredientName}) async =>
      [];
  @override
  Future<String> record(String key, Map<String, dynamic> payload) async {
    saved.add(payload);
    return 'receipt';
  }

  @override
  Future<void> correctAmount(
      String id, double? amount, String currency) async {}
}

class _SwitchingRepo extends _Repo {
  bool switched = false;
  final next = Completer<List<ShoppingFavorite>>();
  @override
  Future<List<ShoppingFavorite>> favorites() =>
      switched ? next.future : super.favorites();
}

ThemeData _previewTheme() {
  final base = AppTheme.light;
  const family = 'ShoppingPreview';
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: family),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: family),
    appBarTheme: base.appBarTheme.copyWith(
        titleTextStyle:
            base.appBarTheme.titleTextStyle?.copyWith(fontFamily: family)),
    chipTheme: base.chipTheme.copyWith(
        labelStyle: base.chipTheme.labelStyle?.copyWith(fontFamily: family)),
    filledButtonTheme: FilledButtonThemeData(
        style: base.filledButtonTheme.style?.copyWith(
            textStyle: WidgetStatePropertyAll(base.textTheme.labelLarge
                ?.copyWith(fontFamily: family, fontWeight: FontWeight.w700)))),
  );
}

Future<void> _pump(WidgetTester tester, _Repo repo, List<Uri> opened,
    {String language = 'ko',
    Stream<User?>? users,
    double width = 360,
    double textScale = 1.15,
    Future<bool> Function(Uri)? launcher}) async {
  if (const bool.fromEnvironment('SHOPPING_SCREENSHOTS')) {
    await tester.runAsync(() async {
      final textFont = FontLoader('ShoppingPreview')
        ..addFont(File('C:/Windows/Fonts/malgun.ttf')
            .readAsBytes()
            .then(ByteData.sublistView));
      final icons = FontLoader('MaterialIcons')
        ..addFont(File(
                '.fvm/flutter_sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
            .readAsBytes()
            .then(ByteData.sublistView));
      await textFont.load();
      await icons.load();
    });
  }
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        authUserProvider.overrideWith((_) => users ?? Stream.value(_user('A'))),
        shoppingAssistantRepositoryProvider.overrideWithValue(repo),
        shoppingLinkLauncherProvider.overrideWithValue((uri) async {
          opened.add(uri);
          return launcher == null ? true : await launcher(uri);
        }),
        kitchenIngredientsProvider.overrideWith((_) async => []),
        kitchenSummaryProvider.overrideWith((_) async => {}),
        kitchenShoppingListsProvider
            .overrideWith((_) async => repo.saved.isNotEmpty
                ? []
                : [
                    shoppingList(shoppingItem('a', 1, 'kg',
                        name: language == 'ko' ? '두부' : 'Tofu')),
                    shoppingList(shoppingItem('b', 500, 'g',
                        name: language == 'ko' ? '두부' : 'Tofu')),
                  ]),
        shoppingPurchaseControllerProvider.overrideWith((ref) async =>
            ShoppingPurchaseController(
                repository: repo,
                keys: CompletionKeyStore(storage: MemoryShoppingStore()),
                currentUser: () => ref.read(activeAccountIdProvider))),
      ],
      child: MaterialApp(
          theme: const bool.fromEnvironment('SHOPPING_SCREENSHOTS')
              ? _previewTheme()
              : AppTheme.light,
          locale: Locale(language),
          supportedLocales: const [Locale('ko'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate
          ],
          builder: (context, child) => RepaintBoundary(
              key: const ValueKey('shopping-shell-preview'),
              child: MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(textScale)),
                  child: child!)),
          home: const RepaintBoundary(
              key: ValueKey('shopping-preview'),
              child: ShoppingAssistantPage()))));
  await tester.pumpAndSettle();
}

Future<void> _show(WidgetTester tester, Finder finder) async {
  // Settle changed search results and keyboard geometry before scrolling.
  await tester.pumpAndSettle();
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 200,
        scrollable: find.byType(Scrollable).last);
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.widgetWithText(TextFormField, label);

void main() {
  if (const bool.fromEnvironment('SHOPPING_SCREENSHOTS')) {
    testWidgets('capture shopping design 390', (tester) async {
      await _pump(tester, _Repo(), [], width: 390, textScale: 1);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('shopping-preview')));
      await tester.runAsync(() async {
        final shot = await boundary.toImage(pixelRatio: 1);
        final bytes = await shot.toByteData(format: ui.ImageByteFormat.png);
        final file = File('.artifacts/design-refresh/shopping-mobile.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        shot.dispose();
      });
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'ingredients and purchase action precede optional management tools',
      (tester) async {
    await _pump(tester, _Repo(), [], textScale: 1);
    expect(find.text('구매할 재료').hitTestable(), findsOneWidget);
    expect(find.text('구매처 찾기').hitTestable(), findsOneWidget);
    expect(find.text('내 구매처 관리'), findsNothing);
    final tools = find.byKey(const PageStorageKey('shopping-management-tools'));
    await _show(tester, tools);
    await tester.tap(find.text('구매 관리 도구'));
    await tester.pumpAndSettle();
    await _show(tester, find.text('내 구매처 관리'));
    expect(find.text('내 구매처 관리'), findsOneWidget);
    await _show(tester, find.text('협력업체에 구매 요청'));
    expect(find.text('협력업체에 구매 요청'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['ko', 'en']) {
    testWidgets(
        '$language store dialog keeps general shopping searches hidden without recording a purchase',
        (tester) async {
      final repo = _Repo();
      final opened = <Uri>[];
      await _pump(tester, repo, opened, language: language);
      final label = language == 'ko' ? '구매처 찾기' : 'Find a store';
      await _show(tester, find.text(label));
      if (const bool.fromEnvironment('SHOPPING_SCREENSHOTS')) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('shopping-preview')));
        await tester.runAsync(() async {
          final shot = await boundary.toImage(pixelRatio: 2);
          final bytes = await shot.toByteData(format: ui.ImageByteFormat.png);
          await File('.artifacts/shopping-assistant-$language.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          shot.dispose();
        });
      }
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      if (const bool.fromEnvironment('SHOPPING_SCREENSHOTS')) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('shopping-shell-preview')));
        await tester.runAsync(() async {
          final shot = await boundary.toImage(pixelRatio: 2);
          final bytes = await shot.toByteData(format: ui.ImageByteFormat.png);
          await File('.artifacts/shopping-search-$language.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          shot.dispose();
        });
      }
      for (final store in ['naver', 'coupang', 'web']) {
        expect(find.byKey(ValueKey('open-store-$store')), findsNothing);
      }
      expect(find.text(language == 'ko' ? '검색어 복사' : 'Copy search terms'),
          findsOneWidget);
      expect(opened, isEmpty);
      expect(repo.saved, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
  for (final language in ['ko', 'en']) {
    testWidgets('$language search and tabs fit 320px at 200 percent text',
        (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      final repo = _Repo();
      final opened = <Uri>[];
      await _pump(tester, repo, opened,
          language: language, width: 320, textScale: 2);
      for (final label in language == 'ko'
          ? ['구매 기록', '저장 상품', '구매 준비']
          : ['Records', 'Favorites', 'Prepare']) {
        await tester.tap(find.widgetWithText(ChoiceChip, label));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      final findStore = find.text(language == 'ko' ? '구매처 찾기' : 'Find a store');
      await _show(tester, findStore);
      await tester.tap(findStore);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final query = find.byKey(const ValueKey('store-search-query'));
      await _show(tester, query);
      await tester.enterText(
          query, language == 'ko' ? '춘장' : 'black bean paste');
      final spec = find.byKey(const ValueKey('store-search-specification'));
      await _show(tester, spec);
      await tester.enterText(spec, '500g');
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      final open = find.text(language == 'ko' ? '검색어 복사' : 'Copy search terms');
      await _show(tester, open);
      if (const bool.fromEnvironment('SHOPPING_SCREENSHOTS')) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('shopping-shell-preview')));
        await tester.runAsync(() async {
          final shot = await boundary.toImage(pixelRatio: 2);
          final bytes = await shot.toByteData(format: ui.ImageByteFormat.png);
          await File('.artifacts/shopping-search-large-$language.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          shot.dispose();
        });
      }
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(copied, language == 'ko' ? '춘장 500g' : 'black bean paste 500g');
      expect(opened, isEmpty);
      expect(
          find.textContaining(
              language == 'ko' ? '검색어를 복사했습니다.' : 'Search terms copied.'),
          findsOneWidget);
      expect(repo.saved, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('search rejects empty terms and cancel does not open or record',
      (tester) async {
    final repo = _Repo();
    final opened = <Uri>[];
    await _pump(tester, repo, opened);
    await _show(tester, find.text('구매처 찾기'));
    await tester.tap(find.text('구매처 찾기'));
    await tester.pumpAndSettle();
    final query = find.byKey(const ValueKey('store-search-query'));
    await tester.enterText(query, '   ');
    tester.testTextInput.hide();
    await _show(tester, find.text('검색어 복사'));
    await tester.tap(find.text('검색어 복사'));
    await tester.pumpAndSettle();
    expect(find.text('검색할 재료나 상품명을 입력해 주세요.'), findsOneWidget);
    expect(opened, isEmpty);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    expect(repo.saved, isEmpty);
  });

  testWidgets(
      'copy uses entered product and package terms without opening a store',
      (tester) async {
    final repo = _Repo();
    final opened = <Uri>[];
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await _pump(tester, repo, opened);
    await _show(tester, find.text('구매처 찾기'));
    await tester.tap(find.text('구매처 찾기'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('store-search-query')), '  국산 두부  ');
    await tester.enterText(
        find.byKey(const ValueKey('store-search-specification')), '500g');
    tester.testTextInput.hide();
    await _show(tester, find.text('검색어 복사'));
    await tester.tap(find.text('검색어 복사'));
    await tester.pumpAndSettle();
    expect(copied, '국산 두부 500g');
    expect(opened, isEmpty);
    expect(repo.saved, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account change dismisses private product search',
      (tester) async {
    final users = StreamController<User?>();
    addTearDown(users.close);
    final repo = _Repo();
    final opened = <Uri>[];
    final pending = _pump(tester, repo, opened, users: users.stream);
    users.add(_user('A'));
    await pending;
    await _show(tester, find.text('구매처 찾기'));
    await tester.tap(find.text('구매처 찾기'));
    await tester.pumpAndSettle();
    users.add(_user('B'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(opened, isEmpty);
    expect(repo.saved, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'user confirms stock and pack amount before recording one purchase',
      (tester) async {
    final repo = _Repo();
    await _pump(tester, repo, []);
    await _show(tester, find.widgetWithText(OutlinedButton, '구매 기록'));
    await tester.tap(find.widgetWithText(OutlinedButton, '구매 기록'));
    await tester.pumpAndSettle();
    expect(repo.saved, isEmpty);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '확인 후 기록'))
            .onPressed,
        isNull);
    await _show(tester, _field('이번 장보기에 사용할 보유량'));
    await tester.enterText(_field('이번 장보기에 사용할 보유량'), '300');
    await tester.enterText(_field('한 포장에 든 수량 (선택)'), '500');
    await tester.pumpAndSettle();
    expect(find.text('추가 필요 1200 g · 3포장'), findsOneWidget);
    await _show(tester, _field('실제 구매 수량'));
    expect(tester.widget<TextFormField>(_field('실제 구매 수량')).controller!.text,
        '1500');
    await _show(tester, _field('이 재료의 실제 결제 금액 (선택)'));
    await tester.enterText(_field('이 재료의 실제 결제 금액 (선택)'), '9000');
    tester.testTextInput.hide();
    await _show(tester, find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인 후 기록'));
    await tester.pumpAndSettle();
    expect(repo.saved, hasLength(1));
    expect(repo.saved.single['quantity'], 1500);
    expect(repo.saved.single['paid_amount'], 9000);
    expect((repo.saved.single['items'] as List).map((e) => e['quantity']),
        [875, 625]);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'cancel leaves status unchanged and unsafe favorite link is rejected',
      (tester) async {
    final repo = _Repo();
    await _pump(tester, repo, []);
    await _show(tester, find.widgetWithText(OutlinedButton, '구매 기록'));
    await tester.tap(find.widgetWithText(OutlinedButton, '구매 기록'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    expect(repo.saved, isEmpty);
    await _show(tester, find.byTooltip('자주 사는 상품 저장'));
    await tester.tap(find.byTooltip('자주 사는 상품 저장'));
    await tester.pumpAndSettle();
    await _show(tester, _field('상품 또는 구매처 링크'));
    await tester.enterText(_field('상품 또는 구매처 링크'), 'javascript:alert(1)');
    tester.testTextInput.hide();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(repo.favoritesList, isEmpty);
    expect(find.text('https://로 시작하는 공개 구매처 링크를 입력해 주세요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('shortfall requires an explicit second confirmation',
      (tester) async {
    final repo = _Repo();
    await _pump(tester, repo, []);
    await _show(tester, find.widgetWithText(OutlinedButton, '구매 기록'));
    await tester.tap(find.widgetWithText(OutlinedButton, '구매 기록'));
    await tester.pumpAndSettle();
    await _show(tester, _field('실제 구매 수량'));
    await tester.enterText(_field('실제 구매 수량'), '500');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await _show(tester, find.text('수량과 단위를 확인했습니다.'));
    await tester.tap(find.text('수량과 단위를 확인했습니다.'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '확인 후 기록'))
            .onPressed,
        isNull);
    expect(repo.saved, isEmpty);
    await _show(tester, find.text('부족한 수량은 이번 목록에서 제외합니다.'));
    await tester.tap(find.text('부족한 수량은 이번 목록에서 제외합니다.'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '확인 후 기록'))
            .onPressed,
        isNotNull);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    expect(repo.saved, isEmpty);
  });
  testWidgets(
      'previous account favorites stay hidden if the next account load fails',
      (tester) async {
    final users = StreamController<User?>();
    addTearDown(users.close);
    final repo = _SwitchingRepo();
    repo.favoritesList.add(const ShoppingFavorite(
        id: 'a',
        ingredientName: '두부',
        unit: 'g',
        productName: 'Account A private product',
        url: 'https://shop.example.com/a'));
    final pending = _pump(tester, repo, [], users: users.stream);
    users.add(_user('A'));
    await pending;
    await _show(tester, find.textContaining('Account A private product'));
    expect(find.textContaining('Account A private product'), findsOneWidget);
    repo.switched = true;
    users.add(_user('B'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Account A private product'), findsNothing);
    repo.next.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Account A private product'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('account change dismisses a private product editor',
      (tester) async {
    final users = StreamController<User?>();
    addTearDown(users.close);
    final repo = _Repo();
    final pending = _pump(tester, repo, [], users: users.stream);
    users.add(_user('A'));
    await pending;
    await _show(tester, find.byTooltip('자주 사는 상품 저장'));
    await tester.tap(find.byTooltip('자주 사는 상품 저장'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    users.add(_user('B'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(repo.favoritesList, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
