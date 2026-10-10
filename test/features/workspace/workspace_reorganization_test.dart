import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:k_youtube/core/theme/app_theme.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/business/data/business_repository.dart';
import 'package:k_youtube/features/business/data/business_menu_repository.dart';
import 'package:k_youtube/features/business/domain/business_navigation.dart';
import 'package:k_youtube/features/business/domain/business_workspace.dart';
import 'package:k_youtube/features/business/presentation/business_pages.dart';
import 'package:k_youtube/features/suppliers/data/supplier_catalog_repository.dart';
import 'package:k_youtube/features/suppliers/domain/supplier_catalog.dart';
import 'package:k_youtube/features/suppliers/presentation/supplier_business_page.dart';
import 'package:k_youtube/features/workspace/domain/workspace_profile.dart';
import 'package:k_youtube/features/workspace/presentation/workspace_frame.dart';
import 'package:k_youtube/features/workspace/presentation/workspace_menu.dart';
import '../business/business_flow_test.dart'
    show MemoryBusiness, EmptyBusinessMenu;
import 'workspace_roles_test.dart'
    show MemoryWorkspaceRepository, choice, pumpRole;

final _account = StateProvider<String?>((_) => 'staff');

BusinessContext access(Set<String> permissions,
        {bool paid = true, bool owner = false}) =>
    BusinessContext(
        id: 'shop',
        name: '행복식당 강남점',
        owner: owner,
        paid: paid,
        approval: true,
        permissions: permissions);

Future<GoRouter> pumpShared(WidgetTester tester,
    {required MemoryBusiness repo,
    String locale = 'ko',
    double width = 390,
    double scale = 1,
    GlobalKey? capture,
    String initial = '/business-workspaces/shop',
    List<Override> overrides = const [],
    Future<bool> Function()? exitEditor}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(initialLocation: initial, routes: [
    ShellRoute(
      builder: (_, state, child) =>
          WorkspaceFrame(location: state.uri.toString(), child: child),
      routes: [
        GoRoute(
            path: '/business-workspaces/:workspace',
            builder: (_, state) => BusinessWorkspacePage(
                key: ValueKey(state.uri),
                workspace: state.pathParameters['workspace']!,
                section: businessSection(state.uri.queryParameters['section']),
                initialStatus: state.uri.queryParameters['status'] ?? 'all')),
        GoRoute(
            path: '/business-workspaces/:workspace/new/recipe',
            onExit: (_, __) async => await exitEditor?.call() ?? true,
            builder: (_, __) =>
                const Scaffold(body: TextField(key: Key('protected-draft')))),
        GoRoute(
            path: '/business-workspaces',
            builder: (_, __) => const Scaffold(body: Text('AREA PICKER'))),
      ],
    )
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        activeAccountIdProvider.overrideWith((ref) => ref.watch(_account)),
        businessRepositoryProvider.overrideWithValue(repo),
        businessMenuRepositoryProvider.overrideWithValue(EmptyBusinessMenu()),
        ...overrides,
      ],
      child: MaterialApp.router(
        routerConfig: router,
        locale: Locale(locale),
        theme: AppTheme.light.copyWith(
            textTheme:
                AppTheme.light.textTheme.apply(fontFamily: 'ReorgPreview'),
            appBarTheme: AppTheme.light.appBarTheme.copyWith(
                titleTextStyle: AppTheme.light.appBarTheme.titleTextStyle
                    ?.copyWith(fontFamily: 'ReorgPreview')),
            navigationBarTheme: AppTheme.light.navigationBarTheme.copyWith(
                labelTextStyle: WidgetStatePropertyAll(AppTheme
                    .light.textTheme.labelMedium
                    ?.copyWith(fontFamily: 'ReorgPreview')))),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: RepaintBoundary(key: capture, child: child!)),
      )));
  await tester.pumpAndSettle();
  return router;
}

Future<void> capturePreview(
    WidgetTester tester, GlobalKey key, String name) async {
  final directory = Platform.environment['SCOUT_REORG_PREVIEW'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    await (FontLoader('ReorgPreview')
          ..addFont(rootBundle.load('assets/fonts/NanumGothic-Regular.ttf')))
        .load();
  });
  test('shared navigation uses actual permissions, not preferred duty', () {
    expect(businessSections(access(businessRolePermissions['purchasing']!)), [
      BusinessSection.collection,
      BusinessSection.recipes,
      BusinessSection.purchasing,
      BusinessSection.settings
    ]);
    expect(businessSections(access(businessRolePermissions['management']!)),
        isNot(contains(BusinessSection.management)));
    expect(
        businessSections(
            access(businessPermissions.toSet(), owner: true, paid: false)),
        isNot(contains(BusinessSection.management)));
    expect(businessSectionKinds(BusinessSection.purchasing), ['purchase']);
    expect(businessSection('finance.write'), BusinessSection.home);
    expect(
        businessLocationSection(
            Uri.parse('/business-workspaces/shop/menu-purchase')),
        BusinessSection.purchasing);
  });
  test('personal studio navigation stays stable across duty preferences', () {
    for (final duty in ProfessionalDuty.values) {
      expect(
          primaryWorkspaceLinks(WorkspaceMode.professional,
                  profile: WorkspaceProfile(
                      active: WorkspaceMode.professional,
                      enabled: const {WorkspaceMode.professional},
                      duties: {duty},
                      dutiesConfigured: true))
              .map((l) => l.path),
          ['/', '/my-recipes', '/shopping', '/workspace-menu']);
    }
    expect(
        workspaceDestinationIndex(Uri.parse('/supplier-business?section=terms'),
            WorkspaceMode.supplier),
        2);
    expect(
        workspaceDestinationIndex(
            Uri.parse('/supplier-business?section=products'),
            WorkspaceMode.supplier),
        1);
  });
  testWidgets('one space selector exposes personal and authorized businesses',
      (tester) async {
    await pumpRole(
        tester, MemoryWorkspaceRepository(choice(WorkspaceMode.professional)),
        account: 'staff',
        initial: '/my-recipes',
        overrides: [
          businessWorkspacesProvider.overrideWith((ref) async => [
                {'id': 'shop', 'name': '행복식당 강남점', 'owner_id': 'owner'}
              ]),
        ]);
    expect(find.byKey(const Key('workspace-space-picker')), findsOneWidget);
    await tester.tap(find.byKey(const Key('workspace-space-picker')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(CheckedPopupMenuItem<String>, '개인 공간'),
        findsOneWidget);
    expect(find.widgetWithText(CheckedPopupMenuItem<String>, '행복식당 강남점'),
        findsOneWidget);
    expect(find.text('업소·전문가'), findsNothing);
  });
  for (final locale in ['ko', 'en']) {
    for (final width in [390.0, 1440.0]) {
      testWidgets(
          'shared $locale navigation fits $width and opens only shared purchasing',
          (tester) async {
        final repo = MemoryBusiness(businessRolePermissions['purchasing']!)
          ..business = access(businessRolePermissions['purchasing']!);
        final key = GlobalKey();
        final router = await pumpShared(tester,
            repo: repo, width: width, locale: locale, capture: key);
        expect(find.textContaining('행복식당 강남점'), findsWidgets);
        expect(find.text(locale == 'ko' ? '경영관리' : 'Management'), findsNothing);
        expect(tester.takeException(), isNull);
        await capturePreview(tester, key, 'shared-$locale-${width.toInt()}');
        if (width < 1100) {
          await tester.tap(find.byType(NavigationDestination).at(2));
        } else {
          await tester
              .tap(find.byKey(const ValueKey('business-nav-purchasing')));
        }
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.toString(),
            '/business-workspaces/shop?section=purchasing');
        expect(
            find.byKey(const Key('business-purchase-start')), findsOneWidget);
        expect(find.byKey(const ValueKey('business-kind-cost')), findsNothing);
        expect(repo.financialQueries, 0);
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets('shared $locale large text at 320px retains navigation',
        (tester) async {
      await pumpShared(tester,
          repo: MemoryBusiness(businessPermissions.toSet()),
          locale: locale,
          width: 320,
          scale: 2);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('mobile More keeps authorized management reachable',
      (tester) async {
    final router = await pumpShared(tester,
        repo: MemoryBusiness(businessPermissions.toSet()));
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations.length, 4);
    expect(bar.labelBehavior, NavigationDestinationLabelBehavior.alwaysShow);
    await tester.tap(find.byType(NavigationDestination).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('원가·매출 관리'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.queryParameters['section'],
        'management');
    expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing account immediately removes the old shared context',
      (tester) async {
    await pumpShared(tester,
        repo: MemoryBusiness(businessRolePermissions['purchasing']!),
        overrides: [
          businessContextProvider('shop').overrideWith((ref) async {
            if (ref.watch(activeAccountIdProvider) != 'staff') {
              throw StateError('BUSINESS_DENIED');
            }
            return access(businessRolePermissions['purchasing']!);
          }),
        ]);
    final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('business-data-owner'))));
    container.read(_account.notifier).state = 'another-account';
    await tester.pumpAndSettle();
    expect(find.textContaining('행복식당 강남점'), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('업소 접근 권한과 연결 상태를 확인해 주세요.'), findsOneWidget);
  });
  testWidgets('business navigation respects an editor exit guard',
      (tester) async {
    var allow = false;
    final router = await pumpShared(tester,
        repo: MemoryBusiness(businessRolePermissions['culinary']!),
        initial: '/business-workspaces/shop/new/recipe',
        exitEditor: () async => allow);
    await tester.enterText(
        find.byKey(const Key('protected-draft')), '아직 저장하지 않은 배합');
    await tester.tap(find.byType(NavigationDestination).first);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path,
        endsWith('/new/recipe'));
    expect(find.text('아직 저장하지 않은 배합'), findsOneWidget);
    allow = true;
    await tester.tap(find.byType(NavigationDestination).first);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path,
        '/business-workspaces/shop');
  });
  testWidgets('permission refresh preserves a draft until access is revoked',
      (tester) async {
    Completer<BusinessContext>? pending;
    await pumpShared(tester,
        repo: MemoryBusiness(businessRolePermissions['culinary']!),
        initial: '/business-workspaces/shop/new/recipe',
        overrides: [
          businessContextProvider('shop').overrideWith((ref) async =>
              pending == null
                  ? access(businessRolePermissions['culinary']!)
                  : await pending.future),
        ]);
    await tester.enterText(find.byKey(const Key('protected-draft')), '버전 2 연구');
    final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('protected-draft'))));
    pending = Completer<BusinessContext>();
    container.invalidate(businessContextProvider('shop'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('버전 2 연구'), findsOneWidget);
    pending.completeError(StateError('BUSINESS_DENIED'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('protected-draft')), findsNothing);
    expect(find.text('업소 접근 권한과 연결 상태를 확인해 주세요.'), findsOneWidget);
  });
  testWidgets(
      'supplier trade terms show delivery conditions without fetching products',
      (tester) async {
    var productReads = 0;
    await tester.pumpWidget(ProviderScope(overrides: [
      activeAccountIdProvider.overrideWithValue('supplier'),
      mySupplierBusinessProvider.overrideWith((ref) async =>
          const CatalogSupplier(
              id: 'supplier',
              name: '행복농산',
              deliveryRegions: ['서울'],
              shippingFee: 3000,
              minimumOrder: 50000,
              freeShippingFrom: 100000)),
      myCatalogProductsProvider('supplier').overrideWith((ref) async {
        productReads++;
        return [];
      }),
    ], child: const MaterialApp(home: SupplierBusinessPage(section: 'terms'))));
    await tester.pumpAndSettle();
    expect(find.textContaining('50000'), findsOneWidget);
    expect(find.textContaining('3000'), findsOneWidget);
    expect(find.textContaining('100000'), findsOneWidget);
    expect(find.text('취급 상품 추가'), findsNothing);
    expect(productReads, 0);
    expect(tester.takeException(), isNull);
  });
}
