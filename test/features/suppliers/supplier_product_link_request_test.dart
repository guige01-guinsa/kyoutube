import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/shopping/data/supplier_request_repository.dart';
import 'package:k_youtube/features/shopping/domain/supplier_request.dart';
import 'package:k_youtube/features/shopping/presentation/supplier_request_editor.dart';
import 'package:k_youtube/features/suppliers/data/supplier_catalog_repository.dart';
import 'supplier_product_link_test.dart' show LinkRepo;
import '../shopping/supplier_request_widget_test.dart' show RequestRepo;

class ImportRepo extends LinkRepo {
  int imports = 0;
  @override
  Future<ShoppingSupplier> selectPublicReference(String id) async {
    imports++;
    return const ShoppingSupplier(
        id: 'saved-direct',
        name: 'Test Foods',
        publicListingId: 'direct',
        website: 'https://food.example.com');
  }
}

Future<void> openEditor(
    WidgetTester tester, ImportRepo repo, RequestRepo requests,
    {List<ShoppingSupplier> suppliers = const []}) async {
  tester.view.physicalSize = const Size(1000, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        activeAccountIdProvider.overrideWithValue('owner'),
        supplierCatalogRepositoryProvider.overrideWithValue(repo),
        supplierRequestRepositoryProvider.overrideWithValue(requests),
      ],
      child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: const [Locale('en'), Locale('ko')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home:
              SupplierRequestEditor(suppliers: suppliers, groups: const []))));
  await tester.pumpAndSettle();
}

Future<void> enterLink(WidgetTester tester, String url) async {
  final add = find.text('Connect supplier and add item from link');
  await tester.ensureVisible(add);
  await tester.tap(add);
  await tester.pumpAndSettle();
  await tester.enterText(
      find
          .descendant(
              of: find.byType(AlertDialog), matching: find.byType(TextField))
          .first,
      url);
  await tester.tap(find.text('Find supplier'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Add item for this supplier'));
  await tester.pumpAndSettle();
}

Future<void> completeItem(WidgetTester tester, String name) async {
  final fields = find.descendant(
      of: find.byType(SupplierRequestLineEditor),
      matching: find.byType(TextFormField));
  await tester.enterText(fields.at(0), name);
  await tester.enterText(fields.at(1), '2');
  await tester.enterText(fields.at(2), 'box');
  await tester.tap(find.text('Confirm'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('adds two products to one imported supplier and saves links',
      (tester) async {
    final repo = ImportRepo();
    final requests = RequestRepo();
    await openEditor(tester, repo, requests);
    await enterLink(tester, 'https://food.example.com/p/1');
    expect(repo.imports, 0);
    await completeItem(tester, 'Carrots');
    expect(repo.imports, 1);
    await enterLink(tester, 'https://m.food.example.com/p/2');
    await completeItem(tester, 'Onions');
    expect(repo.imports, 1);
    final buyer = find.widgetWithText(TextFormField, 'Buyer or business name');
    await tester.ensureVisible(buyer);
    await tester.enterText(buyer, 'Kitchen');
    await tester.tap(find.text('Save and preview'));
    await tester.pumpAndSettle();
    expect(requests.saves, hasLength(1));
    expect(requests.saves.single.supplier.id, 'saved-direct');
    expect(requests.saves.single.lines.map((l) => l.productUrl),
        ['https://food.example.com/p/1', 'https://m.food.example.com/p/2']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel item creation does not register supplier',
      (tester) async {
    final repo = ImportRepo();
    await openEditor(tester, repo, RequestRepo());
    await enterLink(tester, 'https://food.example.com/p/1');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.imports, 0);
    expect(find.text('Test Foods'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
