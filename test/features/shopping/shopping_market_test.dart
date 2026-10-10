import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/shopping/application/shopping_market_provider.dart';
import 'package:k_youtube/features/shopping/data/shopping_assistant_repository.dart';
import 'package:k_youtube/features/shopping/presentation/manual_shopping_dialog.dart';
import 'package:k_youtube/features/shopping/presentation/shopping_affiliate_panel.dart';
import 'package:k_youtube/features/shopping/presentation/shopping_market_widgets.dart';
import 'package:k_youtube/features/shopping/domain/shopping_market.dart';
import 'package:k_youtube/features/shopping/presentation/coupang_purchase_planner.dart';
import 'shopping_preparation_widget_test.dart' as preparation;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('shopping handoff contains only terms and explicit country/language',
      () {
    final uri = const ShoppingMarket(country: 'MX', language: 'es')
        .search('aceite & vinagre', specification: 'orgánico');
    expect(uri.scheme, 'https');
    expect(uri.host, 'www.google.com');
    expect(uri.queryParameters, {
      'q': 'aceite & vinagre orgánico',
      'gl': 'mx',
      'hl': 'es',
      'tbm': 'shop',
    });
    expect(
        const ShoppingMarket(country: 'MX')
            .search('tofu', general: true)
            .queryParameters
            .containsKey('tbm'),
        isFalse);
  });

  test(
      'unsupported countries use web search, unknown region has no country hint',
      () {
    expect(
        const ShoppingMarket(country: 'PE', language: 'es')
            .search('tofu')
            .queryParameters,
        {'q': 'tofu', 'gl': 'pe', 'hl': 'es'});
    expect(
        const ShoppingMarket(country: 'OTHER').search('tofu').queryParameters,
        {'q': 'tofu', 'hl': 'en'});
    expect(const ShoppingMarket().isKorea, isTrue);
  });

  test('aliases translate without substituting cuts, brands or quantities', () {
    expect(ingredientSearchName('계란', 'es'), 'huevos');
    expect(ingredientSearchName('TOFU', 'ko'), '두부');
    expect(ingredientSearchName('국간장', 'es'), contains('para sopa'));
    expect(ingredientSearchName('Brand 돼지고기 앞다리살 500g', 'es'),
        'Brand 돼지고기 앞다리살 500g');
  });

  test('saved preferences reload by account independently from UI language',
      () async {
    final first = ShoppingMarketController('a');
    expect(
        await first.save(const ShoppingMarket(country: 'MX', language: 'en')),
        isTrue);
    first.dispose();
    final restored = ShoppingMarketController('a');
    final other = ShoppingMarketController('b');
    await Future<void>.delayed(Duration.zero);
    expect(restored.state.country, 'MX');
    expect(restored.state.language, 'en');
    expect(other.state.isKorea, isTrue);
    restored.dispose();
    other.dispose();
  });

  test('damaged preferences leave a usable default', () async {
    SharedPreferences.setMockInitialValues({'shopping-market-v1:a': '{broken'});
    final controller = ShoppingMarketController('a');
    expect(
        await controller
            .save(const ShoppingMarket(country: 'PE', language: 'es')),
        isTrue);
    expect(controller.state.country, 'PE');
    controller.dispose();
    expect(
        ShoppingMarket.fromJson({'country': 'bad', 'language': 'bad'}).isKorea,
        isTrue);
  });

  Future<ProviderContainer> pumpSearch(WidgetTester tester,
      {String country = 'MX',
      String locale = 'ko',
      double width = 500,
      double scale = 1,
      bool fail = false,
      required List<Uri> opened}) async {
    tester.view.physicalSize = Size(width, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(overrides: [
      activeAccountIdProvider.overrideWithValue('a'),
      shoppingLinkLauncherProvider.overrideWithValue((uri) async {
        opened.add(uri);
        return !fail;
      }),
    ]);
    addTearDown(container.dispose);
    await container
        .read(shoppingMarketProvider.notifier)
        .save(ShoppingMarket(country: country, language: 'es'));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            locale: Locale(locale),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate
            ],
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: const Scaffold(
                body: ManualShoppingProductsDialog(
                    ingredient: '양파', specification: '')))));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
      'overseas direct-add search skips affiliate catalog and preserves edited query',
      (tester) async {
    final opened = <Uri>[];
    final container = await pumpSearch(tester, opened: opened);
    expect(find.byType(ShoppingAffiliatePanel), findsNothing);
    expect(find.text('cebolla'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('overseas-search-query')), 'cebolla blanca');
    await container
        .read(shoppingMarketProvider.notifier)
        .save(const ShoppingMarket(country: 'US', language: 'en'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Google 쇼핑에서 찾기'));
    await tester.pumpAndSettle();
    expect(opened.single.queryParameters['q'], 'cebolla blanca');
    expect(opened.single.queryParameters['gl'], 'us');
    expect(find.byType(ManualShoppingProductsDialog), findsOneWidget);
  });

  testWidgets('failed launch offers web search retry without losing ingredient',
      (tester) async {
    final opened = <Uri>[];
    await pumpSearch(tester, opened: opened, fail: true);
    await tester.tap(find.text('Google 쇼핑에서 찾기'));
    await tester.pumpAndSettle();
    expect(find.text('검색어를 확인한 뒤 다시 시도하거나 복사하여 브라우저에서 검색하세요.'), findsOneWidget);
    await tester.ensureVisible(find.text('결과가 없나요? 일반 검색'));
    await tester.tap(find.text('결과가 없나요? 일반 검색'));
    await tester.pumpAndSettle();
    expect(opened.last.queryParameters.containsKey('tbm'), isFalse);
    expect(find.text('cebolla'), findsOneWidget);
    expect(find.text('검색어 복사'), findsOneWidget);
  });

  testWidgets('Spanish narrow large-text view uses fallback without overflow',
      (tester) async {
    final opened = <Uri>[];
    await pumpSearch(tester,
        opened: opened, country: 'PE', locale: 'es', width: 320, scale: 2);
    expect(find.byType(OverseasIngredientSearch), findsOneWidget);
    expect(find.text('Buscar ingredientes en Google'), findsOneWidget);
    expect(find.text('Encuentra una tienda'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'country dialog saves explicitly and cancel keeps previous setting',
      (tester) async {
    final container = await pumpSearch(tester, opened: []);
    await tester.tap(find.byIcon(Icons.public));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('shopping-country')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('미국').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(container.read(shoppingMarketProvider).country, 'US');
    expect(container.read(shoppingMarketProvider).language, 'es');
    await tester.tap(find.byIcon(Icons.public));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('shopping-country')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('캐나다').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(container.read(shoppingMarketProvider).country, 'US');
  });

  testWidgets(
      'saved overseas choice renders preparation with original required quantities',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'shopping-market-v1:a': '{"country":"MX","language":"es"}',
    });
    final store = preparation.MemoryPreparationStore();
    await preparation.pump(tester, store, name: '당근');
    expect(find.byType(CoupangPurchasePlanner), findsNothing);
    final search = find.byType(OverseasIngredientSearch);
    await tester.scrollUntilVisible(search.first, 200,
        scrollable: find.byType(Scrollable).first);
    expect(search, findsWidgets);
    expect(find.text('zanahoria'), findsWidgets);
    expect(store.data, isNull);
    expect(tester.takeException(), isNull);
  });
}
