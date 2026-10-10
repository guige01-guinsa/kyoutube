import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/membership/application/membership_providers.dart';
import 'package:k_youtube/features/membership/domain/membership.dart';
import 'package:k_youtube/features/shopping/data/coupang_partners_repository.dart';
import 'package:k_youtube/features/shopping/data/shopping_affiliate_repository.dart';
import 'package:k_youtube/features/shopping/domain/shopping_affiliate.dart';
import 'package:k_youtube/features/shopping/domain/shopping_assistant.dart';
import 'package:k_youtube/features/shopping/presentation/coupang_product_dialog.dart';
import 'package:k_youtube/features/shopping/presentation/shopping_store_search_dialog.dart';

class FakeCoupang implements CoupangPartnersRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  final keywords = <String>[];
  final urls = <String>[];
  String? error;
  Completer<List<CoupangProduct>>? pending;
  @override
  Future<List<CoupangProduct>> search(String keyword) async {
    keywords.add(keyword);
    if (error != null) throw CoupangPartnersException(error!);
    if (pending != null) return pending!.future;
    return [
      const CoupangProduct(
          id: '123',
          title: '진간장 1L',
          url: 'https://www.coupang.com/vp/products/123',
          price: 5000,
          imageUrl: 'https://image8.coupangcdn.com/image/product/ganjang.jpg')
    ];
  }

  @override
  Future<String> deeplink(String url) async {
    urls.add(url);
    if (error != null) throw CoupangPartnersException(error!);
    return 'https://link.coupang.com/a/Issued123';
  }
}

Future<ProviderContainer> pumpDialog(WidgetTester tester, FakeCoupang repo,
    {void Function(Map<String, dynamic>?)? result,
    String language = 'ko',
    double scale = 1}) async {
  final container = ProviderContainer(overrides: [
    activeAccountIdProvider.overrideWithValue('admin'),
    membershipInfoProvider
        .overrideWith((_) async => MembershipInfo.fromJson({'is_admin': true})),
    coupangPartnersRepositoryProvider.overrideWithValue(repo),
  ]);
  addTearDown(container.dispose);
  await container.read(membershipInfoProvider.future);
  tester.view.physicalSize = const Size(360, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: Locale(language),
        supportedLocales: const [Locale('ko'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (_, child) => MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () async => result?.call(
                        await showDialog<Map<String, dynamic>>(
                            context: context,
                            builder: (_) => const CoupangProductDialog())),
                    child: const Text('open')))),
      )));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets(
      'search selection returns an unverified unpublished draft with exact issued link',
      (tester) async {
    final repo = FakeCoupang();
    Map<String, dynamic>? draft;
    await pumpDialog(tester, repo, result: (value) => draft = value);
    await tester.enterText(
        find.byKey(const ValueKey('coupang-keyword')), ' 간장 ');
    await tester.tap(find.text('쿠팡 상품 검색'));
    await tester.pumpAndSettle();
    expect(repo.keywords, ['간장']);
    expect(find.text('진간장 1L'), findsOneWidget);
    await tester.ensureVisible(find.text('링크 생성 후 검토'));
    await tester.tap(find.text('링크 생성 후 검토'));
    await tester.pumpAndSettle();
    expect(repo.urls, ['https://www.coupang.com/vp/products/123']);
    expect(draft?['link'], 'https://link.coupang.com/a/Issued123');
    expect(draft?['ingredients'], ['간장']);
    expect(draft?['title'], '진간장 1L');
    expect(draft?['image_url'],
        'https://image8.coupangcdn.com/image/product/ganjang.jpg');
    for (final key in [
      'published',
      'product_verified',
      'mobile_allowed',
      'web_allowed'
    ]) {
      expect(draft?[key], false);
    }
  });

  testWidgets(
      'URL mode preserves options and rejects spoofed hosts before API call',
      (tester) async {
    final repo = FakeCoupang();
    Map<String, dynamic>? draft;
    await pumpDialog(tester, repo, result: (value) => draft = value);
    final field = find.byKey(const ValueKey('coupang-product-url'));
    await tester.enterText(
        field, 'https://www.coupang.com.evil/vp/products/123');
    await tester.tap(find.text('주소로 제휴 링크 생성'));
    await tester.pumpAndSettle();
    expect(repo.urls, isEmpty);
    expect(find.byKey(const ValueKey('coupang-api-error')), findsOneWidget);
    const url =
        'https://www.coupang.com/vp/products/123?itemId=4&vendorItemId=5';
    await tester.enterText(field, url);
    await tester.tap(find.text('주소로 제휴 링크 생성'));
    await tester.pumpAndSettle();
    expect(repo.urls.single, url);
    expect(draft?['title'], '');
    expect(draft?['ingredients'], isEmpty);
  });

  testWidgets('missing configuration is recoverable and search retries',
      (tester) async {
    final repo = FakeCoupang()..error = 'not_configured';
    await pumpDialog(tester, repo, result: (_) {});
    await tester.enterText(find.byKey(const ValueKey('coupang-keyword')), '간장');
    await tester.tap(find.text('쿠팡 상품 검색'));
    await tester.pumpAndSettle();
    expect(find.textContaining('쿠팡 API 연결 준비'), findsOneWidget);
    repo.error = null;
    await tester.tap(find.text('쿠팡 상품 검색'));
    await tester.pumpAndSettle();
    expect(find.text('진간장 1L'), findsOneWidget);
  });

  testWidgets(
      'account switch ignores pending results and cannot generate a link',
      (tester) async {
    final repo = FakeCoupang()..pending = Completer<List<CoupangProduct>>();
    final container = await pumpDialog(tester, repo, result: (_) {});
    await tester.enterText(find.byKey(const ValueKey('coupang-keyword')), '간장');
    await tester.tap(find.text('쿠팡 상품 검색'));
    await tester.pump();
    container.updateOverrides([
      activeAccountIdProvider.overrideWithValue('other'),
      membershipInfoProvider.overrideWith(
          (_) async => MembershipInfo.fromJson({'is_admin': true})),
      coupangPartnersRepositoryProvider.overrideWithValue(repo),
    ]);
    repo.pending!.complete([
      const CoupangProduct(
          id: '123',
          title: 'private result',
          url: 'https://www.coupang.com/vp/products/123')
    ]);
    await tester.pump();
    expect(find.text('private result'), findsNothing);
    expect(repo.urls, isEmpty);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('English 200 percent text fits narrow screen', (tester) async {
    await pumpDialog(tester, FakeCoupang(),
        result: (_) {}, language: 'en', scale: 2);
    expect(find.text('Coupang products and links'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'editing ingredient refreshes affiliate offers and empty query hides them',
      (tester) async {
    ShoppingAffiliate offer(String title) => ShoppingAffiliate({
          'id': title,
          'title': title,
          'program': 'coupang',
          'link': 'https://link.coupang.com/a/Issued123'
        });
    await tester.pumpWidget(ProviderScope(
        overrides: [
          activeAccountIdProvider.overrideWithValue('member'),
          shoppingAffiliatesProvider('간장')
              .overrideWith((_) async => [offer('간장 상품')]),
          shoppingAffiliatesProvider('소금')
              .overrideWith((_) async => [offer('소금 상품')]),
        ],
        child: const MaterialApp(
            home: Scaffold(
                body: ShoppingStoreSearchDialog(
                    group: ShoppingPurchaseGroup(
                        key: 'a', name: '간장', unit: 'g', sources: []))))));
    await tester.pumpAndSettle();
    expect(find.text('간장 상품'), findsOneWidget);
    expect(find.byKey(const ValueKey('open-store-naver')), findsNothing);
    expect(find.byKey(const ValueKey('open-store-coupang')), findsNothing);
    expect(find.byKey(const ValueKey('open-store-web')), findsNothing);
    expect(find.text('쿠팡에서 검색'), findsNothing);
    expect(find.text('Google 쇼핑 열기'), findsNothing);
    await tester.enterText(
        find.byKey(const ValueKey('store-search-query')), '소금');
    await tester.pumpAndSettle();
    expect(find.text('간장 상품'), findsNothing);
    expect(find.text('소금 상품'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('store-search-query')), '  ');
    await tester.pumpAndSettle();
    expect(find.text('소금 상품'), findsNothing);
  });
}
