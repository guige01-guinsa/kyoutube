import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/core/theme/app_theme.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/membership/application/membership_providers.dart';
import 'package:k_youtube/features/membership/domain/membership.dart';
import 'package:k_youtube/features/shopping/domain/supplier_request.dart';
import 'package:k_youtube/features/suppliers/data/public_supplier_repository.dart';
import 'package:k_youtube/features/suppliers/domain/public_supplier.dart';
import 'package:k_youtube/features/suppliers/presentation/public_supplier_admin_page.dart';
import 'package:k_youtube/features/suppliers/presentation/public_supplier_card.dart';

const listing = PublicSupplier(
    id: 'listing',
    name: 'Test Foods',
    website: 'https://food.example.com/',
    products: 'Vegetables',
    categories: ['produce'],
    deliveryRegions: ['전국'],
    shippingNote: 'Nationwide parcels, excluding islands',
    sourceUrls: ['https://food.example.com/delivery'],
    checkedOn: '2026-09-15',
    revision: 1);

class AdminRepo extends PublicSupplierAdminRepository {
  int searches = 0, discoveries = 0, publishes = 0, saves = 0;
  List<PublicSupplier> rows = [listing];
  @override
  Future<List<PublicSupplier>> search(String query, String status,
      {int offset = 0}) async {
    searches++;
    return rows.skip(offset).toList();
  }

  @override
  Future<List<PublicSupplier>> discover(String query) async {
    discoveries++;
    return [
      PublicSupplier.fromJson(
          {...listing.toJson(), 'id': 'found', 'revision': 0, 'checked_on': ''})
    ];
  }

  @override
  Future<void> publish(List<PublicSupplier> rows) async {
    publishes++;
  }

  @override
  Future<PublicSupplier> save(PublicSupplier row,
      {required bool confirmed}) async {
    saves++;
    return row;
  }
}

Future<void> pump(WidgetTester tester, Widget child,
    {AdminRepo? repo,
    bool admin = true,
    String language = 'ko',
    Size size = const Size(1100, 900),
    double scale = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        activeAccountIdProvider.overrideWithValue('admin'),
        membershipInfoProvider.overrideWith(
            (ref) async => MembershipInfo.fromJson({'is_admin': admin})),
        if (repo != null)
          publicSupplierAdminRepositoryProvider.overrideWithValue(repo)
      ],
      child: MaterialApp(
          theme: AppTheme.light,
          locale: Locale(language),
          supportedLocales: const [Locale('ko'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: child)));
  await tester.pumpAndSettle();
}

void main() {
  test(
      'web candidates preserve saved identity and operator edits for the same domain',
      () {
    final incoming = PublicSupplier.fromJson({
      ...listing.toJson(),
      'id': 'new',
      'website': 'https://www.food.example.com/catalog',
      'products': 'Unreviewed change',
      'revision': 0
    });
    final other = PublicSupplier.fromJson({
      ...listing.toJson(),
      'id': 'other',
      'website': 'https://other.example.com/',
      'revision': 0
    });
    final result = matchPublicSupplierCandidates([incoming, other], [listing]);
    expect(result[0], same(listing));
    expect(result[0].products, 'Vegetables');
    expect(result[1], same(other));
  });
  test(
      'research seed contains twenty unique official-source listings, no fabricated offers',
      () {
    final rows = jsonDecode(
            File('tools/data/public_supplier_sources.json').readAsStringSync())
        as List;
    expect(rows.length, 20);
    expect(
        rows
            .map((r) => Uri.parse(r['website']).host.replaceFirst('www.', ''))
            .toSet()
            .length,
        20);
    for (final row in rows) {
      final s = PublicSupplier.fromJson(Map<String, dynamic>.from(row));
      expect(s.sourceUrls, isNotEmpty);
      expect(s.shippingNote, isNotEmpty);
      expect(s.checkedOn, isNotEmpty);
      expect(row.containsKey('price'), false);
      expect(row.containsKey('rating'), false);
      expect(row.containsKey('owner_id'), false);
      expect(s.toJson()['website'], row['website']);
    }
  });
  test(
      'private supplier provenance cannot be forged through saves or shared orders',
      () {
    final s = ShoppingSupplier.fromJson({
      'id': 'mine',
      'name': 'Supplier',
      'public_listing_id': 'reference',
      'memo': 'private'
    });
    expect(s.publicListingId, 'reference');
    expect(s.toJson().containsKey('public_listing_id'), false);
    expect(s.toRequestJson().containsKey('memo'), false);
    expect(s.toRequestJson().containsKey('public_listing_id'), false);
  });
  testWidgets('ordinary members cannot reach the admin search interface',
      (tester) async {
    final repo = AdminRepo();
    await pump(tester, const PublicSupplierAdminPage(),
        repo: repo, admin: false);
    expect(repo.searches, 0);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('관리자 로그인과 2단계 인증이 필요합니다.'), findsOneWidget);
  });
  testWidgets(
      'web search returns selectable candidates without automatically saving',
      (tester) async {
    final repo = AdminRepo();
    await pump(tester, const PublicSupplierAdminPage(), repo: repo);
    await tester.tap(find.text('인터넷 검색'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '전국 채소 도매');
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    expect(repo.discoveries, 1);
    expect(repo.publishes, 0);
    expect(repo.saves, 0);
    expect(find.text('저장 전 검색 결과'), findsOneWidget);
  });
  testWidgets('publishing requires explicit review of selected businesses',
      (tester) async {
    final repo = AdminRepo();
    await pump(tester, const PublicSupplierAdminPage(), repo: repo);
    final check = find.byKey(const ValueKey('select-listing'));
    await tester.ensureVisible(check);
    await tester.tap(check);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '선택한 업체 공개 저장 · 1'));
    await tester.pumpAndSettle();
    final publish = find.widgetWithText(FilledButton, '공개 저장');
    expect(tester.widget<FilledButton>(publish).onPressed, isNull);
    expect(repo.publishes, 0);
    final review = find.widgetWithText(
        CheckboxListTile, '모든 선택 업체의 공식 출처·취급 품목·배송 조건을 확인했습니다.');
    await tester.ensureVisible(review);
    await tester.tap(review);
    await tester.pumpAndSettle();
    await tester.tap(publish);
    await tester.pumpAndSettle();
    expect(repo.publishes, 1);
  });
  for (final language in ['ko', 'en']) {
    testWidgets(
        'public source card and edit dialog fit narrow large-text $language screens',
        (tester) async {
      await pump(
          tester,
          const Scaffold(
              body: SingleChildScrollView(
                  child: PublicSupplierCard(supplier: listing))),
          language: language,
          size: const Size(390, 844),
          scale: 1.3);
      expect(tester.takeException(), isNull);
      await pump(tester,
          const Scaffold(body: PublicSupplierEditDialog(supplier: listing)),
          language: language, size: const Size(390, 844), scale: 1.3);
      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsWidgets);
    });
  }
}
