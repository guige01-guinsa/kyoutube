import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/business/data/business_menu_fast_repository.dart';
import 'package:k_youtube/features/business/data/business_menu_repository.dart';
import 'package:k_youtube/features/business/domain/business_inventory.dart';
import 'package:k_youtube/features/suppliers/domain/supplier_catalog.dart';
import 'business_flow_test.dart' show MemoryBusiness, pumpBusiness;
import 'business_menu_test.dart' show MenuMemory;
import 'business_menu_fast_test.dart' show FastMemory;

class ManagedPlans extends FastMemory {
  final plans = <Map<String, dynamic>>[
    {
      'id': 'plan-one',
      'name': 'Monday',
      'revision': 4,
      'archived': false,
      'sources': <Map<String, dynamic>>[
        {'kind': 'menu', 'id': 'menu', 'revision': 2, 'servings': 4}
      ],
    }
  ];
  final changes = <String>[];
  @override
  Future<List<Map<String, dynamic>>> templates(String workspace) async =>
      plans.map((r) => Map<String, dynamic>.from(r)).toList();
  @override
  Future<void> manageTemplate(
      String workspace, String id, int revision, String action,
      {String? name}) async {
    final p = plans.firstWhere((r) => r['id'] == id);
    if (p['revision'] != revision) throw StateError('BUSINESS_STALE');
    changes.add(action);
    if (action == 'rename') p['name'] = name;
    if (action != 'rename') p['archived'] = action == 'archive';
    p['revision'] = revision + 1;
  }

  @override
  Future<void> updateTemplate(String workspace, String id, int revision,
      String name, List<Map<String, dynamic>> sources) async {
    final p = plans.firstWhere((r) => r['id'] == id);
    if (p['revision'] != revision) throw StateError('BUSINESS_STALE');
    changes.add('update:$id:$revision');
    p.addAll({'name': name, 'sources': sources, 'revision': revision + 1});
  }

  @override
  Future<void> saveTemplate(String workspace, String id, String name,
      List<Map<String, dynamic>> sources) async {
    changes.add('copy');
    plans.add({
      'id': id,
      'name': name,
      'sources': sources,
      'revision': 1,
      'archived': false
    });
  }
}

Future<void> tapText(WidgetTester t, String text) async {
  final f = find.text(text).last;
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  test(
      'catalog copy retains pack and supplier but requires a fresh price and publication',
      () {
    final original = CatalogProduct(
        id: 'old',
        supplierId: 'supplier',
        name: '진간장',
        contentQuantity: 1,
        contentUnit: 'l',
        saleUnit: '병',
        imagePath: 'owned/photo.png',
        revision: 8,
        active: true,
        price: 12000,
        priceValidUntil: DateTime(2026, 10, 30));
    final copy = original.draftCopy('new');
    expect(copy.id, 'new');
    expect(copy.revision, 0);
    expect(copy.active, false);
    expect(copy.price, isNull);
    expect(copy.priceValidUntil, isNull);
    expect(copy.supplierId, original.supplierId);
    expect(copy.contentQuantity, 1);
    expect(copy.contentUnit, 'l');
    expect(copy.imagePath, original.imagePath);
    expect(original.active, true);
    expect(original.price, 12000);
  });
  test('stock metadata does not replace identity, units or balances', () {
    final s = BusinessStockItem.fromJson({
      'id': 'i',
      'name': '진간장',
      'spec': '',
      'unit': 'ml',
      'on_hand': 500,
      'reserved': 100,
      'available': 400,
      'management_note': '선반 2',
      'management_revision': 3
    });
    expect(findStockItems([s], '선반 2').single.id, 'i');
    expect(s.unit, 'ml');
    expect(s.available, 400);
    expect(s.managementRevision, 3);
  });
  testWidgets('saved plan edits original with revision and copies under new id',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final base = MemoryBusiness(
            {'recipes.read', 'purchasing.read', 'purchasing.write'}),
        plans = ManagedPlans();
    await pumpBusiness(tester, base,
        locale: 'en',
        initial: '/business-workspaces/shop/menu-fast',
        overrides: [
          businessMenuRepositoryProvider.overrideWithValue(MenuMemory(base)),
          businessMenuFastRepositoryProvider.overrideWithValue(plans),
        ]);
    await tester.pumpAndSettle();
    await tapText(tester, 'Saved plans');
    await tapText(tester, 'Edit contents');
    await tester.enterText(
        find.byKey(const ValueKey('fast-servings-menu')), '8');
    await tapText(tester, 'Save changes');
    await tapText(tester, 'Save');
    expect(plans.changes, ['update:plan-one:4']);
    expect((plans.plans.single['sources'] as List).single['servings'], 8);
    await tapText(tester, 'Saved plans');
    await tapText(tester, 'Create a copy');
    await tapText(tester, 'Save');
    expect(plans.plans.length, 2);
    expect(plans.plans.last['id'], isNot('plan-one'));
    expect(plans.calls, 0,
        reason: 'Managing definitions must never place an order');
    expect(tester.takeException(), isNull);
  });
  testWidgets('plan archive and restore remain accessible on a narrow screen',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final base = MemoryBusiness(
            {'recipes.read', 'purchasing.read', 'purchasing.write'}),
        plans = ManagedPlans();
    await pumpBusiness(tester, base,
        locale: 'en',
        initial: '/business-workspaces/shop/menu-fast',
        overrides: [
          businessMenuRepositoryProvider.overrideWithValue(MenuMemory(base)),
          businessMenuFastRepositoryProvider.overrideWithValue(plans),
        ]);
    await tester.pumpAndSettle();
    await tapText(tester, 'Saved plans');
    await tester.tap(find.byTooltip('Manage'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Archive');
    await tapText(tester, 'Confirm');
    expect(plans.plans.single['archived'], true);
    await tapText(tester, 'Archived plans');
    expect(find.text('Monday'), findsOneWidget);
    await tester.tap(find.byTooltip('Manage'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Restore');
    await tapText(tester, 'Confirm');
    expect(plans.plans.single['archived'], false);
    expect(plans.changes, ['archive', 'restore']);
    expect(plans.calls, 0);
    expect(tester.takeException(), isNull);
  });
}
