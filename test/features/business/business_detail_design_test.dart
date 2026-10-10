import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:k_youtube/features/business/data/business_supplier_repository.dart';
import 'business_supplier_test.dart' show SupplierMemory;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/business/data/business_inventory_repository.dart';
import 'package:k_youtube/features/business/data/business_menu_repository.dart';
import 'package:k_youtube/features/business/data/business_menu_fast_repository.dart';
import 'package:k_youtube/features/business/domain/business_workspace.dart';
import 'business_flow_test.dart' show MemoryBusiness, pumpBusiness;
import 'business_inventory_test.dart' show InventoryMemory;
import 'business_menu_test.dart' show MenuMemory;
import 'business_menu_fast_test.dart' show FastMemory;

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('.artifacts/design-complete');
    await directory.create(recursive: true);
    await File('${directory.path}/business-$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    for (final family in ['BusinessPreview', 'RecipeScoutKR']) {
      await (FontLoader(family)
            ..addFont(rootBundle.load('assets/fonts/NanumGothic-Regular.ttf')))
          .load();
    }
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  if (Platform.environment['DESIGN_COMPLETE_CAPTURE'] == 'true') {
    for (final route in [
      'menus',
      'menu-fast',
      'inventory/onion',
      'menu-purchase',
      'suppliers'
    ]) {
      for (final width in [390.0, 1280.0]) {
        testWidgets('business detail visual $route at $width', (tester) async {
          final repo = MemoryBusiness(businessPermissions.toSet());
          final key = GlobalKey();
          await pumpBusiness(tester, repo,
              initial: '/business-workspaces/shop/$route',
              width: width,
              capture: key,
              overrides: [
                businessInventoryRepositoryProvider
                    .overrideWithValue(InventoryMemory()),
                businessMenuRepositoryProvider
                    .overrideWithValue(MenuMemory(repo)),
                businessMenuFastRepositoryProvider
                    .overrideWithValue(FastMemory()),
                businessSupplierRepositoryProvider
                    .overrideWithValue(SupplierMemory()),
              ]);
          expect(tester.takeException(), isNull);
          await _capture(
              tester, key, '${route.replaceAll('/', '-')}-${width.toInt()}');
        });
      }
    }
  }
  for (final locale in ['ko', 'en']) {
    testWidgets(
        'inventory quantities stay separate at 320px with large text ($locale)',
        (tester) async {
      final stock = InventoryMemory();
      final repo = MemoryBusiness(businessRolePermissions['purchasing']!);
      await pumpBusiness(tester, repo,
          initial: '/business-workspaces/shop/inventory/onion',
          width: 320,
          textScale: 2,
          locale: locale,
          overrides: [
            businessInventoryRepositoryProvider.overrideWithValue(stock)
          ]);
      final available = find.text('2000 g');
      await tester.scrollUntilVisible(available, 250,
          scrollable: find.byType(Scrollable).first);
      expect(available, findsOneWidget);
      expect(find.text('2400 g'), findsOneWidget);
      expect(find.text('400 g'), findsOneWidget);
      final reserve =
          find.text(locale == 'ko' ? '조리용 예약' : 'Reserve for cooking');
      await tester.ensureVisible(reserve);
      expect(
          tester
              .widget<FilledButton>(find.ancestor(
                  of: reserve, matching: find.byType(FilledButton)))
              .onPressed,
          isNotNull);
      expect(tester.takeException(), isNull);
      expect(stock.calls, isEmpty);
    });
    testWidgets(
        'quick purchase retains servings across keyboard and review at large text ($locale)',
        (tester) async {
      final repo = MemoryBusiness(
          {'recipes.read', 'purchasing.read', 'purchasing.write'});
      final fast = FastMemory();
      await pumpBusiness(tester, repo,
          initial: '/business-workspaces/shop/menu-fast',
          width: 320,
          textScale: 2,
          locale: locale,
          overrides: [
            businessMenuRepositoryProvider.overrideWithValue(MenuMemory(repo)),
            businessMenuFastRepositoryProvider.overrideWithValue(fast)
          ]);
      final menu = find.widgetWithText(CheckboxListTile, '판매 메뉴');
      await tester.scrollUntilVisible(menu.hitTestable(), 250,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(menu);
      await tester.pumpAndSettle();
      final servings = find.byKey(const ValueKey('fast-servings-menu'));
      await tester.scrollUntilVisible(servings, 160,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.resetViewInsets);
      await tester.enterText(servings, '30');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(servings).controller!.text, '30');
      tester.testTextInput.hide();
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      final calculate = find.text(
          locale == 'ko' ? '재료·구매량 계산' : 'Calculate ingredients and purchases');
      await tester.scrollUntilVisible(calculate.hitTestable(), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(calculate);
      await tester.pumpAndSettle();
      final create = find.text(locale == 'ko'
          ? '업체별 초안 생성·재고 예약'
          : 'Create supplier drafts and reserve stock');
      await tester.scrollUntilVisible(create.hitTestable(), 200,
          scrollable: find.byType(Scrollable).first, maxScrolls: 50);
      expect(
          tester
              .widget<FilledButton>(find.ancestor(
                  of: create, matching: find.byType(FilledButton)))
              .onPressed,
          isNull);
      expect(tester.takeException(), isNull);
      expect(fast.calls, 0);
    });
  }
}
