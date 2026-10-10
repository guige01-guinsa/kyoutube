import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:k_youtube/core/theme/app_theme.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/business/data/business_repository.dart';
import 'package:k_youtube/features/business/domain/business_workspace.dart';
import 'package:k_youtube/features/kitchen/presentation/kitchen_page.dart';
import 'package:k_youtube/features/shopping/data/purchase_cleanup_repository.dart';
import 'package:k_youtube/features/shopping/domain/purchase_cleanup.dart';
import 'package:k_youtube/features/shopping/presentation/purchase_cleanup_page.dart';
import 'package:k_youtube/features/shopping/presentation/purchase_cleanup_menu.dart';
import 'package:k_youtube/features/workspace/application/workspace_navigation.dart';

PurchaseCleanupEntry entry(String id,
        {String status = 'draft', bool archived = false}) =>
    PurchaseCleanupEntry(
        id: id,
        title: '목록 $id',
        detail: '당근 · 테스트 거래처',
        status: status,
        token: '$id:1',
        eligible: !['sent', 'review', 'approved', 'accepted'].contains(status),
        archived: archived,
        date: DateTime(2026, 1, 1));

class CleanupMemory implements PurchaseCleanupRepository {
  final rows = [
    entry('a'),
    entry('b', status: 'received'),
    entry('active', status: 'sent')
  ];
  final hidden = <String>{};
  final calls = <List<String>>[];
  Completer<void>? pending;
  Completer<List<PurchaseCleanupEntry>>? pendingList;
  bool unavailable = false, failAfterApply = false;
  String? lastWorkspace;
  int? lastOffset;
  @override
  Future<PurchaseCleanupIndex> index(String? workspace) async =>
      PurchaseCleanupIndex(hidden
          .map((id) =>
              '${workspace == null ? 'request' : 'business_purchase'}:$id')
          .toSet());
  @override
  Future<List<PurchaseCleanupEntry>> list(
      {String? workspace,
      required String kind,
      required bool archived,
      DateTime? before,
      String query = '',
      int offset = 0}) async {
    if (unavailable) throw PurchaseCleanupUnavailable();
    lastOffset = offset;
    lastWorkspace = workspace;
    if (pendingList != null) return pendingList!.future;
    return rows
        .where((r) =>
            hidden.contains(r.id) == archived &&
            (query.isEmpty || r.title.contains(query)))
        .skip(offset)
        .take(51)
        .map((r) => entry(r.id, status: r.status, archived: archived))
        .toList();
  }

  @override
  Future<int> apply(
      {String? workspace,
      required String kind,
      required List<PurchaseCleanupEntry> entries,
      required bool archive}) async {
    calls.add(entries.map((r) => r.id).toList());
    lastWorkspace = workspace;
    if (pending != null) await pending!.future;
    for (final r in entries) {
      archive ? hidden.add(r.id) : hidden.remove(r.id);
    }
    if (failAfterApply) throw StateError('Uncertain transport');
    return entries.length;
  }
}

final ownerProvider = StateProvider<String?>((_) => 'owner');
Future<GoRouter> pumpCleanup(WidgetTester tester, CleanupMemory repo,
    {String? workspace,
    bool write = true,
    String language = 'ko',
    double width = 390,
    double scale = 1,
    String initial = '/cleanup',
    GlobalKey? capture}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final navigation = WorkspaceNavigation();
  final router = GoRouter(initialLocation: initial, routes: [
    GoRoute(
        path: '/cleanup',
        onExit: (_, __) => navigation.confirmLeave(),
        builder: (_, __) => PurchaseCleanupPage(workspace: workspace)),
    GoRoute(
        path: '/',
        builder: (_, __) =>
            Scaffold(appBar: AppBar(actions: const [PurchaseCleanupMenu()]))),
    GoRoute(
        path: '/shopping/kitchen',
        builder: (_, __) => Consumer(
            builder: (_, ref, __) => KitchenPage(
                key: ValueKey(ref.watch(activeAccountIdProvider)),
                toolsOnly: true))),
    GoRoute(
        path: '/shopping/organize',
        builder: (_, s) => PurchaseCleanupPage(
            archived: s.uri.queryParameters['archived'] == 'true')),
    GoRoute(
        path: '/login',
        builder: (_, __) => const Scaffold(body: Text('LOGIN'))),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        activeAccountIdProvider.overrideWith((ref) => ref.watch(ownerProvider)),
        authUserProvider.overrideWith((_) => Stream.value(const User(
            id: 'owner',
            appMetadata: {},
            userMetadata: {},
            aud: 'authenticated',
            createdAt: '2026-09-29'))),
        purchaseCleanupRepositoryProvider.overrideWithValue(repo),
        workspaceNavigationProvider.overrideWithValue(navigation),
        if (workspace != null)
          businessContextProvider(workspace).overrideWith((_) async =>
              BusinessContext(
                  id: workspace,
                  name: '테스트 업소',
                  owner: false,
                  paid: true,
                  approval: true,
                  permissions: {
                    'purchasing.read',
                    if (write) 'purchasing.write'
                  })),
      ],
      child: RepaintBoundary(
          key: capture,
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            routerConfig: router,
            theme: AppTheme.light.copyWith(
                textTheme: AppTheme.light.textTheme
                    .apply(fontFamily: 'CleanupPreview'),
                chipTheme: AppTheme.light.chipTheme.copyWith(
                    labelStyle: AppTheme.light.chipTheme.labelStyle
                        ?.copyWith(fontFamily: 'CleanupPreview')),
                filledButtonTheme: FilledButtonThemeData(
                    style: AppTheme.light.filledButtonTheme.style?.copyWith(
                        textStyle: WidgetStatePropertyAll(
                            AppTheme.light.textTheme.labelLarge?.copyWith(
                                fontFamily: 'CleanupPreview',
                                fontWeight: FontWeight.w700)))),
                appBarTheme: AppTheme.light.appBarTheme.copyWith(
                    titleTextStyle: AppTheme.light.textTheme.titleLarge
                        ?.copyWith(fontFamily: 'CleanupPreview'))),
            locale: Locale(language),
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
          ))));
  await tester.pumpAndSettle();
  return router;
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(f, 500,
        maxScrolls: 40, scrollable: find.byType(Scrollable).first);
  }
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await (FontLoader('CleanupPreview')
          ..addFont(rootBundle.load('assets/fonts/NanumGothic-Regular.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  testWidgets(
      'nothing selected by default and active requests cannot be selected',
      (tester) async {
    final repo = CleanupMemory();
    await pumpCleanup(tester, repo);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('apply-record-cleanup')))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<CheckboxListTile>(
                find.byKey(const ValueKey('cleanup-item-active')))
            .onChanged,
        isNull);
    expect(repo.calls, isEmpty);
  });
  testWidgets(
      'preview can cancel, archive preserves records and restore returns them',
      (tester) async {
    final repo = CleanupMemory();
    await pumpCleanup(tester, repo);
    await tapKey(tester, 'cleanup-item-a');
    await tapKey(tester, 'apply-record-cleanup');
    expect(find.text('선택한 기록을 보관할까요?'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(repo.calls, isEmpty);
    await tapKey(tester, 'apply-record-cleanup');
    await tapKey(tester, 'confirm-record-cleanup');
    expect(repo.hidden, {'a'});
    expect(repo.rows.length, 3);
    expect(repo.rows.first.status, 'draft');
    await tapKey(tester, 'cleanup-view-true');
    await tapKey(tester, 'cleanup-item-a');
    await tapKey(tester, 'apply-record-cleanup');
    await tapKey(tester, 'confirm-record-cleanup');
    expect(repo.hidden, isEmpty);
    expect(repo.calls, [
      ['a'],
      ['a']
    ]);
  });
  testWidgets('shared read-only access shows records but disables mutation',
      (tester) async {
    final repo = CleanupMemory();
    await pumpCleanup(tester, repo, workspace: 'team', write: false);
    expect(repo.lastWorkspace, 'team');
    expect(
        tester
            .widget<CheckboxListTile>(
                find.byKey(const ValueKey('cleanup-item-a')))
            .onChanged,
        isNull);
    expect(repo.calls, isEmpty);
  });
  testWidgets('uncertain response requires reload and prevents blind repeat',
      (tester) async {
    final repo = CleanupMemory()..failAfterApply = true;
    await pumpCleanup(tester, repo);
    await tapKey(tester, 'cleanup-item-a');
    await tapKey(tester, 'apply-record-cleanup');
    await tapKey(tester, 'confirm-record-cleanup');
    expect(find.byKey(const Key('cleanup-error')), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('apply-record-cleanup')))
            .onPressed,
        isNull);
    await tester.ensureVisible(find.text('다시 불러오기'));
    await tester.tap(find.text('다시 불러오기'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cleanup-item-a')), findsNothing);
    expect(repo.calls.length, 1);
  });
  testWidgets('server not enabled fails closed while preserving navigation',
      (tester) async {
    final repo = CleanupMemory()..unavailable = true;
    final router = await pumpCleanup(tester, repo);
    expect(find.textContaining('서버 준비가 아직'), findsOneWidget);
    expect(repo.calls, isEmpty);
    router.go('/');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('purchase-cleanup-menu')), findsOneWidget);
  });
  testWidgets('busy mutation cannot leave or submit twice', (tester) async {
    final repo = CleanupMemory()..pending = Completer<void>();
    final router = await pumpCleanup(tester, repo);
    await tapKey(tester, 'cleanup-item-a');
    await tapKey(tester, 'apply-record-cleanup');
    await tester.tap(find.byKey(const Key('confirm-record-cleanup')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('apply-record-cleanup')))
            .onPressed,
        isNull);
    router.go('/');
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/cleanup');
    repo.pending!.complete();
    await tester.pumpAndSettle();
    expect(repo.calls.length, 1);
  });
  testWidgets('account change closes preview and removes old records',
      (tester) async {
    final repo = CleanupMemory();
    await pumpCleanup(tester, repo);
    await tapKey(tester, 'cleanup-item-a');
    await tapKey(tester, 'apply-record-cleanup');
    final container = ProviderScope.containerOf(
        tester.element(find.byType(PurchaseCleanupPage)));
    container.read(ownerProvider.notifier).state = null;
    await tester.pumpAndSettle();
    expect(find.text('선택한 기록을 보관할까요?'), findsNothing);
    expect(find.byKey(const ValueKey('cleanup-item-a')), findsNothing);
    expect(repo.calls, isEmpty);
  });
  testWidgets(
      'shopping menu restores kitchen cleanup entry and its four options',
      (tester) async {
    await pumpCleanup(tester, CleanupMemory(), initial: '/');
    await tapKey(tester, 'purchase-cleanup-menu');
    await tester.tap(find.text('주방 정리'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'open-kitchen-cleanup');
    for (final label in [
      '보유 재료 삭제',
      '진행 중 장보기 정리',
      '장보기 완료 내역 정리',
      '조리 완료 기록 정리'
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('최근 정리 되돌리기'), findsOneWidget);
  });
  testWidgets('kitchen cleanup selection closes when the account changes',
      (tester) async {
    await pumpCleanup(tester, CleanupMemory(), initial: '/shopping/kitchen');
    await tapKey(tester, 'open-kitchen-cleanup');
    expect(find.text('보유 재료 삭제'), findsOneWidget);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(KitchenPage)));
    container.read(ownerProvider.notifier).state = null;
    await tester.pumpAndSettle();
    expect(find.text('보유 재료 삭제'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('changing pages clears selection and never applies unseen rows',
      (tester) async {
    final repo = CleanupMemory();
    repo.rows
      ..clear()
      ..addAll(List.generate(55, (i) => entry('page$i')));
    await pumpCleanup(tester, repo);
    await tapKey(tester, 'cleanup-item-page0');
    await tester.scrollUntilVisible(find.text('다음'), 700,
        maxScrolls: 30, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const Key('apply-record-cleanup')), 500,
        maxScrolls: 20, scrollable: find.byType(Scrollable).first);
    expect(repo.lastOffset, 50);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('apply-record-cleanup')))
            .onPressed,
        isNull);
    await tester.drag(find.byType(ListView).first, const Offset(0, 2000));
    await tester.pumpAndSettle();
    await tapKey(tester, 'cleanup-item-page50');
    await tapKey(tester, 'apply-record-cleanup');
    await tapKey(tester, 'confirm-record-cleanup');
    expect(repo.calls.single, ['page50']);
  });
  for (final scene in [
    ('ko', 390.0, 1.0),
    ('en', 320.0, 2.0),
    ('ko', 1440.0, 1.0)
  ]) {
    testWidgets('cleanup fits ${scene.$1} ${scene.$2} scale ${scene.$3}',
        (tester) async {
      final key = GlobalKey();
      await pumpCleanup(tester, CleanupMemory(),
          language: scene.$1, width: scene.$2, scale: scene.$3, capture: key);
      expect(tester.takeException(), isNull);
      final output = Platform.environment['SCOUT_CLEANUP_PREVIEW'];
      if (output != null) {
        await tester.runAsync(() async {
          final image = await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File('$output/cleanup-${scene.$1}-${scene.$2.toInt()}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}
