import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/business/presentation/business_pages.dart';

void main() {
  testWidgets(
      'empty chooser creates and selects an item without leaving the original form',
      (tester) async {
    String? selected;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      selected = await showDialog<String>(
                          context: context,
                          builder: (_) => BusinessSupplierChoice<String>(
                              title: 'Supplier',
                              load: () async => [],
                              label: (s) => s,
                              detail: (_) => '',
                              createLabel: 'Add supplier',
                              onCreate: () async => 'New supplier'));
                    },
                    child: const Text('Choose'))))));
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    expect(find.text('등록된 항목이 없습니다.'), findsOneWidget);
    await tester.tap(find.text('Add supplier'));
    await tester.pumpAndSettle();
    expect(selected, 'New supplier');
    expect(find.text('Choose'), findsOneWidget);
  });
  testWidgets(
      'chooser reloads after failure and keeps search while creation is cancelled',
      (tester) async {
    var attempts = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: BusinessSupplierChoice<String>(
                title: 'Products',
                load: () async {
                  if (attempts++ == 0) throw StateError('connection');
                  return ['Pork shoulder', 'Chicken'];
                },
                label: (s) => s,
                detail: (_) => '',
                createLabel: 'Add product',
                onCreate: () async => null))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다시 불러오기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'shoulder');
    await tester.pumpAndSettle();
    expect(find.text('Pork shoulder'), findsOneWidget);
    expect(find.text('Chicken'), findsNothing);
    await tester.tap(find.text('Add product'));
    await tester.pumpAndSettle();
    expect(find.text('Pork shoulder'), findsOneWidget);
    expect(find.text('Chicken'), findsNothing);
    expect(attempts, 3);
  });
}
