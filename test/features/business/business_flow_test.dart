import 'package:k_youtube/features/business/data/business_supplier_repository.dart';
import 'package:k_youtube/features/business/data/business_menu_repository.dart';
import 'package:k_youtube/features/business/domain/business_menu.dart';
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
import 'package:k_youtube/features/business/domain/business_workspace.dart';
import 'package:k_youtube/features/business/domain/business_navigation.dart';
import 'package:k_youtube/features/business/data/business_repository.dart';
import 'package:k_youtube/features/business/presentation/business_pages.dart';
import 'package:k_youtube/features/business/presentation/business_coupang_page.dart';
import 'package:k_youtube/features/workspace/application/workspace_navigation.dart';

class EmptyBusinessMenu implements BusinessMenuRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<Map<String, dynamic>> revisions(String workspace) async => {};
  @override
  Future<List<BusinessMenuItem>> menus(String workspace) async => [];
  @override
  Future<List<Map<String, dynamic>>> reviews(
          String workspace, String recipe) async =>
      [];
  @override
  Future<Map<String, dynamic>?> basis(String workspace, String request) async =>
      null;
}

class MemoryBusiness implements BusinessRepository {
  MemoryBusiness(Set<String> permissions)
      : business = BusinessContext(
            id: 'shop',
            name: '샘플 한끼 식당',
            owner: false,
            paid: true,
            approval: true,
            permissions: permissions);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  BusinessContext business;
  bool conflict = false;
  int writes = 0;
  int financialQueries = 0;
  @override
  Future<Map<String, dynamic>> salesTotals(BusinessSalesQuery q) async {
    financialQueries++;
    return {'quantity': 3, 'revenue': 15000, 'cost': 9000};
  }

  final data = <String, BusinessRecord>{};
  @override
  Future<BusinessContext> context(String id) async => business;
  @override
  Future<List<BusinessRecord>> records(String workspace, String kind,
          {int offset = 0}) async =>
      data.values
          .where(
              (r) => r.kind == kind && business.can(businessPermission(kind)))
          .skip(offset)
          .take(50)
          .toList();
  @override
  Future<BusinessRecord> record(String workspace, String id) async => data[id]!;
  @override
  Future<BusinessRecord> save(BusinessRecord r) async {
    if (conflict) throw const PostgrestException(message: 'BUSINESS_STALE');
    if (!business.can(businessPermission(r.kind, write: true))) {
      throw const PostgrestException(message: 'BUSINESS_DENIED');
    }
    writes++;
    final saved = BusinessRecord(
        id: r.id,
        workspace: r.workspace,
        kind: r.kind,
        title: r.title,
        data: r.data,
        revision: r.revision + 1);
    data[r.id] = saved;
    return saved;
  }

  @override
  Future<BusinessRecord> transition(BusinessRecord r, String status) async {
    writes++;
    final next = BusinessRecord(
        id: r.id,
        workspace: r.workspace,
        kind: r.kind,
        title: r.title,
        data: r.data,
        revision: r.revision + 1,
        status: status);
    data[r.id] = next;
    return next;
  }
}

Future<GoRouter> pumpBusiness(WidgetTester tester, MemoryBusiness repo,
    {String locale = 'ko',
    String initial = '/business-workspaces/shop',
    double width = 390,
    double? textScale,
    GlobalKey? capture,
    List<Override> overrides = const []}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(initialLocation: initial, routes: [
    GoRoute(
        path: '/business-workspaces/:workspace/inventory',
        builder: (_, __) => const BusinessInventoryPage(workspace: 'shop')),
    GoRoute(
        path: '/business-workspaces/:workspace/coupang/:record',
        builder: (_, s) => BusinessCoupangPage(
            workspace: 'shop', recordId: s.pathParameters['record']!)),
    GoRoute(
        path: '/business-workspaces/:workspace/inventory/:item',
        builder: (_, s) => BusinessInventoryPage(
            workspace: 'shop', itemId: s.pathParameters['item'])),
    GoRoute(
        path: '/business-workspaces/:workspace/receiving/:request',
        builder: (_, s) => BusinessReceivingPage(
            workspace: 'shop', request: s.pathParameters['request']!)),
    GoRoute(
        path: '/business-workspaces/:workspace/suppliers',
        builder: (_, __) => const BusinessSuppliersPage(workspace: 'shop')),
    GoRoute(
        path: '/business-workspaces/:workspace/suppliers/:supplier',
        builder: (_, s) => BusinessSupplierProductsPage(
            workspace: 'shop', supplierId: s.pathParameters['supplier']!)),
    GoRoute(
        path: '/business-workspaces/:workspace/meals',
        builder: (_, __) => const BusinessMealsPage(workspace: 'shop')),
    GoRoute(
        path: '/business-workspaces/:workspace/menus',
        builder: (_, __) => const BusinessMenuPage(workspace: 'shop')),
    GoRoute(
        path: '/business-workspaces/:workspace/menu-fast',
        builder: (_, state) => BusinessMenuFastPage(
            workspace: 'shop',
            mealSources: state.extra as MealPurchaseSelection?)),
    GoRoute(
        path: '/business-workspaces/:workspace/menu-purchase',
        onExit: (ctx, _) => ProviderScope.containerOf(ctx)
            .read(workspaceNavigationProvider)
            .confirmLeave(),
        builder: (_, __) => const BusinessMenuPurchasePage(workspace: 'shop')),
    GoRoute(
        path: '/business-workspaces/:workspace/members',
        builder: (_, __) => const BusinessMembersPage(workspace: 'shop')),
    GoRoute(
        path: '/business-samples',
        builder: (_, __) => const BusinessSamplesPage()),
    GoRoute(
        path: '/membership/admin/business-tests',
        builder: (_, __) => const BusinessTestAdminPage()),
    GoRoute(
        path: '/business-workspaces/:workspace/sales',
        builder: (_, __) => const BusinessSalesPage(workspace: 'shop')),
    GoRoute(
        path: '/business-workspaces/:workspace',
        builder: (_, state) => BusinessWorkspacePage(
            key: ValueKey(state.uri.toString()),
            workspace: 'shop',
            section: businessSection(state.uri.queryParameters['section']),
            initialStatus: state.uri.queryParameters['status'] ?? 'all')),
    GoRoute(
        path: '/business-workspaces/:workspace/new/:kind',
        onExit: (ctx, _) => ProviderScope.containerOf(ctx)
            .read(workspaceNavigationProvider)
            .confirmLeave(),
        builder: (_, state) => BusinessRecordEditorPage(
            workspace: 'shop', kind: state.pathParameters['kind'])),
    GoRoute(
        path: '/business-workspaces/:workspace/edit/:record',
        onExit: (ctx, _) => ProviderScope.containerOf(ctx)
            .read(workspaceNavigationProvider)
            .confirmLeave(),
        builder: (_, state) => BusinessRecordEditorPage(
            workspace: 'shop', recordId: state.pathParameters['record'])),
    GoRoute(
        path: '/business-workspaces/:workspace/records/:record',
        builder: (_, state) => BusinessRecordPage(
            workspace: 'shop', recordId: state.pathParameters['record']!)),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        activeAccountIdProvider.overrideWithValue('staff'),
        businessRepositoryProvider.overrideWithValue(repo),
        businessMenuRepositoryProvider.overrideWithValue(EmptyBusinessMenu()),
        businessSupplierSnapshotProvider.overrideWith((ref, q) async => null),
        ...overrides
      ],
      child: MaterialApp.router(
          theme: AppTheme.light.copyWith(
            textTheme:
                AppTheme.light.textTheme.apply(fontFamily: 'BusinessPreview'),
            appBarTheme: AppTheme.light.appBarTheme.copyWith(
                titleTextStyle: AppTheme.light.appBarTheme.titleTextStyle
                    ?.copyWith(fontFamily: 'BusinessPreview')),
            chipTheme: AppTheme.light.chipTheme.copyWith(
                labelStyle: AppTheme.light.chipTheme.labelStyle
                    ?.copyWith(fontFamily: 'BusinessPreview')),
            filledButtonTheme: FilledButtonThemeData(
                style: AppTheme.light.filledButtonTheme.style?.copyWith(
                    textStyle: const WidgetStatePropertyAll(TextStyle(
                        fontFamily: 'BusinessPreview',
                        fontWeight: FontWeight.w700)))),
          ),
          routerConfig: router,
          locale: Locale(locale),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate
          ],
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  textScaler: textScale == null
                      ? MediaQuery.of(context).textScaler
                      : TextScaler.linear(textScale)),
              child: RepaintBoundary(key: capture, child: child!)))));
  await tester.pumpAndSettle();
  return router;
}

Future<void> fill(WidgetTester tester, String key, String value) async {
  final f = find.byKey(ValueKey('business-field-$key'));
  await tester.scrollUntilVisible(f, 250,
      scrollable: find.byType(Scrollable).first);
  await tester.enterText(f, value);
  await tester.pump();
}

Future<void> save(WidgetTester tester) async {
  final f = find.byKey(const Key('business-record-save'));
  await tester.scrollUntilVisible(f, 300,
      scrollable: find.byType(Scrollable).first);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await (FontLoader('BusinessPreview')
          ..addFont(rootBundle.load('assets/fonts/NanumGothic-Regular.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  testWidgets(
      'purchasing board starts with purchases and never renders financial tools',
      (tester) async {
    final repo = MemoryBusiness(businessRolePermissions['purchasing']!);
    await pumpBusiness(tester, repo,
        initial: '/business-workspaces/shop?section=purchasing');
    expect(find.byKey(const Key('business-purchase-start')), findsOneWidget);
    expect(find.text('작성 중인 목록'), findsOneWidget);
    expect(find.byKey(const ValueKey('business-kind-cost')), findsNothing);
    expect(find.byKey(const ValueKey('business-kind-sale')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'culinary staff save a shared recipe and stale saves retain the form',
      (tester) async {
    final repo = MemoryBusiness(businessRolePermissions['culinary']!);
    await pumpBusiness(tester, repo,
        initial: '/business-workspaces/shop/new/recipe');
    await fill(tester, 'title', '비빔밥 연구');
    await fill(tester, 'ingredients', '밥 120g\n달걀 1개');
    await fill(tester, 'steps', '달걀을 익혀 올립니다.');
    repo.conflict = true;
    await save(tester);
    expect(repo.writes, 0);
    expect(find.text('다른 담당자가 수정했습니다. 최신 자료를 다시 열어 변경 내용을 확인해 주세요.'),
        findsOneWidget);
    repo.conflict = false;
    await save(tester);
    expect(repo.writes, 1);
    expect(repo.data.values.single.data['ingredients'], '밥 120g\n달걀 1개');
    expect(find.text('비빔밥 연구'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('read-only culinary role cannot open a shared recipe editor',
      (tester) async {
    final repo = MemoryBusiness({'recipes.read'});
    await pumpBusiness(tester, repo,
        initial: '/business-workspaces/shop/new/recipe');
    expect(find.byKey(const Key('business-record-save')), findsNothing);
    expect(repo.writes, 0);
  });
  testWidgets(
      'unsaved team recipe keeps the user in the editor when leave is cancelled',
      (tester) async {
    final repo = MemoryBusiness(businessRolePermissions['culinary']!);
    final router = await pumpBusiness(tester, repo,
        initial: '/business-workspaces/shop/new/recipe');
    await fill(tester, 'title', '작성 중');
    router.go('/business-workspaces/shop');
    await tester.pumpAndSettle();
    expect(find.text('저장하지 않고 나갈까요?'), findsOneWidget);
    await tester.tap(find.text('계속 편집'));
    await tester.pumpAndSettle();
    expect(find.text('작성 중'), findsOneWidget);
    expect(repo.writes, 0);
  });
  for (final lang in ['ko', 'en']) {
    for (final width in [390.0, 1440.0]) {
      testWidgets('$lang team board fits $width and enlarged text',
          (tester) async {
        final repo = MemoryBusiness(businessPermissions.toSet());
        repo.data['recipe'] = const BusinessRecord(
            id: 'recipe',
            workspace: 'shop',
            kind: 'recipe',
            title: '샘플 비빔밥 · Bibimbap',
            data: {
              'servings': 4,
              'ingredients': '밥 480 g\n달걀 4개',
              'steps': '재료를 준비하고 밥 위에 담습니다.',
              'notes': '전날 준비할 재료를 확인하세요.'
            },
            revision: 3);
        final key = GlobalKey();
        await pumpBusiness(tester, repo,
            locale: lang, width: width, capture: key);
        expect(tester.takeException(), isNull);
        final output = Platform.environment['SCOUT_BUSINESS_PREVIEW'];
        if (output != null) {
          await tester.runAsync(() async {
            final render = key.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
            final image = await render.toImage(pixelRatio: 1);
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            await Directory(output).create(recursive: true);
            await File('$output/team-$lang-${width.toInt()}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        tester.view.physicalSize = const Size(320, 740);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('revoked financial read hides an already open cost record',
      (tester) async {
    final repo = MemoryBusiness(businessRolePermissions['management']!);
    repo.data['cost'] = const BusinessRecord(
        id: 'cost',
        workspace: 'shop',
        kind: 'cost',
        title: 'Confidential price',
        data: {'unit_cost': 3000, 'unit_price': 5000, 'currency': 'KRW'});
    await pumpBusiness(tester, repo,
        initial: '/business-workspaces/shop/records/cost');
    expect(find.text('Confidential price'), findsOneWidget);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(BusinessRecordPage)));
    repo.business = BusinessContext(
        id: 'shop',
        name: 'Shop',
        owner: false,
        paid: true,
        approval: true,
        permissions: businessRolePermissions['purchasing']!);
    container.invalidate(businessContextProvider('shop'));
    await tester.pumpAndSettle();
    expect(find.text('Confidential price'), findsNothing);
    expect(find.text('5000 KRW'), findsNothing);
  });
  testWidgets('revoking financial read clears the open sales summary',
      (tester) async {
    final repo = MemoryBusiness(businessRolePermissions['management']!);
    await pumpBusiness(tester, repo,
        initial: '/business-workspaces/shop/sales');
    expect(repo.financialQueries, 1);
    expect(find.text('매출: 15,000 KRW'), findsOneWidget);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(BusinessSalesPage)));
    repo.business = BusinessContext(
        id: 'shop',
        name: 'Shop',
        owner: false,
        paid: true,
        approval: true,
        permissions: businessRolePermissions['purchasing']!);
    container.invalidate(businessContextProvider('shop'));
    await tester.pumpAndSettle();
    expect(find.text('매출: 15,000 KRW'), findsNothing);
    expect(repo.financialQueries, 1);
  });
  testWidgets('logout hides the unsaved team editor', (tester) async {
    final account = StateProvider<String?>((_) => 'staff');
    final repo = MemoryBusiness(businessRolePermissions['culinary']!);
    await pumpBusiness(tester, repo,
        initial: '/business-workspaces/shop/new/recipe',
        overrides: [
          activeAccountIdProvider.overrideWith((ref) => ref.watch(account))
        ]);
    await fill(tester, 'title', 'private edit');
    final container = ProviderScope.containerOf(
        tester.element(find.byType(BusinessRecordEditor)));
    container.read(account.notifier).state = null;
    await tester.pumpAndSettle();
    expect(find.text('private edit'), findsNothing);
    expect(find.byKey(const Key('business-record-save')), findsNothing);
    expect(repo.writes, 0);
  });
}
