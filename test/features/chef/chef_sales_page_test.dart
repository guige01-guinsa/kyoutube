import 'package:k_youtube/features/chef/data/chef_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:k_youtube/core/theme/app_theme.dart';
import 'package:k_youtube/features/chef/data/chef_repository.dart';
import 'package:k_youtube/features/chef/data/chef_sales_repository.dart';
import 'package:k_youtube/features/chef/domain/chef_recipe.dart';
import 'package:k_youtube/features/chef/domain/chef_sales.dart';
import 'package:k_youtube/features/chef/presentation/chef_sales_page.dart';
import 'chef_workbench_test.dart' as fixture;
import 'chef_cost_items_test.dart' show reveal;
import 'package:k_youtube/features/auth/application/auth_providers.dart';

class MemorySales extends ChefSalesRepository {
  final rows = <ChefSale>[];
  bool fail = false;
  final changes = <String>[];
  ChefSalesRange? lastRange;
  List<ChefSale> selected(ChefSalesRange range, String currency) => rows
      .where((s) =>
          !s.voided &&
          !s.date.isBefore(range.from) &&
          s.date.isBefore(range.until) &&
          s.currency == currency)
      .toList();
  @override
  Future<ChefSalesTotals> totals(ChefSalesRange range, String currency,
      {String? recipeId}) async {
    if (fail) throw StateError('Offline');
    lastRange = range;
    final selectedRows = selected(range, currency);
    return ChefSalesTotals(
        quantity: selectedRows.fold(0, (sum, s) => sum + s.quantity),
        revenue: selectedRows.fold(0.0, (sum, s) => sum + s.revenue),
        cost:
            selectedRows.fold(0.0, (sum, s) => sum + s.quantity * s.unitCost));
  }

  @override
  Future<List<ChefSale>> list(ChefSalesRange range, String currency,
          {String? recipeId, int? beforeId}) async =>
      selected(range, currency)
          .reversed
          .where((s) => beforeId == null || s.id < beforeId)
          .take(50)
          .toList();
  @override
  Future<void> record(String recipeId, int revision, DateTime date,
      int quantity, String requestKey) async {
    rows.add(ChefSale(
        id: rows.length + 1,
        date: date,
        title: 'Carrots',
        quantity: quantity,
        unitPrice: 3375,
        unitCost: 2250,
        currency: 'KRW'));
  }

  @override
  Future<void> update(int id, DateTime date, int quantity) async {
    final index = rows.indexWhere((s) => s.id == id),
        old = rows.firstWhere((s) => s.id == id);
    rows[index] = ChefSale(
        id: id,
        date: date,
        title: old.title,
        quantity: quantity,
        unitPrice: old.unitPrice,
        unitCost: old.unitCost,
        currency: old.currency);
  }

  @override
  Future<void> correct(
      ChefSale sale, DateTime date, int quantity, String reason) async {
    if (reason.isEmpty) throw StateError('Reason missing');
    changes.add('correct:$reason');
    await update(sale.id, date, quantity);
  }

  @override
  Future<void> setVoided(ChefSale sale, bool voided, String reason) async {
    if (reason.isEmpty) throw StateError('Reason missing');
    changes.add('${voided ? 'void' : 'restore'}:$reason');
    final i = rows.indexWhere((r) => r.id == sale.id),
        r = rows.firstWhere((r) => r.id == sale.id);
    rows[i] = ChefSale(
        id: r.id,
        date: r.date,
        title: r.title,
        quantity: r.quantity,
        unitPrice: r.unitPrice,
        unitCost: r.unitCost,
        currency: r.currency,
        revision: r.revision + 1,
        voided: voided);
  }

  @override
  Future<List<ChefSale>> voidedSales(ChefSalesRange range, String currency,
          {String? recipeId, int? beforeId}) async =>
      rows.where((r) => r.voided).toList();
  @override
  Future<List<Map<String, dynamic>>> history(int id) async => [];
  @override
  Future<void> remove(int id) async {
    rows.removeWhere((s) => s.id == id);
  }
}

Future<void> showSales(WidgetTester tester, String lang, MemorySales sales,
    {double scale = 1}) async {
  final work = fixture.MemoryChefRepository(ChefRecipe.fromJson(
      {...fixture.example(lang).toJson(), 'markupPercent': 50}));
  await tester.pumpWidget(ProviderScope(
      overrides: [
        activeAccountIdProvider.overrideWithValue('sales-owner'),
        chefPaidAccessProvider.overrideWith((ref) async => true),
        chefRepositoryProvider.overrideWithValue(work),
        chefSalesRepositoryProvider.overrideWithValue(sales),
      ],
      child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          locale: Locale(lang),
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
              child: child!),
          home: const ChefSalesPage(recipeId: 'test'))));
  await tester.pumpAndSettle();
}

void main() {
  for (final lang in ['ko', 'en']) {
    testWidgets('$lang sales periods remain usable at 320px and double text',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = MemorySales();
      await showSales(tester, lang, repo, scale: 2);
      await tester.tap(find.text(lang == 'en' ? 'Weekly' : '주별'));
      await tester.pumpAndSettle();
      expect(repo.lastRange!.from.weekday, 1);
      await tester.tap(find.text(lang == 'en' ? 'Monthly' : '월별'));
      await tester.pumpAndSettle();
      expect(repo.lastRange!.from.day, 1);
      expect(repo.lastRange!.until.day, 1);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'corrects with reason and reversibly voids sale without changing price',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = MemorySales();
    await showSales(tester, 'en', repo);
    final record = find.text('Record servings sold');
    await reveal(tester, record);
    await tester.tap(record);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextFormField)),
        '10');
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();
    expect(repo.rows.single.revenue, 33750);
    final edit = find.text('Edit sale');
    await reveal(tester, edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    final fields = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextFormField));
    await tester.enterText(fields.first, '12');
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();
    expect(repo.rows.single.quantity, 10);
    expect(find.text('Enter a reason.'), findsOneWidget);
    await tester.enterText(fields.last, 'Counted again');
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();
    expect(repo.rows.single.quantity, 12);
    expect(repo.rows.single.unitPrice, 3375);
    await reveal(tester, find.byTooltip('Manage'));
    await tester.tap(find.byTooltip('Manage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Void sale'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Duplicate entry');
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();
    expect(repo.rows.single.voided, true);
    expect(repo.changes, ['correct:Counted again', 'void:Duplicate entry']);
    await reveal(tester, find.text('Show voided sales'));
    await tester.tap(find.text('Show voided sales'));
    await tester.pumpAndSettle();
    await reveal(tester, find.byTooltip('Manage'));
    await tester.tap(find.byTooltip('Manage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore sale'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Valid sale');
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();
    expect(repo.rows.single.voided, false);
    expect(repo.rows.single.unitPrice, 3375);
    expect(tester.takeException(), isNull);
  });
  testWidgets('failed sales query shows recovery without healthy zero totals',
      (tester) async {
    await showSales(tester, 'en', MemorySales()..fail = true);
    expect(
        find.text(
            'Could not process sales information. Reload and check your records.'),
        findsOneWidget);
    expect(find.text('Revenue'), findsNothing);
    expect(find.byTooltip('Reload'), findsOneWidget);
  });
}
