import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/shopping/data/owner_record_management_repository.dart';
import 'package:k_youtube/features/shopping/presentation/owner_record_management.dart';

final testAccount = StateProvider<String?>((ref) => 'owner');

class OwnerManagementMemory implements OwnerRecordManagementRepository {
  String? blocked;
  bool stale = false;
  int writes = 0, reads = 0;
  Completer<Map<String, dynamic>>? pending;
  @override
  Future<Map<String, dynamic>> preview(String kind, String id,
      {String? workspace, Map<String, dynamic> change = const {}}) async {
    reads++;
    return {
      'kind': kind,
      'id': id,
      'workspace': workspace,
      'change': change,
      'token': 'preview-token',
      'title': '당근',
      'counts': {'history': 3},
      'blocked': blocked,
      'unit': 'g',
      'balance': {'on_hand': 2000, 'reserved': 500, 'available': 1500},
      'after': {'on_hand': 2, 'reserved': 0.5, 'available': 1.5}
    };
  }

  @override
  Future<Map<String, dynamic>> apply(Map<String, dynamic> p) async {
    writes++;
    if (stale) throw StateError('MANAGEMENT_STALE');
    return pending != null ? pending!.future : {...p, 'applied': true};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<ProviderContainer> showManagement(
    WidgetTester t, OwnerManagementMemory repo,
    {bool conversion = false,
    String language = 'ko',
    double width = 360,
    double scale = 1.4}) async {
  t.view.physicalSize = Size(width, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(ProviderScope(
      overrides: [
        activeAccountIdProvider.overrideWith((ref) => ref.watch(testAccount)),
        ownerRecordManagementRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
          locale: Locale(language),
          supportedLocales: const [Locale('ko'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: Scaffold(
              body: Consumer(
                  builder: (c, ref, _) => TextButton(
                      onPressed: () => manageOwnerRecord(c, ref,
                          kind: conversion ? 'stock_unit' : 'request',
                          id: 'record',
                          currentUnit: 'g'),
                      child: const Text('Open')))))));
  final container = ProviderScope.containerOf(t.element(find.byType(Scaffold)));
  await t.tap(find.text('Open'));
  await t.pumpAndSettle();
  return container;
}

Future<void> tap(WidgetTester t, Finder finder) async {
  await t.ensureVisible(finder);
  await t.tap(finder);
  await t.pumpAndSettle();
}

void main() {
  test('only known dimensional conversions are suggested', () {
    expect(suggestedStockConversion('g', 'kg'), 0.001);
    expect(suggestedStockConversion(' L ', 'mL'), 1000);
    expect(suggestedStockConversion('kg', 'L'), isNull);
    expect(suggestedStockConversion('개', 'g'), isNull);
  });
  testWidgets('erasure needs a fresh preview and explicit confirmation',
      (t) async {
    final repo = OwnerManagementMemory();
    await showManagement(t, repo);
    expect(repo.reads, 1);
    expect(repo.writes, 0);
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    await tap(t, find.byType(CheckboxListTile));
    await tap(t, find.text('영구 삭제'));
    expect(repo.writes, 1);
    expect(find.byType(AlertDialog), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('stale response leaves dialog open and requires review again',
      (t) async {
    final repo = OwnerManagementMemory()..stale = true;
    await showManagement(t, repo);
    await tap(t, find.byType(CheckboxListTile));
    await tap(t, find.text('영구 삭제'));
    expect(find.textContaining('확인 중 기록이 바뀌었거나'), findsOneWidget);
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
  });
  testWidgets('active reservation prevents confirmation and deletion',
      (t) async {
    final repo = OwnerManagementMemory()..blocked = 'MANAGEMENT_RESERVED';
    await showManagement(t, repo);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.text('진행 중인 조리 예약을 먼저 해제해 주세요.'), findsOneWidget);
    expect(repo.writes, 0);
  });
  testWidgets(
      'conversion inputs invalidate preview and arbitrary ratios need input',
      (t) async {
    final repo = OwnerManagementMemory();
    await showManagement(t, repo, conversion: true);
    await t.enterText(find.byType(TextField).first, 'kg');
    await t.pump();
    expect(t.widget<TextField>(find.byType(TextField).last).controller!.text,
        '0.001');
    await tap(t, find.text('환산 영향 확인'));
    expect(find.text('현재고: 2000 g → 2 kg'), findsOneWidget);
    await tap(t, find.byType(CheckboxListTile));
    await t.enterText(find.byType(TextField).first, '봉');
    await t.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(
        t.widget<TextField>(find.byType(TextField).last).controller!.text, '');
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(repo.writes, 0);
    expect(t.takeException(), isNull);
  });
  testWidgets('account change closes the private preview without mutation',
      (t) async {
    final repo = OwnerManagementMemory();
    final container = await showManagement(t, repo);
    container.read(testAccount.notifier).state = 'other';
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(repo.writes, 0);
  });
  testWidgets('English desktop deletion preview fits', (t) async {
    final repo = OwnerManagementMemory();
    await showManagement(t, repo, language: 'en', width: 1280, scale: 2);
    expect(find.text('Review permanent deletion'), findsOneWidget);
    await tap(t, find.text('Close'));
    expect(repo.writes, 0);
    expect(t.takeException(), isNull);
  });
}
