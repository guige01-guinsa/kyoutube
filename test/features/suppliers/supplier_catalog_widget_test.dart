import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:k_youtube/core/router/app_router.dart';
import 'package:k_youtube/core/theme/app_theme.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/kitchen/application/kitchen_providers.dart';
import 'package:k_youtube/features/kitchen/domain/kitchen_models.dart';
import 'package:k_youtube/features/shopping/data/supplier_request_repository.dart';
import 'package:k_youtube/features/shopping/domain/supplier_request.dart';
import 'package:k_youtube/features/shopping/presentation/supplier_request_editor.dart';
import 'package:k_youtube/features/suppliers/data/supplier_catalog_repository.dart';
import 'package:k_youtube/features/suppliers/domain/supplier_catalog.dart';
import 'package:k_youtube/features/suppliers/presentation/supplier_business_page.dart';
import 'package:k_youtube/features/suppliers/presentation/supplier_directory_page.dart';
import 'package:k_youtube/features/suppliers/presentation/procurement_plan_page.dart';
import '../shopping/supplier_request_widget_test.dart' show RequestRepo;

class CatalogRepo extends SupplierCatalogRepository {
  CatalogRepo(this.personal);
  final RequestRepo personal;
  final selected = <String>{};
  CatalogSupplier? business;
  Map<String, String> lastFilters = {};
  final rows = [
    for (var i = 0; i < 4; i++)
      SupplierOffer(
          CatalogSupplier(
              id: 'vendor$i',
              name: 'Supplier $i',
              published: true,
              region: '서울',
              deliveryRegions: const ['전국'],
              shippingFee: 0),
          CatalogProduct(
              id: 'product$i',
              supplierId: 'vendor$i',
              name: '양파',
              imagePath: 'photo$i',
              price: 10 + i.toDouble(),
              priceValidUntil: DateTime(2099),
              contentUnit: 'kg'))
  ];
  @override
  Future<CatalogSupplier?> myBusiness() async => business;
  @override
  Future<List<CatalogProduct>> myProducts(String supplierId) async => [];
  @override
  Future<CatalogSupplier> saveBusiness(CatalogSupplier supplier) async =>
      business = supplier;
  @override
  Future<CatalogProduct> saveProduct(CatalogProduct product) async => product;
  @override
  Future<List<SupplierOffer>> search(
      {String query = '',
      String category = '',
      String subcategory = '',
      String region = '',
      String origin = '',
      String brand = '',
      bool priced = false,
      bool verified = false,
      bool rated = false,
      int offset = 0}) async {
    lastFilters = {
      'query': query,
      'category': category,
      'subcategory': subcategory,
      'region': region,
      'origin': origin,
      'brand': brand
    };
    return rows.skip(offset).toList()
      ..sort((a, b) => (selected.contains(b.supplier.id) ? 1 : 0)
          .compareTo(selected.contains(a.supplier.id) ? 1 : 0));
  }

  @override
  Future<List<SupplierOffer>> currentOffers(List<String> ids) async =>
      rows.where((r) => ids.contains(r.product.id)).toList();
  @override
  Future<ShoppingSupplier> selectSupplier(String id) async {
    selected.add(id);
    final supplier = ShoppingSupplier(
        id: 'personal-$id',
        name: rows.firstWhere((o) => o.supplier.id == id).supplier.name,
        catalogSupplierId: id);
    if (!personal.directory.any((s) => s.id == supplier.id)) {
      personal.directory.add(supplier);
    }
    return supplier;
  }

  @override
  Future<String> imageUrl(String path) async =>
      throw StateError('Fixture image intentionally unavailable');
  @override
  Future<void> discardImage(String path) async {}
  @override
  Future<String> uploadImage(String supplierId, Uint8List bytes) async =>
      'fixture.jpg';
  @override
  Future<void> rate(String requestId, int stars, String note) async {}
}

Future<void> pumpCatalog(WidgetTester tester, Widget home, CatalogRepo catalog,
    {String language = 'ko',
    double scale = 1.0,
    Size size = const Size(390, 844),
    GoRouter? router}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        activeAccountIdProvider.overrideWith((_) => 'buyer'),
        supplierCatalogRepositoryProvider.overrideWithValue(catalog),
        supplierRequestRepositoryProvider.overrideWithValue(catalog.personal),
        kitchenShoppingListsProvider.overrideWith((_) async => [
              KitchenShoppingList(
                  id: 'list',
                  status: 'active',
                  title: 'Recipe shopping',
                  openItemCount: 1,
                  items: [
                    KitchenShoppingItem(
                        id: 'ingredient',
                        listId: 'list',
                        name: '양파',
                        ingredientText: 'Original cooking text',
                        status: KitchenShoppingItemStatus.pending,
                        reviewStatus: KitchenShoppingItemReviewStatus.confirmed,
                        needsReview: false,
                        isChecked: false,
                        revision: 1,
                        updatedAt: DateTime(2026),
                        quantity: 1,
                        unit: 'kg')
                  ])
            ])
      ],
      child: router != null
          ? MaterialApp.router(
              routerConfig: router,
              theme: AppTheme.light,
              locale: Locale(language),
              supportedLocales: const [Locale('ko'), Locale('en')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates)
          : MaterialApp(
              theme: AppTheme.light,
              locale: Locale(language),
              supportedLocales: const [Locale('ko'), Locale('en')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: home)));
  await tester.pumpAndSettle();
}

Future<void> visible(WidgetTester tester, Finder finder) async {
  bool present() {
    try {
      return finder.evaluate().isNotEmpty;
    } on StateError {
      return false;
    }
  }

  for (var i = 0; i < 60 && !present(); i++) {
    await tester.drag(find.byType(ListView).last, const Offset(0, -220));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  for (final lang in ['ko', 'en']) {
    testWidgets(
        '$lang directory selection adds my supplier and returns the personal record',
        (tester) async {
      final catalog = CatalogRepo(RequestRepo()..directory.clear());
      ShoppingSupplier? picked;
      await pumpCatalog(
          tester,
          SupplierDirectoryPage(
              selectMode: true, onSelected: (s) => picked = s),
          catalog,
          language: lang,
          scale: 1.4);
      final filters = find.text(
          lang == 'ko' ? '분류·지역·브랜드 조건' : 'Category, region & brand filters');
      final category = find.text(lang == 'ko' ? '품목 대분류' : 'Category');
      expect(
          find.byKey(const ValueKey('supplier-business-entry')).hitTestable(),
          findsOneWidget);
      await visible(tester, category);
      expect(category, findsOneWidget);
      await visible(tester, filters);
      await tester.tap(filters);
      await tester.pumpAndSettle();
      expect(category.hitTestable(), findsNothing);
      final choose =
          find.text(lang == 'ko' ? '이 업체 선택' : 'Select supplier').first;
      await visible(tester, choose);
      await tester.tap(choose);
      await tester.pumpAndSettle();
      expect(picked?.catalogSupplierId, 'vendor0');
      expect(catalog.personal.directory.length, 1);
      expect(tester.takeException(), isNull);
    });

    for (final layout in [
      (const Size(390, 844), 1.0, 390.0),
      (const Size(1557, 900), 1.0, 950.0),
      (const Size(320, 844), 2.0, 320.0),
    ]) {
      testWidgets(
          '$lang supplier filters have separate readable labels at $layout',
          (tester) async {
        final catalog = CatalogRepo(RequestRepo());
        await pumpCatalog(
            tester,
            Center(
                child: SizedBox(
                    width: layout.$3,
                    child: const SupplierDirectoryPage(selectMode: true))),
            catalog,
            language: lang,
            size: layout.$1,
            scale: layout.$2);
        expect(
            catalog.lastFilters.values.every((value) => value.isEmpty), isTrue);
        await visible(tester, find.byType(ExpansionTile));
        expect(
            tester
                .widget<ExpansionTile>(find.byType(ExpansionTile))
                .initiallyExpanded,
            isTrue);
        for (final label in lang == 'ko'
            ? ['품목 대분류', '소분류', '배송 지역', '원산지']
            : ['Category', 'Subcategory', 'Delivery region', 'Origin']) {
          final text = find.text(label);
          await visible(tester, text);
          final field =
              find.ancestor(of: text, matching: find.byType(Column)).first;
          final input = find.descendant(
              of: field,
              matching: find.byType(DropdownButtonFormField<String>));
          final labelRect = tester.getRect(text),
              inputRect = tester.getRect(input);
          expect(inputRect.top - labelRect.bottom, greaterThanOrEqualTo(7.9));
          final directory = tester.getRect(find.byType(SupplierDirectoryPage));
          expect(inputRect.left, greaterThanOrEqualTo(directory.left));
          expect(inputRect.right, lessThanOrEqualTo(directory.right));
          expect(tester.takeException(), isNull);
        }
      });
    }

    testWidgets('$lang existing supplier sees business management entry',
        (tester) async {
      final catalog = CatalogRepo(RequestRepo())
        ..business = const CatalogSupplier(id: 'own', name: 'Own supplier');
      await pumpCatalog(
          tester, const SupplierDirectoryPage(selectMode: true), catalog,
          language: lang);
      expect(
          find
              .text(
                  lang == 'ko' ? '내 업체·상품 관리' : 'Manage my business & products')
              .hitTestable(),
          findsOneWidget);
    });
  }

  testWidgets(
      'business registration opens above the request picker and returns with its search intact',
      (tester) async {
    final catalog = CatalogRepo(RequestRepo());
    final router = AppRouter.router;
    router.go('/supplier-directory');
    await pumpCatalog(tester, const SizedBox.shrink(), catalog, router: router);
    final context = tester.element(find.byType(SupplierDirectoryPage));
    showDialog<void>(
        context: context,
        builder: (_) => const Dialog.fullscreen(
            child: SupplierDirectoryPage(selectMode: true, query: '양파')));
    await tester.pumpAndSettle();
    await tester.tap(
        find.byKey(const ValueKey('supplier-business-entry')).hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('업체 정보 입력').hitTestable(), findsOneWidget);
    await tester.tap(find.text('업체 정보 입력'));
    await tester.pumpAndSettle();
    expect(find.text('업체 정보 저장').hitTestable(), findsOneWidget);
    Navigator.of(tester.element(find.text('업체 정보 저장'))).pop();
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('양파').hitTestable(), findsOneWidget);
    expect(find.byKey(const ValueKey('supplier-business-entry')).hitTestable(),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'supplier selection works from an empty request editor and populates dropdown',
      (tester) async {
    final catalog = CatalogRepo(RequestRepo()..directory.clear());
    await pumpCatalog(
        tester,
        Builder(
            builder: (context) => Scaffold(
                body: FilledButton(
                    onPressed: () => showDialog(
                        context: context,
                        builder: (_) => const SupplierRequestEditor(
                            suppliers: [], groups: [])),
                    child: const Text('Open')))),
        catalog);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('공개 업체에서 선택 · 내 거래처 등록'));
    await tester.pumpAndSettle();
    final choose = find.text('이 업체 선택').first;
    await visible(tester, choose);
    await tester.tap(choose);
    await tester.pumpAndSettle();
    expect(find.byType(SupplierDirectoryPage), findsNothing);
    expect(
        tester
            .widget<DropdownButton<String>>(
                find.byType(DropdownButton<String>).first)
            .value,
        'personal-vendor0');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'candidate limit is per ingredient, criterion follows selection, draft saves only after editing',
      (tester) async {
    final catalog = CatalogRepo(RequestRepo()..directory.clear());
    await pumpCatalog(tester, const ProcurementPlanPage(), catalog);
    expect(find.text('최저 구매가격'), findsNothing);
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('다음: 업체·기준 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('업체 후보 0/3'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      final tile = find.byWidgetPredicate(
          (w) => w is SupplierOfferCard && w.offer.supplier.id == 'vendor$i');
      await visible(tester, tile);
      final check =
          find.descendant(of: tile, matching: find.byType(CheckboxListTile));
      await visible(tester, check);
      await tester.tap(check);
      await tester.pumpAndSettle();
    }
    expect(find.text('이 재료의 후보는 최대 3개 업체입니다.'), findsWidgets);
    await tester.tap(find.text('3곳 선택 완료 · 내 거래처에 등록'));
    await tester.pumpAndSettle();
    expect(catalog.selected, {'vendor0', 'vendor1', 'vendor2'});
    await visible(tester, find.text('이전: 재료 선택'));
    await tester.tap(find.text('이전: 재료 선택'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
            .value,
        isTrue);
    await tester.tap(find.text('다음: 업체·기준 선택'));
    await tester.pumpAndSettle();
    await visible(tester, find.text('업체 후보 3/3'));
    expect(find.text('업체 후보 3/3'), findsOneWidget);

    expect(catalog.personal.saves, isEmpty);
    await visible(tester, find.text('최저 구매가격'));
    expect(find.text('최저 구매가격'), findsOneWidget);
    await tester.tap(find.text('최저 구매가격'));
    await tester.tap(find.text('구매요청서 초안 만들기'));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await tester.pumpAndSettle();
    expect(find.text('초안 수정·저장'), findsOneWidget);
    expect(catalog.personal.saves, isEmpty);
    await tester.tap(find.text('초안 수정·저장'));
    await tester.pumpAndSettle();
    expect(find.byType(SupplierRequestEditor), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextFormField, '요청자 또는 사업장명'), 'Test kitchen');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장하고 미리보기'));
    await tester.pumpAndSettle();
    expect(catalog.personal.saves.length, 1);
    expect(catalog.personal.saves.single.lines.length, 1);
    expect(find.text('요청서 저장됨'), findsOneWidget);
    final preview = find.text('미리보기·발송');
    await visible(tester, preview);
    await tester.tap(preview);
    await tester.pumpAndSettle();
    final sent = find.text('전달 확인');
    await visible(tester, sent);
    await tester.tap(sent);
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();
    expect(find.text('저장된 초안 수정'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'business registration begins private and requires basic information',
      (tester) async {
    final catalog = CatalogRepo(RequestRepo());
    await pumpCatalog(tester, const SupplierBusinessPage(), catalog);
    expect(find.text('공개하면 무료·유료 구분 없이 로그인한 모든 회원이 업체와 상품을 볼 수 있습니다.'),
        findsOneWidget);
    await tester.tap(find.text('업체 정보 입력'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('업체 정보 저장'));
    await tester.pumpAndSettle();
    expect(catalog.business, isNull);
    expect(find.text('필수 항목입니다.'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
