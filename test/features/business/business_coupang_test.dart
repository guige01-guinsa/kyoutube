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
import 'package:go_router/go_router.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:k_youtube/core/theme/app_theme.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/business/application/business_coupang_service.dart';
import 'package:k_youtube/features/business/data/business_repository.dart';
import 'package:k_youtube/features/business/domain/business_coupang.dart';
import 'package:k_youtube/features/business/domain/business_workspace.dart';
import 'package:k_youtube/features/business/presentation/business_coupang_page.dart';
import 'package:k_youtube/features/shopping/data/shopping_affiliate_repository.dart';
import 'package:k_youtube/features/shopping/domain/shopping_affiliate.dart';
import 'business_flow_test.dart' show MemoryBusiness, pumpBusiness;

BusinessRecord purchase(
        {String status = 'approved',
        int revision = 3,
        double quantity = 2,
        String workspace = 'shop',
        bool practice = false}) =>
    BusinessRecord(
        id: 'request',
        workspace: workspace,
        kind: 'purchase',
        title: '국간장 구매',
        status: status,
        revision: revision,
        isTest: practice,
        data: {
          'supplier': '쿠팡',
          'currency': 'KRW',
          'lines': [
            {
              'id': 'line',
              'name': '국간장',
              'quantity': quantity,
              'unit': '병',
              'spec': '1.8 L / 병',
              'price': 10000
            },
            {
              'id': 'line2',
              'name': '진간장',
              'quantity': 3,
              'unit': 'kg',
              'spec': '조리용',
              'price': 3000
            },
          ]
        });

ShoppingAffiliate product(
        {String link = 'https://link.coupang.com/a/IssuedExact1',
        String spec = '1.8 L, 1병'}) =>
    ShoppingAffiliate({
      'id': 'offer',
      'program': 'coupang',
      'title': '국간장 1.8 L',
      'specification': spec,
      'link': link,
    });

class MemoryOffers implements ShoppingAffiliateRepository {
  List<ShoppingAffiliate> offers = [product()];
  Future<void> Function()? beforeFind;
  final queries = <String>[];
  @override
  Future<List<ShoppingAffiliate>> find(String ingredient) async {
    queries.add(ingredient);
    await beforeFind?.call();
    return offers;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MemoryBusiness buyer() =>
    MemoryBusiness({'purchasing.read', 'purchasing.write'})
      ..data['request'] = purchase();

class RefreshingBuyer extends MemoryBusiness {
  RefreshingBuyer() : super({'purchasing.read', 'purchasing.write'}) {
    data['request'] = purchase();
  }
  Future<void> Function()? beforeContext;
  @override
  Future<BusinessContext> context(String id) async {
    await beforeContext?.call();
    return business;
  }
}

final testAccount = StateProvider<String?>((ref) => 'staff');

Future<ProviderContainer> pumpCoupang(WidgetTester tester, MemoryBusiness repo,
    MemoryOffers catalog, List<Uri> opened,
    {double width = 390,
    double scale = 1,
    String locale = 'ko',
    GlobalKey? capture}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        activeAccountIdProvider.overrideWith((ref) => ref.watch(testAccount)),
        businessRepositoryProvider.overrideWithValue(repo),
        shoppingAffiliateRepositoryProvider.overrideWithValue(catalog),
        businessCoupangLauncherProvider.overrideWithValue((uri) async {
          opened.add(uri);
          return true;
        }),
      ],
      child: MaterialApp(
          theme: AppTheme.light.copyWith(
              textTheme:
                  AppTheme.light.textTheme.apply(fontFamily: 'BusinessPreview'),
              appBarTheme: AppTheme.light.appBarTheme.copyWith(
                  titleTextStyle: AppTheme.light.appBarTheme.titleTextStyle
                      ?.copyWith(fontFamily: 'BusinessPreview')),
              filledButtonTheme: FilledButtonThemeData(
                  style: AppTheme.light.filledButtonTheme.style?.copyWith(
                      textStyle: const WidgetStatePropertyAll(TextStyle(
                          fontFamily: 'BusinessPreview',
                          fontWeight: FontWeight.w600))))),
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
              child: RepaintBoundary(key: capture, child: child!)),
          home: const BusinessCoupangPage(
              workspace: 'shop', recordId: 'request'))));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(
      tester.element(find.byType(BusinessCoupangPage)));
}

Future<void> review(WidgetTester tester, {bool english = false}) async {
  final button =
      find.text(english ? 'Compare with request & buy' : '요청서와 비교·구매');
  await tester.scrollUntilVisible(button, 300,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> confirm(WidgetTester tester) async {
  for (final key in ['coupang-match-confirm', 'coupang-order-confirm']) {
    final checkbox = find.byKey(Key(key));
    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
  }
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
  test('only authorized approved real requests can open external products', () {
    final b = buyer().business;
    expect(businessCoupangBlock(b, purchase()), isNull);
    for (final status in [
      'draft',
      'review',
      'sent',
      'received',
      'cancelled',
      'unknown'
    ]) {
      expect(businessCoupangBlock(b, purchase(status: status)), isNotNull);
    }
    expect(businessCoupangBlock(b, purchase(practice: true)),
        BusinessCoupangBlock.practice);
    expect(businessCoupangBlock(b, purchase(workspace: 'another')),
        BusinessCoupangBlock.access);
    expect(
        businessCoupangBlock(
            MemoryBusiness({'purchasing.read'}).business, purchase()),
        BusinessCoupangBlock.access);
    for (final practice in [true, false]) {
      final context = BusinessContext(
          id: 'shop',
          name: 'Test',
          owner: true,
          paid: practice,
          approval: false,
          isTest: practice,
          permissions: {});
      expect(businessCoupangBlock(context, purchase()), isNotNull);
    }
  });

  test('units and specifications remain separate and order matters', () {
    final original = purchase();
    final lines = businessCoupangLines(original);
    expect(lines[0].quantity, 2);
    expect(lines[0].unit, '병');
    expect(lines[0].spec, '1.8 L / 병');
    expect(lines[1].quantity, 3);
    expect(lines[1].unit, 'kg');
    expect(lines.map((l) => l.index), [0, 1]);
    final snapshot = snapshotBusinessPurchase(original);
    (original.data['lines'] as List).first['quantity'] = 4;
    expect(businessCoupangLines(snapshot).first.quantity, 2);
    expect(sameBusinessPurchase(original, snapshot), false);
  });

  test('successful opening preserves issued link and all original data',
      () async {
    final repo = buyer(), catalog = MemoryOffers(), opened = <Uri>[];
    final request = repo.data['request']!,
        before = jsonEncode(repo.data['request']!.data);
    final service = BusinessCoupangService(repo, catalog, (u) async {
      opened.add(u);
      return true;
    });
    await service.open(
        request: request,
        lineIndex: 0,
        offer: product(),
        isCurrent: () => true);
    expect(opened.single.toString(), product().uri.toString());
    expect(catalog.queries, ['국간장']);
    expect(repo.writes, 0);
    expect(repo.data['request']!.status, 'approved');
    expect(repo.data['request']!.revision, 3);
    expect(jsonEncode(repo.data['request']!.data), before);
  });

  for (final change in [
    'revision',
    'quantity',
    'status',
    'permissions',
    'hidden',
    'link',
    'spec',
    'account',
    'offline'
  ]) {
    test('blocks changed $change before any external navigation', () async {
      final repo = buyer(), catalog = MemoryOffers(), opened = <Uri>[];
      var current = true;
      final expected = purchase();
      catalog.beforeFind = () async {
        switch (change) {
          case 'revision':
            repo.data['request'] = purchase(revision: 4);
          case 'quantity':
            repo.data['request'] = purchase(quantity: 20);
          case 'status':
            repo.data['request'] = purchase(status: 'sent');
          case 'permissions':
            repo.business = MemoryBusiness({'purchasing.read'}).business;
          case 'hidden':
            catalog.offers = [];
          case 'link':
            catalog.offers = [
              product(link: 'https://link.coupang.com/a/Changed')
            ];
          case 'spec':
            catalog.offers = [product(spec: '900 ml')];
          case 'account':
            current = false;
          case 'offline':
            throw StateError('offline');
        }
      };
      final service = BusinessCoupangService(repo, catalog, (u) async {
        opened.add(u);
        return true;
      });
      await expectLater(
          service.open(
              request: expected,
              lineIndex: 0,
              offer: product(),
              isCurrent: () => current),
          throwsA(anything));
      expect(opened, isEmpty);
      expect(repo.writes, 0);
    });
  }

  test('parallel click is rejected and failed launches do not record purchase',
      () async {
    final repo = buyer(), catalog = MemoryOffers(), gate = Completer<void>();
    catalog.beforeFind = () => gate.future;
    var launches = 0;
    final service = BusinessCoupangService(repo, catalog, (_) async {
      launches++;
      return false;
    });
    final first = service.open(
        request: purchase(),
        lineIndex: 0,
        offer: product(),
        isCurrent: () => true);
    final failure = expectLater(first, throwsA(BusinessCoupangFailure.open));
    await expectLater(
        service.open(
            request: purchase(),
            lineIndex: 0,
            offer: product(),
            isCurrent: () => true),
        throwsA(BusinessCoupangFailure.busy));
    gate.complete();
    await failure;
    expect(launches, 1);
    await expectLater(
        service.open(
            request: purchase(),
            lineIndex: 0,
            offer: product(),
            isCurrent: () => true),
        throwsA(BusinessCoupangFailure.open));
    expect(launches, 2);
    expect(repo.writes, 0);
  });

  test('invalid or absent request line cannot open a product', () async {
    final repo = buyer(), catalog = MemoryOffers(), opened = <Uri>[];
    final service = BusinessCoupangService(repo, catalog, (uri) async {
      opened.add(uri);
      return true;
    });
    for (final index in [-1, 2]) {
      await expectLater(
          service.open(
              request: purchase(),
              lineIndex: index,
              offer: product(),
              isCurrent: () => true),
          throwsA(BusinessCoupangFailure.changed));
    }
    repo.data['request'] = purchase(quantity: 0);
    await expectLater(
        service.open(
            request: repo.data['request']!,
            lineIndex: 0,
            offer: product(),
            isCurrent: () => true),
        throwsA(BusinessCoupangFailure.changed));
    expect(catalog.queries, isEmpty);
    expect(opened, isEmpty);
    expect(repo.writes, 0);
  });

  test('non Coupang and malformed affiliate URLs cannot open', () async {
    final repo = buyer(), catalog = MemoryOffers();
    catalog.offers = [
      ShoppingAffiliate({
        'id': 'other',
        'program': 'youtube',
        'title': 'Video',
        'link': 'https://youtu.be/abcdefghijk'
      }),
      product(link: 'https://example.com/product')
    ];
    var calls = 0;
    final service = BusinessCoupangService(repo, catalog, (_) async {
      calls++;
      return true;
    });
    await expectLater(
        service.open(
            request: purchase(),
            lineIndex: 0,
            offer: product(),
            isCurrent: () => true),
        throwsA(BusinessCoupangFailure.unavailable));
    expect(calls, 0);
  });

  testWidgets('approved list entry opens the purchasing route', (tester) async {
    final repo = buyer();
    await pumpBusiness(tester, repo,
        initial: '/business-workspaces/shop?section=purchasing',
        overrides: [
          shoppingAffiliateRepositoryProvider.overrideWithValue(MemoryOffers())
        ]);
    await tester.tap(find.byKey(const Key('shopping-stage-active')));
    await tester.pumpAndSettle();
    final entry = find.byKey(const Key('business-coupang-request'));
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(
        GoRouterState.of(tester.element(find.byType(BusinessCoupangPage)))
            .uri
            .path,
        '/business-workspaces/shop/coupang/request');
    expect(find.byType(BusinessCoupangPage), findsOneWidget);
    expect(repo.writes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('comparison requires both checks; cancel and open never write',
      (tester) async {
    final repo = buyer(), catalog = MemoryOffers(), opened = <Uri>[];
    await pumpCoupang(tester, repo, catalog, opened);
    expect(find.text('구매량: 2 병'), findsOneWidget);
    expect(find.text('규격: 1.8 L / 병'), findsOneWidget);
    expect(find.textContaining('일정액의 수수료'), findsOneWidget);
    await review(tester);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const Key('business-coupang-open')))
            .onPressed,
        isNull);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    await review(tester);
    await confirm(tester);
    await tester.tap(find.byKey(const Key('business-coupang-open')));
    await tester.pumpAndSettle();
    expect(opened.length, 1);
    expect(repo.writes, 0);
    expect(repo.data['request']!.status, 'approved');
    expect(find.textContaining('상품 페이지를 열었습니다'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('request update while confirming prevents launch',
      (tester) async {
    final repo = buyer(), opened = <Uri>[];
    await pumpCoupang(tester, repo, MemoryOffers(), opened);
    await review(tester);
    await confirm(tester);
    repo.data['request'] = purchase(quantity: 20, revision: 4);
    await tester.tap(find.byKey(const Key('business-coupang-open')));
    await tester.pumpAndSettle();
    expect(find.textContaining('요청서가 변경됐습니다'), findsOneWidget);
    expect(opened, isEmpty);
    expect(repo.writes, 0);
  });

  testWidgets('account change closes confirmation and clears private content',
      (tester) async {
    final repo = buyer(), opened = <Uri>[];
    final container = await pumpCoupang(tester, repo, MemoryOffers(), opened);
    await review(tester);
    container.read(testAccount.notifier).state = null;
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('국간장 구매'), findsNothing);
    expect(find.text('로그인'), findsOneWidget);
    expect(opened, isEmpty);
    expect(repo.writes, 0);
  });

  testWidgets('revoked purchasing access at confirmation blocks navigation',
      (tester) async {
    final repo = buyer(), opened = <Uri>[];
    await pumpCoupang(tester, repo, MemoryOffers(), opened);
    await review(tester);
    await confirm(tester);
    repo.business = MemoryBusiness({'purchasing.read'}).business;
    await tester.tap(find.byKey(const Key('business-coupang-open')));
    await tester.pumpAndSettle();
    expect(find.textContaining('현재 계정의 권한과 승인 상태'), findsOneWidget);
    expect(
        tester
            .widget<CheckboxListTile>(
                find.byKey(const Key('coupang-match-confirm')))
            .value,
        isFalse);
    expect(opened, isEmpty);
    expect(repo.writes, 0);
  });

  testWidgets('sign out during fresh lookup never launches after it completes',
      (tester) async {
    final repo = buyer(), catalog = MemoryOffers(), opened = <Uri>[];
    final container = await pumpCoupang(tester, repo, catalog, opened);
    await review(tester);
    await confirm(tester);
    final gate = Completer<void>();
    catalog.beforeFind = () => gate.future;
    await tester.tap(find.byKey(const Key('business-coupang-open')));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    container.read(testAccount.notifier).state = null;
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    expect(repo.writes, 0);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('periodic permission refresh preserves an unchanged comparison',
      (tester) async {
    final repo = RefreshingBuyer(), opened = <Uri>[];
    await pumpCoupang(tester, repo, MemoryOffers(), opened);
    await review(tester);
    await confirm(tester);
    final gate = Completer<void>();
    repo.beforeContext = () => gate.future;
    await tester.pump(const Duration(seconds: 61));
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('business-coupang-open')));
    await tester.pumpAndSettle();
    expect(opened.length, 1);
    expect(repo.writes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty or offline catalog preserves the request and allows retry',
      (tester) async {
    final repo = buyer(),
        catalog = MemoryOffers()..offers = [],
        opened = <Uri>[];
    await pumpCoupang(tester, repo, catalog, opened);
    expect(find.textContaining('공개된 쿠팡 상품이 없습니다'), findsOneWidget);
    catalog.beforeFind = () async => throw StateError('offline');
    await tester.tap(find.byTooltip('최신 자료 다시 확인'));
    await tester.pumpAndSettle();
    expect(find.textContaining('상품을 불러오지 못했습니다'), findsOneWidget);
    catalog.beforeFind = null;
    catalog.offers = [product()];
    await tester.tap(find.textContaining('상품을 불러오지 못했습니다'));
    await tester.pumpAndSettle();
    expect(find.text('국간장 1.8 L'), findsOneWidget);
    expect(repo.writes, 0);
    expect(opened, isEmpty);
  });

  for (final status in ['draft', 'review', 'sent', 'received', 'cancelled']) {
    testWidgets('$status deep link never loads affiliate products',
        (tester) async {
      final repo = buyer()..data['request'] = purchase(status: status);
      final catalog = MemoryOffers();
      await pumpCoupang(tester, repo, catalog, []);
      expect(catalog.queries, isEmpty);
      expect(find.byType(DropdownButtonFormField<int>), findsNothing);
      expect(repo.writes, 0);
    });
  }

  testWidgets('English narrow layout with large text keeps comparison usable',
      (tester) async {
    final repo = buyer(), opened = <Uri>[];
    await pumpCoupang(tester, repo, MemoryOffers(), opened,
        width: 320, scale: 2, locale: 'en');
    await review(tester, english: true);
    await confirm(tester);
    expect(find.text('Buy at Coupang'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(opened, isEmpty);
    expect(repo.writes, 0);
  });

  for (final width in [390.0, 1440.0]) {
    testWidgets('Korean purchasing and comparison fit $width', (tester) async {
      final repo = buyer(), opened = <Uri>[], key = GlobalKey();
      await pumpCoupang(tester, repo, MemoryOffers(), opened,
          width: width, capture: key);
      await capturePreview(tester, key, 'coupang-page-${width.toInt()}');
      await review(tester);
      await capturePreview(tester, key, 'coupang-compare-${width.toInt()}');
      await confirm(tester);
      await tester.tap(find.text('닫기'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(opened, isEmpty);
      expect(repo.writes, 0);
    });
  }
}

Future<void> capturePreview(
    WidgetTester tester, GlobalKey key, String name) async {
  final output = Platform.environment['SCOUT_COUPANG_PREVIEW'];
  if (output == null) return;
  await tester.runAsync(() async {
    final render =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(output).create(recursive: true);
    await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
