import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'chef_workbench_test.dart' as fixture;

Future<void> reveal(WidgetTester tester, Finder finder) async {
  final scroll = find
      .byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down)
      .first;
  for (var i = 0; i < 30 && finder.hitTestable().evaluate().isEmpty; i++) {
    await tester.drag(scroll, const Offset(0, -300));
    await tester.pumpAndSettle();
  }
  expect(finder.hitTestable(), findsOneWidget);
}

void main() {
  testWidgets('selling price slider saves the selected markup', (tester) async {
    final repo = fixture.MemoryChefRepository(fixture.example('en'));
    await fixture.showChef(tester, 'en', repo);
    final slider = find.byType(Slider);
    await reveal(tester, slider);
    await tester.tapAt(tester.getCenter(slider));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save work'));
    await tester.pumpAndSettle();
    expect(repo.document.markupPercent, 50);
    expect(repo.document.sellingPrice, 3375);
  });
  for (final lang in ['ko', 'en']) {
    testWidgets(
        '$lang adds, edits and removes item costs without changing legacy cost',
        (tester) async {
      tester.view.physicalSize = const Size(420, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = fixture.MemoryChefRepository(fixture.example(lang));
      await fixture.showChef(tester, lang, repo);
      final en = lang == 'en';
      final add = find.text(en ? 'Add cost item' : '비용 항목 추가');
      await reveal(tester, add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      await tester.tap(find.text(en ? 'Packaging' : '포장비'));
      await tester.pumpAndSettle();
      final confirm = find.widgetWithText(FilledButton, en ? 'Confirm' : '확인');
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      final amount = find
          .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextFormField))
          .last;
      await tester.enterText(amount, '1,500');
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      await tester.tap(find.text(en ? 'Save work' : '작업 저장'));
      await tester.pumpAndSettle();
      expect(repo.document.extraCost, 1000);
      expect(repo.document.totalExtraCost, 2500);
      expect(repo.document.batchCost, 26250);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(repo.document.costItems.single.name, en ? 'Packaging' : '포장비');
      final row = find
          .ancestor(
              of: find.text(en ? 'Packaging' : '포장비'),
              matching: find.byType(Column))
          .first;
      final edit = find.descendant(
          of: row, matching: find.text(en ? 'Edit cost' : '비용 수정'));
      await tester.ensureVisible(edit);
      await tester.pumpAndSettle();
      expect(edit.hitTestable(), findsOneWidget);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      await tester.enterText(
          find
              .descendant(
                  of: find.byType(AlertDialog),
                  matching: find.byType(TextFormField))
              .last,
          '2000');
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      await tester.tap(find.text(en ? 'Save work' : '작업 저장'));
      await tester.pumpAndSettle();
      expect(repo.document.totalExtraCost, 3000);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      final remove = find.descendant(
          of: row, matching: find.byTooltip(en ? 'Remove cost' : '비용 삭제'));
      await tester.ensureVisible(remove);
      await tester.pumpAndSettle();
      expect(remove.hitTestable(), findsOneWidget);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      await tester
          .tap(find.widgetWithText(FilledButton, en ? 'Remove cost' : '비용 삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en ? 'Save work' : '작업 저장'));
      await tester.pumpAndSettle();
      expect(repo.document.costItems, isEmpty);
      expect(repo.document.extraCost, 1000);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('quick price edit updates pack price and resulting cost',
      (tester) async {
    final repo = fixture.MemoryChefRepository(fixture.example('en'));
    await fixture.showChef(tester, 'en', repo);
    final quick = find.text('Quick price edit');
    await reveal(tester, quick);
    await tester.tap(quick);
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextFormField)),
        findsNWidgets(2));
    await tester.enterText(
        find
            .descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(TextFormField))
            .last,
        '10,000');
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save work'));
    await tester.pumpAndSettle();
    expect(repo.document.ingredients.single.purchasePrice, 10000);
    expect(repo.document.portionCost, 2750);
  });
}
