import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/membership/application/membership_providers.dart';
import 'package:k_youtube/features/membership/domain/membership.dart';
import 'package:k_youtube/features/shopping/data/shopping_affiliate_repository.dart';
import 'package:k_youtube/features/shopping/data/shopping_assistant_repository.dart';
import 'package:k_youtube/features/shopping/domain/shopping_affiliate.dart';
import 'package:k_youtube/features/shopping/presentation/shopping_affiliate_panel.dart';
import 'package:k_youtube/features/shopping/presentation/shopping_affiliate_admin_page.dart';

Future<void> pump(WidgetTester tester,
    {bool admin = false,
    bool fail = false,
    bool Function()? loadFails,
    bool empty = false,
    bool showEmptyCoupang = false,
    bool page = false,
    bool guided = false,
    String language = 'ko',
    double scale = 1,
    List<Uri>? opened}) async {
  tester.view.physicalSize = const Size(360, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        activeAccountIdProvider.overrideWithValue('tester'),
        membershipInfoProvider.overrideWith(
            (_) async => MembershipInfo.fromJson({'is_admin': admin})),
        affiliateAdminPageProvider(
                (query: '', status: guided ? 'draft' : 'active', offset: 0))
            .overrideWith(
                (_) async => {'rows': <Map<String, dynamic>>[], 'total': 0}),
        shoppingAffiliatesProvider('춘장').overrideWith((_) async {
          if (fail || (loadFails?.call() ?? false)) throw StateError('offline');
          return empty
              ? []
              : [
                  ShoppingAffiliate({
                    'id': '1',
                    'program': 'naver',
                    'title': 'Chunjang 500g',
                    'specification': '500g',
                    'link': 'https://naver.me/Example1?c=a%2Bb'
                  }),
                  ShoppingAffiliate({
                    'id': 'c',
                    'program': 'coupang',
                    'title': 'Coupang Chunjang',
                    'image_url':
                        'https://image8.coupangcdn.com/image/product/chunjang.jpg',
                    'link': 'https://link.coupang.com/a/IssuedExact1'
                  }),
                  ShoppingAffiliate({
                    'id': '2',
                    'program': 'youtube',
                    'title': 'Cooking video',
                    'link': 'https://youtu.be/abcdefghijk'
                  })
                ];
        }),
        shoppingLinkLauncherProvider.overrideWithValue((uri) async {
          opened?.add(uri);
          return !fail;
        }),
      ],
      child: MaterialApp(
          locale: Locale(language),
          supportedLocales: const [Locale('ko'), Locale('en')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate
          ],
          builder: (_, child) => MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: page
              ? ShoppingAffiliateAdminPage(guided: guided)
              : Scaffold(
                  body: SingleChildScrollView(
                      child: ShoppingAffiliatePanel(
                          ingredient: '춘장',
                          showEmptyCoupang: showEmptyCoupang))))));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('guided menu starts with drafts and explains the workflow',
      (tester) async {
    await pump(tester, admin: true, page: true, guided: true);
    expect(find.text('상품 등록·공개 도우미'), findsOneWidget);
    expect(find.textContaining('① 링크 등록'), findsOneWidget);
  });
  testWidgets('disclosure is visible and issued link is preserved',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final opened = <Uri>[];
    await pump(tester, opened: opened);
    expect(find.textContaining('운영자가 수수료'), findsOneWidget);
    expect(find.text('Chunjang 500g'), findsNothing);
    expect(find.text('제휴 상품 열기'), findsNothing);
    expect(find.bySemanticsLabel('쿠팡 상품 사진'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Coupang Chunjang')).dy,
        lessThan(tester.getTopLeft(find.text('Cooking video')).dy));
    await tester.ensureVisible(find.text('상품 태그 영상 보기'));
    await tester.tap(find.text('상품 태그 영상 보기'));
    await tester.pumpAndSettle();
    expect(opened.last.host, 'youtu.be');
    expect(find.textContaining('쿠팡 파트너스 활동'), findsOneWidget);
    expect(tester.getTopLeft(find.textContaining('쿠팡 파트너스 활동')).dy,
        greaterThan(tester.getTopLeft(find.text('Coupang Chunjang')).dy));
    await tester.ensureVisible(find.text('구매'));
    await tester.tap(find.text('구매'));
    await tester.pumpAndSettle();
    expect(opened.last.toString(), 'https://link.coupang.com/a/IssuedExact1');
    semantics.dispose();
  });
  testWidgets('empty offers do not add empty promotional section',
      (tester) async {
    await pump(tester, empty: true);
    expect(find.text('제휴 상품'), findsNothing);
  });
  testWidgets(
      'store dialog can explain missing Coupang offers without an invented link',
      (tester) async {
    final opened = <Uri>[];
    await pump(tester, empty: true, showEmptyCoupang: true, opened: opened);
    expect(find.text('쿠팡에서 다른 상품 찾기'), findsOneWidget);
    expect(find.textContaining('일반 검색은 제휴 링크가 아닙니다'), findsOneWidget);
    await tester.tap(find.text('쿠팡에서 다른 상품 찾기'));
    await tester.pumpAndSettle();
    expect(opened.single.host, 'www.coupang.com');
    expect(opened.single.queryParameters, {'q': '춘장'});
    expect(find.text('구매'), findsNothing);
  });
  testWidgets('load failure is recoverable without blocking regular search',
      (tester) async {
    await pump(tester, fail: true);
    expect(find.textContaining('일반 검색은 계속'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('non admin has no editor', (tester) async {
    await pump(tester, page: true);
    expect(find.text('제휴 상품 추가'), findsNothing);
  });
  testWidgets('retry reloads affiliate offers after a temporary failure',
      (tester) async {
    var offline = true;
    await pump(tester, loadFails: () => offline);
    expect(find.textContaining('일반 검색은 계속'), findsOneWidget);
    offline = false;
    await tester.tap(find.text('제휴 상품 다시 불러오기'));
    await tester.pumpAndSettle();
    expect(find.text('구매'), findsOneWidget);
    expect(find.textContaining('일반 검색은 계속'), findsNothing);
  });
  testWidgets('admin can reach setup and draft form', (tester) async {
    await pump(tester, page: true, admin: true);
    await tester.tap(find.text('제휴 상품 추가'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(SwitchListTile), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        false);
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(find.text('링크와 입력 항목을 확인해 주세요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('English large text offers fit narrow layout', (tester) async {
    await pump(tester, language: 'en', scale: 2);
    expect(tester.takeException(), isNull);
    expect(find.text('Affiliate offers'), findsNothing);
    expect(
        find.textContaining('commission through these Coupang Partners links'),
        findsOneWidget);
  });
}
