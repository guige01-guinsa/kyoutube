import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/shopping/domain/supplier_request.dart';
import 'package:k_youtube/features/shopping/presentation/supplier_request_editor.dart';
import 'package:k_youtube/features/suppliers/data/supplier_catalog_repository.dart';
import 'package:k_youtube/features/suppliers/domain/public_supplier.dart';
import 'package:k_youtube/features/suppliers/domain/supplier_product_link.dart';
import 'package:k_youtube/features/suppliers/presentation/supplier_product_link_dialog.dart';
import 'supplier_catalog_widget_test.dart' show CatalogRepo;
import '../shopping/supplier_request_widget_test.dart' show RequestRepo;

const direct = PublicSupplier(
    id: 'direct',
    name: 'Test Foods',
    website: 'https://www.food.example.com/',
    status: 'published');
const market = PublicSupplier(
    id: 'market',
    name: 'Test Market',
    website: 'https://market.example.com/',
    status: 'published',
    businessKind: 'marketplace');
const seller = ShoppingSupplier(id: 'seller', name: 'Actual Seller');

class LinkRepo extends CatalogRepo {
  LinkRepo() : super(RequestRepo());
  List<PublicSupplier> references = [direct, market];
  final queries = <String>[];
  Completer<List<PublicSupplier>>? pending;
  @override
  Future<List<PublicSupplier>> publicReferences(
      {String query = '',
      String category = '',
      String region = '',
      int offset = 0}) async {
    queries.add(query);
    return pending == null
        ? references.skip(offset).take(30).toList()
        : pending!.future;
  }
}

Future<void> pumpDialog(WidgetTester tester, LinkRepo repo,
    {List<ShoppingSupplier> suppliers = const [],
    ValueChanged<SupplierProductLinkSelection>? selected}) async {
  tester.view.physicalSize = const Size(900, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        activeAccountIdProvider.overrideWithValue('owner'),
        supplierCatalogRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: const [Locale('en'), Locale('ko')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        final result =
                            await showDialog<SupplierProductLinkSelection>(
                                context: context,
                                builder: (_) => SupplierProductLinkDialog(
                                    suppliers: suppliers,
                                    createSupplier: () async => seller));
                        if (result != null) selected?.call(result);
                      },
                      child: const Text('Open')))))));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  test('matches only approved hosts and explicit mobile/desktop aliases', () {
    expect(suppliersForProductLink('https://m.food.example.com/p/42', [direct]),
        [direct]);
    for (final link in [
      'https://www.food.example.com.evil.com/p',
      'https://evil.com/?next=https://www.food.example.com',
      'https://food.example.com@evil.com/p',
      'https://sub.food.example.com/p',
      'http://food.example.com/p',
      'javascript:alert(1)',
      'https://127.0.0.1/p',
    ]) {
      expect(suppliersForProductLink(link, [direct]), isEmpty, reason: link);
    }
    expect(
        suppliersForProductLink('https://food.example.com/p', [
          const PublicSupplier(
              id: 'hidden',
              website: 'https://food.example.com/',
              status: 'hidden')
        ]),
        isEmpty);
  });

  test('request product links survive storage and repeat without stale prices',
      () {
    const line = SupplierRequestLine(
        id: 'line',
        name: 'Carrots',
        quantity: 2,
        unit: 'box',
        spec: '10 kg',
        price: 100,
        productUrl: 'https://food.example.com/p/42');
    final read = SupplierRequestLine.fromJson(line.toJson());
    expect(read.productUrl, line.productUrl);
    expect(read.copyForRepeat().productUrl, line.productUrl);
    expect(read.copyForRepeat().price, isNull);
    expect(read.details, contains(line.productUrl));
    expect(
        SupplierRequestLine.fromJson({...line.toJson(), 'product_url': 2})
            .productUrl,
        '');
    expect(
        SupplierRequestLine.fromJson(
                {...line.toJson(), 'product_url': 'javascript:alert(1)'})
            .productUrl,
        '');
    expect(
        SupplierRequestLine.fromJson({...line.toJson()}..remove('product_url'))
            .productUrl,
        '');
  });

  testWidgets(
      'direct link recommends company without registering before confirmation',
      (tester) async {
    final repo = LinkRepo();
    SupplierProductLinkSelection? result;
    await pumpDialog(tester, repo, selected: (v) => result = v);
    await tester.enterText(
        find.byType(TextField), 'https://m.food.example.com/p/42');
    await tester.tap(find.text('Find supplier'));
    await tester.pumpAndSettle();
    expect(find.text('Test Foods'), findsOneWidget);
    expect(repo.queries, ['food.example.com']);
    expect(repo.selected, isEmpty);
    await tester.tap(find.text('Add item for this supplier'));
    await tester.pumpAndSettle();
    expect(result?.reference?.id, direct.id);
    expect(result?.url, 'https://m.food.example.com/p/42');
    expect(repo.selected, isEmpty);
  });

  testWidgets(
      'marketplace requires actual seller and never auto-selects platform',
      (tester) async {
    final repo = LinkRepo();
    SupplierProductLinkSelection? result;
    await pumpDialog(tester, repo,
        suppliers: [
          seller,
          const ShoppingSupplier(
              id: 'platform',
              name: 'Platform',
              publicListingId: 'market',
              website: 'https://market.example.com')
        ],
        selected: (v) => result = v);
    await tester.enterText(
        find.byType(TextField), 'https://market.example.com/p/2');
    await tester.tap(find.text('Find supplier'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('Platform'), findsNothing);
    await tester.tap(find.text('Actual Seller').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add item for this supplier'));
    await tester.pumpAndSettle();
    expect(result?.supplier?.id, 'seller');
  });

  testWidgets('editing URL invalidates pending results', (tester) async {
    final repo = LinkRepo()..pending = Completer<List<PublicSupplier>>();
    await pumpDialog(tester, repo);
    await tester.enterText(
        find.byType(TextField), 'https://food.example.com/p/1');
    await tester.tap(find.text('Find supplier'));
    await tester.pump();
    await tester.enterText(
        find.byType(TextField), 'https://unknown.example.com/p/1');
    repo.pending!.complete([direct]);
    await tester.pumpAndSettle();
    expect(find.text('Test Foods'), findsNothing);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
  });

  testWidgets('item editor preserves product URL on manual edits',
      (tester) async {
    SupplierRequestLine? result;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      result = await showDialog<SupplierRequestLine>(
                          context: context,
                          builder: (_) => const SupplierRequestLineEditor(
                              currency: 'KRW',
                              line: SupplierRequestLine(
                                  id: 'line',
                                  name: 'Carrots',
                                  quantity: 2,
                                  unit: 'box',
                                  productUrl:
                                      'https://food.example.com/p/42')));
                    },
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(result?.productUrl, 'https://food.example.com/p/42');
  });
}
