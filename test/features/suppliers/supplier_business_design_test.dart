import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/suppliers/domain/supplier_catalog.dart';
import 'package:k_youtube/features/suppliers/presentation/supplier_business_page.dart';
import '../shopping/supplier_request_widget_test.dart' show RequestRepo;
import 'supplier_catalog_widget_test.dart'
    show CatalogRepo, pumpCatalog, visible;

class _DesignCatalogRepo extends CatalogRepo {
  _DesignCatalogRepo() : super(RequestRepo()) {
    business = const CatalogSupplier(
      id: 'own',
      name: '제철 식자재 공급업체',
      phone: '02-123-4567',
      region: '서울',
      deliveryRegions: ['서울', '경기'],
      published: true,
    );
  }
  @override
  Future<List<CatalogProduct>> myProducts(String supplierId) async => const [
        CatalogProduct(
            id: 'onion',
            supplierId: 'own',
            name: '국산 양파 10kg',
            imagePath: 'onion.jpg',
            saleUnit: 'box',
            contentUnit: 'kg',
            contentQuantity: 10,
            price: 18000),
        CatalogProduct(
            id: 'potato',
            supplierId: 'own',
            name: '국산 감자',
            imagePath: 'potato.jpg',
            active: false),
      ];
}

ThemeData _previewTheme(ThemeData base) => base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: 'TradePreview'),
      primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'TradePreview'),
      appBarTheme: base.appBarTheme.copyWith(
          titleTextStyle: base.appBarTheme.titleTextStyle
              ?.copyWith(fontFamily: 'TradePreview')),
      filledButtonTheme: FilledButtonThemeData(
          style: base.filledButtonTheme.style?.copyWith(
              textStyle: WidgetStatePropertyAll(base.textTheme.labelLarge
                  ?.copyWith(
                      fontFamily: 'TradePreview',
                      fontWeight: FontWeight.w700)))),
    );

void main() {
  if (const bool.fromEnvironment('DESIGN_TRADE_SCREENSHOTS')) {
    for (final size in [const Size(390, 900), const Size(1440, 1000)]) {
      testWidgets('capture supplier design ${size.width}', (tester) async {
        await tester.runAsync(() async {
          await (FontLoader('TradePreview')
                ..addFont(File('C:/Windows/Fonts/malgun.ttf')
                    .readAsBytes()
                    .then(ByteData.sublistView)))
              .load();
          await (FontLoader('MaterialIcons')
                ..addFont(File(
                        '.fvm/flutter_sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
                    .readAsBytes()
                    .then(ByteData.sublistView)))
              .load();
        });
        await pumpCatalog(
            tester,
            RepaintBoundary(
                key: const ValueKey('supplier-design-preview'),
                child: Builder(
                    builder: (context) => Theme(
                        data: _previewTheme(Theme.of(context)),
                        child: const SupplierBusinessPage()))),
            _DesignCatalogRepo(),
            size: size);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('supplier-design-preview')));
        await tester.runAsync(() async {
          final shot = await boundary.toImage(pixelRatio: 1);
          final bytes = await shot.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
              '.artifacts/design-refresh/supplier-${size.width > 1000 ? 'desktop' : 'mobile'}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          shot.dispose();
        });
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final lang in ['ko', 'en']) {
    for (final layout in [
      (const Size(320, 900), 2.0),
      (const Size(1280, 900), 1.0)
    ]) {
      testWidgets(
          '$lang supplier management fits $layout and keeps public scope clear',
          (tester) async {
        await pumpCatalog(
            tester, const SupplierBusinessPage(), _DesignCatalogRepo(),
            language: lang, size: layout.$1, scale: layout.$2);
        final status = find.text(lang == 'ko' ? '공개 중' : 'Published');
        await visible(tester, status);
        expect(status, findsOneWidget);
        expect(
            find.text(lang == 'ko'
                ? '1 업체 정보 → 2 상품과 사진 → 3 공개하기'
                : '1 Business details → 2 Products & photos → 3 Publish'),
            findsNothing);
        await visible(tester, find.text('국산 양파 10kg'));
        expect(tester.takeException(), isNull);
        await visible(tester, find.text('국산 감자'));
        expect(tester.takeException(), isNull);
        final notice = find.text(lang == 'ko'
            ? '공개하면 무료·유료 구분 없이 로그인한 모든 회원이 업체와 상품을 볼 수 있습니다.'
            : 'Once published, your business and products are visible to all signed-in members, on free and paid plans.');
        await visible(tester, notice);
        expect(notice, findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('trade terms remain editable without reopening onboarding',
      (tester) async {
    await pumpCatalog(tester, const SupplierBusinessPage(section: 'terms'),
        _DesignCatalogRepo());
    await visible(tester, find.text('거래조건 수정'));
    expect(find.text('견적 시 확인'), findsNWidgets(2));
    await tester.tap(find.text('거래조건 수정'));
    await tester.pumpAndSettle();
    expect(find.text('업체 정보 저장'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
