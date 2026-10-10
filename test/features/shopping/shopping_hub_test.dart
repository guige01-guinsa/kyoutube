import 'package:k_youtube/features/shopping/presentation/shopping_store_search_dialog.dart';
import 'package:k_youtube/features/shopping/data/shopping_affiliate_repository.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:k_youtube/core/theme/app_theme.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/business/data/business_repository.dart';
import 'package:k_youtube/features/kitchen/application/kitchen_providers.dart';
import 'package:k_youtube/features/shopping/data/shopping_preparation_store.dart';
import 'package:k_youtube/features/shopping/data/shopping_assistant_repository.dart';
import 'package:k_youtube/features/shopping/domain/shopping_navigation.dart';
import 'package:k_youtube/features/shopping/presentation/shopping_hub_page.dart';
import 'package:k_youtube/features/shopping/presentation/shopping_assistant_dialogs.dart';
import 'package:k_youtube/features/workspace/application/workspace_profile_controller.dart';
import 'package:k_youtube/features/workspace/application/workspace_navigation.dart';
import 'package:k_youtube/features/workspace/domain/workspace_profile.dart';
import 'package:k_youtube/features/workspace/presentation/workspace_frame.dart';
import 'package:k_youtube/features/workspace/presentation/workspace_menu.dart';
import 'shopping_assistant_test.dart' show shoppingItem, shoppingList;
import 'shopping_preparation_widget_test.dart'
    show MemoryPreparationStore, tapText;
import '../workspace/workspace_roles_test.dart'
    show MemoryWorkspaceRepository, choice;

Future<GoRouter> pumpHub(WidgetTester tester, MemoryPreparationStore store,
    {double width = 390,
    double scale = 1,
    String language = 'ko',
    String initial = '/shopping',
    WorkspaceNavigation? navigation,
    GlobalKey? capture}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
      initialLocation: initial,
      redirect: (_, s) => legacyShoppingRedirect(s.uri),
      routes: [
        ShellRoute(
            builder: (_, s, child) =>
                WorkspaceFrame(location: s.uri.toString(), child: child),
            routes: [
              GoRoute(
                  path: '/shopping',
                  builder: (_, s) => ShoppingHubPage(
                      stage: shoppingStage(s.uri.queryParameters['stage']),
                      listId: s.uri.queryParameters['list'],
                      view: s.uri.queryParameters['view'],
                      requestId: s.uri.queryParameters['request'])),
              GoRoute(
                  path: '/shopping-assistant',
                  builder: (_, __) => const SizedBox()),
              GoRoute(
                  path: '/shopping-preparation',
                  builder: (_, __) => const SizedBox()),
              GoRoute(
                  path: '/',
                  builder: (_, __) => const Scaffold(body: Text('HOME'))),
              GoRoute(
                  path: '/business-workspaces/:id',
                  builder: (_, __) => const Scaffold()),
            ])
      ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        activeAccountIdProvider.overrideWithValue('a'),
        authUserProvider.overrideWith((ref) => Stream.value(const User(
            id: 'a',
            appMetadata: {},
            userMetadata: {},
            aud: 'authenticated',
            createdAt: '2026-09-29'))),
        workspaceProfileRepositoryProvider.overrideWithValue(
            MemoryWorkspaceRepository(choice(WorkspaceMode.professional))),
        businessWorkspacesProvider.overrideWith((ref) async => []),
        shoppingPreparationStoreProvider.overrideWithValue(store),
        kitchenShoppingListsProvider.overrideWith((ref) async => [
              shoppingList(shoppingItem('a', 1, 'kg', name: '당근')),
              shoppingList(shoppingItem('b', 500, 'g', name: '당근')),
            ]),
        kitchenIngredientsProvider.overrideWith((ref) async => []),
        kitchenCompletedShoppingListsProvider.overrideWith((ref) async => []),
        shoppingRecordsProvider.overrideWith((ref, list) async => []),
        shoppingFavoritesProvider.overrideWith((ref) async => []),
        shoppingAffiliatesProvider.overrideWith((ref, ingredient) async => []),
        if (navigation != null)
          workspaceNavigationProvider.overrideWithValue(navigation),
      ],
      child: MaterialApp.router(
          routerConfig: router,
          locale: Locale(language),
          theme: AppTheme.light.copyWith(
              textTheme:
                  AppTheme.light.textTheme.apply(fontFamily: 'HubPreview'),
              appBarTheme: AppTheme.light.appBarTheme.copyWith(
                  titleTextStyle: AppTheme.light.textTheme.titleLarge
                      ?.copyWith(fontFamily: 'HubPreview')),
              chipTheme: AppTheme.light.chipTheme.copyWith(
                  labelStyle: AppTheme.light.textTheme.labelMedium
                      ?.copyWith(fontFamily: 'HubPreview')),
              filledButtonTheme: FilledButtonThemeData(
                  style: AppTheme.light.filledButtonTheme.style?.copyWith(
                      textStyle: WidgetStatePropertyAll(AppTheme.light.textTheme.labelLarge
                          ?.copyWith(fontFamily: 'HubPreview')))),
              navigationBarTheme: AppTheme.light.navigationBarTheme.copyWith(
                  labelTextStyle:
                      WidgetStatePropertyAll(AppTheme.light.textTheme.labelMedium?.copyWith(fontFamily: 'HubPreview')))),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate
          ],
          builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: RepaintBoundary(key: capture, child: child!)))));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  setUpAll(() async {
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    await (FontLoader('HubPreview')
          ..addFont(rootBundle.load('assets/fonts/NanumGothic-Regular.ttf')))
        .load();
  });
  test(
      'all personal purposes share the same four destinations and related section',
      () {
    for (final mode in [WorkspaceMode.personal, WorkspaceMode.professional]) {
      for (final compact in [true, false]) {
        expect(primaryWorkspaceLinks(mode, compact: compact).map((l) => l.path),
            ['/', '/my-recipes', '/shopping', '/workspace-menu']);
      }
      expect(
          workspaceDestinationIndex(Uri.parse('/shopping?stage=active'), mode),
          2);
      expect(
          workspaceDestinationIndex(Uri.parse('/shopping-preparation'), mode),
          2);
      expect(workspaceDestinationIndex(Uri.parse('/chef/recipe'), mode), 1);
      expect(workspaceDestinationIndex(Uri.parse('/chef-sales'), mode), 3);
    }
  });
  test(
      'legacy links preserve list and request identifiers without redirect loops',
      () {
    final old = Uri(path: '/supplier-requests', queryParameters: {
      'list': 'a & b',
      'request': 'r/1',
      'stage': 'active'
    });
    final next = Uri.parse(legacyShoppingRedirect(old)!);
    expect(next.path, '/shopping');
    expect(next.queryParameters, {
      'stage': 'active',
      'view': 'requests',
      'list': 'a & b',
      'request': 'r/1'
    });
    expect(legacyShoppingRedirect(next), isNull);
    expect(
        Uri.parse(legacyShoppingRedirect(Uri.parse('/kitchen?tab=history'))!)
            .queryParameters,
        {'stage': 'records', 'view': 'lists'});
    expect(businessShoppingStage('review'), ShoppingStage.active);
    expect(businessShoppingStage('sent'), ShoppingStage.active);
    expect(businessShoppingStage('received'), ShoppingStage.records);
    expect(businessShoppingStage('cancelled'), ShoppingStage.records);
  });
  testWidgets(
      'confirmation continues in the hub and purchase keeps confirmed quantities',
      (tester) async {
    final store = MemoryPreparationStore();
    final router = await pumpHub(tester, store);
    await tester.tap(find.byTooltip('구매 항목 수정'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, '확인한 보유량'), '500');
    await tester.enterText(
        find.widgetWithText(TextFormField, '구매 예정량'), '1200');
    await tapText(tester, '저장');
    await tapText(tester, '구매 리스트 확정');
    expect(router.routeInformationProvider.value.uri.queryParameters['stage'],
        'active');
    expect(find.byType(NavigationBar), findsOneWidget);
    await tapText(tester, '구매처 찾기');
    expect(find.text('구매 필요량 1200 g'), findsOneWidget);
    expect(
        tester
            .widget<ShoppingStoreSearchDialog>(
                find.byType(ShoppingStoreSearchDialog))
            .group
            .neededQuantity,
        1500);
    await tapText(tester, '닫기');
    await tapText(tester, '수량 확인 · 구매 기록');
    final dialog = tester
        .widget<ShoppingPurchaseDialog>(find.byType(ShoppingPurchaseDialog));
    expect(dialog.confirmedStock, 500);
    expect(dialog.suggestedQuantity, 1200);
    expect(dialog.group.neededQuantity, 1500);
    expect(tester.takeException(), isNull);
  });
  testWidgets('explicit list links cannot restore a different saved selection',
      (tester) async {
    final store = MemoryPreparationStore();
    final router = await pumpHub(tester, store);
    await tapText(tester, '구매 리스트 확정');
    router.go('/shopping-preparation?list=list-b');
    await tester.pumpAndSettle();
    expect(find.text('구매 500 g'), findsOneWidget);
    expect(find.text('구매 1500 g'), findsNothing);
    expect(find.text('구매 리스트 확정됨'), findsNothing);
  });
  testWidgets('stage changes respect in-flight save protection',
      (tester) async {
    final navigation = WorkspaceNavigation()
      ..register('save', () async => false);
    final router =
        await pumpHub(tester, MemoryPreparationStore(), navigation: navigation);
    await tester.tap(find.byKey(const Key('shopping-stage-records')));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.queryParameters['stage'],
        isNull);
    navigation.remove('save');
    await tester.tap(find.byKey(const Key('shopping-stage-records')));
    await tester.pumpAndSettle();
    expect(find.text('아직 구매 기록이 없습니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final scenario in [
    ('ko', 390.0, 1.0),
    ('en', 320.0, 2.0),
    ('ko', 1440.0, 1.0)
  ]) {
    testWidgets(
        'unified shopping fits ${scenario.$1} ${scenario.$2} scale ${scenario.$3}',
        (tester) async {
      final key = GlobalKey();
      await pumpHub(tester, MemoryPreparationStore(),
          width: scenario.$2,
          scale: scenario.$3,
          language: scenario.$1,
          capture: key);
      expect(tester.takeException(), isNull);
      if (scenario.$2 < 1100) {
        final navRect = tester.getRect(find.byType(NavigationBar));
        for (final label in find
            .descendant(
                of: find.byType(NavigationBar), matching: find.byType(Text))
            .evaluate()) {
          expect(tester.getRect(find.byWidget(label.widget)).bottom,
              lessThanOrEqualTo(navRect.bottom));
        }
      }
      final directory = Platform.environment['SCOUT_UNIFIED_PREVIEW'];
      if (directory != null) {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(directory).create(recursive: true);
          await File(
                  '$directory/shopping-${scenario.$1}-${scenario.$2.toInt()}.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}
